# Agensi 상품 설명 초안 (zip 에 들어가지 않는 문서)

## Title
samjil-delegate-agy: delegate coding tasks from Claude Code to Antigravity CLI (agy)

## Short description
Cut Claude quota: Claude designs and reviews, agy does the routine work. Windows only. One double-click installer.

## Requirements (put at the top of the listing)
- Windows 10/11 with Windows PowerShell 5.1 (included in Windows). macOS and Linux are NOT supported.
- Claude Code
- Antigravity CLI (`agy`) installed and signed in (open a terminal, run `agy` once)
- One setup step after unzipping: double-click `Install.cmd` (about 1 minute)

## What you get
- A skill that tells Claude when to hand work to agy, how to write the brief, and how to review the result
- A local background watcher that runs agy for each delegated task (no console window)
- Git safety checks: agy is told never to commit; the watcher warns if git state changed
- Optional local dashboard of delegated tasks (127.0.0.1 only, off until you start it)
- `Uninstall.cmd` removes everything

## What it touches on your PC
- `%USERPROFILE%\.samjil\` (scripts, task history, logs) and `%USERPROFILE%\.claude\skills\samjil-delegate-agy\`
- Only with `Install.cmd -AlwaysOn`: one SessionStart hook entry in `%USERPROFILE%\.claude\settings.json` (backed up first)
- The pack makes no network calls. Everything runs locally; agy uses your own sign-in.

## Notes for reviewers / scanners
The installer and scripts use `powershell -ExecutionPolicy Bypass`, `Unblock-File` and a hidden background watcher process. Reasons are listed in `README.txt` ("Why the installer uses these commands"). All files are plain text.

## Price note
The runtime source is public at https://github.com/samjil/skills (MIT/own license: fill in). The listing sells the ready-to-run pack and its English instructions.
