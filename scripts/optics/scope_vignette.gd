class_name ScopeVignette
extends CanvasLayer

## Draws the optic on the screen: a dark border closing in around a clear
## centre as the rifle finishes coming up to the eye.
##
## [b]Why there is no lens on the model[/b]
##
## Ryan's brief was explicit -- "it comes up to your eye then puts like a
## vignette on your screen, the scope doesn't actually need to be see through".
## The rifle's scope is a solid brick (see
## [code]tools/modelling/rifle_build.py[/code]) and stays one: no render
## target, no second camera, no transparent material, no second draw of the
## whole arena. The read comes from this overlay plus the field-of-view change
## [WeaponOptic] already applies, which together cost one full-screen blend.
##
## [b]No clock of its own[/b]
##
## Exactly the argument [RifleAds] makes in its own class notes. The amount of
## vignette on screen is a pure function of
## [method RifleAds.get_aim_progress] -- which is
## [method WeaponOptic.get_shaped_progress], the same value the raised pose and
## the narrowed field of view are computed from -- remapped through
## [member ZoomProfile.vignette_onset]. Because it is the same number and not a
## second timer chasing it, the border cannot arrive late, cannot linger after
## the scope has dropped, and cannot desynchronise when the player feathers the
## aim button.
##
## [b]Whose screen this is[/b]
##
## The guard's, and only the guard's, and only when the guard is the human.
## The gate is [member trigger]: [method MatchController._attach_rifle] turns
## that [WeaponInput] on for a human holder and off for everybody else, so it
## is already the game's own answer to "is the person at this keyboard the one
## holding the rifle". A prisoner never has the rifle; a spectator and a ghost
## are not holding it either; a bot in the tower holds it with the human
## trigger switched off. All four therefore run this file's every line each
## frame and draw nothing -- the bot path is the same path, evaluated to zero,
## rather than a branch that is never taken and never tested.
##
## [b]It writes nothing but its own overlay[/b]
##
## No camera, no field of view, no [code]ViewModel[/code] transform. Deleting
## this node leaves the aim, the zoom and the shot line exactly as they are.

## Godot's own name for "there is no window", as [FxHitConfirm] uses it.
const HEADLESS_DISPLAY: String = "headless"

## The [RifleAds] beside this node in [code]scenes/weapon/rifle.tscn[/code].
## The only source of the transition, and of the [ZoomProfile] the numbers come
## off -- both read through it rather than from an optic exported here, because
## the optic lives on the holder's head and is wired onto Ads at runtime. One
## wire, made once, in one place.
@export var ads: RifleAds

## The rifle's [code]HumanTrigger[/code]. Its active flag is the whole of the
## "is the human holding this rifle" question -- see the class notes.
##
## Left null, the vignette is drawn whenever the optic is aimed, which is what
## a bare test fixture or a preview scene with no match controller wants.
@export var trigger: WeaponInput

## The full-rect [Control] carrying the vignette shader. Authored in
## [code]scenes/fx/scope_vignette.tscn[/code]; nothing here builds it.
@export var overlay: Control

## Go inert with no display server, exactly as the feedback rig's nodes do, so
## a headless bot match or a sweep pays nothing at all for this.
@export var headless_inert: bool = true

## Vignette amount past which the rifle stops being drawn. Negative keeps the
## model on screen at every zoom, which is the old behaviour.
@export var hide_model_above: float = 0.55

## The material actually written to, a private duplicate of the authored one.
## See [method _ready] for why it is not the scene's own resource.
var _material: ShaderMaterial = null

## The last amount pushed at the shader, so a still frame writes nothing.
var _applied: float = -1.0

## The aspect ratio those uniforms were written for. Tracked alongside the
## amount because the player can resize the window while fully aimed -- the
## amount would not change on that frame, and a ring that never re-read the
## aspect would stay stretched into an ellipse for as long as they held the
## scope. See docs/BUILDING.md: the window is resizable on purpose.
var _applied_aspect: float = -1.0


func _ready() -> void:
	if headless_inert and DisplayServer.get_name() == HEADLESS_DISPLAY:
		set_process(false)
		_hide_overlay()
		return
	if overlay == null:
		push_error("ScopeVignette has no overlay Control; no vignette will be drawn.")
		set_process(false)
		return
	# A SubResource in a PackedScene is ONE object shared by every instance of
	# that scene -- the same trap scenes/player/player.tscn records about its
	# collision shape. Two rifles in one tree would otherwise write each
	# other's uniforms. Duplicated, not rebuilt: every authored value, the
	# shader included, comes across untouched.
	var authored: ShaderMaterial = overlay.material as ShaderMaterial
	if authored == null:
		push_error("ScopeVignette's overlay has no ShaderMaterial; no vignette will be drawn.")
		set_process(false)
		return
	_material = authored.duplicate() as ShaderMaterial
	overlay.material = _material
	_apply(0.0)


