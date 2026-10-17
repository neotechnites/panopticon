"""shots.json contract: the closed predicate set (design §2 + §7.4) and the jsonschema translate.py enforces."""

EVENTS = ["shot", "shot_result", "kill", "shove", "out", "portal", "seat", "race_start", "race_won", "brawl_start",
          "brawl_out", "brawl_won", "finale_start", "finale_end", "round_start", "round_end", "scoped", "ragdoll"]
WHO = ["seat", "victim", "other", "guard", "runner:any", "any"]
BODY_STATES = ["run", "cover", "dead", "ragdoll", "ghost", "shoved", "brawl"]
LANDMARKS = ["tower", "portal", "lava", "cover"]
PREDICATES = ["event", "before", "on_screen", "moving", "no_event", "seat_state", "distinct", "scoped", "looking_at", "state"]

_EVENT_MATCH = {
    "type": "object",
    "properties": {
        "ev": {"type": "string", "enum": EVENTS},
        "by": {"type": "string", "enum": WHO},
        "victim": {"type": "string", "enum": WHO},
        "body": {"type": "string", "enum": WHO},
        "cause": {"type": "string", "enum": ["shot", "pit", "lava", "trap", "shove_pit", "brawl"]},
        "result": {"type": "string", "enum": ["hit", "miss"]},
        "outcome": {"type": "string", "enum": ["ring", "pit", "sights", "tower_out"]},
    },
    "required": ["ev"],
}

PREDICATE = {
    "type": "object",
    "properties": {
        "p": {"type": "string", "enum": PREDICATES},
        # event / no_event
        "ev": {"type": "string", "enum": EVENTS},
        "by": {"type": "string", "enum": WHO},
        "victim": {"type": "string", "enum": WHO},
        "body": {"type": "string", "enum": WHO},
        "cause": {"type": "string", "enum": ["shot", "pit", "lava", "trap", "shove_pit", "brawl"]},
        "result": {"type": "string", "enum": ["hit", "miss"]},
        "outcome": {"type": "string", "enum": ["ring", "pit", "sights", "tower_out"]},
        "count": {"type": "integer", "minimum": 1},
        "anchor": {"type": "boolean"},
        # before(a, b)
        "a": _EVENT_MATCH,
        "b": _EVENT_MATCH,
        # on_screen / moving / state / distinct
        "who": {"type": "string", "enum": WHO},
        "min_h": {"type": "number", "minimum": 0, "maximum": 1},
        "for_s_before": {"type": "number", "minimum": 0},
        "for_s_after": {"type": "number", "minimum": 0},
        "min_mps": {"type": "number", "minimum": 0},
        "max_mps": {"type": "number", "minimum": 0},
        "state": {"type": "string", "enum": BODY_STATES + ["alive"]},
        # scoped
        "value": {"type": "boolean"},
        # looking_at
        "landmark": {"type": "string", "enum": LANDMARKS},
        "for_s": {"type": "number", "minimum": 0},
    },
    "required": ["p"],
}

RUNNER_STEP = r"^(run(:\d+(\.\d+)?)?|stop|cover:at:\d+(\.\d+)?|shove_when_rival_within:\d+(\.\d+)?(:\d+(\.\d+)?)?|shove_when_rival_cover:\d+(\.\d+)?(:\d+(\.\d+)?)?|look:(tower|portal)(:\d+(\.\d+)?)?|portal(:\d+(\.\d+)?)?|wait:\d+(\.\d+)?|brawl|idle(:\d+(\.\d+)?)?)$"
GUARD_STEP = r"^(wait:\d+(\.\d+)?|scope|miss:\d+|hit|idle(:\d+(\.\d+)?)?)$"

