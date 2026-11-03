# Model choice

Set a model per task with `@model: <id>` on the first line group of the instruction. Without it the watcher picks an effort level from the request text (rule based, so it can be wrong).

| Difficulty | Model | Examples |
|---|---|---|
| Easy | `gemini-3.8-flash-low` | mechanical conversion, naming, short summaries, translation |
| Normal | `gemini-3.8-flash-medium` | small, well specified edits and tests, ordinary docs and analysis |
| Harder | `gemini-3.8-flash-high` | implementation after a finished design, multi-file changes, code review |

- A well specified implementation (design done, locations and expected result clear): choose `medium` yourself. Automatic selection sends anything over about 500 characters or two files to `high` (about 10 minutes).
- Use `high` when the spec is fuzzy, spans several modules, or a re-submission would be expensive.
- Review failed: raise one step (low, medium, high). For a follow-up of the same job use `@session: <name>`, `@model: <higher>` and `@upgrade: true`. A running `@session` keeps its starting model; asking for another model without `@upgrade` returns an error and keeps the conversation safe.
- If the user names a model ("use pro"), follow that. Only Gemini family models are allowed; the goal is to save Claude quota. Run `agy models` to see what the account can use.
- Allowed list otherwise: `gemini-3.8-flash-high|medium|low`, plus the fallback order `gemini-3.7-flash-high`, `gemini-3.1-pro-high`, `gemini-3.6-flash-high`. A model not on the list fails before agy is called; fix the value and resend, no need to ask the user.
- Typical time: `high` about 9 to 12 minutes, `medium` and `low` less. Batch small edits into one task rather than sending many.
