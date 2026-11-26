extends Node
## Day/night cycle. Moves the Sun (and an opposite Moon) across the sky and
## fades their light in and out.
##
## You don't have to colour the sky yourself: the PhysicalSkyMaterial (in
## main.tscn) simulates the atmosphere from the sun's angle, so it turns blue
## at noon, orange at sunset and dark at night automatically. The fog and the
## ambient light both sample the sky, so they follow along too.
##
## Debug: hold T to fast-forward time.

@export var sun: DirectionalLight3D
@export var moon: DirectionalLight3D

@export_group("Time")
@export_range(0.0, 24.0, 0.1) var time_of_day := 9.0  # hours: 6 = sunrise, 12 = noon, 18 = sunset
@export var day_length_minutes := 20.0  # real minutes per in-game day (big open-world RPGs often use ~70)
@export var paused := false             # tick this in the Inspector to freeze the clock
@export var fast_forward_speed := 120.0 # multiplier while holding T

@export_group("Sun path")
## How far the sun's arc leans towards +Z, in degrees. At 0 the sun passes
## straight overhead at noon. More tilt means longer, more dramatic shadows.
@export_range(1.0, 89.0) var sun_tilt_deg := 35.0

@export_group("Light")
@export var sun_max_energy := 1.0
@export var moon_max_energy := 0.15
@export var sunrise_color := Color(1.0, 0.55, 0.3)
@export var noon_color := Color(1.0, 0.96, 0.9)


func _process(delta: float) -> void:
	# _process runs once per rendered frame. That's right for purely visual
	# things like lighting; gameplay physics stays in _physics_process.
	if not paused:
		var hours_per_second := 24.0 / (day_length_minutes * 60.0)
		if Input.is_physical_key_pressed(KEY_T):
			hours_per_second *= fast_forward_speed
		# fposmod wraps 24.0 back to 0.0 (like % but for floats, never negative).
		time_of_day = fposmod(time_of_day + hours_per_second * delta, 24.0)
	_update_lights()


func _update_lights() -> void:
	# Position along the sun's arc: 0 at 6:00 (east horizon), PI/2 at noon,
	# PI at 18:00 (west horizon), and below the ground at night.
	var theta := (time_of_day - 6.0) / 12.0 * PI
	var tilt := deg_to_rad(sun_tilt_deg)
	# Unit vector from the world towards the sun. East is +X. The arc is a
	# circle tipped over towards +Z by `tilt`.
	var to_sun := Vector3(cos(theta), sin(theta) * cos(tilt), sin(theta) * sin(tilt))

	# Its y component is the sine of the sun's height above the horizon:
	# 1 = straight up, 0 = on the horizon, negative = below the ground.
	var elevation := to_sun.y

	# Sun: fades in just after sunrise and turns warmer near the horizon.
	# smoothstep(a, b, x) goes 0 -> 1 as x goes a -> b, with eased ends.
	_aim(sun, to_sun)
	sun.light_energy = sun_max_energy * smoothstep(-0.02, 0.04, elevation)
	sun.light_color = sunrise_color.lerp(noon_color, smoothstep(0.0, 0.5, elevation))
	# Hiding a light that gives no light skips its shadow rendering (free perf).
	sun.visible = sun.light_energy > 0.0

	# Moon: always opposite the sun, so it's up whenever the sun is down.
	_aim(moon, -to_sun)
	moon.light_energy = moon_max_energy * smoothstep(-0.02, 0.1, -elevation)
	moon.visible = moon.light_energy > 0.0


## Point a directional light so it shines from `towards_light` down onto the
## world. Lights shine along their own -Z axis, and Basis.looking_at builds a
## rotation whose -Z faces the given direction (so no hand-written matrices).
func _aim(light: DirectionalLight3D, towards_light: Vector3) -> void:
	light.global_basis = Basis.looking_at(-towards_light, Vector3.UP)
