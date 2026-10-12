"""Gemini over google-genai Files upload: one place for upload, JSON calls, captions and take checks.
Needs GEMINI_API_KEY and google-genai (the `content` entry point owns the venv)."""
import os
import sys
import time

PRO = "gemini-2.5-pro"
FLASH = "gemini-2.5-flash"
UPLOAD_TIMEOUT_S = 300


class GeminiError(RuntimeError):
    pass


def _client():
    try:
        from google import genai
    except ImportError as e:
        raise GeminiError("gemini: google-genai not installed (run through tools/content/content)") from e
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise GeminiError("gemini: GEMINI_API_KEY is not set")
    return genai.Client(api_key=key)


def _mime(path):
    ext = os.path.splitext(path)[1].lower()
    return {".mp4": "video/mp4", ".mov": "video/quicktime", ".mkv": "video/x-matroska",
            ".avi": "video/x-msvideo", ".webm": "video/webm", ".png": "image/png",
            ".mp3": "audio/mpeg", ".wav": "audio/wav"}.get(ext, "video/mp4")


class Video:
    """An uploaded file, deleted on exit: `with Video(path) as v: v.json(...)`."""

    def __init__(self, path):
        self.path = path
        self.client = _client()
        self.file = None

    def __enter__(self):
        if not os.path.isfile(self.path):
            raise GeminiError(f"gemini: no such file {self.path}")
        f = self.client.files.upload(file=self.path, config={"mime_type": _mime(self.path)})
        t = time.time()
        while f.state.name != "ACTIVE":
            if f.state.name == "FAILED":
                raise GeminiError(f"gemini: upload processing failed for {self.path}")
            if time.time() - t > UPLOAD_TIMEOUT_S:
                raise GeminiError(f"gemini: upload not ACTIVE after {UPLOAD_TIMEOUT_S}s")
            time.sleep(2)
            f = self.client.files.get(name=f.name)
        self.file = f
        return self

    def __exit__(self, *exc):
        if self.file is not None:
            try:
                self.client.files.delete(name=self.file.name)
            except Exception:
                pass

    def part(self):
        """This file as a plain content part (reference audio or image beside the video)."""
        from google.genai import types
        return types.Part(file_data=types.FileData(file_uri=self.file.uri, mime_type=self.file.mime_type))

    def json(self, prompt, schema, model=PRO, fps=2, start=None, end=None, retries=2, refs=()):
        """One schema-constrained call on the video (optionally a window [start, end] s); refs = (label, Video)."""
        from google.genai import types
        meta = {"fps": fps}
        if start is not None:
            meta["start_offset"] = f"{max(0.0, start):.2f}s"
        if end is not None:
            meta["end_offset"] = f"{end:.2f}s"
        part = types.Part(file_data=types.FileData(file_uri=self.file.uri, mime_type=self.file.mime_type),
                          video_metadata=types.VideoMetadata(**meta))
        cfg = types.GenerateContentConfig(response_mime_type="application/json",
                                          response_schema=schema, temperature=0)
        last = None
        for i in range(retries + 1):
            try:
                contents = [part]
                for label, ref in refs:
                    contents += [label, ref.part()]
                resp = self.client.models.generate_content(model=model, contents=contents + [prompt], config=cfg)
                if resp.parsed is not None:
                    return resp.parsed if isinstance(resp.parsed, dict) else dict(resp.parsed)
                import json
                return json.loads(resp.text)
            except Exception as e:  # transient 5xx / quota: back off and retry, then fail loudly
                last = e
                time.sleep(4 * (i + 1))
        raise GeminiError(f"gemini: {model} call failed: {last}")


CAPTION_SCHEMA = {"type": "object", "properties": {"caption": {"type": "string"}}, "required": ["caption"]}
TAKE_SCHEMA = {"type": "object", "properties": {
    "shows_note": {"type": "string", "enum": ["yes", "no"]},
    "defects": {"type": "array", "items": {"type": "string"}},
    "why": {"type": "string"}}, "required": ["shows_note", "defects", "why"]}


def caption(path, model=FLASH):
    """One-sentence description of a clip (inventory captions, cached by the caller on sha1)."""
    with Video(path) as v:
        r = v.json("Describe this clip from a low-poly first-person game in one concrete sentence: "
                   "camera POV, map look, who moves, what happens, any on-screen text.",
                   CAPTION_SCHEMA, model=model, fps=1)
    return r["caption"]


def take_check(path, note, defects, model=FLASH):
    """G14 per-take check: does this take show <note>? Returns {shows_note, defects, why}."""
    with Video(path) as v:
        return v.json(f"Does this game capture show: {note}\nAnswer yes or no, and list any of these defects "
                      f"you can see: {', '.join(defects)}. Judge only what is visible.",
                      TAKE_SCHEMA, model=model, fps=2)


if __name__ == "__main__":
    print(caption(sys.argv[1]))
