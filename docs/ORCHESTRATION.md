# How the Head runs the pod

Written 2026-09-23 after Ryan: "you need to get this shit under control... i give you 4 tasks, and you go 'ok, i spun up one agent to do all of that in one go'".

## One task, one agent

Every independent thing Ryan names gets its own agent. Four fixes = four agents, launched in ONE message so they run in parallel. Never bundle "because they touch the same file" — that is what the owner/parts pattern in the builder agent's instructions is for: sub-agents own disjoint named regions, prove with `--preview`, and the owner welds and builds once.

The only legitimate reason to give one agent two deliverables is that the second cannot start until the first exists (a capture of a feature not yet built).

## Merge protocol (the Head)

An agent's report leads with `GATE GREEN AT <sha>`: that tree passed the full suite and the harness. So:

| situation | what the Head runs |
|---|---|
| fast-forward of a green branch | nothing. Merge, report, move on. |
| clean `ort` merge, branches touched different files | nothing. |
| merge that resolved a conflict, or combined two branches that both touched the same build script or `.glb` | full `tools/test.sh` + harness — that merged tree is one nobody tested |
| the Head edited anything itself | full gate |

Report to Ryan the moment the merge lands. Verification that is still needed runs after, not before, the reply.

## Sync

`tools/pc_sync.sh` once per batch of merges, not once per merge. It pushes `origin` too.

## Things that cost whole hours, and their fixes

- **Re-running the agent's gate.** 5-8 min per merge, for nothing. See the table.
- **Agents that end their turn to "wait" for a build.** Nothing wakes them; they stall until prodded. The builder instructions now forbid it — brief them to block in the foreground with a sleep loop.
- **A map-mesh change per agent.** Every `map_base.glb` edit costs a ~10 min Blender build. Parts, one weld, one build.
- **Model quota.** Fable's quota ran out mid-session on 2026-09-23 and killed three agents at launch. Default to Opus; use `model: fable` only when Ryan asks and the quota is known good.
- **The editor checkout writing to tracked files.** Ryan's open Godot editor has twice moved `MapBase` (once by 3 m, which broke every match) and once re-saved new `.tres` resources as empty stubs. `MapBase` is now `_edit_lock_`ed. Before merging, `git status` the editor checkout and restore anything it touched that Ryan did not mean.


## Ryan says what gets built

2026-09-23, after the Head started work he had not asked for: "just do what i say. you dont need a fucking ledger."

The Head does not self-start work. It builds what Ryan names, when he names it. The ledger records what he has said; it is not a work queue and the Head does not pull from it. Idle capacity is not a problem to solve by inventing tasks.

## One agent, one task, and it ends

Spawn a fresh agent per task. Do NOT resume a completed agent to give it new work -- that is what left a roster of finished agents cluttering Ryan's view of what is actually running. Resume only to finish the SAME task the agent was already on.
