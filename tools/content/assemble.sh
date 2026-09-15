#!/usr/bin/env bash
# Lay the project's rendered shots out in order, on the PC.
#
#   tools/content/assemble.sh <project>
#
# Writes, in content\<project>\cuts\: beats.txt (one line per shot with its
# timecodes, caption and Ryan's words), list.txt, slates\ and timeline.mp4 (the
# 16:9 master, shots back to back; a devlog gets a 1.5 s working slate before
# each shot); and voice\voice_gap.txt (where the silent gaps are). If DaVinci Resolve is
# installed, also builds a Resolve project of the same name: one video track
# per shot, a marker per shot, placeholder text titles and a muted narration
# track (tools/content/resolve_project.lua through fuscript).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/assemble.sh <project>}"
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
KIND=$(brief_head "${BRIEF}" kind short)
SLATES=$(brief_head "${BRIEF}" slates "$([ "${KIND}" = devlog ] && echo yes || echo no)")
DIR=$(project_dir "${NAME}")
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
