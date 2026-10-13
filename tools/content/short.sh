#!/usr/bin/env bash
# One version of a short, end to end: sync, voice, the shots it lacks, assemble, delivered to the Mac.
# A shot is filmed when its cut is missing or its entry says `refilm: <tag>`; --final films every shot --movie.
#
#   tools/content/short.sh <project> [--tag vN] [--final]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

USAGE="usage: tools/content/short.sh <project> [--tag vN] [--final]"
BRIEF=$(brief_path "${1:?${USAGE}}")
NAME=$(basename "${BRIEF}" .md)
DIR=$(project_dir "${NAME}")
V="python3 ${CONTENT_DIR}/versions.py"
TAG=""; FINAL=0
shift
while [ $# -gt 0 ]; do
  case "$1" in --tag) TAG="$2"; shift ;; --final) FINAL=1 ;; *) die "unknown option $1 (${USAGE})" ;; esac
  shift
done
TAG="${TAG:-$(${V} last "${BRIEF}")}"
TAG="${TAG:-v1}"
${V} has "${BRIEF}" "${TAG}" || die "short.sh refuses: no ## script ${TAG}; make it with tools/content/version.sh ${NAME} ${TAG} --from <tag Ryan watched>"
MAC_DIR="${HOME}/Desktop/panopticon-renders/content/shorts/${NAME}"
MAC_COPY="${MAC_DIR}/${NAME}_${TAG}.mp4"
[ ! -e "${MAC_COPY}" ] || die "short.sh refuses: ${MAC_COPY} exists; delivery never overwrites (cut a new tag)"
T_ALL=$(now_ms); TIMES=()
stage() { TIMES+=("$1 $(since "$2")"); echo "== $1: $(since "$2")"; }

pc_lock "short ${NAME}"   # one short owns C:\dev\verify from sync to assemble
T0=$(now_ms); "${CONTENT_DIR}/sync.sh"; stage sync "${T0}"

if python3 -c "import sys; sys.path.insert(0, '${CONTENT_DIR}/pc'); import brief as b; p = b.parse('${BRIEF}'); s = p['scripts'].get('${TAG}') or p['script']; sys.exit(0 if b.voice_rows(s) else 1)"; then
  T0=$(now_ms); "${CONTENT_DIR}/voice.sh" "${BRIEF}" --tag "${TAG}"; stage voice "${T0}"
fi

pc_layout "${DIR}"
HAVE=$(pc <<PS | tr -d '\r'
Get-ChildItem '${DIR}\\cuts' -Filter '*.mp4' -File -EA SilentlyContinue | ForEach-Object { \$_.BaseName }
PS
)
while read -r ID REFILM; do
  [ -n "${ID}" ] || continue
  NN=$(pad2 "${ID}")
  CUT=$(${V} cut "${BRIEF}" "${TAG}" "${NN}")
  if [ -z "${CUT}" ]; then echo "shot ${NN}: not in the ${TAG} table, not filmed"; continue; fi
  FLAGS=()
  if [ "${FINAL}" = 1 ]; then
    WANT="${NN}_${TAG}_final"; FLAGS=(--movie)
  elif [[ " ${REFILM} " == *" ${TAG} "* ]]; then
    WANT="${NN}_${TAG}"
  elif grep -qx "${CUT}" <<< "${HAVE}"; then
    continue
  else
    WANT="${CUT}"
  fi
  if grep -qx "${WANT}" <<< "${HAVE}" && [ "${WANT}" = "${CUT}" ]; then continue; fi   # a resumed run
  T0=$(now_ms)
  "${CONTENT_DIR}/shot.sh" "${BRIEF}" "${ID}" --name "${WANT}" "${FLAGS[@]+"${FLAGS[@]}"}"
  [ "${WANT}" = "${CUT}" ] || ${V} repoint "${BRIEF}" "${TAG}" "${NN}" "${WANT}"
  stage "shot ${NN}" "${T0}"
done <<< "$(${V} shots "${BRIEF}")"

T0=$(now_ms); "${CONTENT_DIR}/assemble.sh" "${BRIEF}" --tag "${TAG}"; stage assemble "${T0}"

T0=$(now_ms)
mkdir -p "${MAC_DIR}"
[ ! -e "${MAC_COPY}" ] || die "short.sh refuses: ${MAC_COPY} exists; delivery never overwrites (cut a new tag)"
pc_pull "$(ff "${DIR}")/final/${TAG}.mp4" "${MAC_COPY}"
stage deliver "${T0}"
echo "short ${NAME} ${TAG}: ${MAC_COPY} in $(since "${T_ALL}") (${TIMES[*]/%/;})"
