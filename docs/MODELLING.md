# Modelling

How a 3D model gets made for PANOPTICON: authored on the Mac, built and
rendered on the Windows PC, looked at on the Mac, and proved in Godot before it
is allowed anywhere near `assets/models/`.

This exists because the expensive part of modelling was never the geometry. It
was that **the agent could not see what it had made**, so it iterated on
arithmetic and waited for a human to say "still wrong". One look now costs
about twenty-five seconds.

## The five stages

| | | |
|---|---|---|
| **Author** | `tools/modelling/<name>_build.py` | in the repo, tunables in one block at the top |
| **Run** | `tools/modelling/model build <name>` | ships it to the PC, runs Blender headless |
| **See** | `~/Desktop/panopticon-renders/` | EEVEE on the GPU, standard views or any angle |
| **Verify** | Godot on the PC | imports the `.glb`, checks it against a contract |
| **Deliver** | `assets/models/<name>.glb` | only if verification passed |

## Commands

Run from the repo root.

    tools/modelling/model build <name>            # the whole pipeline, installs the model
    tools/modelling/model look  <name>            # renders only: no verify, no install
    tools/modelling/model verify <name>           # re-check the .glb already in assets/models/
    tools/modelling/model views                   # list the named views
    tools/modelling/model open                    # reveal the renders in Finder
    tools/modelling/model doctor                  # is the PC reachable, is there a console session

Options for `build` and `look`:

| flag | |
|---|---|
| `--views front,side,threequarter` | named views; default is those three |
| `--cam AZ,EL[,LENS]` | any angle, repeatable |
| `--turntable N` | N shots evenly around |
| `--frame N` | pose an animated rig at frame N before rendering |
| `--rest` | rest pose, action cleared — for debugging a rig |
| `--res WxH` | fixed frame size; default shapes each frame to the subject |
| `--samples N`, `--light W`, `--margin M` | render quality, key light watts, framing slack |
| `--cpu` | Cycles on CPU instead of EEVEE on GPU |
| `--no-verify`, `--no-install`, `--keep` | skip stages; `--keep` archives a timestamped copy |

Azimuth 0 is the model's own front; elevation is degrees above the horizon.
`--cam 215,22` and the named view `hero` are the same thing.

## Writing a build script

`tools/modelling/lib/mdl.py` provides everything except the geometry. A build
script is:

```python
import mdl

NAME = "thing"
FACING_YAW = 180.0        # degrees to rotate the named views so "front" is the model's front

WIDTH = 0.4               # every adjustable number lives up here
...

def build():
    ...
    return objects        # what to export and render

if __name__ == "__main__":
    mdl.main(NAME, build, facing_yaw=FACING_YAW)
```

Useful pieces of `mdl`: `limb` (a capped tapered n-gon tube from a table of
rings — the workhorse), `prism`, `frustum`, `plate_z`, `tube`, `box`,
`flat_material`, `finish`, `join`, `merge_parts`, and for rigs `armature`,
`rigid_bind`, `bake_pose`.

**The build script is the model.** The `.glb` is output. `runner_build.py` had
to be reconstructed by reading the rest pose, section profiles and animation
curves back out of a binary nobody could edit; do not create that situation
again by working in a scratchpad.

## The contract file

`tools/modelling/<name>.contract.json` states what the game addresses the model
by, and `lib/verify_glb.gd` enforces it on the PC after every build:

```json
{
  "node_paths": ["Armature/Skeleton3D/Runner", "AnimationPlayer"],
  "animations": ["Run"],
  "bones": ["Hips", "Spine", "..."],
  "surfaces": 1,
  "max_tris": 700
}
```

A build that breaks any of it is **not installed**. Without this, a lost skin
or a renamed node surfaces days later as a gameplay bug.

## What bit us

**EEVEE cannot run over plain SSH.** A Windows OpenSSH session has no GPU and
no desktop context. Blender's EEVEE and its compositor both die there with
`EXCEPTION_ACCESS_VIOLATION` — no traceback, no message, just a crash. Every
render before this pipeline therefore used Cycles on CPU on an i7-6700, minutes
per iteration.

