# stop-watchdog.ps1
# 실행 중인 워치독(ensure-agy-running.ps1)을 종료합니다.
# 워처(watch-agy.ps1) 본체는 건드리지 않습니다.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { chcp 65001 > $null } catch {}

$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*ensure-agy-running.ps1*" })

if ($procs.Count -eq 0) {
    Write-Host "실행 중인 워치독이 없습니다."
} else {
    foreach ($p in $procs) {
        Write-Host "워치독 종료: PID $($p.ProcessId)"
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