FILM = {
    "type": "object",
    "properties": {
        "seat": {"type": "string", "enum": ["guard", "runner:0", "runner:1", "runner:2", "free"]},
        "map": {"type": "string", "enum": ["hell", "forest", "marble", "grey"]},
        "opening": {"type": "string", "enum": ["race", "brawl", "seat"]},
        "players": {"type": "integer", "minimum": 1, "maximum": 4},
        "old": {"type": "boolean"},
        "intents": {
            "type": "object",
            "description": "body -> comma-joined steps; runner steps: run, stop, cover:at:<s>, shove_when_rival_within:<m>, shove_when_rival_cover:<m> (shove a rival stopped at cover: the step for 'walk up to a runner stopped at cover, shove him'), look:tower:<s>, look:portal:<s>, portal, wait:<s>, brawl, idle; guard steps: wait:<s>, scope, miss:N, hit (always lands), idle. Roster: `players` includes the guard; the runners are runner:0 .. runner:(players-2) (4 players = guard, runner:0, runner:1, runner:2); never name a body outside it. Bodies not named keep their shipped brain.",
            "properties": {"guard": {"type": "string"}, "runner:0": {"type": "string"}, "runner:1": {"type": "string"}, "runner:2": {"type": "string"}},
        },
    },
    "required": ["seat", "map", "opening", "players", "old", "intents"],
}

SHOT = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "film": FILM,
        "line": {"type": "string"},
        "source": {"type": "string", "enum": ["match", "studio", "establishing", "card", "black"]},
        "match": {
            "type": "object",
            "properties": {
                "map": {"type": "string", "enum": ["hell", "forest", "marble", "grey"]},
                "opening": {"type": "string", "enum": ["race", "brawl", "seat"]},
                "players": {"type": "integer", "minimum": 1, "maximum": 4},
                "old": {"type": "boolean"},
                "same_match_as": {"type": ["string", "null"]},
            },
            "required": ["map", "opening", "players", "old", "same_match_as"],
        },
        "seat": {"type": "string", "enum": ["guard", "runner:any", "free"]},
        "find": {"type": "array", "items": PREDICATE},
        "montage": {"type": "integer", "minimum": 1, "maximum": 6},
        "window": {
            "type": "object",
            "properties": {
                "lead_s": {"type": "number", "minimum": 0},
                "tail_s": {"type": "number", "minimum": 0},
                "until": {"type": ["string", "null"], "enum": EVENTS + [None]},
                "beat": {
                    "type": ["object", "null"],
                    "properties": {
                        "word": {"type": "string"},
                        "event": {"type": "string", "enum": EVENTS},
                        "tol_s": {"type": "number", "minimum": 0},
                    },
                    "required": ["word", "event", "tol_s"],
                },
            },
            "required": ["lead_s", "tail_s", "until", "beat"],
        },
        "overlays": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "kind": {"type": "string", "enum": ["comment_card", "gif_fade"]},
                    "at": {"type": "string"},
                    "url": {"type": "string"},
                    "seconds": {"type": "number", "minimum": 0},
                },
                "required": ["kind", "at"],
            },
        },
        "camera": {"type": ["string", "null"]},
        "note": {"type": "string"},
        "unmapped": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"phrase": {"type": "string"}, "optional": {"type": "boolean"}},
                "required": ["phrase", "optional"],
            },
        },
        "interpreted": {"type": "string"},
    },
    "required": ["id", "line", "source", "match", "seat", "film", "find", "window", "overlays", "note", "unmapped", "interpreted"],
}

SHOTS = {"type": "array", "items": SHOT}

