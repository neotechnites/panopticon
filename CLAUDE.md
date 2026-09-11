# Panopticon — rules for anyone editing this repo

Ryan's game. Ryan decides design. You implement exactly what is asked, cheaply, and report what you did.

## Cost rules
- Do exactly the change briefed. No consistency sweeps, no refactors, no extra tests, no "while I was here".
- Verify with the ONE command the brief names. Write no scratch probes, harnesses, diff scripts or PowerShell wrappers.
- Never run Godot with a window on the Mac (it steals Ryan's keyboard). Headless only, or the PC via `tools/verify.sh`.
- Never touch `C:\dev\panopticon` (Ryan's play copy). Never kill a process you did not start.
- Do not commit or push unless told.
- Report in <=120 words: files changed, the verify result, anything you could not do. No reasoning essays.

## Prose budget
This repo was measured at 45–49% comment lines in its core scripts and 41k characters of `editor_description` in one scene. Every edit pays to read that and pays again to extend it.
- Function doc comment: <=2 lines. Say what, not a history of why.
- `editor_description` in `.tscn`: <=1 sentence, or omit it.
- No rationale paragraphs, no quoted conversation, no bug archaeology in comments.
- Prose you have to touch gets shorter, never longer.

## Non-negotiables
- `PlayerController` never reads `Input`. Intent arrives through `IntentSource` → `MoveIntent`.
- `Transform3D(...)` in a `.tscn` takes the basis as ROWS.
- Godot 4.7.2, GL Compatibility renderer. Do not change either.
- Bots are opponents so Ryan can play. They are not a test oracle for the head.
