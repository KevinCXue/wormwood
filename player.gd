extends CharacterBody3D
## The player character. Moves with WASD / arrow keys, jumps with Space.
##
## Scale: a 1.8 m human. The body's origin is at its FEET; the capsule
## collision shape is raised 0.9 m in main.tscn so its bottom touches the ground.

@export var speed := 6.0          # metres per second (a jog; human sprint is ~8-10)
@export var jump_velocity := 5.0  # upward speed at the start of a jump: ~1.3 m high, enough for a 1 m crate
@export var turn_speed := 12.0    # how quickly the model turns to face its movement

# @onready runs these lookups just before _ready(), once child nodes exist.
# `$Name` is shorthand for get_node("Name").
@onready var _camera_rig: Node3D = $CameraRig
@onready var _model: Node3D = $Model  # the mannequin (mannequin.tscn)

# Read gravity from Project Settings so it matches the physics engine.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _spawn_point := Vector3.ZERO


func _ready() -> void:
	# Groups are tags any node can look up: villagers find the player with
	# get_tree().get_first_node_in_group("player") instead of a fixed path.
	add_to_group("player")
	_spawn_point = global_position
	# Set up the controls in code, so you can see exactly what they are.
	# (You can also do this in Project > Project Settings > Input Map.)
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("jump", [KEY_SPACE])
	_add_action("interact", [KEY_E])     # take / drop / talk (interactor.gd)
	_add_action("toggle_view", [KEY_F])  # first / third person (camera_rig.gd)
	_add_mouse_action("attack", MOUSE_BUTTON_LEFT)  # swing the equipped item (combat.gd)


func _physics_process(delta: float) -> void:
	# 1. Gravity: pull the character down while it's in the air.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Jump: only allowed when standing on something.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 3. Movement: turn the keys into a direction on the ground (X/Z plane).
	#    get_vector gives x = right, y = back (so W is -y, matching Godot's
	#    convention that "forward" is -Z).
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	# Make it camera-relative: spin the direction by the camera's yaw, so W
	# always means "away from the camera" rather than "towards world -Z".
	direction = direction.rotated(Vector3.UP, _camera_rig.rotation.y)
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Turn the visible model to face where we're going. We rotate only
		# the Model node, not the whole body, so the collision box (and the
		# camera rig) stay unaffected. atan2(-x, -z) is the Y angle at which
		# a node's forward (-Z) points along `direction`. lerp_angle takes the
		# short way round (e.g. 350° -> 10° goes through 0°, not 180°).
		if not _camera_rig.first_person:
			var target_yaw := atan2(-direction.x, -direction.z)
			_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	# In first person the body always faces where you look (so strafing with
	# A/D side-steps instead of turning, and the held item stays in view).
	if _camera_rig.first_person:
		_model.rotation.y = lerp_angle(_model.rotation.y, _camera_rig.rotation.y, 1.0 - exp(-turn_speed * 2.0 * delta))

	# 4. Let Godot move us and handle collisions with the floor and crates.
	move_and_slide()

	# 5. Animate the body to match how we're actually moving (after
	#    move_and_slide, so walking into a wall doesn't play a full run).
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	_model.update_pose(horizontal_speed, is_on_floor(), delta)

	# 6. Fell off the world? Respawn.
	if global_position.y < -10.0:
		global_position = _spawn_point
		velocity = Vector3.ZERO


func _add_mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
