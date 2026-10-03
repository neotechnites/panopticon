extends TestCase

## Map 2's tower, proved to be SAMPLED correctly rather than painted correctly.
##
## [b]Ryan, 2026-09-23: "the marble tower is still wobbly".[/b] Still, because a
## pass before this one repainted the sheets and the wobble survived it. The
## sheets were never the defect. The sampling was.
##
## [b]What was measured.[/b] maps/marble/models/marble_tower.glb embeds eleven albedo
## sheets ([code]gltf/embedded_image_handling=3[/code], uncompressed). Godot's
## glTF importer built each one as an [ImageTexture] with [b]no mip chain[/b],
## while every material on the tower asked for
## [constant BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS]. A filter that
## wants mipmaps and a texture that has none is not an error anywhere: the
## sampler simply falls back, so every pixel of the tower read mip 0 at every
## distance. From the lane -- 45 m out, where one screen pixel covers about 2.5
## texels -- the 1-texel masonry joints were being point-sampled at better than
## two to one, and the shaft's courses broke into speckle that crawled with the
## camera. That is the wobble.
##
## [b]Geometry was ruled out first, by measurement, not by eye.[/b] All nine
## bare-shaft rings are regular 16-gons: out-of-round 4.2e-7 m, azimuth drift
## 0.000000000 deg, and every ring centroid on the axis to 0.000000000 m. In a
## flat-grey in-game capture the shaft's silhouette is two dead-vertical lines.
## Nothing about the shape moves. Only the stone on it did.
##
## [b]Why a screenshot did not catch it, and cannot.[/b] A still frame is a
## single set of texture fetches, and mip 0 is the sharpest set there is -- the
## still looks better than the fix does. The defect only exists across frames:
## it is the sampled texel CHANGING under a pixel that barely moved. A
## screenshot is precisely the instrument blind to it, which is why this guard
## is a test that asks the imported resource what it is, and not another render.
##
## [b]What this file therefore asserts[/b] is what the importer produced, on the
## resource the game loads: a mip chain on every sheet, the one filter that uses
## it, and eleven sheets still there.

## The tower as the game loads it: the imported .glb. Not the PNGs on disk --
## those were never the thing that was wrong.
const TOWER_PATH: String = "res://maps/marble/models/marble_tower.glb"

## How many albedo sheets the tower ships. Eleven material classes, one tiling
## sheet each (band, coffer, column, dome, floor, iron, marble2, medallion,
## plinth, shade, stone), one texture apiece -- the count the contract in
## tools/modelling/maps/marble/marble_tower.contract.json calls "ELEVEN surfaces". An import
## change that quietly folds two together, or drops one, is a change to the art,
## and this number is how that gets noticed instead of shipping.
const SHEET_COUNT: int = 11

## The only filter the tower may ship, and the whole fix.
##
## [b]NEAREST must survive.[/b] Magnification is the art's deliberate pixel
## look: close up, a texel is meant to be a visible square, and LINEAR would
## smear the masonry into porridge and throw away the model's style to fix a
## problem it does not have. Only MINIFICATION was ever broken, and mipmaps are
## the part that fixes it. ANISOTROPIC is here because the shaft is a near-
## vertical cylinder seen almost edge-on from the lane: its texels are minified
## hard round the silhouette and barely at all up the axis, and an isotropic mip
## choice has to serve both with one level, blurring the courses to kill the
## crawl. So: nearest when magnified, mipmapped when minified, anisotropic about
## which mip.
const REQUIRED_FILTER: int = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC

## Every texture filter by its own enum value, so a failure says which filter is
## set rather than printing a bare integer at whoever has to read it. Keyed off
## the constants themselves, so it cannot drift from the engine's numbering.
const FILTER_NAMES: Dictionary = {
	BaseMaterial3D.TEXTURE_FILTER_NEAREST: "NEAREST",
	BaseMaterial3D.TEXTURE_FILTER_LINEAR: "LINEAR",
	BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS: "NEAREST_WITH_MIPMAPS",
	BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS: "LINEAR_WITH_MIPMAPS",
	BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC: "NEAREST_WITH_MIPMAPS_ANISOTROPIC",
	BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC: "LINEAR_WITH_MIPMAPS_ANISOTROPIC",
}

## What a material with no [member Resource.resource_name] is called in a
## failure message. The glTF materials all carry one
## ([code]marble_tower_stone[/code] and its ten siblings) -- this is only so a
## failure can never come back nameless.
const UNNAMED_MATERIAL: String = "<unnamed material>"

## A mip chain is a chain: one level is the base image and nothing else.
const MIN_MIPMAP_LEVELS: int = 1

var _tower: Node3D

## Every distinct [BaseMaterial3D] on the tower that carries an albedo texture,
## in the order the mesh walk found them. Deduplicated by identity: eleven
## materials over eleven surfaces, and a material shared by two surfaces is one
## sheet to report on, not two identical failures.
var _sheets: Array[BaseMaterial3D] = []


func before_each() -> void:
	var packed: PackedScene = load(TOWER_PATH) as PackedScene
	assert_not_null(packed, "the tower model loads as a scene")
	if packed == null:
		return
	_tower = packed.instantiate() as Node3D
	assert_not_null(_tower, "and instances as a Node3D")
	if _tower == null:
		return
	add_child(_tower)
	_sheets = _textured_materials()


func after_each() -> void:
	_sheets.clear()
	if _tower != null and is_instance_valid(_tower):
		remove_child(_tower)
		_tower.free()
	_tower = null


