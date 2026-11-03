---
name: samjil-delegate-agy
description: "Delegate coding and routine tasks to the Antigravity CLI (agy) through a local watcher to save Claude quota. Claude keeps the design and the hardest part and reviews every result. Use when the user says 'delegate', 'ask agy', 'let agy do it', 'save quota', or turns delegate mode on. Windows only. Run Install.cmd once first."
summary: "Save Claude quota: Claude designs and reviews, the Antigravity CLI (agy) does the routine work."
version: "1.0.0"
tags: [delegation, antigravity, agy, claude-code, quota, windows]
keywords: [delegate to agy, antigravity cli, save claude quota, subagent, background watcher]
docs_url: "https://github.com/samjil/skills"
---

# samjil-delegate-agy

Send the cheap-to-verify parts of a job to the Antigravity CLI (`agy`), keep the thinking for Claude, and review everything that comes back. Goal: spend less Claude quota without lowering quality.

## 0. Setup check (do this first, every conversation)

Check that the runtime exists:

```bash
test -f "$USERPROFILE/.samjil/delegate-agy/scripts/submit-task.ps1" && echo READY || echo MISSING
```

- `READY`: continue.
- `MISSING`: the one-time installer has not run. Tell the user in one line, then run it. If an `install.ps1` sits in the parent folder of this skill folder (the unzipped pack), run:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<parent of this skill folder>/install.ps1"`
  Otherwise ask the user to double-click `Install.cmd` in the unzipped pack. Do not download or run scripts from anywhere else. Until it is installed, do the work yourself.

If `agy` itself is missing or not signed in, the installer says so. The user fixes that once (install Antigravity CLI, run `agy` once to sign in). Never install or sign in for them.

## 1. When to delegate

- **Default (on request):** delegate when the user asks ("ask agy", "delegate this", "use agy for the rest") or says delegate mode is on for this conversation.
- **Always-on:** if the session start context contains `[samjil-delegate-agy]`, the user installed with `-AlwaysOn`: delegate by default for every task.

## 2. Who does what

| Claude does it directly | agy does it |
|---|---|
| Design, architecture, trade-offs, unclear requirements | Implementation after the design is fixed |
| The single hardest piece of a task | Normal bug fixes, refactors, tests |
| Security, auth, payments, migrations, anything hard to undo | UI built from a written spec, docs, translation, cleanup |
| Needs Claude-only tools (web search, browser, MCP, documents) | Scripts, format conversion, log reading, first-pass review |
| Trivial: a one-line edit is cheaper than writing a brief | |

Split big jobs: you design and take the hardest piece, agy gets the rest with the spec. If unsure, delegate and review strictly. If the same problem fails review three times, take that piece yourself.

agy has no web search. Never trust factual claims from agy without checking.

## 3. Delegate in four steps

1. **Watcher.** Check it is running; start it if not (hidden, no window):
   ```bash
   S="$USERPROFILE/.samjil/delegate-agy/scripts/sub"
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/ensure-agy-running.ps1" -CheckOnly -StaleThresholdSeconds 0   # prints ALIVE | DEAD | MANUAL_STOP
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/ensure-agy-running.ps1" -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0   # starts it
   ```
   `MANUAL_STOP` means the user stopped it on purpose: ask before starting. Details: `references/watcher.md`.
2. **Folder.** For tasks that read or write project files, confirm the project folder with the user once per conversation, and say that agy runs with permissions skipped inside it (suggest it be under git). Never guess a folder.
3. **Brief.** Write the instruction (template below) and submit it:
   ```bash
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/submit-task.ps1" <<'CLAUDE_TASK_EOF'
   @cwd: C:\path\to\project
   @model: gemini-3.8-flash-medium
   [1. Goal] one or two lines; say whether it is read-only or edits files
   [2. Spec] file paths (with line numbers), exact AS-IS -> TO-BE, names and values. Do not paste whole files
   [3. Limits] rules that matter for this task, files not to touch. If something is unclear: write [NEED INFO] and a question as the first line of the answer and do not touch that part
   [4. Verify and report] the test/build command; reply as: status, changed files, one-line test result, concerns
   CLAUDE_TASK_EOF
   ```
   Leave out the `@cwd` line for tasks that need no files (translation, writing).
4. **Wait.** The script waits about 170 s. If it prints `===PENDING=== <ID>`, the task is still running: do not resubmit, call `submit-task.ps1 -Poll <ID>` (a `high` model takes about 10 minutes). Output `===RESULT===` means an answer exists (read it, failures can arrive as the answer text); `===ERROR===` means no answer.

More: several tasks at once (`-NoWait`, then `-Poll <ID1>,<ID2>`, at most 5 at a time), `@session`, `@model`, `@upgrade`: `references/brief-and-commands.md` and `references/models.md`.

## 4. Always review what agy returns

Never pass agy output on unchecked. Bar: "as good as if Claude had done it".

- Requirements and spec all met? Nothing invented, nothing skipped?
- Code: read the diff yourself and re-run the key test or build. Do not trust "tests passed" in the report.
- agy must not commit. The watcher warns at the top of the answer if git state changed. You review the diff and you decide on the commit.
- Facts and numbers: check them or leave them out.
- Not good enough: resubmit with concrete feedback (use `@session: <name>` to continue; raise the model one step: low, medium, high).
- Do not touch the same repository while agy is working in it.

## 5. Say what happened

End the answer with one line: `(Delegated to agy and reviewed by Claude)`. If you did it yourself, say why in one line, for example `(Done directly: design)`. If you re-delegated or fixed parts yourself, add that.

## 6. Switch off, remove, more

- Stop the watcher: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/stop-agy.ps1"`.
- Remove everything: double-click `Uninstall.cmd` (also removes the always-on hook).
- Dashboard of delegated tasks: `http://127.0.0.1:8787` (start it with `viewer/ensure-viewer-running.ps1` under `~/.samjil`).
- Troubleshooting, logs, stuck tasks: `references/watcher.md`.
- The author's complete original rules (Korean, long): `references/full-rules-ko.md`. Read only when a case above does not cover it.