The fix is the same one `docs/BUILDING.md` records for running the game
windowed: push the process into the logged-on console session with a scheduled
task created `/it`. `lib/pcrun.ps1` does that. In the console session Blender
finds the RX 6600 XT and EEVEE renders a 1200 px frame in well under a second.
`--cpu` still exists and still works; it is just twenty times slower.

**A scheduled task's exit status tells you nothing** about the process it
launched — it returns as soon as the task is *started*. The batch file writes a
`.done` file containing the real exit code, and `pcrun.ps1` polls for that.

**Blender exits 0 after a Python traceback** under `-b -P`. Checking the exit
code alone reports success for a script that built nothing. The pipeline
requires the `MDL DONE` marker in the log as well.

**Never compute camera `rotation_euler` by hand.** Hand-rolled aim trig points
at empty ground and the render still "succeeds", which reads as a modelling bug
for an hour before anyone suspects the camera. `mdl` always aims with a
`TRACK_TO` constraint on an empty at the bounding-box centre, and solves the
camera distance from the bounding box rather than guessing it.

**Blender's default AgX view transform desaturates**, and turns flat untextured
grey into mud. `mdl` forces `view_transform = 'Standard'`. Standard *clips*
above 1.0 with no roll-off, so an over-bright light rig does not look bright —
it looks like a white silhouette with no surface detail at all. That is what
the `--light` flag is for.

**`view_layer.update()` after every camera move.** Constraints have not solved
at the moment you set `cam.location`, and the render will use the old aim.

**Clearing an action does not reset a pose.** Blender leaves every pose bone at
whatever it was last evaluated to, so a naive "rest pose" render silently shows
the last baked frame of the animation. `--rest` zeroes the channels by hand.

**`Action.fcurves` is gone in Blender 4.4+.** Keyframes moved to
layer → strip → channelbag(slot). `mdl.action_fcurves` handles both.

**Godot prints an import's complaints exactly once.** Reuse the import cache
and the second run of a broken model is silent and green. The pipeline deletes
the scratch `.godot/` before every verify, which is what makes "zero warnings"
mean something. Verification runs in a throwaway project on the PC, never in
PANOPTICON itself and never on the Mac — **Godot on the Mac steals the
keyboard.**

**Loop mode lives in the `.import` file, not in the `.glb`.**
`assets/models/runner.glb.import` carries `"Run": {"settings/loop_mode": 1}`
along with the `uid://` the scenes reference, so the pipeline leaves that file
alone when it installs a rebuilt model. Verification reports `loop=0` because
the scratch project has no such override; that is expected, not a regression.
Keep the animation's NAME stable or the override stops matching.

**Several agents share this repo and this PC.** Each model therefore gets its
own job directory (`C:\Users\ddd\panopticon-modelling\jobs\<name>\`), its own
copy of `mdl.py`, and its own scheduled-task name. A shared `build.log` /
`build.done` / task name means one agent's run silently eats another's, and it
presents as "blender failed" on a script that is perfectly fine. It cost a run
to find. Expect Blender to take much longer than usual when two builds are in
flight — there is one GPU.

**`C:\dev\panopticon` on the PC is Ryan's play copy.** The pipeline works in
`C:\Users\ddd\panopticon-modelling` and never touches it.

## Current models

| model | build script | notes |
|---|---|---|
| `runner.glb` | `runner_build.py` | 544 tris, 16-joint rig, 21-frame `Run` clip at 30 fps, 1.8 m |
| `rifle.glb` | `rifle_build.py` | no skin, no animation, muzzle at local `(0, 0, -1.150)` |
| `eye.glb` | **none** | predates this pipeline |

Each script's own header states the contract it holds to; the tri budget is in
`<name>.contract.json`. `eye.glb` is still unregenerable — it is the next thing
to reconstruct if it ever needs to change.
