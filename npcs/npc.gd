class_name Npc
extends CharacterBody3D
## A villager. They stand in their spot, breathe, turn their head to watch
## you when you come near, and talk when you press E: a conversation from
## their dialogue script (dialogue/*.txt, played by ui/dialogue_box.gd) if
## they have one, otherwise their next line from `lines` as a subtitle. If
## their script starts or completes quests, a speech bubble over their head
## shows whether they have one for you (npcs/quest_marker.gd).
##
## They can be hurt (a Health child, combat/health.gd) and can die. Attack
## one, or attack anyone within `witness_range` of them, and they react:
## fighters come at you (fists, or their `weapon` if they have one), others
## run. They calm down once you're far away, and walk back to their spot.
##
## How they behave is a small state machine: `_state` says what they're
## doing right now, and _physics_process runs that state's code each frame.
## It's the standard pattern for game AI, like a handler switching on a
## status field.
##
## The body is whichever one the player uses (blocky mannequin or detailed
## humanoid, see characters/body_slot.gd), dressed in _ready() from the
## "Look" exports. Everything that makes one villager different from another
## is an @export below, so a new villager is just another instance of
## npc.tscn with different values in the Inspector.

enum State { CALM, FIGHT, FLEE, RETURN, DEAD }

@export var display_name := "Villager"
## A conversation script (dialogue/*.txt). Empty: they just say `lines`.
@export_file("*.txt") var dialogue_file := ""
## One-liners for villagers without a script, shown in turn as subtitles.
@export_multiline var lines: PackedStringArray = ["Hello there."]

@export_group("Look")
@export_enum("male", "female") var body_type := "male"
@export_enum("peasant", "ranger") var outfit := "peasant"  # detailed body only
@export var skin_color := Color(0.78, 0.62, 0.5)
@export var tunic_color := Color(0.4, 0.4, 0.4)
@export var trousers_color := Color(0.25, 0.2, 0.16)
@export var boots_color := Color(0.14, 0.1, 0.08)
@export var hair_color := Color(0.25, 0.16, 0.1)
@export_enum("short", "long", "buzzed") var hair_style := "short"
@export var beard := false
@export var hood := false  # ranger outfit only
@export var skirt := false
@export_range(0.8, 1.2) var height_scale := 1.0

@export_group("Behaviour")
@export var notice_range := 7.0  # metres: closer than this and they watch you
@export var turn_speed := 4.0    # how quickly head and body turn
## The animation they stand around with. "Idle_Talking" gestures as if mid
## conversation: put two villagers face to face and they chat.
@export_enum("Idle", "Idle_Talking") var idle_animation := "Idle"

@export_group("Combat")
## Hit points. 0 = the default for their body type (men 20, women 10).
@export var max_health := 0
## When attacked or witnessing an attack: "fight" or "flee". "auto" = the
## default for their body type (men fight, women flee).
@export_enum("auto", "fight", "flee") var reaction := "auto"
## An item name from props/items/ ("sword") drawn when they fight. Empty: fists.
@export var weapon := ""
@export var witness_range := 10.0   # metres: attacks this close set them off
@export var chase_speed := 4.5      # metres per second
@export var flee_speed := 5.0       # metres per second
@export var walk_speed := 1.4       # metres per second, going home
@export var attack_reach := 1.5     # metres: close enough to swing
@export var attack_cooldown := 1.4  # seconds between swings
@export var give_up_distance := 30.0  # metres: fighters stop chasing beyond this
@export var safe_distance := 25.0     # metres: fleers feel safe beyond this...
@export var calm_down_time := 6.0     # ...for this many seconds, then go home

const ATTENTION_TIME := 6.0 # seconds they keep facing you after you talk
## The save system's static helpers, by file: referring to the SaveGame
## autoload by name would stop this script compiling in tool and test runs.
const SaveHelpers := preload("res://save/save_game.gd")

@onready var _model: BodySlot = $Model