# --- The chain ----------------------------------------------------------------

## Every albedo sheet on the tower has mips to fall back on.
##
## This is the defect itself, asked of the resource. The sheet is fetched from
## the material the renderer will actually use, its [Image] is taken off the
## texture, and [method Image.has_mipmaps] is the answer -- true only if the
## importer built the chain. The failure names the material, so it says which
## sheet went out flat instead of saying that one did.
func test_every_sheet_carries_a_mip_chain() -> void:
	if _sheets.is_empty():
		fail("no textured materials on the tower to check")
		return

	var flat: int = 0
	var levels_total: int = 0
	for material: BaseMaterial3D in _sheets:
		var sheet: String = _name_of(material)
		var texture: Texture2D = material.albedo_texture
		var image: Image = texture.get_image()
		if not assert_not_null(image, "%s: its albedo sheet hands back an image" % sheet):
			continue
		var levels: int = image.get_mipmap_count()
		levels_total += levels
		if not assert_true(
			image.has_mipmaps(),
			"%s: its albedo sheet (%d x %d) carries a mip chain -- with none, every pixel of it reads mip 0 at every distance and the courses crawl from the lane" % [
				sheet, image.get_width(), image.get_height(),
			],
		):
			flat += 1
			continue
		assert_ge(
			float(levels), float(MIN_MIPMAP_LEVELS),
			"%s: and the chain has levels in it, not just the base image" % sheet,
		)

	print("      %d sheets, %d flat, %d mip levels in total" % [_sheets.size(), flat, levels_total])


# --- The filter ---------------------------------------------------------------

## Minified through the mip chain, magnified nearest.
##
## The chain existing is half of it; being read is the other half. Every
## material on the tower must ask for
## [constant BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC] --
## see [constant REQUIRED_FILTER] for why each of those three words is load-
## bearing, and in particular why NEAREST is not the bug and must not be
## "fixed" to LINEAR.
func test_minification_is_mipmapped_and_magnification_is_nearest() -> void:
	if _sheets.is_empty():
		fail("no textured materials on the tower to check")
		return

	var wanted: String = _filter_name(REQUIRED_FILTER)
	for material: BaseMaterial3D in _sheets:
		var filter: int = int(material.texture_filter)
		assert_eq_int(
			filter, REQUIRED_FILTER,
			"%s: filter is %s, wanted %s -- minification has to read the mip chain, and NEAREST has to survive that fix: magnification is the art's deliberate pixel look, and only minification was ever broken" % [
				_name_of(material), _filter_name(filter), wanted,
			],
		)

	print("      %d sheets, all asking for %s" % [_sheets.size(), wanted])


# --- The inventory ------------------------------------------------------------

## The tower still ships all eleven sheets.
##
## Distinct albedo textures, counted by identity. The two tests above are both
## "every sheet ...", which a tower that lost ten of them would pass in silence;
## an import change that merges or drops a sheet is caught here and nowhere
## else.
func test_the_tower_still_ships_every_sheet() -> void:
	var seen: Dictionary = {}
	for material: BaseMaterial3D in _sheets:
		var texture: Texture2D = material.albedo_texture
		seen[texture.get_instance_id()] = true

	assert_eq_int(
		seen.size(), SHEET_COUNT,
		"the tower ships its %d distinct albedo sheets, across %d textured materials" % [
			SHEET_COUNT, _sheets.size(),
		],
	)
	print("      %d distinct albedo sheets on %d materials" % [seen.size(), _sheets.size()])


# --- Helpers ------------------------------------------------------------------

## Every node under [param root], [param root] itself included.
func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var index: int = 0
	while index < out.size():
		for child: Node in out[index].get_children():
			out.append(child)
		index += 1
	return out


## The material the renderer will actually use on one surface, in Godot's own
## order of precedence: the whole-instance override, then the per-surface
## override, then the one the mesh carries. The tower's own materials ride on
## the mesh; the two overrides are consulted anyway, because a scene that set
## one would otherwise be judged on a material it never draws.
static func _material_on(instance: MeshInstance3D, surface: int, mesh: Mesh) -> Material:
	if instance.material_override != null:
		return instance.material_override
	var override: Material = instance.get_surface_override_material(surface)
	if override != null:
		return override
	return mesh.surface_get_material(surface)


## Every distinct [BaseMaterial3D] with an albedo texture, over every surface of
## every [MeshInstance3D] in the tower. The [code]-colonly[/code] collision node
## contributes nothing: Godot turns it into a [StaticBody3D] and drops its mesh,
## so what is walked here is only what is drawn.
func _textured_materials() -> Array[BaseMaterial3D]:
	var out: Array[BaseMaterial3D] = []
	var seen: Dictionary = {}
	for node: Node in _descendants(_tower):
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance == null:
			continue
		var mesh: Mesh = instance.mesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var base: BaseMaterial3D = _material_on(instance, surface, mesh) as BaseMaterial3D
			if base == null or base.albedo_texture == null:
				continue
			var id: int = base.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			out.append(base)
	return out


## What to call a material in a failure message.
static func _name_of(material: BaseMaterial3D) -> String:
	var named: String = material.resource_name
	return named if not named.is_empty() else UNNAMED_MATERIAL


## What to call a texture filter in a failure message.
static func _filter_name(filter: int) -> String:
	if FILTER_NAMES.has(filter):
		return str(FILTER_NAMES[filter])
	return "filter %d" % filter
