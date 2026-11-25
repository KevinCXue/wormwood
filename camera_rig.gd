extends Node3D
## Orbit camera with a first/third-person toggle (F), Skyrim-style.
##
## Node layout (all under Player):
##   CameraRig (this, Node3D)  -> rotates left/right (yaw) with the mouse
##     SpringArm3D             -> rotates up/down (pitch) with the mouse
##       Camera3D              -> sits at the end of the arm
##
## Why split yaw and pitch across two nodes? Each node then only ever rotates
## around one axis, so you never get the weird "roll" that happens when you
## stack both rotations on a single node.
##
## SpringArm3D is a built-in node: it casts a shape from its origin backwards
## along its +Z axis and pulls its children in if something is in the way, so
## the camera never ends up inside a crate or wall.
##
## First person is the same rig with the arm shrunk to zero length and the
## pivot raised to eye height. The switch is animated by easing both values.
##
## `top_level = true` (set in main.tscn) means this node ignores its parent's
## transform. It's still a child of Player for organisation, but it doesn't
## inherit the player's position/rotation; instead we follow the player
## ourselves below.

## Render layer for body parts hidden in first person (everything but the
## right arm; set per mesh in mannequin.tscn). Otherwise you'd see the inside
## of your head and your chest filling the bottom of the screen. Shadows are
## unaffected, so you still see your own shadow.
const BODY_LAYER := 2

@export var mouse_sensitivity := 0.003   # radians of turn per pixel of mouse movement
@export var start_pitch_deg := -20.0     # initial downward tilt

@export_group("Third person")
@export var third_person_distance := 4.0 # metres behind the pivot
@export var third_person_height := 1.55  # pivot height above the feet (~shoulders)
@export var third_person_pitch_deg := Vector2(-70.0, 35.0)  # (min, max) look down / up
@export var follow_smoothing := 15.0     # higher = camera catches up to the player faster

@export_group("First person")
@export var first_person_height := 1.64  # eye height above the feet
@export var first_person_pitch_deg := Vector2(-80.0, 80.0)

@export_group("")
@export var view_blend_speed := 10.0     # how fast the camera moves when switching views

var first_person := false

@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var _player: CharacterBody3D = get_parent()
@onready var _arm: SpringArm3D = $SpringArm3D
var _height := 0.0  # current (animated) pivot height


func _ready() -> void:
	# Don't let the spring arm "collide" with the player's own capsule, or the
	# camera would snap right up against the back of the player.
	_arm.add_excluded_object(_player.get_rid())
	_arm.rotation.x = deg_to_rad(start_pitch_deg)
	_arm.spring_length = third_person_distance
	_height = third_person_height
	global_position = _target_position()
	_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	# _unhandled_input only receives events the UI didn't already consume,
	# so later, clicks on menus won't also spin the camera.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		var limits := _pitch_limits()
		_arm.rotation.x = clampf(_arm.rotation.x - event.relative.y * mouse_sensitivity, limits.x, limits.y)
	elif event.is_action_pressed("toggle_view"):
		first_person = not first_person
		var limits := _pitch_limits()  # third person allows less looking up
		_arm.rotation.x = clampf(_arm.rotation.x, limits.x, limits.y)
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# The OS can still release the mouse (e.g. Cmd+Tab away); clicking
		# back into the window resumes mouse look. Esc quits (see main.gd).
		_capture_mouse()


func _physics_process(delta: float) -> void:
	# Ease the arm length and pivot height towards the current view's values.
	# 1 - exp(-k * dt) is a frame-rate-independent version of "lerp by k * dt".
	var blend := 1.0 - exp(-view_blend_speed * delta)
	var target_length := 0.0 if first_person else third_person_distance
	_arm.spring_length = lerpf(_arm.spring_length, target_length, blend)
	_height = lerpf(_height, first_person_height if first_person else third_person_height, blend)

	# Hide the body once the camera is close enough to be inside it.
	camera.set_cull_mask_value(BODY_LAYER, _arm.spring_length > 0.6)

	if first_person:
		# Eyes are attached to the body: no lag, or the view feels floaty.
		global_position = _target_position()
	else:
		# Follow in the physics step (same step the player moves in) so the
		# two stay in sync and the player doesn't appear to jitter.
		var t := 1.0 - exp(-follow_smoothing * delta)
		global_position = global_position.lerp(_target_position(), t)


func _target_position() -> Vector3:
	return _player.global_position + Vector3.UP * _height


func _pitch_limits() -> Vector2:
	var deg := first_person_pitch_deg if first_person else third_person_pitch_deg
	return Vector2(deg_to_rad(deg.x), deg_to_rad(deg.y))


func _capture_mouse() -> void:
	# Hides the cursor and locks it to the window; mouse motion still arrives
	# as InputEventMouseMotion.relative.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