var health: Health
var _state := State.CALM
var _threat: Node3D = null    # who they're fighting or running from
var _player: Node3D = null
var _line := 0
var _home := Vector3.ZERO     # where they stand when calm
var _home_yaw := 0.0          # the way the model faced when the game started
var _attention := 0.0         # seconds left of turning to face the player
var _grounded := false        # snapped down onto the ground yet?
var _cooldown := 0.0          # seconds until they can swing again
var _calm_for := 0.0          # seconds a fleer has felt safe; seconds spent going home
var _dodge := 0.0             # fleeing into a wall: seconds left of veering sideways
var _held_weapon: Equipable = null  # the drawn weapon, while fighting
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("persist")  # health and death are saved (save/save_game.gd)
	set_collision_layer_value(3, true)  # "hittable": combat.gd can hit them
	_home = global_position
	_home_yaw = _model.rotation.y
	health = Health.new()
	health.name = "Health"
	add_child(health)
	health.reset(max_health if max_health > 0 else (20 if body_type == "male" else 10))
	health.died.connect(func(_attacker): _die(false))
	_model.apply_look({
		"body_type": body_type, "outfit": outfit, "height_scale": height_scale,
		"skin": skin_color, "tunic": tunic_color, "trousers": trousers_color,
		"boots": boots_color, "hair": hair_color, "hair_style": hair_style,
		"skirt": skirt, "beard": beard, "hood": hood, "idle": idle_animation,
	})
	# The player adds itself to the "player" group (player.gd). Looking it up
	# by group means this scene doesn't need a hard-coded path to the player.
	_player = get_tree().get_first_node_in_group("player")
	_add_quest_marker()


## A bubble over the head if this villager's script deals in quests.
func _add_quest_marker() -> void:
	var ids := quest_ids()
	if ids.is_empty():
		return
	var marker: Sprite3D = preload("res://npcs/quest_marker.gd").new()
	marker.name = "QuestMarker"
	marker.quest_ids = ids
	marker.height = 2.35 * height_scale
	add_child(marker)


## Quests this villager's script starts or completes (their quests).
func quest_ids() -> PackedStringArray:
	if dialogue_file == "":
		return PackedStringArray()
	return preload("res://dialogue/dialogue_script.gd").load_script(dialogue_file).quest_ids()


func is_dead() -> bool:
	return _state == State.DEAD


## Calm and alive: the only time they'll talk.
func can_talk() -> bool:
	return _state == State.CALM


func is_hostile() -> bool:
	return _state == State.FIGHT


## Called by the dialogue box: face the player for the whole conversation.
func begin_conversation() -> void:
	_attention = INF


func end_conversation() -> void:
	_attention = ATTENTION_TIME  # keep facing them a moment longer


## Next line of dialogue. Steps through `lines` and then repeats the last
## one, the way a villager runs out of new things to say.
func talk() -> String:
	_attention = ATTENTION_TIME
	var text := lines[mini(_line, lines.size() - 1)] if lines.size() > 0 else "..."
	_line += 1
	return text


# --- Being hit -----------------------------------------------------------------------

## The hittable contract (see combat.gd): struck by `weapon` (null = a fist)
## swung from `from` in direction `dir`, by `attacker`.
func on_hit(weapon_used: Equipable, from: Vector3, dir: Vector3, attacker: Node3D = null) -> void:
	if is_dead():
		return
	health.damage(Health.damage_from(weapon_used), attacker)
	if attacker and attacker.is_in_group("player"):
		attacker.get_node("HUD").show_target(display_name, health)  # the killing blow too
	var chest := global_position + Vector3.UP * 1.2 * height_scale
	HitFx.burst(self, chest, Color(0.55, 0.06, 0.05), dir, 14, 0.025, 2.0)
	if is_dead():
		return
	_model.flinch()
	# Only the player starts fights: a villager defending themselves isn't
	# an attack that sets the rest of the town off.
	if attacker and attacker.is_in_group("player"):
		raise_alarm(attacker, self)


## An attack by `attacker` on `victim`: everyone within their witness range
## of the victim (and the victim) reacts.
static func raise_alarm(attacker: Node3D, victim: Node3D) -> void:
	for npc: Npc in victim.get_tree().get_nodes_in_group("npcs"):
		if npc == victim or npc.global_position.distance_to(victim.global_position) <= npc.witness_range:
			npc._react(attacker)


