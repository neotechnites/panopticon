#!/usr/bin/env bash
# ragdoll_short M2 as a real Godot-editor take: this branch synced to the short's PC checkout, a scrubbed throwaway
# copy opened in the editor on characters/death_editor.tscn (editor.ps1), the Death clip triggered, the whole screen
# recorded; the cut is the central 9:16 slice of the 3D viewport, in at the fall minus 0.95 s (v14's beat), 3.6 s.
#
#   tools/content/projects/ragdoll_short/editor/take.sh <tag> [--eye x,y,z] [--at x,y,z] [--fov N] [--seconds S] [--go S]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "${HERE}/../../../lib.sh"
TAG="${1:?usage: take.sh <tag> [--eye x,y,z] [--at x,y,z] [--fov N] [--seconds S] [--go S]}"; shift
EYE="0, 2.1, 4.1"; AT="0, 0.65, 0"; FOV=40; SECONDS_=9; GO=4; LEAD=0.95; CUT=3.6
while [ $# -gt 0 ]; do
  case "$1" in --eye) EYE="$2";; --at) AT="$2";; --fov) FOV="$2";; --seconds) SECONDS_="$2";; --go) GO="$2";; *) die "unknown option $1";; esac
  shift 2
done
pc_use_project ragdoll_short
DIR=$(project_dir ragdoll_short)
PROOF="${HOME}/Desktop/panopticon-renders/_work/proofs/short4_editor/${TAG}"
mkdir -p "${PROOF}"
"${CONTENT_DIR}/sync.sh"
KIT="${DIR}\\scripts\\editor"; TAKE="${DIR}\\takes\\editor_${TAG}.avi"; COPY='C:\dev\worktrees\ragdoll_editor'
pc_layout "${DIR}"
pc <<PS
New-Item -ItemType Directory -Force -Path '${KIT}' | Out-Null
PS
TMP=$(mktemp -d)
sed -e "s/@EYE@/${EYE}/" -e "s/@AT@/${AT}/" -e "s/@FOV@/${FOV}/" "${HERE}/frame.gd" > "${TMP}/frame.gd"
pc_push "${TMP}/frame.gd" "$(ff "${KIT}")/frame.gd"
pc_push "${HERE}/death_editor.tscn" "$(ff "${KIT}")/death_editor.tscn"
pc_push "${HERE}/editor.ps1" "$(ff "${KIT}")/editor.ps1"
python3 - "${TMP}/job.json" "${PC_PROJECT}" "${COPY}" "${KIT}" "${TAKE}" "${SECONDS_}" "${GO}" "${DIR}" "${TAG}" <<'PY'
import json, sys
p = sys.argv
json.dump({"src": p[2], "copy": p[3], "kit": p[4], "scene": "res://characters/death_editor.tscn", "take": p[5],
           "seconds": float(p[6]), "go_at": float(p[7]), "log": p[8] + "\\notes\\editor_" + p[9] + ".log"}, open(p[1], "w"))
PY
pc_push "${TMP}/job.json" "$(ff "${KIT}")/job_${TAG}.json"
pc_lock_take "editor take ragdoll_short ${TAG}" 400
T0=$(now_ms)
pc <<PS
& powershell -NoProfile -ExecutionPolicy Bypass -File '${KIT}\\editor.ps1' -Job '${KIT}\\job_${TAG}.json'
Get-Content '${TAKE}.json' -Raw
PS
pc_unlock_take
echo "take: $(since "${T0}")"
pc_pull "$(ff "${TAKE}").json" "${PROOF}/take.json"
pc_pull "$(ff "${TAKE}").listing.txt" "${PROOF}/listing.txt"
python3 -c "import json,sys; j=json.load(open('${PROOF}/take.json', encoding='utf-8-sig')); sys.exit(0 if j.get('ok') else ('take failed: ' + str(j.get('error'))))"
read -r CX CY CW CH <<< "$(python3 -c "
import json; f = json.load(open('${PROOF}/take.json', encoding='utf-8-sig'))['framing']
ch = int(f['vh']) // 2 * 2; cw = int(round(ch * 9 / 16)) // 2 * 2
print(int(f['vx']) + (int(f['vw']) - cw) // 2, int(f['vy']), cw, ch)")"
echo "viewport slice: ${CW}x${CH} at ${CX},${CY}"
# The fall: the first frame after 1 s whose difference from the one before it is not still.
pc <<PS
cmd /c "ffmpeg -hide_banner -nostats -i ${TAKE} -vf crop=${CW}:${CH}:${CX}:${CY},scale=64:-2,format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG -f null - 2> ${DIR}\\takes\\editor_${TAG}.diff.txt"
PS
pc_pull "$(ff "${DIR}")/takes/editor_${TAG}.diff.txt" "${PROOF}/diff.txt"
ONSET=$(python3 - "${PROOF}/diff.txt" <<'PY'
import re, sys
t = None; onset = None
for line in open(sys.argv[1]):
    m = re.search(r"pts_time:([0-9.]+)", line)
    if m: t = float(m.group(1)); continue
    m = re.search(r"YAVG=([0-9.]+)", line)
    if m and t is not None and t > 1.0 and float(m.group(1)) > 0.8 and onset is None:
        onset = t
print("" if onset is None else "%.4f" % onset)
PY
)
[ -n "${ONSET}" ] || die "no fall found in the take (diff.txt in ${PROOF})"
IN=$(python3 -c "print(max(0.0, ${ONSET} - ${LEAD}))")
echo "fall at ${ONSET} s of the take; cut in at ${IN} s for ${CUT} s"
pc <<PS
ffmpeg -hide_banner -loglevel error -y -ss ${IN} -i '${TAKE}' -t ${CUT} -vf "crop=${CW}:${CH}:${CX}:${CY},scale=1080:1920:flags=lanczos" -r ${FPS} -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p -movflags +faststart '${DIR}\\cuts\\02_${TAG}.mp4'
ffmpeg -hide_banner -loglevel error -y -i '${DIR}\\cuts\\02_${TAG}.mp4' -vf "fps=5,scale=180:-2,tile=9x2" -frames:v 1 '${DIR}\\takes\\editor_${TAG}_cut.png'
ffmpeg -hide_banner -loglevel error -y -ss ${ONSET} -i '${TAKE}' -frames:v 1 '${DIR}\\takes\\editor_${TAG}_screen.png'
ffmpeg -hide_banner -loglevel error -y -ss ${IN} -i '${TAKE}' -frames:v 1 '${DIR}\\takes\\editor_${TAG}_screen0.png'
PS
pc_pull "$(ff "${DIR}")/takes/editor_${TAG}_cut.png" "${PROOF}/cut_tile.png"
pc_pull "$(ff "${DIR}")/takes/editor_${TAG}_screen.png" "${PROOF}/screen_fall.png"
pc_pull "$(ff "${DIR}")/takes/editor_${TAG}_screen0.png" "${PROOF}/screen_in.png"
rm -rf "${TMP}"
echo "cut: ${DIR}\\cuts\\02_${TAG}.mp4; proofs in ${PROOF}"
