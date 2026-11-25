extends Node
## Looking at, picking up, equipping and dropping items, and talking to
## villagers. A child of Player.
##
## Two hands, two jobs (no inventory yet):
##   Right hand: carries one ordinary Item (plate, goblet...). E drops it.
##   Left hand:  one Equipable (axe, sword). Equipping another drops the old one.
##
## Every physics frame we cast a ray from the camera through the centre of the
## screen (where the crosshair is). If it hits an Item within reach, that's the
## target and the HUD shows "E  Take <name>" or "E  Equip <name>". If it hits a
## villager (Npc), the HUD shows "E  Talk <name>" and E shows their next line.
##
## Holding works the same in both hands: the item stops being simulated
## (freeze), stops colliding, and is re-parented to a hand socket on the
## mannequin. Letting go undoes that, adds a gentle toss and lets physics
## take over.

@export var reach := 2.3       # metres from the player's eyes to the item
@export var toss_speed := 1.2  # forward speed added when dropping
@export var talk_reach := 3.0  # metres: talking works from a bit further than grabbing
@export var talk_range := 6.0  # walk further than this away and the conversation ends

@onready var _player: CharacterBody3D = get_parent()
@onready var _rig: Node3D = $"../CameraRig"
@onready var _model: BodySlot = $"../Model"
@onready var _hud: CanvasLayer = $"../HUD"

var _target: Item = null         # the item under the crosshair, if any
var _npc: Npc = null             # the villager under the crosshair, if any
var _talking_to: Npc = null      # who said the line currently on screen
var _held: Item = null           # right hand
var _equipped: Equipable = null  # left hand
# Where each item lived and its collision settings before we took it, so we
# can restore them on release. Keyed by the item itself.
var _saved := {}


func _physics_process(_delta: float) -> void:
	var hit := _find_target()
	# `as` converts to the given type, or gives null if it isn't one.
	_target = hit as Item
	_npc = hit as Npc
	# With the right hand full, only equipables (left hand) are worth targeting.
	if _held and not _target is Equipable:
		_target = null
	if _held:
		_place_carried()
	if _equipped:
		_place_equipped()
	if _talking_to and _talking_to.global_position.distance_to(_player.global_position) > talk_range:
		_hud.hide_line()
		_talking_to = null
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _npc:
		_talking_to = _npc
		_hud.show_line(_npc.display_name, _npc.talk())
	elif _target is Equipable:
		_equip(_target)
	elif _held:
		_release(_held)
		_held = null
		_model.holding = false
	elif _target:
		_take(_target)


## The weapon/tool in the left hand, or null. Used by combat.gd.
func get_equipped() -> Equipable:
	return _equipped


## Whatever is under the crosshair and close enough to use: an Item, an Npc,
## or null.
func _find_target() -> Node3D:
	var cam: Camera3D = _rig.camera
	var from := cam.global_position
	var forward := -cam.global_basis.z  # cameras look down their -Z axis
	var eyes := _player.global_position + Vector3.UP * 1.6
	# In third person the camera sits ~4 m behind the player, so the ray has
	# to be long enough to get past the player and then `reach` further.
	var length := from.distance_to(eyes) + maxf(reach, talk_reach)
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * length)
	query.exclude = [_player.get_rid()]  # don't hit our own capsule
	# direct_space_state is the physics world, queryable right now.
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var distance := eyes.distance_to(hit.position)
	if hit.collider is Item and distance <= reach:
		return hit.collider
	if hit.collider is Npc and distance <= talk_reach:
		return hit.collider
	return null  # nothing usable, or in view but too far away


func _take(item: Item) -> void:
	_held = item
	_grab(item, _model.carry_socket)
	_model.holding = true
	_place_carried()


func _equip(item: Equipable) -> void:
	if _equipped:
		_release(_equipped)  # one slot: the old one falls from the left hand
	_equipped = item
	_grab(item, _model.weapon_socket)
	_model.equipped = true
	_place_equipped()


func _grab(item: Item, socket: Node3D) -> void:
	_saved[item] = [item.get_parent(), item.collision_layer, item.collision_mask]
	# freeze: the physics engine stops moving it, so we can place it ourselves.
	item.freeze = true
	# Layer/mask 0: it neither collides nor gets collided with, so it can't
	# shove the player or snag on tables while carried.
	item.collision_layer = 0
	item.collision_mask = 0
	# reparent() moves a node to a new parent; it then follows the hand.
	item.reparent(socket)


func _release(item: Item) -> void:
	var saved: Array = _saved[item]
	_saved.erase(item)
	if item == _equipped:
		_equipped = null
		_model.equipped = false
	# reparent() keeps the global transform by default, so it lets go exactly
	# where the hand was.
	item.reparent(saved[0])
	item.collision_layer = saved[1]
	item.collision_mask = saved[2]
	item.freeze = false
	# Carry the player's momentum plus a gentle toss forward and up.
	var forward := -_model.global_basis.z
	item.linear_velocity = _player.velocity + forward * toss_speed + Vector3.UP * 0.5
	item.angular_velocity = Vector3.ZERO


## Where exactly a held item sits depends on the body (a code-animated
## mannequin vs a skeleton), so the body works it out. See body_slot.gd.
func _place_carried() -> void:
	_model.place_carried(_held)


func _place_equipped() -> void:
	_model.place_equipped(_equipped)


func _update_hud() -> void:
	if _npc:
		_hud.show_prompt("Talk", _npc.display_name, false)
	elif _target is Equipable:
		_hud.show_prompt("Equip", _target.display_name, false)
	elif _target:
		_hud.show_prompt("Take", _target.display_name, false)
	elif _held:
		_hud.show_prompt("Drop", _held.display_name, true)
	else:
		_hud.hide_prompt()
	_hud.set_crosshair(_rig.first_person, _target != null or _npc != null)
