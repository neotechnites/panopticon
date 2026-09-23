extends TestCase

## The draw budgets, per map, as tests.
##
## [b]The hole this fills.[/b] B1-B5 in [code]tests/test_budgets.gd[/code] are
## physics and wire, and every one of them is measured on one map -- the arena a
## bot match happens to load. Maps do not differ on the physics side; they differ
## on the DRAW side, and nothing gated that. Two maps each arrived carrying a
## runtime shadow-casting light where the Bentham Ring has none, and one arrived
## with nearly twice the Ring's triangles. Both landed silently, because a map is
## data and data had no gate.
##
## [b]What is measured.[/b] Every map in [MapCatalog] is instanced into the live
## tree and allowed to [method Node._ready] -- which matters, because
## [method TowerLight._apply_profile] writes
## [member Light3D.shadow_enabled] from its [TowerLightProfile] at ready and
## therefore OVERWRITES whatever the [code].tscn[/code] was saved with. Reading
## the scene file would measure the wrong number. Then the tree is walked and six
## counts are taken: visible triangles, surfaces, distinct materials, the
## triangles that are transparent or additive, lights, and the lights that both
## cast shadows and are visible.
##
## [b]The decisive one is [code]shadow_casters[/code].[/b] Under GL Compatibility
## a realtime shadow-casting light re-renders the geometry it reaches, so one
## added light is not a percentage on the frame -- it is a second pass. It gets an
## exact ceiling, not headroom: zero means zero, one means one. The other five
## are the measured value plus 20 % headroom, in the same spirit as B1-B5.
##
## [b]These are gates, not targets.[/b] A triangle count says nothing about
## whether the map holds 60 fps on Ryan's PC -- see [code]docs/PERF_REVIEW.md[/code]
## §2. What a gate catches is a CHANGE OF ORDER: a shadow light switched on, an
## alpha-blended canopy drawn over the whole arena, a section rebuilt at four
## times its old density. Unlike B1-B5 these numbers are scene data, not wall
## clock, so they are identical on every machine and this file never skips.
##
## [b]A map with no entry FAILS.[/b] That is the point. A new map cannot slip in
## un-measured; the failure prints the row to paste into [constant DRAW_BUDGETS].

