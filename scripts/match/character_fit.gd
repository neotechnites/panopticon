class_name CharacterFit
extends Resource
## How one map lights its players on top of its own lights: the players' key and fill, and its tint on their paint.
## One .tres per map scene, registered in [constant CharacterLight.FITS].

## The players' key, from the viewer's upper side: its colour, and its brightness as the largest channel.
@export var light: Color = Color(1.0, 1.0, 1.0, 1.0)
## The players' fill, from the viewer's other side, so the planes the key misses still read.
@export var shade: Color = Color(0.4, 0.4, 0.4, 1.0)
## What the map does to the body's own paint (skin, trousers), before any light.
@export var body: Color = Color(1.0, 1.0, 1.0, 1.0)
## How bright a team shirt runs against the body, so its colour still reads.
@export_range(0.0, 3.0, 0.01) var shirt: float = 1.0
## The share of its paint every surface glows with, so no plane goes black where no light reaches.
@export_range(0.0, 1.0, 0.01) var glow: float = 0.1
## The map's leaf dapple texture, laid on the players' sun as on its ground; null for none.
@export var dapple: Texture2D = null
## The ground's dapple shader, whose defaults (scale, flecks, sway) the players take.
@export var dapple_shader: Shader = null
## The body's level in full leaf shade, 1 = untouched.
@export_range(0.0, 1.0, 0.01) var dapple_shade: float = 1.0
