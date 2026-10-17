"""One door to the model for the whole sv3 pipeline: the Claude Code CLI headless (logged-in account, no API key).
    ask_json(prompt, schema, images=(), model="opus") -> the parsed, schema-valid JSON; raises LLMError with both outputs on failure.
"""
import json
import os
import re
import subprocess

import jsonschema

TIMEOUT_S = 300
FENCE_RE = re.compile(r"^\s*```[a-zA-Z0-9_-]*\s*\n?(.*?)\n?\s*```\s*$", re.S)


class LLMError(RuntimeError):
    pass


def _env():
    """A nested `claude -p` must not think it runs inside this session's tool loop."""
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE" and not k.startswith("CLAUDE_CODE_ENTRYPOINT")}
    return env


def _call(prompt, model, images):
    cmd = ["claude", "-p", prompt, "--output-format", "json", "--model", model]
    if images:
        cmd += ["--allowedTools", "Read"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_S, env=_env(), cwd="/")
    except subprocess.TimeoutExpired:
        raise LLMError("claude -p timed out after %d s" % TIMEOUT_S)
    if r.returncode != 0:
        raise LLMError("claude -p exit %d: %s" % (r.returncode, (r.stderr or r.stdout)[-2000:]))
    try:
        envelope = json.loads(r.stdout)
    except ValueError:
        raise LLMError("claude -p did not return a JSON envelope: %r" % r.stdout[-2000:])
    if envelope.get("is_error") or envelope.get("subtype", "success") != "success":
        raise LLMError("claude -p error envelope: %s" % json.dumps(envelope)[:2000])
    text = envelope.get("result")
    if not isinstance(text, str):
        raise LLMError("claude -p envelope has no `result` string: %s" % json.dumps(envelope)[:2000])
    return text


def _strip_fences(text):
    m = FENCE_RE.match(text)
    if m:
        return m.group(1)
    t = text.strip()
    if "```" in t:   # prose around a fenced block: take the block
        m = re.search(r"```[a-zA-Z0-9_-]*\s*\n(.*?)\n\s*```", t, re.S)
        if m:
            return m.group(1)
    return t


def parse_json(text):
    """The answer as JSON: fences off, else the first {...} or [...] in the text; ValueError when there is none."""
    body = _strip_fences(text)
    try:
        return json.loads(body)
    except ValueError:
        pass
    starts = [i for i in (body.find("{"), body.find("[")) if i >= 0]
    if not starts:
        raise ValueError("no JSON object or array in the reply")
    i = min(starts)
    dec = json.JSONDecoder()
    obj, end = dec.raw_decode(body[i:])
    if body[i + end:].strip():
        raise ValueError("text after the JSON: %r" % body[i + end:][:200])
    return obj


def _prompt(prompt, schema, images, error=None):
    parts = [prompt]
    if images:
        parts.append("IMAGES: read every one of these files with the Read tool before answering (they are the evidence; "
                     "an answer about a file you did not read is wrong):\n" + "\n".join(os.path.abspath(p) for p in images))
    parts.append("Your reply must be a single JSON value valid against this JSON schema:\n" + json.dumps(schema, ensure_ascii=False))
    if error:
        parts.append("Your previous reply was rejected: " + error + "\nReply again, corrected.")
    parts.append("Reply with ONLY the JSON. No prose, no markdown fences.")
    return "\n\n".join(parts)


def ask_json(prompt, schema, images=(), model="opus"):
    """Strict JSON from Claude: parse + jsonschema.validate; on failure one retry with the error appended; then raise with both."""
    images = [os.path.abspath(p) for p in images]
    for p in images:
        if not os.path.isfile(p):
            raise LLMError("image not found: " + p)
    first = _call(_prompt(prompt, schema, images), model, images)
    try:
        obj = parse_json(first)
        jsonschema.validate(obj, schema)
        return obj
    except (ValueError, jsonschema.ValidationError) as e1:
        err1 = "%s: %s" % (type(e1).__name__, str(e1)[:600])
    second = _call(_prompt(prompt, schema, images, error=err1), model, images)
    try:
        obj = parse_json(second)
        jsonschema.validate(obj, schema)
        return obj
    except (ValueError, jsonschema.ValidationError) as e2:
        raise LLMError("model answer failed the schema twice.\n--- first (%s):\n%s\n--- second (%s: %s):\n%s"
                       % (err1, first[:3000], type(e2).__name__, str(e2)[:600], second[:3000]))
