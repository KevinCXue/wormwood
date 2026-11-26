extends CharacterBody3D
## The player character. Moves with WASD / arrow keys, runs while Shift is
## held, jumps with Space.
##
## Scale: a 1.8 m human. The body's origin is at its FEET; the capsule
## collision shape is raised 0.9 m in main.tscn so its bottom touches the ground.

@export var speed := 6.0          # metres per second (a jog; human sprint is ~8-10)
@export var sprint_speed := 10.5  # metres per second while Shift is held (the Sprint clip plays faster above its own 8.25 pace to keep up)
@export var overloaded_factor := 0.5  # fraction of `speed` when carrying more than the bag's limit
@export var speed_change := 6.0   # how quickly you speed up / slow down between jog and sprint (1/s; higher = snappier)
@export var jump_velocity := 5.0  # upward speed at the start of a jump: ~1.3 m high, enough for a 1 m crate
@export var turn_speed := 12.0    # how quickly the model turns to face its movement

# @onready runs these lookups just before _ready(), once child nodes exist.
# `$Name` is shorthand for get_node("Name").
@onready var _camera_rig: Node3D = $CameraRig
@onready var _model: BodySlot = $Model  # holds the body (characters/body_slot.gd)
@onready var _inventory: Node = $Inventory  # the bag (inventory/inventory.gd)
@onready var health: Health = $Health        # 40 hit points (combat/health.gd)
@onready var _hud: CanvasLayer = $HUD

@export_group("Health")
@export var regen_delay := 10.0     # seconds without being hurt before health creeps back
@export var regen_interval := 2.0   # seconds per point regained
@export var game_over_delay := 2.5  # seconds between falling and the death screen
@export_group("")

var _since_hurt := 0.0
var _regen_timer := 0.0

# Read gravity from Project Settings so it matches the physics engine.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## True while the player shouldn't act: talking to someone (ui/dialogue_box.gd)
## or on the title screen (ui/title_screen.gd). No moving, jumping, swinging
## or opening menus until it's false again.
var locked := false

var _spawn_point := Vector3.ZERO
var _move_speed := 6.0  # current top speed, eased between `speed` and `sprint_speed`


func _ready() -> void:
	# Groups are tags any node can look up: villagers find the player with
	# get_tree().get_first_node_in_group("player") instead of a fixed path.
	add_to_group("player")
	add_to_group("persist")  # saved by save/save_game.gd (see save_state below)
	health.died.connect(_on_died)
	health.changed.connect(func(h, m): _hud.set_health(h, m))
	_spawn_point = global_position
	_move_speed = speed
	# Set up the controls in code, so you can see exactly what they are.
	# (You can also do this in Project > Project Settings > Input Map.)
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("jump", [KEY_SPACE])
	_add_action("sprint", [KEY_SHIFT])   # hold to run
	_add_action("interact", [KEY_E])     # take / drop / talk (interactor.gd)
	_add_action("toggle_view", [KEY_F])  # first / third person (camera_rig.gd)
	_add_action("inventory", [KEY_I, KEY_TAB])  # open the bag (ui/inventory_menu.gd)
	_add_action("quick_select", [KEY_Q])  # hold for the favourites wheel (ui/quick_wheel.gd)
	_add_action("help", [KEY_H])  # the controls screen (ui/help_menu.gd)
	_add_action("journal", [KEY_J])  # quests (ui/journal.gd)
	# Menus: Godot's built-in "ui_up"/"ui_down" actions move between buttons
	# and list rows (arrow keys by default). Add W and S, so every menu works
	# with the hand already on WASD. (Typing w/s in a text box still types.)
	_add_key_to_action("ui_up", KEY_W)
	_add_key_to_action("ui_down", KEY_S)
	_add_mouse_action("attack", MOUSE_BUTTON_LEFT)  # swing the equipped item (combat.gd)