## Render-tick driven, like [WeaponOptic] and [RifleRecoil], and for the same
## reason: this is a drawn quantity and the value it reads is republished on
## the render tick.
func _process(_delta: float) -> void:
	tick()


# --- Public API ---------------------------------------------------------------

## Recompute the overlay from the optic's current progress and write it.
##
## Public and parameterless, the same seam [method WeaponOptic.tick] and
## [method RifleRecoil.tick] offer: a test can [code]set_process(false)[/code],
## drive the optic with fixed deltas and call this to see what the screen would
## have shown, with no real clock anywhere.
func tick() -> void:
	var amount: float = compute_amount()
	_apply(amount)
	_show_or_hide_the_model(amount)


## Take the rifle off the screen once the optic has closed over it.
##
## Ryan: "the scope still doesnt come up to my eye, you can litterally see the
## model for the sniper through whats supposed to be the scope." The scope is a
## solid brick with no bore, so putting it on the eye line -- which is what
## "comes up to my eye" means -- puts an opaque slab inside the vignette's clear
## centre. The answer every game that fakes an optic uses: at full aim the view
## model stops being drawn and the overlay IS the scope. Below the threshold the
## rifle is fully visible, so the raise still reads as a raise.
func _show_or_hide_the_model(amount: float) -> void:
	if ads == null or ads.view_model == null:
		return
	ads.view_model.visible = not (hide_model_above >= 0.0 and amount > hide_model_above)


## How much vignette belongs on screen right now, from 0.0 (none) to 1.0
## (fully closed). The whole decision, in one pure function of the optic's
## progress and the profile, so a test can assert the shape of the ramp without
## a viewport.
func compute_amount() -> float:
	if ads == null:
		return 0.0
	if trigger != null and not trigger.is_active():
		# A bot in the tower, a prisoner, a spectator, a ghost. Same path,
		# every frame, evaluating to nothing.
		return 0.0
	var profile: ZoomProfile = ads.get_zoom_profile()
	if profile == null:
		return 0.0
	var progress: float = ads.get_aim_progress()
	var onset: float = clampf(profile.vignette_onset, 0.0, 0.99)
	return clampf((progress - onset) / (1.0 - onset), 0.0, 1.0)


## The amount last written to the shader. For a test, and for anything that
## wants to know whether the player is currently looking through the optic.
func get_amount() -> float:
	return maxf(_applied, 0.0)


# --- Internals ----------------------------------------------------------------

func _apply(amount: float) -> void:
	if _material == null or overlay == null:
		return
	var aspect: float = _viewport_aspect()
	if is_equal_approx(amount, _applied) and is_equal_approx(aspect, _applied_aspect):
		return
	_applied = amount
	_applied_aspect = aspect

	# Nothing on screen means nothing drawn: at hipfire the overlay is hidden
	# outright rather than blended at zero alpha, so the 99% of the match that
	# is not aimed pays for no full-screen blend at all.
	overlay.visible = amount > 0.0
	if amount <= 0.0:
		return

	var profile: ZoomProfile = ads.get_zoom_profile() if ads != null else null
	if profile != null:
		_material.set_shader_parameter("opacity", clampf(profile.vignette_opacity, 0.0, 1.0))
		_material.set_shader_parameter("clear_fraction", maxf(profile.vignette_clear_fraction, 0.0))
		_material.set_shader_parameter("softness", maxf(profile.vignette_softness, 0.01))
	_material.set_shader_parameter("aspect", aspect)
	_material.set_shader_parameter("amount", amount)


## Width over height of the window the overlay is drawn into, re-read rather
## than cached: the player can resize the window mid-match (see
## docs/BUILDING.md), and a stale aspect turns the optic into an ellipse.
func _viewport_aspect() -> float:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return 1.0
	var size: Vector2 = viewport.get_visible_rect().size
	if size.y <= 0.0:
		return 1.0
	return size.x / size.y


func _hide_overlay() -> void:
	if overlay != null:
		overlay.visible = false
	# Never leave a rifle hidden on a screen that is no longer aiming it.
	if ads != null and ads.view_model != null:
		ads.view_model.visible = true
	_applied = 0.0
	_applied_aspect = -1.0
