# Building the Windows and macOS executables

First produced 2026-09-10 from commit `f0efb32`. This records what actually
works, not what ought to.

## Engine and templates

The engine version is pinned in `.godot-version`:

    4.7.2.stable.official.ed1daf0bf

Export templates **must** be the same build. Mismatched templates fail in ways
that read as project bugs.

Godot expects them at:

| OS      | Path                                                                   |
|---------|------------------------------------------------------------------------|
| macOS   | `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`    |
| Linux   | `~/.local/share/godot/export_templates/4.7.2.stable/`                   |
| Windows | `%APPDATA%\Godot\export_templates\4.7.2.stable\`                        |

The directory name is `4.7.2.stable` — version and channel, no `.official`
suffix. It contains a `version.txt` reading `4.7.2.stable` and ~1.9 GB of
per-platform templates. `windows_release_x86_64.exe` is the one this build uses.

If they are missing, fetch them from the GitHub release assets for the exact
tag rather than the Godot download host:

    curl --fail --location --output templates.tpz \
      https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz

The `.tpz` is a zip whose contents live under `templates/`; move that directory
to the path above and rename it `4.7.2.stable`. **Verify the download is ~1 GB
of binary, not a few KB of HTML** — download hosts behind Cloudflare return an
interstitial page with a 200 status, and Godot will then report templates as
present-but-corrupt.

## The preset

`export_presets.cfg` is **gitignored on purpose** and is not the source of
truth. The reviewed source is:

    tools/ci/export_presets.windows.cfg

It is copied into place immediately before exporting. The Godot editor rewrites
`export_presets.cfg` on every visit to the export dialog and accumulates local
absolute paths, so a committed one is a merge conflict and a path leak. See that
file's header comment.

## Commands

Run from the project root. The import step is not optional — without it every
`class_name` resolves to an unknown type and everything downstream fails with
hundreds of meaningless errors.

    godot --headless --path . --import
    godot --headless --path . --script res://tools/audit_warnings.gd
    godot --headless --path . --script res://tools/run_tests.gd

    cp tools/ci/export_presets.windows.cfg export_presets.cfg
    mkdir -p build/windows
    godot --headless --path . --export-release "Windows Desktop" build/windows/panopticon.exe

Godot's exporter has been known to report failure and still exit 0, so check the
artifacts, not the exit code:

    test -s build/windows/panopticon.exe
    test -s build/windows/panopticon.pck

## Output

`build/windows/` (gitignored via the `/build/` rule):

| File             | Size    |
|------------------|---------|
| `panopticon.exe` | ~104 MB |
| `panopticon.pck` | ~503 KB |

The `.exe` is the engine template; all game content is in the `.pck`. The pack
holds 274 files. `embed_pck` is deliberately off — two files is what a Steam
depot upload expects, and an embedded pack makes the exe opaque to a hash-based
patcher. Both files must ship together.

`tests/*` and `tools/*` are excluded by the preset's `exclude_filter`, so the
shipped build contains no test suite and no harness scripts.

## Cross-compiling

The export does not need Windows. This build was produced on macOS and CI
produces the same artifact on Linux. Only `application/modify_resources`
requires a Windows-specific tool (`rcedit`), and it is currently off.

## Verifying a build actually runs

"Done" means a build that ran. Headless is enough to prove the pack loads and
the main scene instantiates:

    panopticon.exe --headless --verbose --quit-after 120

Look for `Completed load for: 'res://scenes/ui/main_menu.tscn'` and exit code 0.

## What bit us

**A Windows OpenSSH session has no GPU context.** Launching the game windowed
over plain `ssh` fails with:

    WARNING: Your video card drivers seem not to support the required OpenGL 3.3 version, switching to ANGLE.
    ERROR: Failed to create ANGLE OpenGL window.

This is the SSH session, not the build. To run windowed on the real desktop,
push it into the logged-on console session with a scheduled task:

    schtasks /create /tn PanopticonGuiRun /tr "C:\path\run_gui.bat" /sc once /st 23:59 /ru <user> /it /f
    schtasks /run /tn PanopticonGuiRun
    schtasks /delete /tn PanopticonGuiRun /f

`/it` is the flag that matters — it runs in the interactive session. In that
session the game reports a real device and exits 0:

    OpenGL API 3.3.0 Core Profile Context 26.8.1.260806 - Compatibility - Using Device: ATI Technologies Inc. - AMD Radeon RX 6600 XT

**The renderer is GL Compatibility and that is deliberate**, pinned for
install-base reach. Do not change it.

## Building the macOS app

Export templates go at
`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`, fetched
the same way as the Windows ones above.

The preset is `tools/ci/export_presets.macos.cfg`, copied into place as
`export_presets.cfg` immediately before exporting, same rule as Windows.

    cp tools/ci/export_presets.macos.cfg export_presets.cfg
    godot --headless --path . --import
    mkdir -p build/panopticon-mac
    godot --headless --path . --export-release "macOS" build/panopticon-mac/Panopticon.app

The preset builds a **universal binary** (x86_64 + arm64) with **ad-hoc code
signing** (`codesign/codesign=1`, built-in `/usr/bin/codesign`, no Xcode or
`rcodesign` needed) and **no notarisation**. Ad-hoc signing is not optional:
an unsigned arm64 binary will not execute on Apple Silicon at all.

A universal export also requires ETC2/ASTC texture import enabled in project
settings (`rendering/textures/vram_compression/import_etc2_astc=true`) or the
exporter refuses to build for arm64.

Verify with `lipo -info` and `codesign -dv`:

    lipo -info build/panopticon-mac/Panopticon.app/Contents/MacOS/Panopticon
    codesign -dv --verbose=2 build/panopticon-mac/Panopticon.app

**Never run the exported app with a window on the Mac that built it** — same
keyboard-stealing problem as the editor. Verify headless instead:

    build/panopticon-mac/Panopticon.app/Contents/MacOS/Panopticon --headless --verbose --quit-after 60

Look for `Completed load for: 'res://scenes/ui/main_menu.tscn'` and exit code 0.

**Friends opening the app will hit Gatekeeper.** It is ad-hoc signed, not
notarised, so macOS blocks the first launch ("cannot be opened because the
developer cannot be verified"). Tell them: right-click (or Control-click) the
app and choose **Open**, then confirm in the dialog. This is only needed the
first time.
