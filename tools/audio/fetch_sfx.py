#!/usr/bin/env python3
"""Fetch CC0 field recordings from Freesound for every PANOPTICON SFX key.

    tools/audio/.venv/bin/python tools/audio/fetch_sfx.py            # search + download + process
    tools/audio/.venv/bin/python tools/audio/fetch_sfx.py --process  # re-trim/normalise/crush from src/
    tools/audio/.venv/bin/python tools/audio/fetch_sfx.py --only jump land

Writes assets/audio/sfx/src/<key>_<id>.ogg (raw previews), src/manifest.json,
sfx/clean/<name>.wav (44.1 kHz 16-bit, trimmed, peak -1 dBFS),
sfx/<name>.wav (22.05 kHz 8-bit) and assets/audio/LICENSE.md.
Needs ffmpeg; run with tools/audio/.venv (requests, numpy). API key read from ~/.config/freesound_key, never printed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import subprocess
import sys
import time
import urllib.parse
import wave
from pathlib import Path

import numpy as np
import requests

ROOT = Path(__file__).resolve().parents[2]
SFX = ROOT / "assets" / "audio" / "sfx"
SRC = SFX / "src"
CLEAN = SFX / "clean"
MANIFEST = SRC / "manifest.json"
LICENSE = ROOT / "assets" / "audio" / "LICENSE.md"
API = "https://freesound.org/apiv2/"
FIELDS = "id,name,username,license,duration,previews,tags,avg_rating,num_downloads"
CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0/"
SR_CLEAN = 44100
SR_CRUSH = 22050
RETRY_BUDGET_S = 300.0
UA = "panopticon-fetch-sfx/1.0"

# Words in a name or tag that mean "asset pack / synthesised / another game".
BAD_WORDS = (
    "pack", "kenney", "opengameart", "asset", "sfxr", "bfxr", "chiptune", "8bit",
    "8-bit", "synth", "synthesized", "synthesised", "generated", "retro", "arcade",
    "videogame", "video-game", "video game", "minecraft", "mario", "zelda", "doom",
    "quake", "halo", "fortnite", "sample-pack", "library", "bundle", "midi", "cartoon", "stock", "hanna",
)

# key: (queries, min_s, max_s, variants, cap_s)
KEYS: dict[str, tuple[list[str], float, float, int, float]] = {
    "rifle_fired": (["rifle gunshot single", "rifle shot outdoor", "bolt action rifle shot"], 0.5, 3.0, 1, 2.5),
    "rifle_hit": (["bullet impact flesh", "bullet hit body thud", "meat impact thud"], 0.1, 1.5, 1, 1.0),
    "rifle_missed": (["bullet ricochet", "ricochet rock", "bullet whizz"], 0.2, 2.0, 1, 1.5),
    "rifle_reload_started": (["bolt action open", "rifle bolt open", "magazine out rifle"], 0.2, 2.0, 1, 1.2),
    "rifle_reload_finished": (["bolt action close", "rifle bolt close", "magazine insert rifle"], 0.2, 2.0, 1, 1.2),
    "match_started": (["gong hit", "large bell strike", "air horn blast"], 0.5, 4.0, 1, 3.0),
    "race_started": (["starting pistol", "starter pistol", "whistle blow short"], 0.3, 3.0, 1, 1.5),
    "round_started": (["boxing bell", "bell ding single", "desk bell"], 0.3, 3.0, 1, 2.0),
    "seat_changed": (["heavy lever pull", "metal lever switch", "large switch clunk"], 0.2, 2.0, 1, 1.5),
    "round_resolved": (["gong low", "bell chime low", "cymbal hit single"], 0.5, 4.0, 1, 3.0),
    "runner_converted": (["handcuff click", "chain rattle short", "metal shackle"], 0.3, 3.0, 1, 2.0),
    "match_won": (["crowd cheer short", "applause short crowd", "trumpet fanfare short"], 1.0, 6.0, 1, 4.0),
    "footstep": (["footsteps gravel", "footstep concrete", "footstep stone", "boots dirt step"], 0.05, 1.5, 4, 0.6),
    "jump": (["jump grunt", "clothes rustle jump", "fabric whoosh short"], 0.1, 1.5, 1, 0.8),
    "land": (["landing thud feet", "jump land thud", "body land floor thud"], 0.1, 1.5, 1, 0.9),
    "slide_start": (["abrupt stopping gravel", "gravel skid", "dirt scrape"], 0.2, 3.0, 1, 1.0),
    "slide_end": (["shoe scuff", "foot scuff floor", "scrape stop gravel"], 0.1, 3.0, 1, 0.8),
    "hit_taken": (["punch impact body", "body hit thud", "grunt pain hit"], 0.1, 1.5, 1, 1.0),
    "catch_made": (["cloth grab", "snatch fabric", "hand grab clothes"], 0.1, 1.5, 1, 0.9),
    "catch_taken": (["metal drop concrete", "chain drop floor", "heavy object drop"], 0.2, 3.0, 1, 1.5),
    "lava_death": (["sizzle burn", "fire whoosh burst", "steam hiss burst"], 0.5, 4.0, 1, 2.5),
    "boost_pad": (["steam release burst", "air pressure release", "pneumatic hiss"], 0.3, 3.0, 1, 1.5),
    "portal_drone": (["low hum drone", "electrical hum", "transformer hum"], 1.0, 12.0, 1, 6.0),
    "ui_click": (["switch click single", "button click plastic", "mouse click single"], 0.02, 0.6, 1, 0.3),
    "ui_focus": (["soft tick", "pen click", "small click quiet"], 0.02, 0.5, 1, 0.2),
    "ui_back": (["toggle switch off", "light switch click", "wooden click"], 0.02, 0.6, 1, 0.3),
    "ui_menu_opened": (["wooden drawer open", "latch open", "book open"], 0.1, 1.5, 1, 0.8),
    "ui_menu_closed": (["wooden drawer close", "latch close", "book close"], 0.1, 1.5, 1, 0.8),
}


# --- Freesound ---------------------------------------------------------------

def read_key() -> str:
    return (Path.home() / ".config" / "freesound_key").read_text().strip()


def get_json(url: str) -> dict:
    """GET with 20 s timeout; non-JSON / 5xx / 429 / timeouts retry with backoff up to RETRY_BUDGET_S."""
    started = time.monotonic()
    delay = 5.0
    while True:
        try:
            resp = requests.get(url, headers={"User-Agent": UA, "Accept": "application/json"}, timeout=20)
            if resp.status_code < 500 and resp.status_code != 429:
                resp.raise_for_status()
                return resp.json()
            reason = "HTTP %d" % resp.status_code
        except requests.exceptions.SSLError:
            raise
        except (ValueError, requests.exceptions.RequestException) as exc:
            reason = "non-JSON" if isinstance(exc, ValueError) else type(exc).__name__
        if time.monotonic() - started + delay > RETRY_BUDGET_S:
            raise RuntimeError("Freesound still busy after %.0fs" % RETRY_BUDGET_S)
        print("    busy (%s); retry in %.0fs" % (reason, delay), flush=True)
        time.sleep(delay)
        delay = min(delay * 2, 60.0)


def search(token: str, query: str, min_s: float, max_s: float) -> list[dict]:
    params = {
        "query": query,
        "token": token,
        "filter": 'license:"Creative Commons 0" duration:[%g TO %g]' % (min_s, max_s),
        "fields": FIELDS,
        "page_size": 40,
        "sort": "rating_desc",
    }
    url = API + "search/text/?" + urllib.parse.urlencode(params)
    return get_json(url).get("results", [])


def looks_like_pack(sound: dict) -> bool:
    hay = (sound.get("name", "") + " " + " ".join(sound.get("tags", []))).lower()
    return any(w in hay for w in BAD_WORDS)


def score(sound: dict) -> float:
    rating = float(sound.get("avg_rating") or 0.0)
    downloads = float(sound.get("num_downloads") or 0)
    return rating - 0.6 * math.log10(downloads + 1.0)


def pick(token: str, key: str) -> list[dict]:
    queries, min_s, max_s, variants, _cap = KEYS[key]
    pool: dict[int, dict] = {}
    for q in queries:
        for s in search(token, q, min_s, max_s):
            if not str(s.get("license", "")).endswith("/publicdomain/zero/1.0/") or looks_like_pack(s):
                continue
            if not (min_s <= float(s["duration"]) <= max_s):
                continue
            pool.setdefault(int(s["id"]), s)
    ranked = sorted(pool.values(), key=score, reverse=True)
    chosen: list[dict] = []
    seen_users: set[str] = set()
    for s in ranked:
        if variants > 1 and s["username"] in seen_users:
            continue
        chosen.append(s)
        seen_users.add(s["username"])
        if len(chosen) == variants:
            break
    return chosen


def download(url: str, dest: Path) -> None:
    started = time.monotonic()
    delay = 5.0
    while True:
        try:
            resp = requests.get(url, headers={"User-Agent": UA}, timeout=20)
            if resp.status_code >= 500:
                raise ValueError("HTTP %d" % resp.status_code)
            resp.raise_for_status()
            data = resp.content
            if data[:4] != b"OggS":
                raise ValueError("not an ogg")
            dest.write_bytes(data)
            return
        except requests.exceptions.SSLError:
            raise
        except (ValueError, requests.exceptions.RequestException) as exc:
            if time.monotonic() - started + delay > RETRY_BUDGET_S:
                raise RuntimeError("download failed: %s" % exc)
            print("    download busy (%s); retry in %.0fs" % (type(exc).__name__, delay), flush=True)
            time.sleep(delay)
            delay = min(delay * 2, 60.0)


# --- DSP ---------------------------------------------------------------------

def decode(path: Path, sr: int) -> np.ndarray:
    out = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(out, dtype=np.float32).astype(np.float64)


def trim(x: np.ndarray, sr: int, cap_s: float) -> np.ndarray:
    peak = np.max(np.abs(x)) or 1.0
    env = np.abs(x) / peak
    win = max(1, sr // 200)
    smooth = np.convolve(env, np.ones(win) / win, mode="same")
    above = np.flatnonzero(smooth > 10 ** (-42 / 20))
    if above.size == 0:
        return x
    start = max(0, int(above[0]) - sr * 3 // 1000)
    end = min(x.size, int(above[-1]) + sr * 40 // 1000)
    y = x[start:end]
    cap = int(cap_s * sr)
    fade = min(y.size, sr // 50)
    if y.size > cap:
        y = y[:cap]
        fade = min(y.size, int(sr * min(0.3, cap_s * 0.25)))
    y = y.copy()
    y[-fade:] *= np.linspace(1.0, 0.0, fade)
    attack = min(y.size, sr // 500)
    y[:attack] *= np.linspace(0.0, 1.0, attack)
    return y


def normalise(x: np.ndarray, db: float = -1.0) -> np.ndarray:
    peak = np.max(np.abs(x))
    return x * (10 ** (db / 20) / peak) if peak > 0 else x


def write_wav(path: Path, x: np.ndarray, sr: int, bits: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setframerate(sr)
        if bits == 8:
            w.setsampwidth(1)
            w.writeframes((np.round(x * 127.0) + 128).astype(np.uint8).tobytes())
        else:
            w.setsampwidth(2)
            w.writeframes(np.round(x * 32767.0).astype("<i2").tobytes())


def resample(x: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    tmp = SRC / "_resample.wav"
    write_wav(tmp, x, sr_in, 16)
    y = decode(tmp, sr_out)
    tmp.unlink()
    return y


def process(src: Path, name: str, cap_s: float) -> None:
    x = normalise(trim(decode(src, SR_CLEAN), SR_CLEAN, cap_s))
    write_wav(CLEAN / (name + ".wav"), x, SR_CLEAN, 16)
    write_wav(SFX / (name + ".wav"), normalise(resample(x, SR_CLEAN, SR_CRUSH)), SR_CRUSH, 8)


# --- Driver ------------------------------------------------------------------

def out_names(key: str) -> list[str]:
    n = KEYS[key][3]
    return [key] if n == 1 else ["%s_%d" % (key, i + 1) for i in range(n)]


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}


def write_license(manifest: dict) -> None:
    lines = [
        "# assets/audio/sfx licence",
        "",
        "Every recording below is CC0 1.0 (public domain, no attribution required) from",
        "Freesound. `sfx/src/` holds the untouched previews, `sfx/clean/` the trimmed and",
        "peak-normalised 44.1 kHz versions the bank plays, `sfx/*.wav` the 22.05 kHz 8-bit",
        "crush. Regenerate with `python3 tools/audio/fetch_sfx.py`.",
        "",
        "| file | freesound id | title | author | licence | retrieved |",
        "|---|---|---|---|---|---|",
    ]
    for key in KEYS:
        for entry in manifest.get(key, []):
            lines.append("| `%s.wav` | [%d](https://freesound.org/s/%d/) | %s | %s | [CC0 1.0](%s) | %s |" % (
                entry["out"], entry["id"], entry["id"], entry["name"].replace("|", "/"),
                entry["author"], entry["license"], entry["retrieved"],
            ))
    LICENSE.write_text("\n".join(lines) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--process", action="store_true", help="skip search/download; reprocess src/")
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--refresh", action="store_true", help="re-search keys already in the manifest")
    args = ap.parse_args()
    keys = args.only or list(KEYS)
    SRC.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    token = None if args.process else read_key()
    today = dt.date.today().isoformat()
    missing: list[str] = []
    for key in keys:
        names = out_names(key)
        if not args.process and (args.refresh or key not in manifest):
            print("%s" % key, flush=True)
            chosen = pick(token, key)
            if not chosen:
                print("    NOTHING found under CC0", flush=True)
                missing.append(key)
                continue
            entries = []
            for name, s in zip(names, chosen):
                dest = SRC / ("%s_%d.ogg" % (key, s["id"]))
                if not dest.exists():
                    download(s["previews"]["preview-hq-ogg"], dest)
                entries.append({
                    "out": name, "id": int(s["id"]), "name": s["name"], "author": s["username"],
                    "license": s["license"], "src": dest.name, "duration": float(s["duration"]),
                    "rating": float(s.get("avg_rating") or 0), "downloads": int(s.get("num_downloads") or 0),
                    "retrieved": today,
                })
                print("    %-20s %8d  %-40s by %s" % (name, s["id"], s["name"][:40], s["username"]), flush=True)
            if len(chosen) < len(names):
                print("    only %d of %d variants found" % (len(chosen), len(names)), flush=True)
            manifest[key] = entries
            MANIFEST.write_text(json.dumps(manifest, indent=1))
        for entry in manifest.get(key, []):
            process(SRC / entry["src"], entry["out"], KEYS[key][4])
    write_license(manifest)
    if missing:
        print("missing: %s" % ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