func _react(attacker: Node3D) -> void:
	if is_dead() or (attacker is Npc):
		return
	var fights := reaction == "fight" or (reaction == "auto" and body_type == "male")
	_threat = attacker
	_attention = 0.0
	if fights:
		if _state != State.FIGHT:
			_state = State.FIGHT
			_draw_weapon()
	elif _state != State.FLEE:
		_state = State.FLEE
		_calm_for = 0.0


func _die(instant: bool) -> void:
	_state = State.DEAD
	_threat = null
	_drop_weapon(not instant)
	_model.set_look_target(null)
	_model.die(instant)
	$CollisionShape3D.set_deferred("disabled", true)  # walk over the body
	set_collision_layer_value(3, false)
	if not instant:
		# Their quests can't go on without them.
		var player := get_tree().get_first_node_in_group("player")
		var quest_log: Node = player.get_node_or_null("QuestLog") if player else null
		if quest_log:
			for id in quest_ids():
				quest_log.fail(id, display_name)


# --- Each frame ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null:
		# Villagers start up before the player (they come first in the
		# scene), so the lookup in _ready() can miss it.
		_player = get_tree().get_first_node_in_group("player")
	if _state == State.DEAD:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _held_weapon:
		_model.place_equipped(_held_weapon)
	match _state:
		State.CALM:
			_be_calm(delta)
		State.FIGHT:
			_fight(delta)
		State.FLEE:
			_flee(delta)
		State.RETURN:
			_go_home(delta)


func _be_calm(delta: float) -> void:
	if not _grounded:
		_snap_to_ground()
	# Standing still: speed 0 gives the idle pose with its slow breathing.
	_model.update_pose(0.0, true, delta)
	var k := 1.0 - exp(-turn_speed * delta)

	var to_player := Vector3.ZERO
	var near := false
	if _player:
		to_player = _player.global_position - global_position
		to_player.y = 0.0
		near = to_player.length() < notice_range

	# Body: after you talk to them, turn to face you; otherwise drift back to
	# the way they were placed in the editor.
	_attention = maxf(_attention - delta, 0.0)
	var body_target := _home_yaw
	if _attention > 0.0 and near:
		# The model's rotation is relative to this node, so subtract our own.
		body_target = _yaw_towards(to_player) - global_rotation.y
	_model.rotation.y = lerp_angle(_model.rotation.y, body_target, k)

	# Head: watch the player while they're nearby. (The body works out how
	# far the neck can turn.)
	_model.set_look_target(_player.global_position + Vector3.UP * 1.6 if _player and near else null)


func _fight(delta: float) -> void:
	if _threat == null or not is_instance_valid(_threat) or _threat_dead():
		_calm_down()
		return
	var to := _flat(_threat.global_position - global_position)
	var dist := to.length()
	if dist > give_up_distance:
		_calm_down()
		return
	_model.set_look_target(_threat.global_position + Vector3.UP * 1.5)
	if dist > attack_reach:
		_move(to.normalized() * chase_speed, delta)
	else:
		_move(Vector3.ZERO, delta)
		_face(to, delta * 3.0)
		if _cooldown <= 0.0 and not _model.is_swinging():
			_attack()


func _flee(delta: float) -> void:
	if _threat == null or not is_instance_valid(_threat) or _threat_dead():
		_calm_down()
		return
	var away := _flat(global_position - _threat.global_position)
	if away.length() > safe_distance:
		_calm_for += delta
		if _calm_for > calm_down_time:
			_calm_down()
			return
	else:
		_calm_for = 0.0
	var dir := away.normalized()
	if _dodge > 0.0:  # ran into a wall: veer off to one side for a moment
		_dodge -= delta
		dir = dir.rotated(Vector3.UP, PI / 2.0)
	_move(dir * flee_speed, delta)
	if is_on_wall() and _dodge <= 0.0:
		_dodge = 1.0


func _go_home(delta: float) -> void:
	var to := _flat(_home - global_position)
	_calm_for += delta
	# Stuck somewhere (no proper pathfinding yet)? Pop home while you're not looking.
	var unseen := _player == null or _player.global_position.distance_to(global_position) > 25.0
	if to.length() < 0.5 or (_calm_for > 45.0 and unseen):
		global_position = _home
		velocity = Vector3.ZERO
		_state = State.CALM
		_grounded = false  # settle onto the ground again
		return
	_move(to.normalized() * walk_speed, delta)


