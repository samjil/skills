# serve-handoff.ps1
# Agent Handoff 대화 기록을 브라우저로 열람하는 독립 로컬 웹 뷰어 서버
#
# 사용법:
#   .\serve-handoff.ps1                  # http://127.0.0.1:8787 에서 서빙
#   .\serve-handoff.ps1 -Port 9000       # 포트 지정
#   종료: 터미널에서 Ctrl+C

param(
    [string]$HandoffDir = "",
    [string]$WebDir     = "",
    [int]$Port          = 8787,
    [switch]$NoBrowser  = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

if (-not $HandoffDir) {
    if ($env:AGENT_HANDOFF_ROOT) {
        $HandoffDir = $env:AGENT_HANDOFF_ROOT
    } else {
        $HandoffDir = Join-Path $env:USERPROFILE ".samjil\agent-handoff"
    }
}

if (-not $WebDir) {
    $WebDir = Join-Path $PSScriptRoot "web"
}

# Handoff 디렉터리 자동 생성
if (-not (Test-Path $HandoffDir)) {
    New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null
}

# 기존 ~/.samjil/handoff 또는 ~/.agent-handoff 에 프로젝트가 있고 새 경로에 없다면 자동 복사 마이그레이션
$legacyPaths = @(
    (Join-Path $env:USERPROFILE ".samjil\handoff"),
    (Join-Path $env:USERPROFILE ".agent-handoff")
)
foreach ($legacy in $legacyPaths) {
    if ((Test-Path $legacy) -and (Get-ChildItem -LiteralPath $HandoffDir).Count -eq 0) {
        try {
            Get-ChildItem -LiteralPath $legacy -Directory | ForEach-Object {
                $dest = Join-Path $HandoffDir $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item -Recurse -Force -LiteralPath $_.FullName -Destination $dest
                    Write-Host "[•] 기존 대화 기록을 ~/.samjil/agent-handoff 로 복사했습니다: $($_.Name)" -ForegroundColor Green
                }
            }
        } catch {}
    }
}

if (-not (Test-Path $WebDir)) {
    Write-Error "web 폴더를 찾을 수 없습니다: $WebDir"
    exit 1
}

$MimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".htm"  = "text/html; charset=utf-8"
    ".js"   = "text/javascript; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".md"   = "text/plain; charset=utf-8"
    ".txt"  = "text/plain; charset=utf-8"
    ".svg"  = "image/svg+xml"
    ".png"  = "image/png"
    ".ico"  = "image/x-icon"
}

