#!/usr/bin/env bash
# Cut a project on the PC: from its ## script table (voice-first), or, for a
# brief without one, the shots back to back (timeline.mp4 + beats.txt).
#
#   tools/content/assemble.sh <project> [--tag NAME] [--no-captions]
#
# With a `## script` table in the brief (the format is in README.md and in
# tools/content/pc/assemble.py), every voice line maps to a clip and a fit:
# the voice decides each slot's length, the picture is trimmed, held, slowed
# or waited for to match, an external clip can carry its own sound in a
# window the music ducks under, and the word captions pop in from
# voice\words.json. Segments are cached per source and per number in
# cuts\_cache\, so re-cutting after a caption, music or voice change encodes
# no video; the caption burn is its own pass. Output: final\<tag>.mp4
# (tag defaults to the project name), cuts\<tag>_timing.txt (the table, printed
# here too) and cuts\<tag>_lines.json. Voice first: tools/content/voice.sh.
#
# Without a script table (the older, gap-based briefs): beats.txt, list.txt,
# slates\ and timeline.mp4 in cuts\, voice\voice_gap.txt, and a Resolve
# project when Resolve is installed -- then render.sh makes the final.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/assemble.sh <project>}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
KIND=$(brief_head "${BRIEF}" kind short)
SLATES=$(brief_head "${BRIEF}" slates "$([ "${KIND}" = devlog ] && echo yes || echo no)")
DIR=$(project_dir "${NAME}")

TAG="${NAME}"; CAPTIONS=""
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --no-captions) CAPTIONS="--no-captions"; shift ;;
    *) die "unknown option $1" ;;
  esac
done
if grep -q '^## script' "${BRIEF}"; then
  T_ALL=$(now_ms)
  pc_layout "${DIR}"
  pc_push "${BRIEF}" "$(ff "${DIR}")/notes/brief.md"
  pc_push "${CONTENT_DIR}/pc/brief.py" "$(ff "${DIR}")/scripts/brief.py"
  pc_push "${CONTENT_DIR}/pc/assemble.py" "$(ff "${DIR}")/scripts/assemble.py"
  pc_push "${CONTENT_DIR}/pc/card.py" "$(ff "${DIR}")/scripts/card.py"
  pc <<EOF
\$ErrorActionPreference = 'Continue'
& '${PC_PYTHON}' '${DIR}\\scripts\\assemble.py' '${DIR}' '${DIR}\\notes\\brief.md' '${TAG}' ${CAPTIONS} 2>&1
EOF
  echo "assemble done in $(since "$T_ALL"): ${DIR}\\final\\${TAG}.mp4"
  exit 0
fi
CUTS="${DIR}\\cuts"
COUNT=$(brief_count "${BRIEF}")
[ "${COUNT}" -gt 0 ] || die "${NAME} has no shots"
T_ALL=$(now_ms)

# --- beats.txt, voice_gap.txt and the concat list, computed from the brief. ----
BEATS=$(mktemp) GAPS=$(mktemp) LIST=$(mktemp) SLATE_TEXT=$(mktemp -d)
printf '# %s\n# n\tstart\tend\tgap_start\tgap_end\tcaption (- is none)\tsaid\n' "${NAME}" > "${BEATS}"
: > "${GAPS}"
T=0
for n in $(seq 1 "${COUNT}"); do
  NN=$(pad2 "${n}")
  SECS=$(brief_field "${BRIEF}" "${n}" seconds 6)
  GAP=$(brief_field "${BRIEF}" "${n}" gap 0)
  AT=$(brief_field "${BRIEF}" "${n}" at)
  STILL=$(brief_field "${BRIEF}" "${n}" still)
  CAPTION=$(brief_field "${BRIEF}" "${n}" caption -)   # "-" is no caption: an empty tab field would collapse
  SAID=$(brief_field "${BRIEF}" "${n}" said)
  # A still is held for `hold`; a before/after pair plays `seconds` twice.
  LEN=$(python3 -c "print(${SECS} + ${GAP})")
  [ -n "${STILL}" ] && LEN=$(brief_field "${BRIEF}" "${n}" hold 3)
  [ -n "${AT}" ] && LEN=$(python3 -c "print(2 * ${SECS} + ${GAP})")
  if [ "${SLATES}" = yes ]; then
    printf '%s\n' "${NN}  ${SAID}" > "${SLATE_TEXT}/${NN}.txt"
    echo "file 'slates/${NN}.mp4'" >> "${LIST}"
    T=$(python3 -c "print(${T} + 1.5)")
  fi
  START=${T}
  END=$(python3 -c "print(${T} + ${LEN})")
  GAP_START=$(python3 -c "print(${END} - ${GAP})")
  printf '%s\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%s\n' "${n}" "${START}" "${END}" "${GAP_START}" "${END}" "${CAPTION}" "${SAID}" >> "${BEATS}"
  if python3 -c "import sys; sys.exit(0 if ${GAP} > 0 else 1)"; then
    printf 'shot %s: silent from %.2f s for %.2f s (voice_%s.wav goes here)\n' "${NN}" "${GAP_START}" "${GAP}" "${NN}" >> "${GAPS}"
  fi
  echo "file '${NN}.mp4'" >> "${LIST}"
  T=${END}
