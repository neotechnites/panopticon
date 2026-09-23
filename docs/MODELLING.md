# Modelling

How a 3D model gets made for PANOPTICON: authored on the Mac, built on
whichever box has Blender, looked at on the Mac, and proved in Godot before it
is allowed anywhere near `assets/models/`.

This exists because the expensive part of modelling was never the geometry. It
was that **the agent could not see what it had made**, so it iterated on
arithmetic and waited for a human to say "still wrong".

The second expensive part was the round trip. Every look used to cross the
network to the PC and back, and every model, referenced by a scene or not, then
paid for the whole game suite and the bot harness. That is four minutes to move
a bush half a metre. One look now costs seconds, on this machine, and a prop no
scene loads is gated on what can actually observe it.

## The fast loop

This is the default way to build a prop. Write, build, one preview, look, change
a number, again:

    tools/modelling/model build bush --preview     # glb + 3 quarter-res views

Full renders and the full gate are a **final pass**, run once, at the end:

    tools/modelling/model build bush --prop        # full sheet, verify, install, gate

`--preview` is a look, not a delivery: it renders at a quarter resolution with
no denoise and stands a 1.8 m human proxy next to the model for scale, and it
neither verifies against the contract nor installs over the shipped `.glb`.

## The five stages

| | | |
|---|---|---|
| **Author** | `tools/modelling/<name>_build.py` | in the repo, tunables in one block at the top |
| **Run** | `tools/modelling/model build <name>` | Blender headless, on this Mac if it is installed here |
| **See** | `~/Desktop/panopticon-renders/` | EEVEE, standard views or any angle |
| **Verify** | Godot headless | imports the `.glb`, checks it against a contract |
| **Gate** | the gate the model has earned | audit only, or the whole suite — decided by grep |
| **Deliver** | `assets/models/<name>.glb` | only if verification passed |

## Where it builds

Blender on the Mac is the default the moment it is installed:

    brew install --cask blender

Keep it on the **same Blender series as the PC** — `model doctor` prints both
(5.2.2 on the Mac against 5.2.1 on the PC produces identical bytes; a different
major version would change the glTF exporter and therefore every file). The
real test is `model parity <name>`, not the version string. The PC is the
automatic fallback
when there is no Mac Blender, and `--pc` forces it; nothing else changes — same
build script, same spec JSON, same `mdl.py`, and for most models the same bytes
out. `model parity <name>` builds on both boxes and compares them byte for byte.

## Commands

Run from the repo root.

    tools/modelling/model build <name> --preview  # the fast loop: 3 quarter-res views, seconds
    tools/modelling/model build <name>            # the whole pipeline, installs the model
    tools/modelling/model build <name> --prop     # ...and run the gate the model has earned
    tools/modelling/model look  <name>            # renders only: no verify, no install
    tools/modelling/model verify <name>           # re-check the .glb already in assets/models/
    tools/modelling/model audit  <name>           # contiguity and quality of the shipped .glb
    tools/modelling/model refs   <name>           # which scenes reference it (this picks the gate)
    tools/modelling/model gate   <name>           # run that gate without rebuilding
    tools/modelling/model parity <name>           # do the Mac and the PC produce the same bytes?
    tools/modelling/model views                   # list the named views
    tools/modelling/model open                    # reveal the renders in Finder
    tools/modelling/model doctor                  # both toolchains, and is the PC reachable

Options for `build` and `look`:

| flag | |
|---|---|
| `--variant V` | build `<name>_V` from `<name>_build.py`; also on `verify`, one contract covers all variants |
| `--views front,side,threequarter` | named views; default is those three |
| `--cam AZ,EL[,LENS]` | any angle, repeatable |
| `--turntable N` | N shots evenly around |
| `--frame N` | pose an animated rig at frame N before rendering |
| `--rest` | rest pose, action cleared — for debugging a rig |
| `--res WxH` | fixed frame size; default shapes each frame to the subject |
| `--samples N`, `--light W`, `--margin M` | render quality, key light watts, framing slack |
| `--preview` | the fast loop: `threequarter`, `front` and `eye` at quarter resolution, no denoise, scale proxy; no verify, no install |
| `--prop` | after installing, run the gate this model has earned (see below) |
| `--local`, `--pc` | force the backend instead of letting it be chosen |
| `--cpu` | Cycles on CPU instead of EEVEE on GPU |
| `--no-verify`, `--no-install`, `--keep` | skip stages; `--keep` archives a timestamped copy |