PREDICATE_DOC = """FILMING (§9, the main method): every match/studio shot is FILMED by scripted players + a real-time screen recording from the
seat's eyes: film.intents gives each scripted body its steps (comma-joined, in order); bodies not named keep their shipped
brain. Runner steps: run, cover:at:<s> (stop at cover at <s> seconds), shove_when_rival_within:<m>, look:tower:<s>,
portal, wait:<s>, brawl, idle. Guard steps: miss:N (N deliberate misses), hit, scope, idle. The guard that shoots at
runners and misses twice then hits = intents {"guard": "miss:2,hit"}; the runner the pov watches get shot = that runner
"run" and the guard "hit"; a shove into the sights = victim "run,cover:at:3", shover "run,wait:3,shove_when_rival_cover:3", guard "scope,miss:2,hit" (the hit lands after the shove). A portal/finale line (the seat reaches the tower and throws the guard out) needs the seat ALIVE: guard "scope,miss:8" (never "hit" in that match), seat "run,portal" and the predicates event(portal,by=seat), event(shove,by=seat,outcome=tower_out). A shove into the sights: the shover's step is shove_when_rival_cover:<m>:<timeout> (it walks to the covering rival), the victim cover:at:<s>, the guard scope,miss:2,wait:6,hit; its predicates are event(shove,by=seat) then event(kill,by=guard,victim=other,cause=shot) with before(shove,kill) -- never outcome=sights (the game decides that word; the kill after the shove is what the note means). Beats: only when the note names a word ("when i say ragdolls"); never a beat on a line without one. Predicates must be consistent with the intents: a kill by the guard needs guard "hit"; a shove by the seat needs the seat's shove step.
film.seat names the exact body filmed (runner:1 for a runner pov). The `find` predicates then VERIFY the take's logs.
Predicates (closed set; p = the predicate name; every field optional unless named):
- event(ev, by?, victim?, body?, cause?, result?, outcome?, count>=n, anchor?) : the event occurs >= count times in the window.
  by/victim/body are roles: seat (the recorded player), other (any other body), guard, runner:any, any.
  anchor:true marks the event the window is built around (default: the beat event, else the last event predicate).
- before(a, b) : a {ev,...} happens before b {ev,...} inside the window.
- on_screen(who, min_h, for_s_before, for_s_after) : who (victim|seat|other|guard|runner:any) is visible (vis `on`)
  with screen height >= min_h for for_s_before seconds before the anchor and for_s_after after it.
- moving(who, min_mps, max_mps?, for_s_before=1.0, for_s_after=0) : who moves at >= min_mps (and <= max_mps when given;
  idle = min_mps 0, max_mps 0.2) over for_s_before seconds before the anchor and for_s_after after it ("walk up to" =
  moving(seat) before; "continue the course"/"and run" = moving(seat, for_s_after=1.5) after).
- no_event(ev, by?) : the event never occurs in the window.
- seat_state(state=alive|dead|ghost) : the seat body's state through the window.
- distinct(who=victim) : for a montage, every clip has a different victim.
- scoped(value) : the guard seat is (not) scoped at the anchor.
- looking_at(landmark=tower|portal|lava|cover, for_s, for_s_after?) : the landmark is on screen for for_s seconds before the
  anchor (and for_s_after after it). "the lava parkour section" = looking_at(lava, ...); "get up to the portal" = looking_at(portal) + event(portal, by=seat).
- state(who, state=run|cover|dead|ragdoll|ghost|shoved|brawl) : who is in that game state before the anchor.
Game vocabulary: `kill` cause shot|pit|lava|trap|shove_pit|brawl; `shot_result` result hit|miss; `shove` outcome
ring|pit|sights|tower_out; `portal` = a runner enters the tower portal; `finale_start`/`finale_end` = the shove-the-guard
cinematic; `brawl_*` = the opening brawl in the tower; `race_*` = the opening race; `ragdoll` = a body ragdolls.
Seats: guard = the sniper's own scope camera; runner:any = a runner's own eyes; free = studio/establishing only.
The finale ("the usual cinematic shot", "watch them go flying", "they go flying") is what the SHOVING PLAYER sees in the game:
seat runner:any, event(portal, by=seat), event(finale_start, by=seat) or event(shove, by=seat, outcome=tower_out), until finale_end.
A "bust shot"/close shot of a body "idle animating" = source studio, match.map = the named map (grey if none), players 1,
seat free, camera "bust", find on_screen(other, min_h 0.5) + moving(other, min_mps 0, max_mps 0.2).
Openings: seat (guard already seated, the round runs), brawl (everyone starts in the tower), race.
Sources: match (a real bot match), studio (grey room, one body, --kill at 3.0 s), establishing (camera move over the
map, no bodies, camera "orbit"|"dolly"), card, black. "old"=true means the old death animation (pre-ragdoll build)."""
