#!/usr/bin/env bash
# Render the deliverable from timeline.mp4 on the PC: aspect, captions, voice.
#
#   tools/content/render.sh <project> [--still]
#
# Header fields: aspect (9:16 | 16:9), frame (crop | letterbox, for 9:16). Each
# shot's caption: line becomes a lower third for that shot's duration -- plain
# white text, the kind a player would type; nothing else is drawn. Every
# voice_NN.wav in the project folder is laid at shot NN's gap. Output:
# final.mp4, or final__speak-at-<t>s-for-<g>s.mp4 while a gap still has no
# recording, so the filename says when to talk. --still pulls one frame to the Mac.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

PROJECT="${1:?usage: tools/content/render.sh <project> [--still]}"
WANT_STILL=0; [ "${2:-}" = "--still" ] && WANT_STILL=1
BRIEF=$(brief_path "${PROJECT}")
NAME=$(basename "${BRIEF}" .md)
KIND=$(brief_head "${BRIEF}" kind short)
[ "${KIND}" = devlog ] && FOLDER=devlogs || FOLDER=shorts
ASPECT=$(brief_head "${BRIEF}" aspect "$([ "${KIND}" = devlog ] && echo 16:9 || echo 9:16)")
FRAME=$(brief_head "${BRIEF}" frame crop)
DIR="${PC_CONTENT}\\${FOLDER}\\${NAME}"
COUNT=$(brief_count "${BRIEF}")
T_ALL=$(now_ms)

# Geometry: the 720p master to the delivery frame.
case "${ASPECT}" in
  9:16)
    if [ "${FRAME}" = letterbox ]; then
      GEOMETRY="scale=1080:-2,pad=1080:1920:(ow-iw)/2:(oh-ih)/2"
    else
      GEOMETRY="crop=ih*9/16:ih,scale=1080:1920"
    fi
    CAPTION_SIZE=54; CAPTION_Y="h*0.74" ;;
  16:9) GEOMETRY="scale=1920:1080"; CAPTION_SIZE=48; CAPTION_Y="h*0.80" ;;
  *) die "aspect must be 9:16 or 16:9" ;;
esac

# Captions and voice offsets come from beats.txt (assemble.sh wrote it).
BEATS=$(mktemp)
pc_pull "$(ff "${DIR}")/beats.txt" "${BEATS}"
FILTER="[0:v]${GEOMETRY}"
CAPTIONS=$(mktemp -d)
GAP_MARK=""
DIR_FF=$(ff "${DIR}" | sed 's/:/\\:/')
while IFS=$'\t' read -r n start end gap_start gap_end caption said; do
  [[ "${n}" =~ ^[0-9]+$ ]] || continue
  NN=$(pad2 "${n}")
  if [ -n "${caption}" ] && [ "${caption}" != "-" ]; then
    printf '%s' "${caption}" > "${CAPTIONS}/${NN}.txt"
    pc_push "${CAPTIONS}/${NN}.txt" "$(ff "${DIR}")/caption_${NN}.txt"
    FILTER="${FILTER},drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':textfile='${DIR_FF}/caption_${NN}.txt':fontcolor=white:shadowcolor=black@0.7:shadowx=2:shadowy=2:fontsize=${CAPTION_SIZE}:x=(w-text_w)/2:y=${CAPTION_Y}:enable='between(t,${start},${end})'"
  fi
  if [ -z "${GAP_MARK}" ] && python3 -c "import sys; sys.exit(0 if ${gap_end} > ${gap_start} else 1)"; then
    GAP_MARK="__speak-at-${gap_start}s-for-$(python3 -c "print('%g' % (${gap_end} - ${gap_start}))")s"
  fi
done < "${BEATS}"
rm -rf "${BEATS}" "${CAPTIONS}"
FILTER="${FILTER}[vout]"

T0=$(now_ms)
pc <<EOF
\$ErrorActionPreference = 'Stop'
\$dir = '${DIR}'
\$voices = @()
\$inputs = @()
\$mix = ''
\$k = 0
foreach (\$w in (Get-ChildItem "\$dir\\voice_*.wav" -ErrorAction SilentlyContinue | Sort-Object Name)) {
  \$nn = \$w.BaseName -replace 'voice_', ''
  \$beat = Get-Content "\$dir\\beats.txt" | Where-Object { \$_ -match "^\$([int]\$nn)\`t" } | Select-Object -First 1
  if (-not \$beat) { continue }
  \$gap = [double](\$beat -split "\`t")[3]
  \$k += 1
  \$inputs += @('-i', \$w.FullName)
  \$mix += ('[{0}:a]adelay={1}|{1}[v{0}];' -f \$k, [int](\$gap * 1000))
  \$voices += \$nn
}
if (\$k -gt 0) {
  \$refs = (1..\$k | ForEach-Object { "[v\$_]" }) -join ''
  \$afilter = "[0:a]volume=1.0[game];" + \$mix + "[game]" + \$refs + "amix=inputs=" + (\$k + 1) + ":duration=first:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11[aout]"
  \$out = "\$dir\\final.mp4"
} else {
  \$afilter = "[0:a]loudnorm=I=-16:TP=-1.5:LRA=11[aout]"
  \$out = "\$dir\\final${GAP_MARK}.mp4"
}
Remove-Item "\$dir\\final*.mp4" -ErrorAction SilentlyContinue
ffmpeg -hide_banner -loglevel error -y -i "\$dir\\timeline.mp4" @(\$inputs) -filter_complex "${FILTER};\$afilter" -map '[vout]' -map '[aout]' -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p -r ${FPS} -c:a aac -ar 48000 -b:a 192k -movflags +faststart \$out
\$len = ffprobe -v error -show_entries format=duration -of csv=p=0 \$out
Write-Output ("final: " + \$out + " " + [math]::Round([double]\$len, 2) + " s, voices: " + (\$voices -join ',' ))
if (${WANT_STILL} -eq 1) {
  ffmpeg -hide_banner -loglevel error -y -ss ([double]\$len * 0.4) -i \$out -frames:v 1 "\$dir\\final_still.png"
}
EOF
echo "render: $(since "$T0")"
if [ "${WANT_STILL}" = 1 ]; then
  mkdir -p "${MAC_STILLS}"
  pc_pull "$(ff "${DIR}")/final_still.png" "${MAC_STILLS}/${NAME}_final.png"
  echo "still: ${MAC_STILLS}/${NAME}_final.png"
fi
echo "render done in $(since "$T_ALL")"
