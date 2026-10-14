class_name CharacterFit
extends Resource
## How one map dresses its players on top of its own lights (OoT style): tint, shirt, actor ambient and fill, leaf dapple.
## One .tres per map scene, registered in [constant CharacterLight.FITS].

## What the map does to the body's own paint (skin, trousers), before any light.
@export var body: Color = Color(1.0, 1.0, 1.0, 1.0)
## How bright a team shirt runs against the body, so its colour still reads.
@export_range(0.0, 3.0, 0.01) var shirt: float = 1.0
## The body's ambient in place of the map's: its dark side in the place's shade colour, as a rock there in shade.
@export var ambient: Color = Color(0.0, 0.0, 0.0, 1.0)
## A weak fill fixed in the world, on the bodies only, so their shadow side keeps its facets; black for none.
@export var fill: Color = Color(0.0, 0.0, 0.0, 1.0)
## Toward the fill (world).
@export var fill_from: Vector3 = Vector3(0.0, 1.0, 0.0)
## The map's leaf dapple texture, laid on the players' sun as on its ground; null for none.
@export var dapple: Texture2D = null
## The ground's dapple shader, whose defaults (scale, flecks, sway) the players take.
@export var dapple_shader: Shader = null
## The body's level in full leaf shade, 1 = untouched.
@export_range(0.0, 1.0, 0.01) var dapple_shade: float = 1.0
