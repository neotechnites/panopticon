# Panopticon

A 3D first-person asymmetrical multiplayer game. One player occupies the tower at the centre
of the map; the others are prisoners in the ring around it, travelling from a start position
to an end position. The guard stops them by shooting them.

Ships on Steam **2027-04-01**. Windows first. Godot. Not Early Access.

## Identity — read before any git operation

This is **personal** work under `neotechnites`, and it must never touch Stack Integrated.

- Remote is SSH only: `git@github-olympus:neotechnites/panopticon.git`
- Bound to `~/.ssh/olympus_ed25519` via the `github-olympus` alias in `~/.ssh/config`
- **Never use the `gh` CLI here.** It is authenticated as the company account
  `RyanStackIntegrated` and would create repos and stamp commits under Stack Integrated.
- Local git identity is `Ryan <ryan@olympus.local>`, not the company address.

## Engine

Godot **4.7.2.stable** — pinned in `.godot-version`. Both machines must match exactly; a
mismatch silently rewrites `project.godot` and can one-way upgrade scene formats.

Renderer is **GL Compatibility**, chosen so the game runs on a wide install base.

## Layout

```
scenes/      .tscn by domain — ring/ tower/ player/ ui/
scripts/     .gd mirroring scenes, plus systems/ for non-node logic
resources/   .tres — including rules/, the match rule configs
assets/      models, audio, textures
tests/       headless suite
tools/       harness, CI helpers, ingest
```

## Two machines, synced by git and nothing else

- **Mac** — code, tests, headless runs, CI, review.
- **PC** — editor work, geometry, art, performance and feel, footage.

Never two people editing the same scene at once. Paths are **all lowercase**: exported builds
are case-sensitive even though both dev machines are not.

## Running headless

```
godot --headless --import --path .
godot --headless --path .
```

The bot harness never requires Steam — development and all headless matches run on ENet.
