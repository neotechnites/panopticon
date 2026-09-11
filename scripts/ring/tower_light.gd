class_name TowerLight
extends OmniLight3D

## The only light source in the Bentham Ring: one reddish [OmniLight3D]
## hanging directly above the tower.
##
## [b]Why a point above the tower, and why omni[/b]
##
## The game is about being watched from a central tower. Making the tower the
## literal origin of all light in the scene is the same idea rendered as
## lighting: every piece of cover, every trap block, every prisoner throws a
## shadow that points away from the tower, because the tower is the only
## thing anything is lit by. A [DirectionalLight3D] (the old "Sun" this
## replaces) has no position at all, so it could not do this even keyed
## straight down. A [SpotLight3D] pointed straight down was the other real
## option -- it would give a harder-edged pool of light -- but its cone has
## to be tuned to exactly clear r=62 (the outer wall) or the ring's edge goes
## black outside the cone, and an omni's spherical falloff already covers
## every bearing from the tower by construction. Omni was picked for that
## margin of safety on playability.
##
## [b]Why this is a script and not just numbers baked into the .tscn[/b]
##
## Same reason as [WeaponProfile] on [Rifle]: the project's rule is that a
## tunable never lives only as
## a literal in a scene file. [TowerLightProfile] is the knob; this script's
## only job is to read it onto the [OmniLight3D] it extends, once, at ready.
##
## [b]GL Compatibility[/b]
##
## The project pins the Compatibility renderer, which does not support
## cubemap omni shadows -- only dual paraboloid. [member OmniLight3D.omni_shadow_mode]
## is forced to [constant OmniLight3D.SHADOW_DUAL_PARABOLOID] here rather than
## left on whatever the scene file happens to have, so this light degrades
## correctly under that renderer even if someone changes the default in the
## inspector.

## The colour, brightness, reach and height. Falls back to a
## default-constructed [TowerLightProfile] with a warning rather than to
## whatever the inspector happened to leave on the node, because a silently
## unlit or mis-hued tower light reads as "the mood change didn't happen".
@export var profile: TowerLightProfile


func _ready() -> void:
	if profile == null:
		push_warning("TowerLight has no TowerLightProfile; falling back to defaults.")
		profile = TowerLightProfile.new()
	_apply_profile()


func _apply_profile() -> void:
	light_color = profile.color
	light_energy = profile.energy
	omni_range = profile.range_metres
	omni_attenuation = profile.attenuation
	shadow_enabled = profile.shadow_enabled
	omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	position = Vector3(0.0, profile.height_metres, 0.0)