done
printf '# total %.2f s\n' "${T}" >> "${BEATS}"

pc_layout "${DIR}"
pc <<EOF
New-Item -ItemType Directory -Force -Path '${CUTS}\\slates' | Out-Null
EOF
pc_push "${BEATS}" "$(ff "${CUTS}")/beats.txt"
pc_push "${GAPS}" "$(ff "${DIR}")/voice/voice_gap.txt"
pc_push "${LIST}" "$(ff "${CUTS}")/list.txt"
if [ "${SLATES}" = yes ]; then
  for f in "${SLATE_TEXT}"/*.txt; do pc_push "${f}" "$(ff "${CUTS}")/slates/$(basename "${f}")"; done
fi
rm -rf "${BEATS}" "${GAPS}" "${LIST}" "${SLATE_TEXT}"

# --- timeline.mp4 --------------------------------------------------------------
T0=$(now_ms)
pc <<EOF
\$ErrorActionPreference = 'Stop'
\$dir = '${CUTS}'
\$slash = \$dir -replace '\\', '/' -replace ':', '\\:'   # a filter string reads backslashes as escapes
\$missing = @()
foreach (\$line in Get-Content "\$dir\\list.txt") {
  \$rel = \$line -replace "^file '", '' -replace "'$", ''
  if (\$rel -like 'slates/*') {
    \$nn = [IO.Path]::GetFileNameWithoutExtension(\$rel)
    ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=black:s=1280x720:r=${FPS}:d=1.5" -f lavfi -i "anullsrc=r=48000:cl=stereo" -t 1.5 -vf "drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':textfile='\$slash/slates/\$nn.txt':fontcolor=white:fontsize=30:x=60:y=h-120" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -shortest "\$dir\\slates\\\$nn.mp4"
  } elseif (-not (Test-Path "\$dir\\\$rel")) { \$missing += \$rel }
}
if (\$missing) { Write-Output ("missing shots: " + (\$missing -join ', ') + " -- run tools/content/shot.sh for them"); exit 3 }
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "\$dir\\list.txt" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -r ${FPS} -c:a aac -ar 48000 -b:a 160k "\$dir\\timeline.mp4"
\$len = ffprobe -v error -show_entries format=duration -of csv=p=0 "\$dir\\timeline.mp4"
Write-Output ("timeline.mp4 " + [math]::Round([double]\$len, 2) + " s")
Get-Content '${DIR}\\voice\\voice_gap.txt'
EOF
echo "assemble: timeline $(since "$T0")"

# --- DaVinci Resolve project, when Resolve is installed. -----------------------
T0=$(now_ms)
pc_push "${CONTENT_DIR}/resolve_project.lua" "$(ff "${DIR}")/scripts/resolve_project.lua"
pc <<EOF
if (-not (Test-Path '${PC_RESOLVE}')) { Write-Output 'resolve: not installed; timeline.mp4 and beats.txt are the edit'; exit 0 }
if (-not (Get-Process -Name Resolve -ErrorAction SilentlyContinue)) {
  Start-Process '${PC_RESOLVE}' -ArgumentList '-nogui' | Out-Null
  Start-Sleep -Seconds 25
}
\$env:PANOPTICON_PROJECT_DIR = '${CUTS}'
\$env:PANOPTICON_PROJECT_NAME = '${NAME}'
& '${PC_FUSCRIPT}' -l lua '${DIR}\\scripts\\resolve_project.lua' 2>&1 | Select-Object -Last 8
EOF
echo "assemble: resolve $(since "$T0")"
echo "assemble done in $(since "$T_ALL"): ${CUTS}\\timeline.mp4"
