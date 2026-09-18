#!/usr/bin/env python3
"""
glb_region_diff -- prove that editing one angular section of the PANOPTICON
map left the rest of the mesh triangle-identical.

The map is a ring. Work on it arrives as "resculpt the section from 145 to 200
degrees": one wedge of the panopticon, one set of cells, one stretch of wall.
The whole ring is rebuilt by the generator every time, because the generator is
the only thing that knows how the ring is stitched. So every edit to one wedge
re-emits all 360 degrees of geometry, and the claim that only the wedge moved
is a claim about a file that was written from scratch.

That claim is the thing that gets believed without evidence. A parameter that
was meant to be local turns out to be read by the whole loop; a vertex count
change shifts a seam ring two degrees away; a "harmless" cleanup pass reflows
the whole mesh. Nothing warns. The section under review looks right in Godot,
it ships, and three sections away a wall is a centimetre thinner than the
collision that was cooked against the old build.

A byte diff cannot settle it -- the exporter reorders buffers freely, so two
byte-different files are routinely the same geometry. A triangle count cannot
settle it either: counts are preserved by exactly the reflow that matters. So
this bins the geometry by WHERE IT IS and compares each bin's contents.

    python3 tools/modelling/lib/glb_region_diff.py <old.glb> <new.glb>
                                                   --section A,B
                                                   [--bucket 5.0] [--json]

WHAT IT MEASURES

For each file, every art triangle is placed in an angular bucket by the game
bearing of its centroid, and each bucket gets:

* a triangle count, and
* a fingerprint -- a hash over the bucket's triangles, each reduced to its
  three welded corner positions. The triangles in a bucket are sorted before
  hashing and each triangle's three corners are sorted within it, so the
  fingerprint is invariant to the order the exporter happened to emit
  geometry in and to which corner it called first. Two builds that emit the
  same geometry differently compare EQUAL; that is the whole point, because
  reordering is the normal, innocent difference between two builds.

A bucket wholly outside the edited section must match on BOTH. Matching
counts with different fingerprints is the dangerous case -- geometry moved
without changing how much of it there is -- and it is the case a count-only
check misses.

FRAME

Vertices arrive in the .glb's own space and are pushed through their node
transforms first, exactly as glb_audit does, so instanced and parented
geometry is compared in one space. glTF is Y-UP: a build script authored in
Blender's Z-up frame comes out of the exporter as (x, z_blender, -y_blender),
which is precisely Godot's own (x, y, z). So axis 1 is HEIGHT, the ground
plane is axes 0 and 2, and the game bearing of a point is

    degrees(atan2(z, x)) mod 360

with no sign flip: the handedness change already happened in the exporter.
(Reading axis 1 as a ground coordinate is the mistake this comment exists to
stop: on this map it silently bins the whole ring by its HEIGHT, every bucket
comes out plausible, and the answer is meaningless.) Radius and height are
deliberately ignored. A section is a wedge of all radii and all heights, so
bearing is the only coordinate the question is about, and binning on radius as
well would only split identical geometry into more bins without making the
answer sharper.

A triangle whose centroid sits exactly on the ring axis has no meaningful
bearing; atan2 gives it 0.0 and it lands in the first bucket. The map has no
geometry there, and if it ever does, it is reported in a bucket like anything
else rather than silently dropped.

ART VERSUS COLLISION

Only art triangles are compared, and art versus collision is decided exactly
as glb_audit decides it: by glb_audit.is_collision_name, applied per node and
per mesh inside glb_audit.collect_primitives. Collision hulls are cooked from
the art and are regenerated wholesale, so holding them to a per-bucket identity
rule would fail every build for a reason that is not a defect.

SECTION EDGES

Buckets and the section are both half-open, [start, end). A bucket is INSIDE
when it lies wholly within the section, OUTSIDE when it does not touch the
section at all, and STRADDLING otherwise. A straddling bucket contains both
edited and untouched geometry, so it can never be judged: it is always
reported and never fails the run. Choosing a bucket size that divides the
section evenly (the default 5.0 divides 145..200) leaves no straddling
buckets at all, which is why the default is a round number.

A section may wrap past 360: --section 350,10 is the twenty degrees either
side of north, not the three hundred and forty degrees between them.

Exits 0 after printing REGION OK, or 1 after printing REGION FAIL <reason>
naming the first offending bucket.
"""

