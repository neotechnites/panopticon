class_name PanopticonEye
extends Node3D

## The eye: a box with a picture of an eye on each side, standing on the tower
## platform with the guard inside it.
##
## [b]It is one mesh, and that is on purpose[/b]
##
## There was a thirty-one-metre tower here -- socket, lids, brow, crown -- and
## after that a lit red ball with a black band round its middle, and after that
## the same box as this one floating 16.7 m overhead. On 2026-09-10 Ryan ruled,
## having asked three times for something simpler: [i]"i dont want the cylinder,
## all i want is a one way mirror, it can be the simple jpg of an eye four times
## in a box if needed"[/i], and then, on seeing it, [i]"the eye box is right but
## should be at eye level, and be a one way mirror to cover the shooter."[/i]
## So the box came down out of the sky and closed round the guard. Git has
## everything that used to be here.
##
## [b]The one-way mirror, and how it actually works[/b]
##
## The box is a closed surface whose triangles all face outward, drawn with
## [constant BaseMaterial3D.CULL_BACK]. From the ring every face is front-facing:
## an opaque wall with an eye on it, four metres of it, and nothing of the guard.
## From inside -- which is where the guard is, and the only place anybody is
## inside it -- every face is back-facing and the rasteriser throws all of them
## away before they are ever shaded. The guard looks out through a wall that
## costs them nothing: no tint, no glass, no seam, not one pixel of the ring.
##
## That is not a trick invented here. It is what the old 15 m socket drum did,
## and it is the only technique in the project that makes "one-way" a fact about
## the renderer rather than an intention. The scale is new; the mechanism is not.
##
## [b]Why it is at y=1.9[/b]
##
## Because that is where the guard's eye is: they spawn at y=0.25 and their head
## sits 1.65 m above their feet. The box is centred there, so its pupils are
## level with the guard inside it and level with every prisoner running the deck
## outside it. Until today the eye floated at 16.7 m and the guard sat at 1.9,
## and the project had carried that disagreement as an open question all night.
## Ryan settled it in this direction: the eye comes down to the guard.
##
## [b]The one thing this class must never do[/b]
##
## Ryan settled guard vision on 2026-09-09 (pod fact
## [code]panopticon.open.guard_vision[/code]): the guard can see the whole ring at
## once, but their point of view is not 360 degrees. They see what they are
## looking at, with an ordinary field of view. Attention is a real, scarce
## resource, and the entire tension of the game is that the prisoners cannot tell
## where it is being spent.
##
## So the eye [b]must not carry a single bit of information about the guard[/b].
## It does not turn towards them, brighten towards them, track them, or change
## when they aim, fire, reload, zoom, or leave the tower entirely. A box is not a
## solid of revolution -- it has four sides and they can be told apart -- so that
## promise is kept three structural ways rather than by discipline:
##
## 1. [b]Every face carries the same picture, the same way up, at the same size.[/b]
##    One texture, one material, and [method uv_tiling_for] laid over Godot's box
##    UV atlas so each face receives whole upright copies rather than a sixth of
##    the image. There is no per-face material and no second texture to diverge,
##    so there is no bearing from which the box looks unlike any other bearing.
## 2. [b]It never turns.[/b] There is no rotation authored on it and nothing here
##    writes one. A box that never turns cannot point.
## 3. [b]It cannot see.[/b] There is no reference anywhere in this file, or in
##    [EyeProfile], to a camera, to a rifle, to a seat, to [MatchController] or to
##    any match state. [code]tests/test_tower.gd[/code] reads both source files
##    and asserts that, so a later edit that reaches for one fails the suite.
##
## Nothing here animates at all. If anything ever does, it must be a pure
## function of the wall clock and of nothing else.
##
## [b]It is unshaded[/b]
##
## [constant BaseMaterial3D.SHADING_MODE_UNSHADED], so the picture reads
## identically from every bearing and at every time of day. Under a lit material
## the arena's sun would put a highlight on one face and leave another in shadow,
## and a face brighter than its neighbours is a difference between sides -- the
## exact shape of a tell, arrived at by lighting rather than by anybody meaning
## it, and one that would drift through the day.
##
## [b]It does not trap the guard and it does not stop a bullet[/b]
##
## Nothing here has collision and nothing here is on the rifle's hit mask. The
## guard walks through their own cover if they want to, and their shots leave
## through it without knowing it was there.
##
## [b]Renderer[/b]
##
## GL Compatibility, which is pinned for this project. One albedo texture,
## unshaded, backface-culled. There is no custom shader to fail to compile, and
## backface culling is the oldest guarantee the pipeline has.

