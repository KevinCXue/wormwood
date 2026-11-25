class_name BodySlot
extends Node3D
## Where a character's body goes. At startup it spawns either the blocky
## mannequin or the detailed rigged humanoid (Settings.character_detail), and
## passes calls through to it. That lets the player, villagers, combat and the
## interactor use either body without knowing which one it is.
##
## This file is the "body contract". Any body scene (mannequin.tscn,
## characters/humanoid.tscn, ...) must provide:
##
##   update_pose(speed, on_floor, delta)  animate for this frame
##   start_swing() / is_swinging()        the attack animation
##   strike_time                          seconds into a swing when it lands
##   carry_socket / weapon_socket         nodes held items are parented to
##   holding / equipped                   flags: carrying something / weapon out
##   place_carried(item) / place_equipped(item)  put a held item in the hand
##   apply_look(look: Dictionary)         colours, hair, build (villagers)
##   set_look_target(position or null)    turn the head towards something
##   use_as_player(is_player)             render layers for first person
##
## Like an interface in other languages. GDScript has no interfaces, so this
## is a convention: each body simply has these members ("duck typing").
##
## Rotate this node (not the body inside it) to turn the character.

const SCENES := {
	"blocky": "res://mannequin.tscn",
	"detailed": "res://characters/humanoid.tscn",
}

## True for the player's body: its meshes hide from the first-person camera.
@export var is_player := false

var body: Node3D


func _ready() -> void:
	var detail: String = Settings.character_detail
	if not ResourceLoader.exists(SCENES.get(detail, "")):
		detail = "blocky"  # e.g. the detailed character isn't set up yet
	body = load(SCENES[detail]).instantiate()
	add_child(body)
	body.use_as_player(is_player)


# --- Pass-throughs ------------------------------------------------------------------

var strike_time: float:
	get: return body.strike_time
var carry_socket: Node3D:
	get: return body.carry_socket
var weapon_socket: Node3D:
	get: return body.weapon_socket
var holding: bool:
	get: return body.holding
	set(value): body.holding = value
var equipped: bool:
	get: return body.equipped
	set(value): body.equipped = value


func update_pose(speed: float, on_floor: bool, delta: float) -> void:
	body.update_pose(speed, on_floor, delta)


func start_swing() -> void:
	body.start_swing()


func is_swinging() -> bool:
	return body.is_swinging()


func place_carried(item: Item) -> void:
	body.place_carried(item)


func place_equipped(item: Equipable) -> void:
	body.place_equipped(item)


func apply_look(look: Dictionary) -> void:
	body.apply_look(look)


func set_look_target(target: Variant) -> void:
	body.set_look_target(target)