Azimuth 0 is the model's own front; elevation is degrees above the horizon.
`--cam 215,22` and the named view `hero` are the same thing.

## The gate a model has earned

`tools/test.sh` and the bot harness cannot observe a `.glb` that no scene loads.
Running them for a new prop proves nothing and costs four minutes, which is why
the prop loop used to be measured in tens of minutes. So the gate is chosen, not
argued:

| | |
|---|---|
| **nothing references it** | the contract check, `lib/glb_audit.py`, and the Godot import check |
| **a scene references it** | all of that, then `bash tools/test.sh` **and** the bot harness, every time |

Which one applies is not a judgement call and there is no flag to override it.
`lib/scene_refs.sh <name>` greps `scenes/`, `scripts/`, `resources/` and
`project.godot` for both spellings a scene can use — the path
`assets/models/<name>.glb` and the `uid://` its `.import` file carries — and
`model build <name> --prop` runs whichever gate that answer names. A `.tscn`
saved by the editor carries the uid and not the path, so grepping for the
filename alone quietly answers "no" for a model half the map uses; that is why
the uid is in there.

The moment a scene references the model, the full gate is mandatory. Wiring a
prop into a scene is therefore the change that carries the suite, not the build
that made the prop.

`lib/glb_audit.py` parses the `.glb` itself — no Blender, no Godot, hundredths
of a second — and reports triangles, vertices, connected components after
welding, duplicate positions and degenerate triangles, art and collision
separately. It is the contiguity audit: a `.glb` can import perfectly and still
be five loose shells.

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

Map meshes texture through `lib/texel.py`: one tiling sheet per material
class (`Sheet`), painted on a wrapping canvas so it has no seam, sampled
REPEAT, and projected in world cylindrical coordinates at one metres-per-texel
(`texel.MPT`, 0.05) so texels are the same size everywhere and the only UV
seams are corners. No atlas, so nothing bleeds at any mip. `texel.preview`
writes a sheet as a tiled PNG without Blender: that is the painter's fast loop.

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

**arm64 and x86-64 do not always build the same model.** `torch`, `boulder` and
`marble_bars` come off the Mac byte-for-byte identical to the PC. `forest_tree`
does not: 323 bytes of 889,312 differ, all of them in the *geometry* buffers,
because the script picks quads with `sorted(key=...)` on a floating-point dot
product and the two machines land on opposite sides of a tie. The models are
deterministic on each box and different between them. So: `model parity <name>`
before you trust a local build of anything that ships, and `--pc` for the final
build of a script that fails it. `lib/glb_diff.py` says whether the difference is
geometry (a different model) or painted texels (the same shape).

**The Windows paths used to be called `$BLENDER` and `$GODOT`.** The moment the
Mac backend read `${GODOT:-…}` for its own binary, the script's own `GODOT`
shadowed the environment and every local verification ran `C:\tools\godot\godot.exe`
on macOS. It presented as "godot verification FAILED" with an empty log. They
are `PC_BLENDER` and `PC_GODOT` now.

**Blender's UV sphere does not emit its faces in a stable order.** The same
`eye_build.py`, run six times on one Mac with nothing changed, produced five
different index arrays for `Eye_Sclera_Mesh`. The vertex POSITIONS were
identical every time and so was the set of 528 triangles — only the order the
triangles are listed in varies, and it varies per longitude column, by a
different cyclic rotation each run. It is below the API: `bmesh`'s uvsphere
hands the exporter a scrambled face order and the exporter faithfully preserves
it. So `model parity eye` can never pass, a byte-for-byte rebuild of anything
containing `primitive_uv_sphere_add` is not a thing, and the honest proof for
such a model is positions elementwise, node transforms exactly, and the
triangle multiset — not the bytes. `lib/glb_audit.py` and the contract check
both see through it; a naive `cmp` does not.

**`C:\dev\panopticon` on the PC is Ryan's play copy.** The pipeline works in
`C:\Users\ddd\panopticon-modelling` and never touches it.

## Current models

| model | build script | notes |
|---|---|---|
| `runner.glb` | `runner_build.py` | 544 tris, 16-joint rig, 21-frame `Run` clip at 30 fps, 1.8 m |
| `rifle.glb` | `rifle_build.py` | no skin, no animation, muzzle at local `(0, 0, -1.150)` |
| `eye.glb` | `eye_build.py` | 768 tris, 3 nodes, no rig; the sclera's exported triangle ORDER is not reproducible (see below) |

Each script's own header states the contract it holds to; the tri budget is in
`<name>.contract.json`.