func _calm_down() -> void:
	_threat = null
	_put_weapon_away()
	_state = State.RETURN
	_calm_for = 0.0


func _threat_dead() -> bool:
	var h: Node = _threat.get_node_or_null("Health")
	return h != null and h.is_dead()


## Swing (or punch); a moment later, if the target is still in front and in
## reach, it's hit. Same timing idea as the player's combat.gd.
func _attack() -> void:
	_cooldown = attack_cooldown
	_model.start_swing(_held_weapon == null)
	await get_tree().create_timer(_model.strike_time).timeout
	if is_dead() or _threat == null or not is_instance_valid(_threat) or _threat_dead():
		return
	var to := _flat(_threat.global_position - global_position)
	var facing := -_model.global_basis.z
	if to.length() <= attack_reach + 0.6 and facing.dot(to.normalized()) > 0.3:
		if _threat.has_method("on_hit"):
			_threat.on_hit(_held_weapon, global_position, to.normalized(), self)


## Walk/run with gravity, turning the body to face the way they're going.
func _move(horizontal: Vector3, delta: float) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length()
	_model.update_pose(speed, is_on_floor(), delta)
	if horizontal.length() > 0.1:
		_face(horizontal, delta)


func _face(dir: Vector3, delta: float) -> void:
	var target := _yaw_towards(dir) - global_rotation.y
	_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - exp(-turn_speed * 2.0 * delta))


# --- Weapon --------------------------------------------------------------------------

func _draw_weapon() -> void:
	if weapon == "" or _held_weapon:
		return
	var scene_path := "res://props/items/%s.tscn" % weapon
	if not ResourceLoader.exists(scene_path):
		push_warning("%s: no item called %s" % [display_name, weapon])
		return
	_held_weapon = load(scene_path).instantiate()
	_held_weapon.freeze = true
	_model.weapon_socket.add_child(_held_weapon)
	# After adding: an item's _ready() puts it in the "items" group and on the
	# items layer. In someone's hand it's neither collidable nor takeable (nor
	# saved as an item lying in the world).
	_held_weapon.collision_layer = 0
	_held_weapon.collision_mask = 0
	_held_weapon.remove_from_group("items")
	_model.equipped = true


func _put_weapon_away() -> void:
	if _held_weapon:
		_held_weapon.queue_free()
		_held_weapon = null
		_model.equipped = false


## On death the weapon falls from their hand, as an ordinary item you can take.
func _drop_weapon(drop: bool) -> void:
	if _held_weapon == null:
		return
	var where := _held_weapon.global_transform
	_put_weapon_away()
	if drop:
		var item: Item = load("res://props/items/%s.tscn" % weapon).instantiate()
		get_parent().add_child(item)
		item.global_transform = where


# --- Saving --------------------------------------------------------------------------

func save_state() -> Dictionary:
	var state := {"health": health.health, "dead": is_dead()}
	if is_dead():
		state["transform"] = SaveHelpers.transform_to_array(global_transform)
		state["yaw"] = _model.rotation.y
	return state


## Alive: back at their spot with their saved health. Dead: lying where they fell.
func load_state(state: Dictionary) -> void:
	health.reset(health.max_health, int(state.get("health", health.max_health)))
	if state.get("dead", false):
		global_transform = SaveHelpers.array_to_transform(state.transform)
		_model.rotation.y = state.get("yaw", _model.rotation.y)
		_die(true)


# --- Helpers -------------------------------------------------------------------------

## Villagers standing still don't fall under gravity, so place them on
## whatever is below: terrain, a plaza, a building's floor. Cast a ray
## straight down from a little above; the terrain's collision may take a
## frame or two to exist, so keep trying until something is hit.
func _snap_to_ground() -> void:
	var from := global_position + Vector3.UP * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 12.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = hit.position.y
		_grounded = true


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## The Y rotation at which a node's forward (-Z) points along `dir`.
func _yaw_towards(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
