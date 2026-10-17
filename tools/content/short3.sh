#!/usr/bin/env bash
# Shorts v3 on the stage path (pod DESIGN §10): Ryan's script in, a reviewed 9:16 draft out, every step timed.
#
#   tools/content/short3.sh <script.md> --name <project> --tag vN [--mac-only]
#
# Steps: seams, script, translate, voice, words, plan, short (short.sh), pull, frames, review (advisory: its
# exit is recorded, never fatal), deliver. --mac-only stops after short.sh's Mac smokes, never taking the PC lock.
# Any other non-zero exit stops the run. Times go to tools/content/projects/<project>/sv3/<tag>/timing.json.
# Delivery: PC final\<tag>.mp4 -> ~/Desktop/panopticon-renders/social/shorts/<NN>_<project>/<project>_<tag>.mp4, never overwritten.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

USAGE="usage: tools/content/short3.sh <script.md> --name <project> --tag vN [--mac-only]"
SCRIPT="${1:?${USAGE}}"; shift
SCRIPT="$(cd "$(dirname "${SCRIPT}")" && pwd)/$(basename "${SCRIPT}")"   # sv3 steps run from tools/content
NAME=""; TAG=""; MAC_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in --name) NAME="$2"; shift ;; --tag) TAG="$2"; shift ;; --mac-only) MAC_ONLY=1 ;; *) die "unknown option $1 (${USAGE})" ;; esac
  shift
done
[ -f "${SCRIPT}" ] || die "no script at ${SCRIPT}"
[ -n "${NAME}" ] && [ -n "${TAG}" ] || die "${USAGE}"
[[ "${TAG}" =~ ^v[0-9]+$ ]] || die "--tag is vN"
SV3="${CONTENT_DIR}/sv3"
STAGES="${SV3}/stages.json"
PY="${CONTENT_DIR}/.venv/bin/python"
[ -x "${PY}" ] || die "short3: no ${PY}; run tools/content/sv3/setup.sh (WP2) first"
[ -f "${STAGES}" ] || die "short3: no ${STAGES}; run sv3.catalogue first"
BRIEF="${CONTENT_DIR}/projects/${NAME}.md"
WORK="${CONTENT_DIR}/projects/${NAME}/sv3/${TAG}"
DIR=$(project_dir "${NAME}")
SOCIAL="${HOME}/Desktop/panopticon-renders/social/shorts"
mkdir -p "${WORK}/voice" "${WORK}/frames" || die "cannot make ${WORK}"
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
step() {  # step <name> <command...> : timed; a non-zero exit ends the run here (ADVISORY=1: recorded only)
  local name="$1" t0 code secs; shift
  t0=$(now_ms)
  echo "== ${name}: $*"
  "$@"; code=$?
  secs=$(( ($(now_ms) - t0) / 1000 ))
  record "${name}" "${secs}" "${code}"
  echo "== ${name}: ${secs}s (exit ${code})"
  if [ "${code}" -ne 0 ] && [ "${ADVISORY:-0}" = 0 ]; then
    echo "short3: stopped at ${name} (exit ${code}) after $(since "${T_ALL}"); timings in ${TIMING}" >&2
    exit "${code}"
  fi
}
need() {  # need <step> <module> : the WP2 module must exist; nothing is skipped or faked
  [ -f "${SV3}/$2.py" ] || { record "$1" 0 3; die "short3: step $1 needs tools/content/sv3/$2.py (WP2), which is not built"; }
}
sv3() { (cd "${CONTENT_DIR}" && "${PY}" -m "sv3.$1" "${@:2}"); }