## Per-map ceilings, keyed by [member MapDefinition.id].
##
## Measured on this suite, then: [code]tris[/code], [code]surfaces[/code],
## [code]materials[/code], [code]transparent_tris[/code] and [code]lights[/code]
## are the measured value plus 20 %, rounded up. [code]shadow_casters[/code] is
## the measured value EXACTLY -- see the header for why that one gets no slack.
##
## A zero ceiling is therefore a real gate: the Ring has no transparent surface
## and no shadow caster, and the first one added fails this file.
##
## [b]What the first measurement found[/b], and why these rows are not all alike:
## [codeblock]
##   bentham_ring   78722 tris   37 surfaces   20 lights   0 shadow casters
##   marble         99250 tris   75 surfaces    2 lights   1 shadow caster
##   forest        143895 tris    9 surfaces    2 lights   1 shadow caster
## [/codeblock]
## The Ring carries twenty lights and casts no shadow from any of them; the two
## newer maps each carry two lights and let one of them cast. That difference is
## the whole reason this file exists -- it arrived twice, unremarked, and no
## budget could see it. Forest is 1.83x the Ring's triangles and holds the only
## transparent geometry in the game. None of these three numbers is asserted to
## be RIGHT here. They are asserted not to move without somebody saying so.
const DRAW_BUDGETS: Dictionary = {
	# The reference map. B1-B5 were all measured on this one.
	#
	# Re-measured after S3's demon pads became lava cracks, then one crack
	# network, then a dense crazed one (Ryan: "significantly more cracked with
	# clearer edges"): 99156 tris, because the cracks are cut into
	# map_base.glb itself -- 367 fissures in 36 cells, 9556 fissure tris and
	# 7688 deck tris round them (the deck between the cracks is bisected down
	# to 1.2 m edges so no facet drops its texel density) -- against 87268
	# with the pad models. Inside the 107595 ceiling the network was first
	# measured under; that ceiling stays, it is the gate the crazing was built
	# to; 99478 once the lip wall rose to hide a standing body. Surfaces 62:
	# each `lava_crack` node draws one haze MeshInstance3D where each
	# `demon_pad` drew one model, and the pit's LavaSea surface was gone --
	# the sea was the atlas's own glowing cell (materials 13 for the same
	# reason). Re-measured 2026-09-22 with the sea back on its own surface
	# (Ryan: "the lava pit is using the old texture not the one i made": his
	# 256 px tile repeated every 5 m cannot live in an atlas cell, so
	# map_base.glb is three surfaces again, rock, river, LavaSea): 95522 tris,
	# 62 surfaces and 13 materials against 61 / 12 the commit before, inside
	# the 78 / 18 ceilings, which stay. `transparent_tris` leaves zero
	# for the first time on this map: the heat haze is 36 x 4 triangles of a
	# spatial shader that reads the screen (hint_screen_texture) and writes
	# ALPHA, so it is 144 triangles in the sorted pass plus one screen copy a
	# frame; ceiling 173 (144 + 20 %). Lights measured 19, inside the 24 it had.
	"bentham_ring": {
		"tris": 107595, "surfaces": 78, "materials": 18,
		"transparent_tris": 173, "lights": 24, "shadow_casters": 0,
	},
	# THE LANE IS BARE AGAIN (Ryan, 2026-09-22: "for the marble level, can you
	# just get rid of all the elements on the ring?"). The obstacle course --
	# 71 placed prop instances -- came off scenes/ring/marble.tscn, and the
	# surfaces row is where an obstacle course always showed: 75 surfaces to 4,
	# 11 materials to 4, 99250 tris to 75632. What is left to draw is the
	# rotunda, the tower, the portal and the bars at 353 deg, and the four
	# surfaces are exactly those four .glb files. (The bars stayed on the
	# harness's evidence, not on taste: see the scene's Bars node.)
	#
	# The ceilings are LOWERED to the new measurement + 20 % rather than kept:
	# 119100 tris and 90 surfaces over a 4-surface arena is a gate that could
	# not see a whole course being put back, which is the one change this map
	# now has to be told about. tris 90759, surfaces 5, materials 5, lights 3
	# (2 measured: the tower's lamp and the portal's glow). The shadow caster is
	# still one and still exact.
	#
	# Lights re-measured at 3 on 2026-09-22 (Ryan: "the lighting in the marble
	# level is absolutely terrible"): the Skylight on the axis is the map's key
	# and its ONE shadow caster now, the tower's lamp is unshadowed, the
	# portal's glow is the third. Ceiling 4 (3 + 20 %); shadow_casters exact at 1.
	#
	# Textures re-measured 2026-09-22 (Ryan: "when you get close it looks like
	# shit"): the stone is one tiling sheet per class through lib/texel.py, so
	# MarbleStone draws 12 surfaces where the atlas drew 1 -- surfaces 15,
	# materials 15, ceilings 18 (+20 %). Triangles unchanged in the .glb; the
	# tris row below counts vertices/3 and fell with the shared UVs.
	#
	# Surfaces re-measured 2026-09-23, when the last two models on the atlas went
	# onto lib/texel.py too (Ryan: "the texturing on the dome of the tower looks
	# like it didnt get fixed" and "the texturing on the gate is bad"). The tower
	# draws 11 surfaces where its atlas drew 1 and the gate 7 where it drew 1, so
	# the arena measures surfaces 15 -> 31, materials 15 -> 31; ceilings 37
	# (+20 %). TRIANGLES DID NOT MOVE -- 88624 before and after, because the
	# tower's geometry is bit-identical and the widened gate kept its topology --
	# so the tris ceiling is left where it was rather than raised to fit a number
	# that did not change. Lights, transparency and the one shadow caster are
	# untouched.
	"marble": {
		"tris": 90759, "surfaces": 37, "materials": 37,
		"transparent_tris": 0, "lights": 4, "shadow_casters": 1,
	},
	# The expensive one: 2.5x the Ring, plus 2196 transparent triangles, plus a
	# shadow caster. Re-measured after the obstacle course came off the lane
	# and the wood went on (Ryan: "spread trees across the whole thing"):
	# 143 placed prop instances (113 trees, 30 bushes and rocks, placed by
	# tools/forest_trees.py) measure 249815 tris and 152 surfaces against the
	# course's 170443 and 54; materials fall from 20 to 16 with the pads, orb
	# and thorn patches gone. tris and surfaces ceilings are the new
	# measurement plus 20 %, as the header says; the rest keep the ceilings
	# they had. transparent_tris re-measured at 5220 after the pit fog became
	# fourteen rolling layers instead of seven flat discs (Ryan: "thorns coming
	# out of a block of butter"): 5040 fog tris + the portal's 180, plus 20 %.
	# Materials re-measured at 27 on 2026-09-22 with ForestGround on twelve
	# tiling sheets (lib/texel.py) instead of one atlas; ceiling 33 (+20 %).
	"forest": {
		"tris": 299778, "surfaces": 183, "materials": 33,
		"transparent_tris": 6264, "lights": 3, "shadow_casters": 1,
	},
}

