#!/bin/bash
# Make tools/content/.venv (google-genai + jsonschema) and register tools/content on its path so
# `.venv/bin/python -m sv3.<cmd>` works from any directory.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
CONTENT="$(dirname "$HERE")"
VENV="$CONTENT/.venv"
[ -x "$VENV/bin/python" ] || python3 -m venv "$VENV"
"$VENV/bin/python" -m pip install -q --upgrade pip
"$VENV/bin/python" -m pip install -q google-genai jsonschema
SITE="$("$VENV/bin/python" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
echo "$CONTENT" > "$SITE/sv3.pth"
"$VENV/bin/python" -c 'import google.genai, jsonschema, sv3; print("sv3 ok", google.genai.__version__)'
