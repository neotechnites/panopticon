class_name CharacterFit
extends Resource
## How one map lights its players, as on-screen multiples of their painted colour.
## One .tres per map scene, registered in [constant CharacterLight.FITS].

## Faces turned from the map's light.
@export var shade: Color = Color(1.0, 1.0, 1.0, 1.0)
## Faces turned to it.
@export var light: Color = Color(1.0, 1.0, 1.0, 1.0)
## Where the light comes from at a body: x toward the arena's axis (the tower), y up.
@export var light_from: Vector2 = Vector2(0.5, 0.85)
## How far round the body the light reaches: 0 a hard half, 1 all the way.
@export_range(0.0, 1.0, 0.01) var wrap: float = 0.5
## What a full patch of the map's own sun adds on top, in the light's colour; 0 when no sun reaches players.
@export_range(0.0, 2.0, 0.01) var sun: float = 0.0
## What the map does to the body's own paint (skin, trousers), before the light.
@export var body: Color = Color(1.0, 1.0, 1.0, 1.0)
## How bright a team shirt runs against the body, so its colour still reads.
@export_range(0.0, 3.0, 0.01) var shirt: float = 1.0
## How much of its own hue a team shirt keeps under the map's coloured light: 0 takes all of it, 1 none.
@export_range(0.0, 1.0, 0.01) var shirt_hue: float = 0.0
## A thin edge of the light's colour round the silhouette, so a body separates from dark ground.
@export_range(0.0, 2.0, 0.01) var rim: float = 0.0
## The map's leaf dapple texture, laid on the players' sun as on its ground; null for none.
@export var dapple: Texture2D = null
## The ground's dapple shader, whose defaults (scale, light, flecks, sway) the players take.
@export var dapple_shader: Shader = null
## The body's level in full leaf shade, 1 = untouched; its ambient stays so it never goes black.
@export_range(0.0, 1.0, 0.01) var dapple_shade: float = 1.0
