#!/usr/bin/env bash
# One-command release build, run from the Mac.
#
#   tools/build.sh [win|mac|all] [--tag vX.Y.Z]   # default: all
#   tools/build.sh --check                          # templates + presets only
#
# Windows exports on the PC in its scratch worktree C:\dev\verify (checked out
# at this HEAD via a `build` ref; the play copy is never touched) and lands in
# C:\Users\ddd\Desktop\panopticon-builds\<version>\panopticon-win.zip. macOS
# exports headless here into build/<version>/panopticon-mac.zip. Each build is
# smoke-run headless and a row goes to the pod DB `builds` table.
set -euo pipefail
cd "$(dirname "$0")/.."

PC_HOST=panopticon-pc
PC_GODOT='C:\tools\godot\godot.exe'
PC_WORKTREE='C:\dev\verify'
PC_PLAY='C:\dev\panopticon'
PC_OUT_ROOT='C:\Users\ddd\Desktop\panopticon-builds'
POD_DB="${PANOPTICON_POD_DB:-$HOME/Documents/senate/domains/panopticon/data/panopticon.db}"
GODOT="${GODOT:-$(command -v godot || true)}"
ENGINE="$(cat .godot-version)"                       # 4.7.2.stable.official.ed1daf0bf
TPL_VER="$(echo "$ENGINE" | cut -d. -f1-4)"         # 4.7.2.stable
TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/$TPL_VER"
TPL_URL="https://github.com/godotengine/godot/releases/download/${TPL_VER%.stable}-stable/Godot_v${TPL_VER%.stable}-stable_export_templates.tpz"

TARGET=all; TAG=""; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    win|mac|all) TARGET="$1" ;;
    --tag) TAG="$2"; shift ;;
    --check) CHECK=1 ;;
    *) echo "usage: tools/build.sh [win|mac|all] [--tag vX.Y.Z] | --check" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "build.sh: $*" >&2; exit 1; }
mb() { awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }
pc() { ssh "$PC_HOST" "$@"; }

install_mac_templates() {
  echo "-- Mac templates missing; installing $TPL_VER from GitHub"
  local tpz tmp
  tpz="$(mktemp -t godot-templates).tpz"; tmp="$(mktemp -d -t godot-templates)"
  curl --fail --location --silent --show-error --output "$tpz" "$TPL_URL"
  [ "$(stat -f%z "$tpz")" -gt 100000000 ] || die "template download is not a ~1 GB tpz (got $(stat -f%z "$tpz") bytes)"
  unzip -q "$tpz" -d "$tmp"
  mkdir -p "$(dirname "$TPL_DIR")"
  mv "$tmp/templates" "$TPL_DIR"
  rm -rf "$tpz" "$tmp"
}

# --- checks -----------------------------------------------------------------
FAILED=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; FAILED=1; }

check_mac() {
  [ -n "$GODOT" ] && [ -x "$GODOT" ] || { bad "no godot on PATH (set GODOT=)"; return; }
  local v; v="$("$GODOT" --version 2>/dev/null | tail -1)"
  [ "$v" = "$ENGINE" ] && ok "godot $v" || bad "godot is $v, .godot-version pins $ENGINE"
  if [ ! -f "$TPL_DIR/version.txt" ] && [ "$CHECK" = 0 ]; then install_mac_templates; fi
  [ "$(cat "$TPL_DIR/version.txt" 2>/dev/null)" = "$TPL_VER" ] && ok "Mac templates $TPL_DIR" || bad "Mac templates missing at $TPL_DIR (build.sh installs them on a real build)"
  [ -s "$TPL_DIR/macos.zip" ] && ok "template macos.zip" || bad "template macos.zip missing"
  [ -s tools/ci/export_presets.macos.cfg ] && grep -q '^name="macOS"' tools/ci/export_presets.macos.cfg && ok "preset tools/ci/export_presets.macos.cfg" || bad "macOS preset missing/unnamed"
  grep -q '^textures/vram_compression/import_etc2_astc=true' project.godot && ok "import_etc2_astc=true (universal binary)" || bad "project.godot needs rendering/textures/vram_compression/import_etc2_astc=true"
}

check_common() {
  grep -q '^export/convert_text_resources_to_binary=false' project.godot && ok "convert_text_resources_to_binary=false" || bad "project.godot must set editor/export/convert_text_resources_to_binary=false (binary conversion dropped nodes)"
  [ -s tools/ci/export_presets.windows.cfg ] && grep -q '^name="Windows Desktop"' tools/ci/export_presets.windows.cfg && ok "preset tools/ci/export_presets.windows.cfg" || bad "Windows preset missing/unnamed"
}