import hashlib
import json
import math
import os
import sys

# glb_audit lives beside this file. Importing it by name has to work when this
# script is run by path from anywhere in the build, which is the normal case.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from glb_audit import (  # noqa: E402  (deliberately after the path insert)
    WELD_QUANTUM,
    collect_primitives,
    parse_glb,
    weld_key,
)

# =============================================================================
# TUNABLES
# =============================================================================

# Bucket width in degrees. Wide enough that a bucket holds thousands of
# triangles (so a fingerprint is cheap relative to the number of triangles it
# certifies), narrow enough to localise a defect to a wedge a modeller can
# find. 5.0 divides 360 exactly and divides the section sizes the map is
# authored in, which keeps straddling buckets out of the report.
DEFAULT_BUCKET_DEGREES = 5.0

# Bucket widths outside this range are refused rather than coped with: below
# it the buckets hold single triangles and float noise in a centroid decides
# which bucket a triangle falls in; above it a bucket is most of the map and
# the report stops localising anything.
MIN_BUCKET_DEGREES = 0.01
MAX_BUCKET_DEGREES = 180.0

# A full turn. Named because it appears as a modulus, a clip and a bound.
FULL_TURN_DEGREES = 360.0

# Hex characters of the per-bucket hash that get printed and compared. A
# fingerprint is compared against a fingerprint of the same geometry, not
# searched for in a corpus, so this only has to make an accidental collision
# between two different wedges implausible. 16 hex characters is 64 bits.
FINGERPRINT_DIGITS = 16

# Corner positions are quantised onto glb_audit's weld grid (WELD_QUANTUM,
# one micrometre) before hashing, for the reason glb_audit welds at all: the
# same authored vertex reached through two different node matrices can differ
# in the last bit of a float, and two builds are not different because of it.
FINGERPRINT_QUANTUM = WELD_QUANTUM

# Zone names, so the text report and the JSON report cannot drift apart.
ZONE_INSIDE = "inside"
ZONE_OUTSIDE = "outside"
ZONE_STRADDLE = "straddle"


# =============================================================================
# BEARINGS AND BUCKETS
# =============================================================================


def game_bearing_degrees(ground_x, ground_z):
    """Game bearing of a glTF/Godot ground position, in [0, 360).

    Takes axes 0 and 2 of a .glb position -- NOT axis 1, which is height.
    """
    bearing = math.degrees(math.atan2(ground_z, ground_x))
    bearing = math.fmod(bearing, FULL_TURN_DEGREES)
    if bearing < 0.0:
        bearing += FULL_TURN_DEGREES
    # fmod of a tiny negative angle can round up to exactly 360.0 once the
    # turn is added back, which would index one bucket past the end.
    if bearing >= FULL_TURN_DEGREES:
        bearing = 0.0
    return bearing


def bucket_count_for(bucket_degrees):
    """Number of buckets covering the full turn at this bucket width."""
    return int(math.ceil(FULL_TURN_DEGREES / bucket_degrees))


def bucket_bounds(bucket_index, bucket_degrees):
    """Return the half-open [start, end) degrees of one bucket.

    The last bucket is clipped to 360 so that a width which does not divide
    the turn evenly still covers it exactly once, with no overlap.
    """
    start = bucket_index * bucket_degrees
    end = min((bucket_index + 1) * bucket_degrees, FULL_TURN_DEGREES)
    return start, end


def bucket_index_for(bearing, bucket_degrees, total_buckets):
    """Bucket holding this bearing. Clamped, because float division at the
    very top of the range can land one past the last bucket."""
    index = int(bearing / bucket_degrees)
    if index < 0:
        return 0
    if index >= total_buckets:
        return total_buckets - 1
    return index


def normalise_degrees(value):
    """Fold any angle into [0, 360)."""
    folded = math.fmod(float(value), FULL_TURN_DEGREES)
    if folded < 0.0:
        folded += FULL_TURN_DEGREES
    if folded >= FULL_TURN_DEGREES:
        folded = 0.0
    return folded


