class_name PanopticonEye
extends Node3D

## The eye over the yard: a box with a picture of an eye on each of its sides.
##
## [b]It is one mesh, and that is on purpose[/b]
##
## There was a thirty-one-metre tower here -- socket, lids, brow, crown -- and
## after that a lit red ball with a black band round its middle. Both were art
## nobody asked for. On 2026-09-10 Ryan ruled, having asked three times:
## [i]"i dont want the cylinder, all i want is a one way mirror, it can be the
## simple jpg of an eye four times in a box if needed."[/i] So it is a box with a
## jpg of an eye on it, floating over the centre of the ring with nothing holding
## it up. Git has everything that used to be here.
##
## [b]The one thing this class must never do[/b]
##
## Ryan settled guard vision on 2026-09-09 (pod fact
## [code]panopticon.open.guard_vision[/code]): the guard can see the whole ring
## at once -- no part of the course is hidden from the tower by geometry -- but
## the guard's point of view is NOT 360 degrees. They see what they are looking
## at, with an ordinary field of view. Attention is therefore a real, scarce
## resource the guard spends, and the entire tension of the game is that the
## prisoners cannot tell where it is being spent.
##
## So the eye [b]must not carry a single bit of information about the guard[/b].
## It does not turn towards them, brighten towards them, track them, or change
## when they aim, fire, reload, zoom, or leave the tower entirely.
##
## [b]How that survives being a box[/b]
##
## The old ball kept the promise by its shape: a solid of revolution has no
## distinguishable side, so no arrangement of it could indicate a direction. A
## box is not a solid of revolution -- it has four sides and they can be told
## apart -- so the promise is now kept three other ways, each of them structural
## rather than a matter of discipline:
##
## 1. [b]Every face carries the same picture, the same way up.[/b] One texture,
##    one material, and [member UV_TILING] laid over Godot's box UV atlas so each
##    face receives a full upright copy of it rather than a sixth of it. There is
##    no per-face material and no second texture to diverge, so there is no
##    bearing from which the box looks unlike any other bearing.
## 2. [b]It never turns.[/b] There is no rotation authored on it and nothing here
##    writes one. A box that never turns cannot point, and a box whose four sides
##    are identical could not be read even if it did.
## 3. [b]It cannot see.[/b] There is no reference anywhere in this file, or in
##    [EyeProfile], to a camera, to a rifle, to a seat, to [MatchController] or to
##    any match state. [code]tests/test_tower.gd[/code] reads both source files
##    and asserts that, so a later edit that reaches for one fails the suite.
##
## Nothing here animates at all. If anything ever does, it must be a pure
## function of the wall clock and of nothing else.
##
## Measured rather than argued: rendered from a prisoner's eye on the deck at all
## four bearings, the front face is the same 256x254 block of pixels every time
## -- at most 10 of 65,024 differ, and never by more than one step of 255, which
## is the rasteriser rounding and not a picture. There is nothing there to read.
##
## [b]The lid and the floor[/b]
##
## The tiling puts the picture on all six faces, not four, so the box has an eye
## underneath it as well -- which a prisoner does see, foreshortened, from out on
## the ring. That is a bonus rather than a cost: it is the one face everybody in
## the yard shares a view of. Its picture does turn with the world, so the same
## four renders differ over the underside where they are identical over the
## sides. That leaks a compass bearing, not a guard: which way is north is
## already obvious from the arena, and no amount of staring at it says anything
## about where the tower is looking. Removing it would take a second material,
## and a second material is the thing most likely to let the four sides drift
## apart later, which is the failure that would actually matter.
##
## [b]It is unshaded[/b]
##
## [constant BaseMaterial3D.SHADING_MODE_UNSHADED], so the picture reads
## identically from every bearing and at every time of day. Under a lit material
## the arena's sun would put a highlight on one face and leave another in shadow,
## and a face that is brighter than its neighbours is a difference between sides
## -- which is the exact shape of a tell, arrived at by lighting rather than by
## anybody meaning it.
##
## [b]What the strip-back gave up[/b]
##
## The old socket was a 15 m wall at r=8.5 that enclosed the guard, and it is
## what made the tower a literal one-way mirror: opaque from the ring, culled
## away from inside. Without it the guard stands on an open platform in plain
## sight of the course. The box is opaque and unreadable, but it does not hide
## the guard's body. Whether anything should is a design ruling of Ryan's, not
## something to restore quietly.
##
## [b]It is not in the guard's way[/b]
##
## Nothing here exists below y=12.7, and a guard's camera tops out at y=3.0 with
## the jump apex included. The box's underside is therefore well above the
## horizon from anywhere the guard can stand, and the ring is at or below the
## horizon, so no face of it is ever between them and the course. That is checked
## on a screen rather than assumed -- see the scene's editor_description for the
## measured pixel counts.
##
## Nothing here has collision and nothing here is on the rifle's hit mask, so the
## guard shoots straight through the eye and it costs the physics server nothing.
##
## [b]Renderer[/b]
##
## GL Compatibility, which is pinned for this project. One albedo texture,
## unshaded, backface-culled. There is no custom shader to fail to compile.