check_win() {
  local r
  r="$(pc "Write-Output ('godot=' + (& $PC_GODOT --version | Select-Object -Last 1)); Write-Output ('tpl=' + (Get-Content \$env:APPDATA\\Godot\\export_templates\\$TPL_VER\\version.txt -ErrorAction SilentlyContinue)); Write-Output ('exe=' + (Get-Item \$env:APPDATA\\Godot\\export_templates\\$TPL_VER\\windows_release_x86_64.exe -ErrorAction SilentlyContinue).Length); Write-Output ('wt=' + (git -C $PC_WORKTREE rev-parse --is-inside-work-tree 2>\$null))" 2>/dev/null | tr -d '\r')" || { bad "PC $PC_HOST unreachable"; return; }
  local pv pt pl wt
  pv="$(echo "$r" | sed -n 's/^godot=//p')"; pt="$(echo "$r" | sed -n 's/^tpl=//p')"; pl="$(echo "$r" | sed -n 's/^exe=//p')"; wt="$(echo "$r" | sed -n 's/^wt=//p')"
  [ "$pv" = "$ENGINE" ] && ok "PC godot $pv" || bad "PC godot is '$pv', want $ENGINE"
  [ "$pt" = "$TPL_VER" ] && [ "${pl:-0}" -gt 0 ] && ok "PC templates $TPL_VER (windows_release_x86_64.exe $(mb "$pl"))" || bad "PC templates missing at %APPDATA%\\Godot\\export_templates\\$TPL_VER"
  [ "$wt" = "true" ] && ok "PC worktree $PC_WORKTREE" || bad "PC worktree $PC_WORKTREE is not a git worktree"
}

echo "== check"
check_common
[ "$TARGET" != win ] && check_mac
[ "$TARGET" != mac ] && check_win
[ "$FAILED" = 0 ] || die "checks failed"
[ "$CHECK" = 1 ] && exit 0

# --- version stamp ----------------------------------------------------------
SHA="$(git rev-parse --short=7 HEAD)"
DIRTY=""; [ -z "$(git status --porcelain --untracked-files=no)" ] || DIRTY="-dirty"
if [ -n "$TAG" ]; then VERSION="$TAG-g$SHA$DIRTY"; else VERSION="$(git describe --tags --always)$DIRTY"; fi
[ -z "$DIRTY" ] || echo "!! working tree has uncommitted edits: macOS builds them, Windows builds the committed HEAD ($SHA)"
BUILT_ON="$(date +%Y-%m-%d)"
OUT="build/$VERSION"; mkdir -p "$OUT"
echo "== version $VERSION"

STAMP_BACKUP="$(mktemp -t project.godot)"
cp project.godot "$STAMP_BACKUP"
restore() { cp "$STAMP_BACKUP" project.godot; rm -f "$STAMP_BACKUP" export_presets.cfg; }
trap restore EXIT
if grep -q '^config/version=' project.godot; then
  sed -i '' "s|^config/version=.*|config/version=\"$VERSION\"|" project.godot
else
  sed -i '' "/^config\/name=/a\\
config/version=\"$VERSION\"
" project.godot
fi
grep -q "^config/version=\"$VERSION\"" project.godot || die "version stamp failed"

db_row() {  # platform launched notes
  [ -f "$POD_DB" ] || { echo "  (no pod DB at $POD_DB; row not written)"; return; }
  python3 - "$POD_DB" "$VERSION-$1" "$BUILT_ON" "$SHA" "$1" "$2" "$3" <<'EOF'
import sqlite3, sys
db, tag, built_on, sha, platform, launched, notes = sys.argv[1:]
c = sqlite3.connect(db)
c.execute(
    "INSERT INTO builds(tag, built_on, commit_sha, platform, launched, headless_match_passed, notes) "
    "VALUES(?,?,?,?,?,0,?) ON CONFLICT(tag) DO UPDATE SET built_on=excluded.built_on, "
    "commit_sha=excluded.commit_sha, launched=excluded.launched, notes=excluded.notes",
    (tag, built_on, sha, platform, int(launched), notes))
c.commit()
print(f"  db    {db} builds.tag={tag}")
EOF
}