def classify_bucket(start, end, section_start, section_end):
    """Return which zone the half-open bucket [start, end) is in.

    The section is half-open too. When section_start > section_end the section
    wraps past 360 and is the union [section_start, 360) + [0, section_end).
    """
    if section_start <= section_end:
        if start >= section_start and end <= section_end:
            return ZONE_INSIDE
        if end <= section_start or start >= section_end:
            return ZONE_OUTSIDE
        return ZONE_STRADDLE

    # Wrapped section.
    if start >= section_start or end <= section_end:
        return ZONE_INSIDE
    if end <= section_start and start >= section_end:
        return ZONE_OUTSIDE
    return ZONE_STRADDLE


# =============================================================================
# PER-FILE MEASUREMENT
# =============================================================================


def triangle_identity(corner_a, corner_b, corner_c, quantum=FINGERPRINT_QUANTUM):
    """Order-independent identity of one triangle: its three welded corners.

    Each corner is snapped onto the weld grid by glb_audit's weld_key, giving
    integers rather than floats so that the identity carries no representation
    noise. The three corners are then SORTED, which throws away winding along
    with corner order: a triangle whose normal was flipped without moving is
    reported as unchanged. That is the right trade here -- this tool answers
    "did the geometry outside the section move", and glb_audit is what checks
    the mesh is well formed -- but it is a real limit and not a bug.
    """
    corners = sorted((
        weld_key(corner_a, quantum),
        weld_key(corner_b, quantum),
        weld_key(corner_c, quantum),
    ))
    return (
        corners[0][0], corners[0][1], corners[0][2],
        corners[1][0], corners[1][1], corners[1][2],
        corners[2][0], corners[2][1], corners[2][2],
    )


def bucket_art_triangles(path, bucket_degrees):
    """Bin one .glb's art triangles by centroid bearing.

    Returns (counts, identities, total_triangles) where counts and identities
    are lists indexed by bucket: counts[i] is how many art triangles fell in
    bucket i, identities[i] is the unsorted list of their triangle identities.
    """
    gltf, blob = parse_glb(path)
    # collect_primitives applies the node transforms and splits art from
    # collision by glb_audit.is_collision_name. The collision population is
    # not compared, for the reason in the module brief.
    art_primitives, _collision_primitives, _stats = collect_primitives(gltf, blob)

    total_buckets = bucket_count_for(bucket_degrees)
    counts = [0] * total_buckets
    identities = [[] for _ in range(total_buckets)]
    total_triangles = 0

    one_third = 1.0 / 3.0
    for positions, indices in art_primitives:
        for corner in range(0, len(indices) - 2, 3):
            corner_a = positions[indices[corner]]
            corner_b = positions[indices[corner + 1]]
            corner_c = positions[indices[corner + 2]]

            centroid_x = (corner_a[0] + corner_b[0] + corner_c[0]) * one_third
            centroid_z = (corner_a[2] + corner_b[2] + corner_c[2]) * one_third
            bearing = game_bearing_degrees(centroid_x, centroid_z)
            index = bucket_index_for(bearing, bucket_degrees, total_buckets)

            counts[index] += 1
            identities[index].append(triangle_identity(corner_a, corner_b, corner_c))
            total_triangles += 1

    return counts, identities, total_triangles


def fingerprint_bucket(triangle_identities):
    """Stable hash of one bucket's triangles, independent of emission order.

    Sorting the identities is what makes the hash order-independent; hashing
    the sorted run rather than, say, summing per-triangle hashes is what keeps
    it sensitive to a triangle being duplicated or dropped.
    """
    digest = hashlib.sha256()
    for identity in sorted(triangle_identities):
        digest.update(("%d,%d,%d;%d,%d,%d;%d,%d,%d\n" % identity).encode("ascii"))
    return digest.hexdigest()[:FINGERPRINT_DIGITS]


def fingerprint_all_buckets(identities):
    """Fingerprint every bucket of one file."""
    return [fingerprint_bucket(bucket) for bucket in identities]


# =============================================================================
# COMPARISON
# =============================================================================


