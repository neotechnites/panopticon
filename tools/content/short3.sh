#!/usr/bin/env bash
# Shorts v3 (docs/SHORTS_V3_DESIGN.md): Ryan's script in, a reviewed 9:16 draft out, every step timed.
#
#   tools/content/short3.sh <script.md> --name <project> --tag vN [--pool DIR]
#
# Steps, in order, each a WP2 CLI (design 8) or a PC script: script, translate, voice, plan, capture,
# search, edl, assemble, review, deliver. The first non-zero exit stops the run with that step's
# output; a step whose module is not built stops the run naming it (no skip, no fallback). Times go
# to tools/content/projects/<project>/sv3/<tag>/timing.json; the total clock is printed last.
# Delivery: PC final\<tag>.mp4 -> ~/Desktop/panopticon-renders/social/shorts/<NN>_<project>/<project>_<tag>.mp4, never overwritten.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

USAGE="usage: tools/content/short3.sh <script.md> --name <project> --tag vN [--pool DIR]"
SCRIPT="${1:?${USAGE}}"; shift
NAME=""; TAG=""; POOL="${HOME}/Desktop/panopticon-renders/content/_tapes"
while [ $# -gt 0 ]; do
  case "$1" in --name) NAME="$2"; shift ;; --tag) TAG="$2"; shift ;; --pool) POOL="$2"; shift ;; *) die "unknown option $1 (${USAGE})" ;; esac
  shift
done
[ -f "${SCRIPT}" ] || die "no script at ${SCRIPT}"
[ -n "${NAME}" ] && [ -n "${TAG}" ] || die "${USAGE}"
[[ "${TAG}" =~ ^v[0-9]+$ ]] || die "--tag is vN"
SV3="${CONTENT_DIR}/sv3"
PY="${CONTENT_DIR}/.venv/bin/python"
[ -x "${PY}" ] || die "short3: no ${PY}; run tools/content/sv3/setup.sh (WP2) first"
BRIEF="${CONTENT_DIR}/projects/${NAME}.md"
WORK="${CONTENT_DIR}/projects/${NAME}/sv3/${TAG}"
DIR=$(project_dir "${NAME}")
SOCIAL="${HOME}/Desktop/panopticon-renders/social/shorts"
mkdir -p "${WORK}/voice" "${POOL}" || die "cannot make ${WORK}"
[ -f "${BRIEF}" ] || printf '# %s\nkind: short\n' "${NAME}" > "${BRIEF}"

# The Mac copy's folder: the existing <NN>_<name>, else the next number.
NN_DIR=$(ls -d "${SOCIAL}"/[0-9][0-9]_"${NAME}" 2>/dev/null | head -1)
if [ -z "${NN_DIR}" ]; then
  LAST=$(ls "${SOCIAL}" 2>/dev/null | grep -o '^[0-9][0-9]' | sort -n | tail -1)
  NN_DIR="${SOCIAL}/$(printf '%02d' $(( ${LAST:-0} + 1 )))_${NAME}"
fi
MAC_COPY="${NN_DIR}/${NAME}_${TAG}.mp4"
[ ! -e "${MAC_COPY}" ] || die "short3 refuses: ${MAC_COPY} exists; delivery never overwrites (cut a new tag)"

