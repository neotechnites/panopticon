class_name WatchingEyeLook
extends Resource

## What the eyeball over the tower is MADE OF, on one map.
##
## [b]The whole of a variant is three materials.[/b]
## [code]assets/models/eye.glb[/code] is a unit sphere with three nodes --
## [code]Eye_Sclera[/code], [code]Eye_Iris[/code], [code]Eye_Pupil[/code] -- one
## surface each and one flat, untextured material each, so the eye's entire look
## is nine numbers and an emission. Ryan, 2026-09-23: [i]"create two new textures
## for the eye, one for the forest level thats green, and one for the marble
## level that matches the color palette."[/i]
##
## [b]Why this is a material swap and not a second model.[/b] The geometry of a
## forest eye and a marble eye is the geometry of the hell eye to the last
## vertex: the same sclera, the same two spherical caps on the same measured
## depth budget (see [code]tools/modelling/eye_build.py[/code], where the iris and
## pupil biases are a z-fighting gate, not a look). Building
## [code]eye_forest.glb[/code] and [code]eye_marble.glb[/code] with
## [code]model --variant[/code] would ship two more copies of 768 triangles and
## two more clearance gates to keep in step, to change six colours. A
## [method MeshInstance3D.set_surface_override_material] costs one material each
## and cannot drift from the mesh, because there is only one mesh.
##
## [b]The map picks the look, the eye does not know the map.[/b] Each arena's
## [code]Watcher[/code] node points [member WatchingEye.look] at its own resource,
## exactly as it already points [member WatchingEye.profile] at its own
## [WatchingEyeProfile]. A null look is the hell eye: the Bentham Ring sets none,
## and its eyeball draws the materials that came out of the glTF, unchanged and
## un-overridden.
##
## [b]Colours are glTF linear, not inspector sRGB.[/b] Godot's glTF importer
## writes [code]baseColorFactor[/code] -- a LINEAR number -- straight into
## [member BaseMaterial3D.albedo_color], so the shipped eye's dark sclera is
## [code]Color(0.03, 0.03, 0.038)[/code] and not the much lighter colour that
## would look like in a picker. Every material here is authored in the same space
## as the constants at the top of [code]eye_build.py[/code], because the two paths
## meet in the same field and a variant mixed in the other space reads two stops
## too bright.

## The eyeball. [code]M_Sclera[/code] in the glTF: base colour, roughness 0.30,
## no metal, double sided, no emission.
@export var sclera: Material

## The coloured ring, and the only emissive surface on the model -- it is what
## makes the eye readable from the lane when the map's key light is somewhere
## else. [code]M_Iris[/code] in the glTF.
@export var iris: Material

## The black centre. [code]M_Pupil[/code] in the glTF, and the darkest thing on
## the map by some distance: it is what stops the iris from reading as a plain
## coloured ball.
@export var pupil: Material


## The material for the glTF node called [param node_name], or null if that node
## is not one of the eye's three.
##
## Matched by NODE name rather than by material name or by surface index because
## the node names are what [code]tools/modelling/eye.contract.json[/code] pins and
## [code]lib/verify_glb.gd[/code] enforces on every build -- a renamed node fails
## the model's own gate before it can quietly stop being painted here. Surface
## index would match nothing: each node carries exactly one surface, numbered 0.
func material_for(node_name: StringName) -> Material:
	match node_name:
		&"Eye_Sclera":
			return sclera
		&"Eye_Iris":
			return iris
		&"Eye_Pupil":
			return pupil
	return null