def compare(old_path, new_path, section_start, section_end,
            bucket_degrees=DEFAULT_BUCKET_DEGREES):
    """Compare two .glb files bucket by bucket and return the full result."""
    old_counts, old_identities, old_total = bucket_art_triangles(old_path, bucket_degrees)
    new_counts, new_identities, new_total = bucket_art_triangles(new_path, bucket_degrees)
    old_fingerprints = fingerprint_all_buckets(old_identities)
    new_fingerprints = fingerprint_all_buckets(new_identities)

    total_buckets = bucket_count_for(bucket_degrees)
    buckets = []
    zone_totals = {
        ZONE_INSIDE: [0, 0],
        ZONE_OUTSIDE: [0, 0],
        ZONE_STRADDLE: [0, 0],
    }
    fail_reason = None

    for index in range(total_buckets):
        start, end = bucket_bounds(index, bucket_degrees)
        zone = classify_bucket(start, end, section_start, section_end)
        old_count = old_counts[index]
        new_count = new_counts[index]
        old_fingerprint = old_fingerprints[index]
        new_fingerprint = new_fingerprints[index]
        changed = (old_count != new_count) or (old_fingerprint != new_fingerprint)

        zone_totals[zone][0] += old_count
        zone_totals[zone][1] += new_count

        if zone == ZONE_OUTSIDE and changed and fail_reason is None:
            if old_count != new_count:
                fail_reason = (
                    "bucket %s..%s outside the section changed count old=%d new=%d"
                    % (format_degrees(start), format_degrees(end), old_count, new_count)
                )
            else:
                fail_reason = (
                    "bucket %s..%s outside the section kept %d triangle(s) but moved "
                    "them: fingerprint %s -> %s"
                    % (format_degrees(start), format_degrees(end), old_count,
                       old_fingerprint, new_fingerprint)
                )

        buckets.append({
            "index": index,
            "start": start,
            "end": end,
            "zone": zone,
            "old_tris": old_count,
            "new_tris": new_count,
            "delta_tris": new_count - old_count,
            "old_fingerprint": old_fingerprint,
            "new_fingerprint": new_fingerprint,
            "changed": changed,
        })

    return {
        "old_file": os.path.basename(old_path),
        "new_file": os.path.basename(new_path),
        "old_path": old_path,
        "new_path": new_path,
        "section_start": section_start,
        "section_end": section_end,
        "section_wraps": section_start > section_end,
        "bucket_degrees": bucket_degrees,
        "buckets": buckets,
        "art_tris_old": old_total,
        "art_tris_new": new_total,
        "art_tris_delta": new_total - old_total,
        "inside_old": zone_totals[ZONE_INSIDE][0],
        "inside_new": zone_totals[ZONE_INSIDE][1],
        "inside_delta": zone_totals[ZONE_INSIDE][1] - zone_totals[ZONE_INSIDE][0],
        "outside_old": zone_totals[ZONE_OUTSIDE][0],
        "outside_new": zone_totals[ZONE_OUTSIDE][1],
        "outside_delta": zone_totals[ZONE_OUTSIDE][1] - zone_totals[ZONE_OUTSIDE][0],
        "straddle_old": zone_totals[ZONE_STRADDLE][0],
        "straddle_new": zone_totals[ZONE_STRADDLE][1],
        "outside_identical": fail_reason is None,
        "ok": fail_reason is None,
        "fail_reason": fail_reason,
    }


# =============================================================================
# REPORT
# =============================================================================


def format_degrees(value):
    """Degrees with at least one decimal and no trailing noise."""
    text = "%.4f" % float(value)
    if "." in text:
        text = text.rstrip("0")
        if text.endswith("."):
            text += "0"
    return text


def reported_buckets(result):
    """The buckets the report prints: every changed one, plus every bucket
    that touches the section. A reader has to be able to see the section they
    asked about even when nothing in it moved -- an edit that silently did
    nothing is its own kind of defect."""
    out = []
    for bucket in result["buckets"]:
        touches_section = bucket["zone"] in (ZONE_INSIDE, ZONE_STRADDLE)
        if bucket["changed"] or touches_section:
            out.append(bucket)
    return out


def format_block(result):
    """The greppable block. One fact per token, never reordered."""
    lines = [
        "REGION old=%s new=%s section=%s..%s bucket=%s" % (
            result["old_file"], result["new_file"],
            format_degrees(result["section_start"]),
            format_degrees(result["section_end"]),
            format_degrees(result["bucket_degrees"])),
        "REGION art_tris old=%d new=%d delta=%+d" % (
            result["art_tris_old"], result["art_tris_new"], result["art_tris_delta"]),
        "REGION inside  old=%d new=%d delta=%+d" % (
            result["inside_old"], result["inside_new"], result["inside_delta"]),
        "REGION outside old=%d new=%d delta=%+d  identical=%s" % (
            result["outside_old"], result["outside_new"], result["outside_delta"],
            "yes" if result["outside_identical"] else "no"),
    ]
    for bucket in reported_buckets(result):
        lines.append("REGION bucket %s..%s old=%d new=%d  %s" % (
            format_degrees(bucket["start"]), format_degrees(bucket["end"]),
            bucket["old_tris"], bucket["new_tris"],
            "CHANGED" if bucket["changed"] else "same"))
    return lines


