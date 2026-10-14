#!/usr/bin/env bash
# Refilm every shot of rough_v59_beats with Movie Maker on the PC and rebuild it as rough_v60_beats on v59's edit.
# Mac smoke first (a miss stops before the PC), then sync, 16 shots, align, build, copy to ~/Desktop/panopticon-renders/trailer_reveal/.
# Resumes where it stopped (v60_work/filmed.txt). Plan: ~/Desktop/panopticon-renders/trailer_reveal/refilm_v60_plan.md
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 tools/content/refilm_v60.py "${1:-all}" "${@:2}"
