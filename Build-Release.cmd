@echo off
setlocal
title samjil-skills release zip
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build-release.ps1" -Open %*
echo.
pause
