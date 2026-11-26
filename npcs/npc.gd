class_name Npc
extends CharacterBody3D
## A villager. For now they stand in one spot, breathe, turn their head to
## watch you when you come near, and talk when you press E: a conversation
## from their dialogue script (dialogue/*.txt, played by ui/dialogue_box.gd)
## if they have one, otherwise their next line from `lines` as a subtitle.
## If their script starts or completes quests, a speech bubble over their
## head shows whether they have one for you (npcs/quest_marker.gd).
##
## The body is whichever one the player uses (blocky mannequin or detailed
## humanoid, see characters/body_slot.gd), dressed in _ready() from the
## "Look" exports. Everything that makes one villager different from another
## is an @export below, so a new villager is just another instance of
## npc.tscn with different values in the Inspector.
##
## Why CharacterBody3D? It's the body type for things that move under their
## own control (like the player). These villagers don't walk yet, but when
## they do, the node type is already right. Until then it's a solid capsule
## the player bumps into.

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

const ATTENTION_TIME := 6.0 # seconds they keep facing you after you talk

@onready var _model: BodySlot = $Model

var _player: Node3D = null
var _line := 0
var _home_yaw := 0.0       # the way the model faced when the game started
var _attention := 0.0      # seconds left of turning to face the player
var _grounded := false     # snapped down onto the ground yet?


func _ready() -> void:
	add_to_group("npcs")
	_home_yaw = _model.rotation.y
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
	if dialogue_file == "":
		return
	var ids: PackedStringArray = preload("res://dialogue/dialogue_script.gd").load_script(dialogue_file).quest_ids()
	if ids.is_empty():
		return
	var marker: Sprite3D = preload("res://npcs/quest_marker.gd").new()
	marker.name = "QuestMarker"
	marker.quest_ids = ids
	marker.height = 2.35 * height_scale
	add_child(marker)


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


func _physics_process(delta: float) -> void:
	if _player == null:
		# Villagers start up before the player (they come first in the
		# scene), so the lookup in _ready() can miss it.
		_player = get_tree().get_first_node_in_group("player")
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
	_model.set_look_target(_player.global_position + Vector3.UP * 1.6 if near else null)


## Villagers don't fall under gravity (they don't move yet), so place them on
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


## The Y rotation at which a node's forward (-Z) points along `dir`.
func _yaw_towards(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