T_ALL=$(now_ms)
TIMING="${WORK}/timing.json"
echo '{"steps": []}' > "${TIMING}" || die "cannot write ${TIMING}"
record() {  # record <step> <seconds> <exit>
  python3 - "${TIMING}" "$1" "$2" "$3" <<'PY'
import json, sys
p, step, secs, code = sys.argv[1:5]
d = json.load(open(p))
d["steps"].append({"step": step, "seconds": int(secs), "exit": int(code)})
d["total_seconds"] = sum(s["seconds"] for s in d["steps"])
json.dump(d, open(p, "w"), indent=1)
PY
}
step() {  # step <name> <command...> : timed; a non-zero exit ends the run here
  local name="$1" t0 code secs; shift
  t0=$(now_ms)
  echo "== ${name}: $*"
  "$@"; code=$?
  secs=$(( ($(now_ms) - t0) / 1000 ))
  record "${name}" "${secs}" "${code}"
  echo "== ${name}: ${secs}s (exit ${code})"
  if [ "${code}" -ne 0 ]; then
    echo "short3: stopped at ${name} (exit ${code}) after $(since "${T_ALL}"); timings in ${TIMING}" >&2
    exit "${code}"
  fi
}
need() {  # need <step> <module> : the WP2 module must exist; nothing is skipped or faked
  [ -f "${SV3}/$2.py" ] || { record "$1" 0 3; die "short3: step $1 needs tools/content/sv3/$2.py (WP2), which is not built"; }
}
sv3() { (cd "${CONTENT_DIR}" && "${PY}" -m "sv3.$1" "${@:2}"); }

# The voice is spoken from the brief's ## script <tag> rows; until edl.py writes the real table, a
# provisional one carries every voiced line's text (his words, verbatim) so every slot's length is known.
provisional_table() {
  grep -q "^## script ${TAG}\$" "${BRIEF}" && return 0
  python3 - "${WORK}/spec.json" "${TAG}" >> "${BRIEF}" <<'PY'
import json, sys
spec, tag = json.load(open(sys.argv[1])), sys.argv[2]
lines = spec["lines"] if isinstance(spec, dict) else spec
print("\n## script %s\n# provisional (short3.sh): voice only; sv3.edl writes the cut's table\nvoice: en-US-AndrewNeural +5%%\n"
      "| line | clip | in | len | fit | speed | text |" % tag)
for l in lines:
    if l.get("text") and not l.get("beat"):
        print("| %s |  |  |  | line |  | %s |" % (l["id"], l["text"].replace("|", "/")))
PY
}
pull_words() { pc_pull "$(ff "${DIR}")/voice/words.json" "${WORK}/voice/words.json"; }
pull_final() { pc_pull "$(ff "${DIR}")/final/${TAG}.mp4" "${WORK}/final.mp4"; }
deliver() {
  mkdir -p "${NN_DIR}"
  [ ! -e "${MAC_COPY}" ] || { echo "short3 refuses: ${MAC_COPY} exists" >&2; return 2; }
  cp "${WORK}/final.mp4" "${MAC_COPY}" && echo "delivered ${MAC_COPY}"
}

need script script;       step script    sv3 script "${SCRIPT}" --out "${WORK}/spec.json"
need translate translate; step translate sv3 translate "${WORK}/spec.json" --out "${WORK}/shots.json"
step voice_table provisional_table
step voice "${CONTENT_DIR}/voice.sh" "${NAME}" --tag "${TAG}"
step words pull_words
need plan plan;           step plan      sv3 plan "${WORK}/shots.json" --pool "${POOL}" --out "${WORK}/plan.json"
need capture capture;     step capture   sv3 capture "${WORK}/plan.json" --pool "${POOL}"
need search search;       step search    sv3 search "${WORK}/plan.json" "${WORK}/shots.json" --pool "${POOL}" --words "${WORK}/voice/words.json" --out "${WORK}/edl.json"
need edl edl;             step edl       sv3 edl "${WORK}/edl.json" "${WORK}/shots.json" "${WORK}/spec.json" --brief "${BRIEF}" --tag "${TAG}"
step assemble "${CONTENT_DIR}/assemble.sh" "${NAME}" --tag "${TAG}"
step pull pull_final
need review review;       step review    sv3 review "${WORK}/final.mp4" "${WORK}/edl.json" "${WORK}/shots.json" --out "${WORK}/review.json"
step deliver deliver
echo "short3 ${NAME} ${TAG}: ${MAC_COPY} in $(since "${T_ALL}") -- $(python3 -c "import json; print(', '.join('%s %ss' % (s['step'], s['seconds']) for s in json.load(open('${TIMING}'))['steps']))")"