## The keys every row carries, in the order the [code]BUDGET[/code] line prints
## them. Named once so the row-missing message can build a paste-able row.
const COUNT_KEYS: Array[String] = [
	"tris", "surfaces", "materials", "transparent_tris", "lights", "shadow_casters",
]


# --- Measuring ----------------------------------------------------------------

## What one map costs to draw. Plain counts, taken once, off a live tree.
class DrawCounts:
	var tris: int = 0
	var surfaces: int = 0
	var materials: int = 0
	var transparent_tris: int = 0
	var lights: int = 0
	var shadow_casters: int = 0

	## Distinct [Material] instances seen, by instance id. A map that reuses one
	## material across forty meshes costs one material, and that is the number
	## that matters to the renderer's state changes.
	var _material_ids: Dictionary = {}

	func get_count(key: String) -> int:
		match key:
			"tris": return tris
			"surfaces": return surfaces
			"materials": return materials
			"transparent_tris": return transparent_tris
			"lights": return lights
			"shadow_casters": return shadow_casters
		return -1

	## Walk [param node] and everything under it. [param visible_chain] is false
	## once any ancestor is hidden, so a hidden group costs nothing even though
	## its own children still say [code]visible = true[/code].
	func walk(node: Node, visible_chain: bool) -> void:
		var here: bool = visible_chain
		var spatial: Node3D = node as Node3D
		if spatial != null and not spatial.visible:
			here = false

		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance != null and here:
			_add_mesh(mesh_instance)

		var light: Light3D = node as Light3D
		if light != null:
			lights += 1
			# Both halves matter: a shadow light switched off costs nothing, and
			# neither does one on a hidden node. Only a light that is on AND
			# reachable makes the renderer take a second pass.
			if light.shadow_enabled and here:
				shadow_casters += 1

		for child: Node in node.get_children():
			walk(child, here)

	func _add_mesh(instance: MeshInstance3D) -> void:
		var mesh: Mesh = instance.mesh
		if mesh == null:
			return
		for surface: int in mesh.get_surface_count():
			surfaces += 1
			var count: int = _triangles_on(mesh, surface)
			tris += count
			var material: Material = _material_on(instance, surface, mesh)
			if material == null:
				continue
			_material_ids[material.get_instance_id()] = true
			materials = _material_ids.size()
			if _is_see_through(material):
				transparent_tris += count

	## Triangles on one surface. Indexed surfaces are counted by index, unindexed
	## by vertex; anything that is not a triangle list (a line gizmo, a point
	## cloud) draws no triangles and is counted as none.
	static func _triangles_on(mesh: Mesh, surface: int) -> int:
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return 0
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_INDEX:
			return 0
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if not indices.is_empty():
			return indices.size() / 3
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		return vertices.size() / 3

	## The material the renderer will actually use, in Godot's own order of
	## precedence: the whole-instance override, then the per-surface override,
	## then the one the mesh carries. The brief asked for the last two; the
	## instance override is included because a map that set one would otherwise
	## be measured against a material it never draws.
	static func _material_on(instance: MeshInstance3D, surface: int, mesh: Mesh) -> Material:
		if instance.material_override != null:
			return instance.material_override
		var override: Material = instance.get_surface_override_material(surface)
		if override != null:
			return override
		return mesh.surface_get_material(surface)

	## Transparent or additive: either costs the sorted, un-depth-written pass
	## that opaque geometry avoids. A [BaseMaterial3D] is asked directly. A
	## [ShaderMaterial] is read off its shader's source: a spatial shader that
	## writes ALPHA, declares a blend mode other than mix, or reads the screen
	## through hint_screen_texture (which costs a screen copy per frame on top
	## of the sorted pass) goes through the transparent pass, and this gate
	## must see it -- the S3 lava haze is exactly that.
	static func _is_see_through(material: Material) -> bool:
		var base: BaseMaterial3D = material as BaseMaterial3D
		if base != null:
			if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				return true
			return base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX
		var shaded: ShaderMaterial = material as ShaderMaterial
		if shaded == null or shaded.shader == null:
			return false
		var code: String = shaded.shader.code
		for mark: String in ["hint_screen_texture", "ALPHA =", "ALPHA=", "blend_add", "blend_sub", "blend_mul"]:
			if code.contains(mark):
				return true
		return false


