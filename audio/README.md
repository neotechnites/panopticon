# assets/audio

Everything in here beginning with `placeholder_` is a **synthesised beep, not
sound design.** They are square waves, sine sweeps and noise bursts, generated
by `scripts/audio/placeholder_forge.gd`, and they exist for two reasons: so the
audio event system can be proved to work end to end before any audio has been
commissioned, and so the game is legible to play in the meantime. They are meant
to be replaced and to sound obviously temporary until they are.

## Swapping in real audio

One cue, one drag. No code changes, no scene changes.

1. Put the file (`.wav` or `.ogg`) anywhere under `res://assets/audio/`. Godot
   imports it on the next editor focus, or on
   `godot --headless --path . --import`.
2. Open `res://scenes/audio/placeholder_bank.tres` in the inspector.
3. Expand `Cues` and find the one whose `Event` is the name you are replacing —
   the names are the constants in `scripts/audio/audio_events.gd`.
4. Drag the new file onto that cue's `Stream`. Save the bank.

That is the whole procedure. Nothing outside the bank knows a filename: gameplay
code posts an event name and stops there, so a replaced sound is invisible to
every script in the project. Trim, pitch, bus, world placement and rate limits
are the other fields on the same cue and can be tuned in the same pass.

Once every cue that referenced a `placeholder_*.wav` has been repointed, delete
that `.wav` and its `.import` sibling.

## Adding a sound that does not exist yet

1. Add a constant to `AudioEvents` and put it in `AudioEvents.ALL`.
2. Add a cue for it to the bank with the stream attached.
3. Post it from wherever the thing happens — usually by adding one line to
   `MatchAudioListener` or `UIAudioListener`, so no gameplay file has to change.

An event with no cue, and a cue with no stream, are both silent no-ops. Steps
can therefore be done in any order and a half-finished one never crashes.

## Regenerating the placeholders

```
godot --headless --path . --script res://scripts/audio/placeholder_forge.gd -- --wavs
godot --headless --path . --import
godot --headless --path . --script res://scripts/audio/placeholder_forge.gd -- --bank
```

The third step **overwrites `scenes/audio/placeholder_bank.tres`** and will
discard any hand-editing. Once real audio starts landing, run only the first
step: the filenames do not change, so an existing bank keeps working.

## Proving it still works

```
godot --headless --path . --script res://scripts/audio/audio_system_check.gd
```