T0=$SECONDS
# --- Windows (on the PC) ----------------------------------------------------
if [ "$TARGET" != mac ]; then
  echo "== windows (via $PC_HOST, $PC_WORKTREE)"
  PLAY_BEFORE="$(pc "git -C $PC_PLAY status --porcelain" | tr -d '\r')"
  git push -q -f pc "HEAD:refs/heads/build"
  pc "git -C $PC_WORKTREE checkout -q --detach refs/heads/build; git -C $PC_WORKTREE clean -fdq; git -C $PC_WORKTREE log --oneline -1" | tr -d '\r' | sed 's/^/  at    /'
  scp -q tools/ci/export_presets.windows.cfg "$PC_HOST:$PC_WORKTREE\\export_presets.cfg"
  scp -q project.godot "$PC_HOST:$PC_WORKTREE\\project.godot"
  scp -q tools/ci/export_windows.ps1 "$PC_HOST:$PC_WORKTREE\\tools\\ci\\export_windows.ps1"
  TW=$SECONDS
  WIN_LOG="$OUT/win-export.out"
  set +e
  pc "powershell -NoProfile -ExecutionPolicy Bypass -File $PC_WORKTREE\\tools\\ci\\export_windows.ps1 -Version '$VERSION' -Godot '$PC_GODOT' -Worktree '$PC_WORKTREE' -OutRoot '$PC_OUT_ROOT'" 2>&1 | tr -d '\r' >"$WIN_LOG"
  WIN_STATUS=$?
  set -e
  grep -v '^WIN_' "$WIN_LOG" | sed 's/^/  /' || true
  [ "$WIN_STATUS" = 0 ] || die "Windows export failed (exit $WIN_STATUS, see $WIN_LOG)"
  WIN_ZIP="$(sed -n 's/^WIN_ZIP=//p' "$WIN_LOG")"; WIN_ZIP_BYTES="$(sed -n 's/^WIN_ZIP_BYTES=//p' "$WIN_LOG")"
  WIN_EXE_BYTES="$(sed -n 's/^WIN_EXE_BYTES=//p' "$WIN_LOG")"; WIN_PCK_BYTES="$(sed -n 's/^WIN_PCK_BYTES=//p' "$WIN_LOG")"
  WIN_SMOKE="$(sed -n 's/^WIN_SMOKE=//p' "$WIN_LOG")"
  [ "$WIN_SMOKE" = ok ] || die "Windows smoke: $WIN_SMOKE"
  PLAY_AFTER="$(pc "git -C $PC_PLAY status --porcelain" | tr -d '\r')"
  [ "$PLAY_BEFORE" = "$PLAY_AFTER" ] || die "PC play copy $PC_PLAY changed during the build; inspect it"
  WIN_SECS=$((SECONDS - TW))
  echo "  smoke ok (headless, main_menu loaded)  ${WIN_SECS}s"
  db_row windows 1 "$WIN_ZIP ($WIN_ZIP_BYTES bytes; exe $WIN_EXE_BYTES, pck $WIN_PCK_BYTES). Headless smoke: main_menu loaded, exit 0. ${WIN_SECS}s on the PC."
fi

# --- macOS (here, headless) -------------------------------------------------
if [ "$TARGET" != win ]; then
  echo "== macos (local, headless)"
  TM=$SECONDS
  MAC_DIR="$OUT/panopticon-mac"; APP="$MAC_DIR/Panopticon.app"; MAC_ZIP="$OUT/panopticon-mac.zip"; MAC_LOG="$OUT/mac-export.log"
  rm -rf "$MAC_DIR" "$MAC_ZIP"; mkdir -p "$MAC_DIR"
  cp tools/ci/export_presets.macos.cfg export_presets.cfg
  "$GODOT" --headless --path . --import >"$MAC_LOG" 2>&1 || true
  "$GODOT" --headless --path . --export-release "macOS" "$APP" >>"$MAC_LOG" 2>&1 || true
  rm -f export_presets.cfg
  BIN="$APP/Contents/MacOS/Panopticon"
  [ -s "$BIN" ] && [ -s "$APP/Contents/Resources/Panopticon.pck" ] || { tail -30 "$MAC_LOG"; die "macOS export: app binary or pck missing (see $MAC_LOG)"; }
  lipo -info "$BIN" | sed 's/^/  /'
  codesign -dv "$APP" 2>&1 | grep -E '^(Signature|Identifier)' | sed 's/^/  /'
  SMOKE="$OUT/mac-smoke.log"
  set +e; "$BIN" --headless --verbose --quit-after 60 >"$SMOKE" 2>&1; CODE=$?; set -e
  grep -q "Completed load for: 'res://ui/main_menu.tscn'" "$SMOKE" && [ "$CODE" = 0 ] || { tail -20 "$SMOKE"; die "macOS smoke failed (exit $CODE, see $SMOKE)"; }
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$MAC_ZIP"
  [ "$(unzip -Z1 "$MAC_ZIP" | grep -cx 'Panopticon.app/Contents/MacOS/Panopticon')" = 1 ] || die "macOS zip is missing the executable"
  MAC_ZIP_BYTES="$(stat -f%z "$MAC_ZIP")"; MAC_APP_BYTES="$(du -sk "$APP" | cut -f1)"; MAC_APP_BYTES=$((MAC_APP_BYTES * 1024))
  MAC_SECS=$((SECONDS - TM))
  echo "  smoke ok (headless, main_menu loaded)  ${MAC_SECS}s"
  db_row macos 1 "$(pwd)/$MAC_ZIP ($MAC_ZIP_BYTES bytes; app $MAC_APP_BYTES). Universal, ad-hoc signed. Headless smoke: main_menu loaded, exit 0. ${MAC_SECS}s."
fi

echo
echo "== built $VERSION ($SHA) in $((SECONDS - T0))s"
[ "$TARGET" = mac ] || echo "  Windows  $PC_HOST:$WIN_ZIP  $(mb "$WIN_ZIP_BYTES")  (exe $(mb "$WIN_EXE_BYTES"), pck $(mb "$WIN_PCK_BYTES"))"
[ "$TARGET" = win ] || echo "  macOS    $(pwd)/$MAC_ZIP  $(mb "$MAC_ZIP_BYTES")  (app $(mb "$MAC_APP_BYTES"))"
