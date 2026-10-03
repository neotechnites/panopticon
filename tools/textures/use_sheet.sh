#!/usr/bin/env bash
# Usage: use_sheet.sh <forest|prisoner> <photo|hand>. Swaps which sheet is live, saving the other first; exports.
# <home>_hand.ase exists only while the photo sheet is live, so nothing is ever overwritten unsaved.
set -e
cd "$(dirname "$0")/../.."
case "$1" in
  forest) live=maps/forest/textures/forest.ase ;;
  prisoner) live=characters/textures/prisoner.ase ;;
  *) echo "usage: $0 <forest|prisoner> <photo|hand>"; exit 1 ;;
esac
hand="${live%.ase}_hand.ase"; photo="${live%.ase}_photo.ase"
case "$2" in
  photo)
    if [ -f "$hand" ]; then echo "$1: photo sheet already live"; exit 0; fi
    [ -f "$photo" ] || { echo "no $photo: run photo_to_texture.py batch $1"; exit 1; }
    cp "$live" "$hand"; cp "$photo" "$live" ;;
  hand)
    if [ ! -f "$hand" ]; then echo "$1: hand-drawn sheet already live"; exit 0; fi
    cp "$live" "$photo"; cp "$hand" "$live"; rm "$hand" ;;
  *) echo "usage: $0 <forest|prisoner> <photo|hand>"; exit 1 ;;
esac
tools/textures/export_sheets.sh
echo "$1: $2 sheet live, PNGs exported"