def json_payload(result):
    """The same facts as the block, as one object."""
    payload = dict(result)
    payload["buckets"] = [dict(bucket) for bucket in reported_buckets(result)]
    return payload


USAGE = """usage: glb_region_diff.py <old.glb> <new.glb> --section A,B
                          [--bucket 5.0] [--json]

  --section A,B   the angular section that was edited, in game-bearing
                  degrees, half-open [A, B). A > B wraps past 360.
  --bucket D      bucket width in degrees (default %s). Pick one that divides
                  the section, so no bucket straddles its edges.
  --json          print the result as one JSON object instead of the block

Exits 0 when every bucket wholly outside the section has both an identical
triangle count and an identical order-independent fingerprint; 1 otherwise.
Buckets straddling a section edge are reported and never fail the run.
""" % format_degrees(DEFAULT_BUCKET_DEGREES)


def parse_section(text):
    """Parse 'A,B' into two normalised bearings."""
    parts = text.split(",")
    if len(parts) != 2:
        raise ValueError("--section wants two comma-separated degrees, got %r" % text)
    try:
        start = float(parts[0])
        end = float(parts[1])
    except ValueError:
        raise ValueError("--section wants two numbers, got %r" % text)
    return normalise_degrees(start), normalise_degrees(end)


def main(argv):
    old_path = None
    new_path = None
    section_text = None
    bucket_degrees = DEFAULT_BUCKET_DEGREES
    as_json = False

    rest = list(argv)
    while rest:
        arg = rest.pop(0)
        if arg == "--json":
            as_json = True
        elif arg in ("-h", "--help"):
            sys.stdout.write(USAGE)
            return 0
        elif arg in ("--section", "--bucket"):
            if not rest:
                sys.stdout.write("REGION FAIL %s needs a value\n" % arg)
                return 1
            value = rest.pop(0)
            if arg == "--section":
                section_text = value
            else:
                try:
                    bucket_degrees = float(value)
                except ValueError:
                    sys.stdout.write("REGION FAIL --bucket needs a number\n")
                    return 1
        elif arg.startswith("-"):
            sys.stdout.write("REGION FAIL unknown option %s\n" % arg)
            return 1
        elif old_path is None:
            old_path = arg
        elif new_path is None:
            new_path = arg
        else:
            sys.stdout.write("REGION FAIL more than two files given\n")
            return 1

    if old_path is None or new_path is None:
        sys.stdout.write(USAGE)
        return 1
    if section_text is None:
        sys.stdout.write("REGION FAIL --section A,B is required\n")
        return 1
    if not MIN_BUCKET_DEGREES <= bucket_degrees <= MAX_BUCKET_DEGREES:
        sys.stdout.write("REGION FAIL --bucket %s is outside %s..%s degrees\n" % (
            format_degrees(bucket_degrees), format_degrees(MIN_BUCKET_DEGREES),
            format_degrees(MAX_BUCKET_DEGREES)))
        return 1

    try:
        section_start, section_end = parse_section(section_text)
        result = compare(old_path, new_path, section_start, section_end,
                         bucket_degrees=bucket_degrees)
    except (ValueError, OSError, KeyError, IndexError) as error:
        # This runs inside the build pipeline and the pipeline reads the exit
        # code, so an unreadable file is a failed comparison, not a traceback.
        sys.stdout.write("REGION FAIL cannot compare %s and %s: %s\n"
                         % (old_path, new_path, error))
        return 1

    if as_json:
        sys.stdout.write(json.dumps(json_payload(result), indent=2, sort_keys=True) + "\n")
    else:
        for line in format_block(result):
            sys.stdout.write(line + "\n")
        if result["ok"]:
            sys.stdout.write("REGION OK outside the section is triangle-identical\n")
        else:
            sys.stdout.write("REGION FAIL %s\n" % result["fail_reason"])

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