func _physics_process(delta: float) -> void:
	# 1. Gravity: pull the character down while it's in the air.
	if not is_on_floor():
		velocity.y -= gravity * delta
	if health.is_dead():
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()  # a body still falls, but does nothing else
		return
	_regenerate(delta)

	# 2. Jump: only allowed when standing on something.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not locked:
		velocity.y = jump_velocity

	# 3. Movement: turn the keys into a direction on the ground (X/Z plane).
	#    get_vector gives x = right, y = back (so W is -y, matching Godot's
	#    convention that "forward" is -Z).
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if locked:
		input_dir = Vector2.ZERO  # stand still while talking
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	# Make it camera-relative: spin the direction by the camera's yaw, so W
	# always means "away from the camera" rather than "towards world -Z".
	direction = direction.rotated(Vector3.UP, _camera_rig.rotation.y)
	# Hold Shift to run. Ease the top speed rather than snapping it, so the
	# body's animation blends smoothly from jog to sprint. Only change pace on
	# the ground: you can't speed up mid-jump.
	if is_on_floor():
		var target_speed := sprint_speed if Input.is_action_pressed("sprint") else speed
		if _inventory.is_overloaded():
			target_speed = speed * overloaded_factor  # too heavy: no running, and slow
		_move_speed = lerpf(_move_speed, target_speed, 1.0 - exp(-speed_change * delta))
	if direction != Vector3.ZERO:
		velocity.x = direction.x * _move_speed
		velocity.z = direction.z * _move_speed
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
	_model.set_first_person(_camera_rig.first_person)
	_model.update_pose(horizontal_speed, is_on_floor(), delta)

	# 6. Fell off the world? Respawn.
	if global_position.y < -10.0:
		global_position = _spawn_point
		velocity = Vector3.ZERO


# --- Health -----------------------------------------------------------------------

## The hittable contract (see combat.gd): a villager hits you with `weapon`
## (null = a fist).
func on_hit(weapon: Equipable, _from: Vector3, dir: Vector3, attacker: Node3D = null) -> void:
	if health.is_dead():
		return
	health.damage(Health.damage_from(weapon), attacker)
	_since_hurt = 0.0
	_model.flinch()
	HitFx.burst(self, global_position + Vector3.UP * 1.2, Color(0.55, 0.06, 0.05), dir, 10, 0.025, 2.0)
	_hud.flash_hurt()
	if attacker is Npc:
		_hud.show_target(attacker.display_name, attacker.health)


## Eat one of `data` from the bag (food: ItemData.heal > 0). Returns whether
## anything was eaten.
func eat(data: ItemData) -> bool:
	if data.heal <= 0 or health.is_dead() or _inventory.remove(data, 1) == 0:
		return false
	health.heal(data.heal)
	_hud.show_note("Ate %s  (+%d health)" % [data.display_name, data.heal])
	return true


## Out of combat for regen_delay seconds: a point back every regen_interval.
func _regenerate(delta: float) -> void:
	_since_hurt += delta
	if _since_hurt < regen_delay or health.health >= health.max_health:
		return
	_regen_timer += delta
	if _regen_timer >= regen_interval:
		_regen_timer = 0.0
		health.heal(1)


func _on_died(_attacker: Node) -> void:
	locked = true
	SaveGame.blocked = true  # no autosave of a dead player
	_model.die()
	await get_tree().create_timer(game_over_delay).timeout
	$GameOver.show_screen()


## Where you are and how you're looking (save/save_game.gd).
func save_state() -> Dictionary:
	return {
		"position": SaveGame.vector_to_array(global_position),
		"body_yaw": _model.rotation.y,
		"camera_yaw": _camera_rig.rotation.y,
		"camera_pitch": _camera_rig.get_node("SpringArm3D").rotation.x,
		"camera_distance": _camera_rig.third_person_distance,
		"first_person": _camera_rig.first_person,
		"health": health.health,
	}


func load_state(state: Dictionary) -> void:
	health.reset(health.max_health, int(state.get("health", health.max_health)))
	global_position = SaveGame.array_to_vector(state.position)
	velocity = Vector3.ZERO
	_model.rotation.y = state.get("body_yaw", 0.0)
	_camera_rig.rotation.y = state.get("camera_yaw", 0.0)
	_camera_rig.get_node("SpringArm3D").rotation.x = state.get("camera_pitch", 0.0)
	_camera_rig.third_person_distance = state.get("camera_distance", _camera_rig.third_person_distance)
	_camera_rig._set_first_person(state.get("first_person", false))
	# The camera normally glides after the player; jump it there instead.
	_camera_rig.global_position = _camera_rig._target_position()


func _add_mouse_action(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _add_key_to_action(action: String, key: Key) -> void:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == key:
			return  # already added (the player is re-created on every load)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
