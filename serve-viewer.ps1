# serve-viewer.ps1
# samjil AI Agent 통합 웹 뷰어 서버 (Delegate QA 실행 기록 & Handoff 인수인계)
#
# 사용법:
#   .\serve-viewer.ps1                   # 브라우저 실행 및 http://127.0.0.1:8787 서빙
#   .\serve-viewer.ps1 -Port 9000        # 포트 지정
#   종료: 이 창에서 Ctrl+C

param(
    [string]$HandoffDir = "",
    [string]$DataDir    = "",
    [string]$WebDir     = "",
    [int]$Port          = 8787,
    [switch]$NoBrowser  = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

if (-not $HandoffDir) {

    if ($env:AGENT_HANDOFF_ROOT) {

        $HandoffDir = $env:AGENT_HANDOFF_ROOT

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\handoff")) {

        $HandoffDir = Join-Path $env:USERPROFILE ".samjil\handoff"

    } elseif (Test-Path (Join-Path $env:USERPROFILE ".samjil\samjil-handoff")) {

        $HandoffDir = Join-Path $env:USERPROFILE ".samjil\samjil-handoff"

    } elseif (Test-Path (Join-Path $PSScriptRoot "runtime\handoff")) {

        $HandoffDir = Join-Path $PSScriptRoot "runtime\handoff"

    } else {

        $HandoffDir = Join-Path $env:USERPROFILE ".samjil\handoff"

    }

}



if (-not $DataDir) {

    $dataCandidates = @(

        (if ($env:AGY_DELEGATE_RUNTIME) { Join-Path $env:AGY_DELEGATE_RUNTIME "logs\data" } else { $null }),

        (Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime\logs\data"),

        (Join-Path $env:USERPROFILE ".samjil\samjil-delegate-agy\runtime\logs\data"),

        "D:\Repos\github.com\samjil\agy-bridge\runtime\logs\data",

        (Join-Path $PSScriptRoot "runtime\delegate-agy\runtime\logs\data")

    )

    foreach ($cand in $dataCandidates) {

        if ($cand -and (Test-Path (Join-Path $cand "index.json"))) {

            $DataDir = $cand

            break

        }

    }

    if (-not $DataDir) {

        $DataDir = Join-Path $env:USERPROFILE ".samjil\delegate-agy\runtime\logs\data"

    }

}



if (-not $WebDir) {

    $WebDir = Join-Path $PSScriptRoot "web"

}



if (-not (Test-Path $HandoffDir)) {

    New-Item -ItemType Directory -Force -Path $HandoffDir | Out-Null

}

if (-not (Test-Path $DataDir)) {

    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

}



if (-not (Test-Path $WebDir)) {

    Write-Error "web 폴더를 찾을 수 없습니다: $WebDir"

    exit 1

}



$RouteMap = [ordered]@{

    "/handoff/" = (Resolve-Path $HandoffDir).Path

    "/data/"    = (Resolve-Path $DataDir).Path

    "/"         = (Resolve-Path $WebDir).Path

}



$MimeTypes = @{

    ".html"  = "text/html; charset=utf-8"

    ".htm"   = "text/html; charset=utf-8"

    ".js"    = "text/javascript; charset=utf-8"

    ".css"   = "text/css; charset=utf-8"

    ".json"  = "application/json; charset=utf-8"

    ".jsonl" = "application/x-ndjson; charset=utf-8"

    ".csv"   = "text/csv; charset=utf-8"

    ".txt"   = "text/plain; charset=utf-8"

    ".md"    = "text/plain; charset=utf-8"

    ".ico"   = "image/x-icon"

    ".svg"   = "image/svg+xml"

    ".png"   = "image/png"

    ".jpg"   = "image/jpeg"

    ".jpeg"  = "image/jpeg"

    ".gif"   = "image/gif"

    ".webp"  = "image/webp"

    ".bmp"   = "image/bmp"

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



function Get-ContentType($path) {

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()

    if ($MimeTypes.ContainsKey($ext)) { return $MimeTypes[$ext] }

    return "application/octet-stream"

}



function Resolve-SafePath([string]$urlPath) {

    $rootPrefix = "/"

    $root = $RouteMap["/"]

    foreach ($prefix in $RouteMap.Keys) {

        if ($prefix -ne "/" -and $urlPath.StartsWith($prefix)) {

            $rootPrefix = $prefix

            $root = $RouteMap[$prefix]

            break

        }

    }



    $relative = $urlPath.Substring($rootPrefix.Length).TrimStart('/')

    if ([string]::IsNullOrWhiteSpace($relative)) { $relative = "index.html" }

    $relative = [System.Uri]::UnescapeDataString($relative)



    $combined = Join-Path $root $relative

    $full = $null

    try { $full = [System.IO.Path]::GetFullPath($combined) } catch { return $null }



    $rootWithSep = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    if ($full -ne $root -and -not $full.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {

        return $null

    }

    return $full

}



function Get-HandoffRoots {

    $roots = [System.Collections.Generic.List[string]]::new()

    if ($HandoffDir -and (Test-Path $HandoffDir)) {

        $roots.Add((Resolve-Path $HandoffDir).Path)

    }

    $cands = @(

        (Join-Path $env:USERPROFILE ".samjil\handoff"),

        (Join-Path $env:USERPROFILE ".samjil\samjil-handoff"),

        (Join-Path $PSScriptRoot "runtime\handoff")

    )

    foreach ($c in $cands) {

        if (Test-Path $c) {

            $p = (Resolve-Path $c).Path

            if (-not $roots.Contains($p)) {

                $roots.Add($p)

            }

        }

    }

    return $roots

}



function Find-HandoffProjectDir([string]$projectName) {

    foreach ($r in (Get-HandoffRoots)) {

        $testP = Join-Path $r $projectName

        if (Test-Path -LiteralPath $testP -PathType Container) {

            return $testP

        }

    }

    return $null

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

Write-Host "  samjil 에이전트 통합 대시보드 (Unified Dashboard)" -ForegroundColor Cyan

Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host "  웹 대시보드     : $prefix" -ForegroundColor Green

Write-Host "  위임 기록(/data): $DataDir" -ForegroundColor White

Write-Host "  대화 저장소     : $HandoffDir" -ForegroundColor White

Write-Host "  종료 방법       : 이 창에서 Ctrl+C" -ForegroundColor Gray

Write-Host "==========================================================" -ForegroundColor Cyan

Write-Host ""



if (-not $NoBrowser) {

    try { Start-Process $prefix } catch {}

}



try {

    while ($listener.IsListening) {

        $context = $null

        try {

            $context = $listener.GetContext()

        } catch [System.Net.HttpListenerException] {

            break

        }



        $request = $context.Request

        $response = $context.Response



        try {

            $rawPath = $request.Url.AbsolutePath

            $urlPath = [System.Uri]::UnescapeDataString($rawPath)



            if ($urlPath -eq "/api/handoff/projects" -or $urlPath -eq "/api/projects") {

                $projects = @()

                $seenNames = @{}

                foreach ($hRoot in (Get-HandoffRoots)) {

                    if (-not (Test-Path $hRoot)) { continue }

                    $dirs = Get-ChildItem -LiteralPath $hRoot -Directory -ErrorAction SilentlyContinue

                    foreach ($d in $dirs) {

                        if ($d.Name -eq "templates" -or $d.Name -eq "viewer" -or $d.Name -eq "scripts" -or $seenNames.ContainsKey($d.Name)) { continue }

                        $seenNames[$d.Name] = $true

                        $briefPath = Join-Path $d.FullName "BRIEF.md"

                        $indexPath = Join-Path $d.FullName "INDEX.md"

                        $msgDir = Join-Path $d.FullName "msg"

                        $msgCount = 0

                        if (Test-Path $msgDir) {

                            $msgFiles = Get-ChildItem -LiteralPath $msgDir -Filter "*.md" -File -ErrorAction SilentlyContinue

                            $msgCount = if ($msgFiles) { @($msgFiles).Count } else { 0 }

                        }

                        $lastUpdated = $d.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")

                        $latestMsg = $null

                        if (Test-Path $indexPath) {

                            $idxContent = Get-Content -LiteralPath $indexPath -Encoding UTF8 -ErrorAction SilentlyContinue

                            if ($idxContent) {

                                $tableLines = $idxContent | Where-Object { $_ -match '^\s*\|\s*\d{4}\s*\|' }

                                if ($tableLines) {

                                    $lastLine = @($tableLines)[-1]

                                    $parts = $lastLine.Split('|') | ForEach-Object { $_.Trim() }

                                    if ($parts.Length -ge 6) {

                                        $latestMsg = [PSCustomObject]@{

                                            num    = $parts[1]

                                            time   = $parts[2]

                                            dir    = $parts[3]

                                            title  = $parts[4]

                                            status = $parts[5]

                                        }

                                    }

                                }

                            }

                        }

                        $projects += [PSCustomObject]@{

                            name      = $d.Name

                            hasBrief  = (Test-Path $briefPath)

                            hasIndex  = (Test-Path $indexPath)

                            msgCount  = $msgCount

                            updated   = $lastUpdated

                            latestMsg = $latestMsg

                        }

                    }

                }

                $arr = @($projects)

                if ($arr.Count -eq 0) {

                    $json = "[]"

                } elseif ($arr.Count -eq 1) {

                    $json = "[" + ($arr[0] | ConvertTo-Json -Depth 5) + "]"

                } else {

                    $json = $arr | ConvertTo-Json -Depth 5

                }

                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

                $response.ContentType = "application/json; charset=utf-8"

                $response.ContentLength64 = $bytes.Length

                $response.Headers.Add("Cache-Control", "no-store")

                $response.OutputStream.Write($bytes, 0, $bytes.Length)



            } elseif ($urlPath -eq "/api/handoff/project" -or $urlPath -eq "/api/project") {

                $params = Get-Utf8QueryParams $request.Url

                $pName = $params["name"]

                if ([string]::IsNullOrWhiteSpace($pName) -or $pName.Contains("..") -or $pName.Contains("/") -or $pName.Contains("\")) {

                    $response.StatusCode = 400

                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("Invalid project name")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $bytes.Length

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                } else {

                    $pDir = Find-HandoffProjectDir $pName

                    if (-not $pDir) {

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

            } elseif ($urlPath -eq "/api/handoff/message" -or $urlPath -eq "/api/message") {

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

                    $pDir = Find-HandoffProjectDir $pName

                    $msgFilePath = if ($pDir) { Join-Path $pDir "msg\$fName" } else { $null }

                    if (-not $msgFilePath -or -not (Test-Path -LiteralPath $msgFilePath -PathType Leaf)) {

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

            } elseif ($urlPath -eq "/image") {

                $params = Get-Utf8QueryParams $request.Url

                $imgParam = $params["path"]

                $cwdParam = $params["cwd"]

                $targetPath = $null

                if (-not [string]::IsNullOrWhiteSpace($imgParam)) {

                    $targetPath = $imgParam.Trim()

                    if (-not [System.IO.Path]::IsPathRooted($targetPath) -and -not [string]::IsNullOrWhiteSpace($cwdParam)) {

                        $targetPath = Join-Path $cwdParam.Trim() $targetPath

                    }

                }



                $fullPath = $null

                try {

                    if ($targetPath) { $fullPath = [System.IO.Path]::GetFullPath($targetPath) }

                } catch { $fullPath = $null }



                $ext = if ($fullPath) { [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant() } else { "" }

                $allowedImageExts = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".ico")



                if (-not $fullPath -or -not ($allowedImageExts -contains $ext) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {

                    $response.StatusCode = 404

                    $body = [System.Text.Encoding]::UTF8.GetBytes("404 Image Not Found")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $body.Length

                    $response.OutputStream.Write($body, 0, $body.Length)

                } else {

                    $bytes = [System.IO.File]::ReadAllBytes($fullPath)

                    $response.ContentType = Get-ContentType $fullPath

                    $response.ContentLength64 = $bytes.Length

                    $response.Headers.Add("Cache-Control", "public, max-age=3600")

                    $response.Headers.Add("Content-Disposition", "inline")

                    $response.OutputStream.Write($bytes, 0, $bytes.Length)

                }

            } else {

                $filePath = Resolve-SafePath $urlPath



                if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {

                    if (-not $urlPath.StartsWith("/data/") -and -not [System.IO.Path]::HasExtension($urlPath)) {

                        $filePath = Join-Path $RouteMap["/"] "index.html"

                    }

                }



                if (-not $filePath -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {

                    $response.StatusCode = 404

                    $body = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $urlPath")

                    $response.ContentType = "text/plain; charset=utf-8"

                    $response.ContentLength64 = $body.Length

                    $response.OutputStream.Write($body, 0, $body.Length)

                } else {

                    $bytes = [System.IO.File]::ReadAllBytes($filePath)

                    $response.ContentType = Get-ContentType $filePath

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