## How the one texture is spread over Godot's box UVs.
##
## [BoxMesh] does not give each face the full 0..1 square. It lays the six faces
## out as an atlas -- three across, two down -- so an untiled texture would put a
## different sixth of the image on each face, which is the worst possible outcome
## here: six sides that are all different. Scaling UV1 by exactly that atlas
## shape maps every cell back onto the whole texture, so each face draws a
## complete, upright copy.
##
## It is a constant rather than an export because it is not a preference. It is
## the mechanism by which all four sides are the same, and a value in the
## inspector could quietly break the promise the class exists to keep.
## [code]tests/test_tower.gd[/code] asserts it.
const UV_TILING: Vector3 = Vector3(3.0, 2.0, 1.0)

## The material the box is drawn with. It is exported rather than found by
## walking the mesh children so that this script never has to guess: the scene
## says it, once, in one place.
##
## It is [member Resource.resource_local_to_scene], so each eye owns the material
## it draws with and writing a profile onto one eye cannot reach another -- or,
## more to the point, cannot leak out of a test and into the rest of the suite.
## [code]tests/test_tower.gd[/code] asserts that the material this script writes
## to is the same object the mesh renders with, because a mis-remapped local
## resource fails silently: the profile is applied perfectly, to a copy nothing
## renders.
@export var face_material: StandardMaterial3D

## The picture and the size. Falls back to a default-constructed [EyeProfile]
## with a warning rather than to nothing, because an eye that silently failed to
## appear is a bug that reads as "the tower is just a platform again".
@export var profile: EyeProfile


func _ready() -> void:
	if profile == null:
		push_warning("PanopticonEye has no EyeProfile; falling back to defaults.")
		profile = EyeProfile.new()

	scale = Vector3.ONE * profile.size_scale
	_apply_faces()


func _apply_faces() -> void:
	if not _usable(face_material):
		return
	face_material.albedo_texture = profile.eye_texture
	face_material.uv1_scale = UV_TILING
	if profile.eye_texture == null:
		push_warning("EyeProfile has no eye_texture; the box will be blank on every side.")


## Reports a missing material, and refuses to let a shaded, front-face-culled,
## transparent or depth-testless one through quietly.
##
## Each of those breaks the eye in a way no other test would notice. Shading
## lights one face differently from another, which is a difference between sides.
## Culling off or reversed draws the inside of the box as well as the outside.
## Transparency lets a prisoner see into it. No depth test draws it over the
## whole ring from anywhere on the map. All four are one line to get wrong in the
## inspector and none of them can be seen in a headless run, so they are checked
## here as well as in the suite.
func _usable(material: StandardMaterial3D) -> bool:
	if material == null:
		push_error("PanopticonEye.face_material is unset; the eye will render untextured.")
		return false
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		push_error("PanopticonEye.face_material must be unshaded, or the sun tells one side from another.")
	if material.cull_mode != BaseMaterial3D.CULL_BACK:
		push_error("PanopticonEye.face_material must be backface-culled.")
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		push_error("PanopticonEye.face_material must be opaque; prisoners must not see into the eye.")
	if material.no_depth_test:
		push_error("PanopticonEye.face_material has depth testing off; it would draw over the whole ring.")
	return true