# The voice is spoken from the brief's ## script <tag> rows; until plan.py writes the real table, a
# provisional one carries every voiced line's text (his words, verbatim) so every slot's length is known.
provisional_table() {
  grep -q "^## script ${TAG}\$" "${BRIEF}" && return 0
  python3 - "${WORK}/spec.json" "${TAG}" >> "${BRIEF}" <<'PY'
import json, sys
spec, tag = json.load(open(sys.argv[1])), sys.argv[2]
lines = spec["lines"] if isinstance(spec, dict) else spec
print("\n## script %s\n# provisional (short3.sh): voice only; sv3.plan writes the cut's table\nvoice: en-US-AndrewNeural +5%%\n"
      "| line | clip | in | len | fit | speed | text |" % tag)
for l in lines:
    if l.get("text") and not l.get("beat"):
        print("| %s |  |  |  | line |  | %s |" % (l["id"], l["text"].replace("|", "/")))
PY
}
unprovision() {  # the provisional table leaves the brief before plan.py appends the cut's ## script <tag>
  python3 - "${BRIEF}" "${TAG}" <<'PY'
import re, sys
p, tag = sys.argv[1:3]
src = open(p).read()
m = re.search(r"\n## script %s\n# provisional \(short3\.sh\)[^\n]*\n.*?(?=\n## |\Z)" % re.escape(tag), src, re.S)
if m:
    open(p, "w").write(src[:m.start()] + src[m.end():])
PY
}
review_edl() {  # the cut's windows for sv3.review, from the brief's ## script <tag> rows (numeric len only)
  python3 - "${BRIEF}" "${TAG}" "${WORK}/edl.json" "${CONTENT_DIR}/pc" <<'PY'
import json, sys
brief, tag, out, pc = sys.argv[1:5]
sys.path.insert(0, pc)
import brief as b
edl = []
for r in b.parse(brief)["scripts"][tag]["rows"]:
    try:
        edl.append({"id": r["line"], "line": r["line"], "len": float(r["len"])})
    except (KeyError, TypeError, ValueError):
        pass
json.dump(edl, open(out, "w"), indent=1)
PY
}
pull_words() { pc_pull "$(ff "${DIR}")/voice/words.json" "${WORK}/voice/words.json"; }
pull_final() { pc_pull "$(ff "${DIR}")/final/${TAG}.mp4" "${WORK}/final.mp4"; }
frames() { ffmpeg -loglevel error -y -i "${WORK}/final.mp4" -vf fps=1 "${WORK}/frames/%03d.png"; }
deliver() {
  mkdir -p "${NN_DIR}"
  [ ! -e "${MAC_COPY}" ] || { echo "short3 refuses: ${MAC_COPY} exists" >&2; return 2; }
  cp "${WORK}/final.mp4" "${MAC_COPY}" && echo "delivered ${MAC_COPY}"
}

need seams seams;         step seams     sv3 seams
need script script;       step script    sv3 script "${SCRIPT}" --out "${WORK}/spec.json"
need translate translate; step translate sv3 translate "${WORK}/spec.json" --stages "${STAGES}" --out "${WORK}/shots.json"
step voice_table provisional_table
step voice "${CONTENT_DIR}/voice.sh" "${NAME}" --tag "${TAG}"
step words pull_words
step unprovision unprovision
need plan plan;           step plan      sv3 plan "${WORK}/shots.json" --stages "${STAGES}" --words "${WORK}/voice/words.json" --brief "${BRIEF}" --tag "${TAG}"
if [ "${MAC_ONLY}" = 1 ]; then
  tapes() {  # one tape per name, recorded headless on the PC (tape.sh) before any smoke or take plays it
  local seen="" sync=""
  for id in $(grep '^## [0-9]' "${BRIEF}" | awk '{print $2}'); do
    local t; t=$(brief_field "${BRIEF}" "${id}" tape)
    [ -n "${t}" ] || continue
    [[ " ${seen} " == *" ${t} "* ]] && continue
    seen="${seen} ${t}"
    "${CONTENT_DIR}/tape.sh" "${NAME}" "${id}" ${sync} || return $?
    sync="--no-sync"
  done
  [ -z "${seen}" ] || (cd "${REPO_DIR}" && git add "tools/content/projects/${NAME}/tapes" && git -c user.name=Ryan -c user.email=ryan@olympus.local commit -qm "${NAME} ${TAG}: tapes${seen}" ) || true
}
step tapes tapes
step short "${CONTENT_DIR}/short.sh" "${NAME}" --tag "${TAG}" --smoke-only
  echo "short3 ${NAME} ${TAG} --mac-only: Mac smokes passed in $(since "${T_ALL}"); timings in ${TIMING}"
  exit 0
fi
step short "${CONTENT_DIR}/short.sh" "${NAME}" --tag "${TAG}"
step pull pull_final
step frames frames
step review_edl review_edl
need review review;       ADVISORY=1 step review sv3 review "${WORK}/final.mp4" "${WORK}/edl.json" "${WORK}/shots.json" --out "${WORK}/review.json"
step deliver deliver
echo "short3 ${NAME} ${TAG}: ${MAC_COPY} in $(since "${T_ALL}") -- $(python3 -c "import json; print(', '.join('%s %ss' % (s['step'], s['seconds']) for s in json.load(open('${TIMING}'))['steps']))")"