## Instance [param map], let it run [method Node._ready], count it, free it.
## Returns null when the scene will not load, which the caller reports.
func _measure(map: MapDefinition) -> DrawCounts:
	var packed: PackedScene = load(map.scene_path) as PackedScene
	if packed == null:
		return null
	var arena: Node3D = packed.instantiate() as Node3D
	if arena == null:
		return null

	add_child(arena)
	# One tick, so anything deferring its setup past _ready has had its turn --
	# TowerLight does not, but a map that hid a group on the first frame would.
	await step_ticks(1)

	var counts: DrawCounts = DrawCounts.new()
	counts.walk(arena, arena.visible)

	remove_child(arena)
	arena.queue_free()
	return counts


# --- The gate -----------------------------------------------------------------

func test_every_map_stays_inside_its_draw_budget() -> void:
	var maps: Array[MapDefinition] = MapCatalog.all()
	if not assert_gt(float(maps.size()), 0.0, "the catalog names at least one map to measure"):
		return

	for map: MapDefinition in maps:
		if map == null or not map.is_playable():
			fail("the catalog holds an entry with no loadable scene; nothing to measure")
			continue

		var counts: DrawCounts = await _measure(map)
		if counts == null:
			fail("map %s: %s would not instance, so it could not be measured" % [
				map.id, map.scene_path,
			])
			continue

		# Printed before anything is asserted, and on every run pass or fail:
		# drift towards a ceiling is the thing worth seeing, and a run that only
		# printed on failure would show it for the first time too late.
		print("          BUDGET draw map=%s tris=%d surfaces=%d materials=%d transparent_tris=%d lights=%d shadow_casters=%d" % [
			map.id, counts.tris, counts.surfaces, counts.materials,
			counts.transparent_tris, counts.lights, counts.shadow_casters,
		])

		_assert_inside_budget(map, counts)


func _assert_inside_budget(map: MapDefinition, counts: DrawCounts) -> void:
	var key: String = String(map.id)
	if not DRAW_BUDGETS.has(key):
		fail(_unmeasured_message(key, counts))
		return

	var budget: Dictionary = DRAW_BUDGETS[key] as Dictionary
	for name: String in COUNT_KEYS:
		if not budget.has(name):
			fail("map %s has a budget row with no %s; add it or the count is ungated" % [key, name])
			continue
		assert_le(
			float(counts.get_count(name)),
			float(int(budget[name])),
			"map %s: %s is inside budget" % [key, name],
		)


## What an author who just added a map is told. It carries the row to paste, so
## the gate is a thirty-second obligation rather than a puzzle -- but it is still
## a FAILURE, because the whole point is that no map reaches the suite with its
## draw cost un-looked-at.
func _unmeasured_message(key: String, counts: DrawCounts) -> String:
	var headroom: PackedStringArray = PackedStringArray()
	for name: String in COUNT_KEYS:
		var measured: int = counts.get_count(name)
		# shadow_casters is exact; everything else gets the 20 % B1-B5 headroom.
		var ceiling: int = measured if name == "shadow_casters" else int(ceilf(float(measured) * 1.2))
		headroom.append("\"%s\": %d" % [name, ceiling])
	return (
		"map %s has no entry in DRAW_BUDGETS, so its draw cost is ungated. "
		% key
		+ "Measure it, look at the numbers, and if they are what the map should cost add: "
		+ "\"%s\": {%s}," % [key, ", ".join(headroom)]
	)


## The other direction: a row for a map that is no longer in the catalog is a
## ceiling nothing enforces, and a reader who trusts it is reading a lie.
func test_the_budget_table_names_no_map_the_catalog_lost() -> void:
	for key: Variant in DRAW_BUDGETS.keys():
		assert_true(
			MapCatalog.has(StringName(String(key))),
			"DRAW_BUDGETS row \"%s\" names a map the catalog still has" % key,
		)