function Get-ContentType([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($MimeTypes.ContainsKey($ext)) { return $MimeTypes[$ext] }
    return "application/octet-stream"
}

function Get-Utf8QueryParams([System.Uri]$uri) {
    $dict = @{}
    $q = $uri.Query
    if (-not [string]::IsNullOrWhiteSpace($q)) {
        $trimmed = $q.TrimStart('?')
        $pairs = $trimmed.Split('&')
        foreach ($p in $pairs) {
            if ($p) {
                $idx = $p.IndexOf('=')
                if ($idx -ge 0) {
                    $k = [System.Uri]::UnescapeDataString($p.Substring(0, $idx))
                    $v = [System.Uri]::UnescapeDataString($p.Substring($idx + 1))
                    $dict[$k] = $v
                } else {
                    $k = [System.Uri]::UnescapeDataString($p)
                    $dict[$k] = ""
                }
            }
        }
    }
    return $dict
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Error "HTTP 리스너 시작 실패 ($prefix): $($_.Exception.Message)"
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Agent Handoff Viewer (에이전트 비동기 대화 뷰어)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  웹 대시보드 : $prefix" -ForegroundColor Green
Write-Host "  대화 저장소 : $HandoffDir" -ForegroundColor White
Write-Host "  종료 방법   : 이 창에서 Ctrl+C" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $NoBrowser) {
    try { Start-Process $prefix } catch {}
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        try {
            $rawPath = $request.Url.AbsolutePath
            $urlPath = [System.Uri]::UnescapeDataString($rawPath)

            if ($urlPath -eq "/api/projects") {
                $projects = @()
                if (Test-Path $HandoffDir) {
                    $dirs = Get-ChildItem -LiteralPath $HandoffDir -Directory | Sort-Object Name
                    foreach ($d in $dirs) {
                        $msgDir = Join-Path $d.FullName "msg"
                        $cnt = 0
                        if (Test-Path $msgDir) {
                            $cnt = (Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File).Count
                        }
                        $projects += [PSCustomObject]@{
                            name     = $d.Name
                            msgCount = $cnt
                        }
                    }
                }
                $json = $projects | ConvertTo-Json -Depth 5
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.Headers.Add("Cache-Control", "no-store")
                $response.OutputStream.Write($bytes, 0, $bytes.Length)

            } elseif ($urlPath -eq "/api/project") {
                $params = Get-Utf8QueryParams $request.Url
                $pName = $params["name"]
                if ([string]::IsNullOrWhiteSpace($pName) -or $pName.Contains("..") -or $pName.Contains("/") -or $pName.Contains("\")) {
                    $response.StatusCode = 400
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid project name")
                    $response.ContentType = "text/plain; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $pDir = Join-Path $HandoffDir $pName
                    if (-not (Test-Path -LiteralPath $pDir -PathType Container)) {
                        $response.StatusCode = 404
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Project not found")
                        $response.ContentType = "text/plain; charset=utf-8"
                        $response.ContentLength64 = $bytes.Length
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    } else {
                        $briefPath = Join-Path $pDir "BRIEF.md"
                        $briefText = if (Test-Path $briefPath) { [System.IO.File]::ReadAllText($briefPath, [System.Text.Encoding]::UTF8) } else { "" }

                        $indexPath = Join-Path $pDir "INDEX.md"
                        $indexLines = if (Test-Path $indexPath) { Get-Content -LiteralPath $indexPath -Encoding UTF8 } else { @() }
                        $parsedMessages = @()
                        foreach ($line in $indexLines) {
                            if ($line -match '^\s*\|\s*(\d{4})\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|') {
                                $parsedMessages += [PSCustomObject]@{
                                    num    = $Matches[1].Trim()
                                    time   = $Matches[2].Trim()
                                    dir    = $Matches[3].Trim()
                                    title  = $Matches[4].Trim()
                                    status = $Matches[5].Trim()
                                }
                            }
                        }

                        $msgDir = Join-Path $pDir "msg"
                        $fileList = @()
                        if (Test-Path $msgDir) {
                            $files = Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File | Sort-Object Name
                            foreach ($f in $files) {
                                $fileList += $f.Name
                            }
                        }

                        $resObj = [PSCustomObject]@{
                            name     = $pName
                            brief    = $briefText
                            messages = $parsedMessages
                            files    = $fileList
                        }
                        $json = $resObj | ConvertTo-Json -Depth 5
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                        $response.ContentType = "application/json; charset=utf-8"
                        $response.ContentLength64 = $bytes.Length
                        $response.Headers.Add("Cache-Control", "no-store")
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    }
                }

            } elseif ($urlPath -eq "/api/message") {
                $params = Get-Utf8QueryParams $request.Url
                $pName = $params["project"]
                $fName = $params["file"]
                if ([string]::IsNullOrWhiteSpace($pName) -or [string]::IsNullOrWhiteSpace($fName) -or
                    $pName.Contains("..") -or $pName.Contains("/") -or $pName.Contains("\") -or
                    $fName.Contains("..") -or $fName.Contains("/") -or $fName.Contains("\")) {
                    $response.StatusCode = 400
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid project or file name")
                    $response.ContentType = "text/plain; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $msgFilePath = Join-Path $HandoffDir "$pName\msg\$fName"
                    if (-not (Test-Path -LiteralPath $msgFilePath -PathType Leaf)) {
                        $response.StatusCode = 404
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Message file not found: $fName")
                        $response.ContentType = "text/plain; charset=utf-8"
                        $response.ContentLength64 = $bytes.Length
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    } else {
                        $bytes = [System.IO.File]::ReadAllBytes($msgFilePath)
                        $response.ContentType = "text/plain; charset=utf-8"
                        $response.ContentLength64 = $bytes.Length
                        $response.Headers.Add("Cache-Control", "no-store")
                        $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    }
                }

            } else {
                # 정적 파일 서빙
                $rel = $urlPath.TrimStart('/')
                if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }
                $localPath = Join-Path $WebDir $rel

                if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                    $localPath = Join-Path $WebDir "index.html"
                }

                if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                    $response.StatusCode = 404
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                    $response.ContentType = "text/plain; charset=utf-8"
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $bytes = [System.IO.File]::ReadAllBytes($localPath)
                    $response.ContentType = Get-ContentType $localPath
                    $response.ContentLength64 = $bytes.Length
                    $response.Headers.Add("Cache-Control", "no-store")
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                }
            }

        } catch {
            try {
                $response.StatusCode = 500
                $bytes = [System.Text.Encoding]::UTF8.GetBytes("500 Server Error: $($_.Exception.Message)")
                $response.ContentType = "text/plain; charset=utf-8"
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } catch {}
        } finally {
            try { $response.OutputStream.Close() } catch {}
        }
    }
} finally {
    try { $listener.Stop() } catch {}
    try { $listener.Close() } catch {}
    Write-Host "`n웹 뷰어 서버를 종료했습니다."
}