## The shape of [BoxMesh]'s UV atlas: three cells across, two down.
##
## [BoxMesh] does not give each face the full 0..1 square. It lays the six faces
## out in this grid, so a texture applied naively puts a [i]different sixth of the
## image[/i] on each face -- six sides that are all different, which is the worst
## possible outcome here and looks perfectly reasonable in the inspector.
## Scaling UV1 by this shape maps every cell back onto the whole texture.
const UV_ATLAS: Vector2 = Vector2(3.0, 2.0)

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

## The box. Named rather than found by walking the children, for the same reason
## the material is exported: this script should never have to guess which node is
## which. Read for its proportions only -- the tiling has to know how much wider
## a face is than it is tall. A [NodePath] rather than a typed node reference
## because that is the idiom the rest of the project uses (see
## [member MatchController.spawn_marker_path]) and it survives a hand-edited
## scene file, which a typed export does not.
@export var box_path: NodePath = ^"Box"

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


## How many times the picture repeats across a face, so that every copy is
## square.
##
## The box is much wider than it is tall -- it has to span an 18 m platform while
## staying low enough not to be a tower again -- so one copy per face would be an
## eye stretched four times wider than it is high, which does not read as an eye
## at all. Repeating it along the face instead keeps every copy square, and the
## count falls out of the proportions rather than being a number somebody typed:
## a face four times wider than it is tall gets four eyes. This is where Ryan's
## "the simple jpg of an eye four times in a box" landed literally.
##
## Vertical faces only decide this. The lid and the floor take whatever it gives
## them, which is fine, because nobody can get above the box or under the
## platform to look at either.
##
## Static and pure so the suite can assert the shape of the tiling without
## building an eye.
static func uv_tiling_for(size: Vector3) -> Vector3:
	var aspect: float = 1.0 if size.y <= 0.0 else size.x / size.y
	return Vector3(UV_ATLAS.x * aspect, UV_ATLAS.y, 1.0)


func _apply_faces() -> void:
	if not _usable(face_material):
		return
	face_material.albedo_texture = profile.eye_texture

	var surface: MeshInstance3D = get_node_or_null(box_path) as MeshInstance3D
	var mesh: BoxMesh = null if surface == null else surface.mesh as BoxMesh
	if mesh == null:
		push_error("PanopticonEye.box_path does not point at a BoxMesh; the eye cannot size its own picture.")
		return
	face_material.uv1_scale = uv_tiling_for(mesh.size)
	if profile.eye_texture == null:
		push_warning("EyeProfile has no eye_texture; the box will be blank on every side.")


## Reports a missing material, and refuses to let a shaded, front-face-culled,
## transparent or depth-testless one through quietly.
##
## Each of those breaks the eye in a way no other test would notice, and the
## culling one breaks it in both directions at once. Front-face culling turns the
## box inside out: the guard would be walled in and the ring would see straight
## through to them, which is the one-way mirror exactly backwards. Shading lights
## one face differently from another. Transparency lets a prisoner see in. No
## depth test draws the box over the whole ring from anywhere on the map. All
## four are one line to get wrong in the inspector and none of them can be seen
## in a headless run, so they are checked here as well as in the suite.
func _usable(material: StandardMaterial3D) -> bool:
	if material == null:
		push_error("PanopticonEye.face_material is unset; the eye will render untextured.")
		return false
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		push_error("PanopticonEye.face_material must be unshaded, or the sun tells one side from another.")
	if material.cull_mode != BaseMaterial3D.CULL_BACK:
		push_error("PanopticonEye.face_material must be backface-culled, or the mirror faces the wrong way.")
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		push_error("PanopticonEye.face_material must be opaque; prisoners must not see the guard through it.")
	if material.no_depth_test:
		push_error("PanopticonEye.face_material has depth testing off; it would draw over the whole ring.")
	return true
