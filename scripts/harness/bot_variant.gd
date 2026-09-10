class_name BotVariant
extends RefCounted

## One arm of a sweep: a name, a [MatchRules], and the reason it is in the run.
##
## A sweep exists to answer "which of these is better", and an answer is only
## worth having if the question survives next to it. [member notes] is written
## into the aggregate file so a result nobody remembers commissioning can still
## be read six months later.

## Short, file-safe label. Becomes part of the result filenames.
var name: String = "default"

## What this arm is being asked. Free text, carried into the aggregate.
var notes: String = ""

## The rules this arm plays. Owned by the variant: every arm gets its own
## instance, so a match cannot retune the arm that runs after it.
var rules: MatchRules = null
