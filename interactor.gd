extends Node
## Looking at things and using them with E: taking items into the bag,
## carrying them, equipping weapons and talking to villagers. Also does the
## hand work for the inventory screen (equip, unequip, drop). A child of Player.
##
## Every physics frame we cast a ray from the camera through the centre of the
## screen (where the crosshair is). If it hits an Item within reach, that's the
## target; a villager (Npc) within talking reach works the same way.
##
## E on an item:
##   tap   puts it in the bag (inventory.gd); a weapon is also added to the
##         quick-select wheel if there's room, and equipped if your weapon
##         hand is empty
##   hold  carries it in the right hand, like a goblet you want to move to
##         another table (E again drops it), or, for a weapon, puts it in the
##         bag AND equips it
## E on a villager shows their next line as a subtitle.
##
## Hands:
##   Right hand: one carried Item (in the world, not in the bag).
##   Weapon hand: the equipped weapon. It counts as in the bag; equipping
##   spawns a copy into the hand, unequipping removes it again.
##
## Holding works the same in both hands: the item stops being simulated
## (freeze), stops colliding, and is re-parented to a hand socket on the body.
## Dropping undoes that, adds a gentle toss and lets physics take over.

@export var reach := 2.3       # metres from the player's eyes to the item
@export var toss_speed := 1.2  # forward speed added when dropping
@export var talk_reach := 3.0  # metres: talking works from a bit further than grabbing
@export var talk_range := 6.0  # walk further than this away and the conversation ends
@export var hold_time := 0.35  # seconds E must be held to carry/equip instead of taking

@onready var _player: CharacterBody3D = get_parent()
@onready var _rig: Node3D = $"../CameraRig"
@onready var _model: BodySlot = $"../Model"
@onready var _hud: CanvasLayer = $"../HUD"
@onready var _inventory: Node = $"../Inventory"
@onready var _dialogue: CanvasLayer = $"../DialogueBox"

var _target: Item = null         # the item under the crosshair, if any
var _npc: Npc = null             # the villager under the crosshair, if any
var _talking_to: Npc = null      # who said the line currently on screen
var _held: Item = null           # right hand
var _equipped: Equipable = null  # weapon hand
var _pressed_on: Item = null     # item E went down on, waiting to see if it's a tap or a hold
var _pressed_for := 0.0          # seconds E has been held on it
# Where each item lived and its collision settings before we took it, so we
# can restore them on release. Keyed by the item itself.
var _saved := {}


func _ready() -> void:
	add_to_group("persist")  # saved by save/save_game.gd, after the Inventory (tree order)


## What's in each hand. The bag itself is saved by inventory.gd.
func save_state() -> Dictionary:
	return {
		"equipped": _inventory.equipped.resource_path if _inventory.equipped else "",
		"carrying": _held.data.resource_path if _held and _held.data else "",
	}


func load_state(state: Dictionary) -> void:
	var equipped_path: String = state.get("equipped", "")
	if equipped_path:
		var data := SaveGame._item_data(equipped_path)
		if data and _inventory.count_of(data) > 0:
			equip(data)
	var carrying_path: String = state.get("carrying", "")
	if carrying_path:
		var data := SaveGame._item_data(carrying_path)
		if data:
			var item := data.spawn()
			_player.get_parent().add_child(item)
			item.global_position = _model.carry_socket.global_position
			_take(item)


func _physics_process(delta: float) -> void:
	var hit := _find_target()
	# `as` converts to the given type, or gives null if it isn't one.
	_target = hit as Item
	_npc = hit as Npc
	if _held:
		_target = null  # hands full: E means "drop"
		_place_carried()
	if _equipped:
		_place_equipped()
	_update_press(delta)
	if _talking_to and _talking_to.global_position.distance_to(_player.global_position) > talk_range:
		_hud.hide_line()
		_talking_to = null
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or _player.locked:
		return
	if _npc and _npc.dialogue_file != "":
		_dialogue.start(_npc)  # a conversation with choices
	elif _npc:
		_talking_to = _npc
		_hud.show_line(_npc.display_name, _npc.talk())
	elif _held:
		_drop_carried()
	elif _target:
		# Tap or hold? We find out in _update_press, once E is released or
		# has been down for hold_time.
		_pressed_on = _target
		_pressed_for = 0.0


## The weapon/tool in the weapon hand, or null. Used by combat.gd.
func get_equipped() -> Equipable:
	return _equipped


# --- Used by the inventory screen ------------------------------------------------

## Put a copy of a weapon from the bag into the weapon hand.
func equip(data: ItemData) -> void:
	unequip()
	var item := data.spawn() as Equipable
	if item == null:
		return
	_player.get_parent().add_child(item)  # the world root (main.tscn)
	_grab(item, _model.weapon_socket)
	_equipped = item
	_model.equipped = true
	_place_equipped()
	_inventory.equipped = data
	_inventory.changed.emit()


## Empty the weapon hand. The weapon stays in the bag.
func unequip() -> void:
	if _equipped == null:
		return
	_saved.erase(_equipped)
	_equipped.queue_free()  # just the copy in the hand
	_equipped = null
	_model.equipped = false
	_inventory.equipped = null
	_inventory.changed.emit()


## Take one of an item out of the bag into the right hand, as if you'd held
## E on it (the quick-select wheel uses this for non-weapons).
func hold(data: ItemData) -> void:
	if _held:
		_drop_carried()
	if _inventory.remove(data, 1) == 0:
		return
	var item := data.spawn()
	_player.get_parent().add_child(item)
	item.global_position = _model.carry_socket.global_position
	_take(item)


## Take one of an item out of the bag and toss it on the ground in front.
func drop(data: ItemData) -> void:
	if _inventory.equipped == data and _inventory.count_of(data) == 1:
		unequip()  # dropping the last one: it leaves the hand too
	if _inventory.remove(data, 1) == 0:
		return
	var item := data.spawn()
	_player.get_parent().add_child(item)  # the world root (main.tscn)
	var forward := -_model.global_basis.z
	item.global_position = _player.global_position + forward * 0.7 + Vector3.UP * 1.2
	_toss(item)


# --- Tap / hold ---------------------------------------------------------------------

func _update_press(delta: float) -> void:
	if _pressed_on == null:
		return
	if not is_instance_valid(_pressed_on) or _pressed_on != _target:
		_pressed_on = null  # looked away (or it vanished) before deciding
		return
	if Input.is_action_pressed("interact"):
		_pressed_for += delta
		if _pressed_for >= hold_time:
			var item := _pressed_on
			_pressed_on = null
			_hold_action(item)
	else:
		var item := _pressed_on  # released before hold_time: a tap
		_pressed_on = null
		_stash(item)


## Tap: into the bag, gone from the world.
func _stash(item: Item) -> void:
	if item.data == null:
		_take(item)  # nothing to store it as: just carry it
		return
	var data := item.data
	_inventory.add(data, item.amount)
	item.queue_free()
	var note := ("%s added" if item.amount == 1 else "%s x%d added" % ["%s", item.amount]) % item.get_display_name()
	if item is Equipable:
		if data not in _inventory.favourites and _inventory.toggle_favourite(data):
			note += " to the wheel"
		if _equipped == null:
			equip(data)
			note += ", equipped"
	_hud.show_note(note)


## Hold: weapons go in the bag and into the hand; anything else is carried.
func _hold_action(item: Item) -> void:
	if item is Equipable and item.data:
		var data := item.data
		_stash(item)
		if _inventory.equipped != data:
			equip(data)  # _stash only equips if the hand was empty
	else:
		_take(item)


# --- Hands ----------------------------------------------------------------------------

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


func _drop_carried() -> void:
	var item := _held
	_held = null
	_model.holding = false
	var saved: Array = _saved[item]
	_saved.erase(item)
	# reparent() keeps the global transform by default, so it lets go exactly
	# where the hand was.
	item.reparent(saved[0])
	item.collision_layer = saved[1]
	item.collision_mask = saved[2]
	_toss(item)


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


## Hand an item back to physics: the player's momentum plus a gentle toss
## forward and up.
func _toss(item: Item) -> void:
	item.freeze = false
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
	if _player.locked:
		_hud.hide_prompt()
	elif _npc:
		_hud.show_prompt("Talk", _npc.display_name, false)
	elif _target:
		var hold := "equip" if _target is Equipable else "carry"
		_hud.show_prompt("Take", _target.get_display_name(), false, "hold: " + hold)
	elif _held:
		_hud.show_prompt("Drop", _held.get_display_name(), true)
	else:
		_hud.hide_prompt()
	_hud.set_crosshair(_rig.first_person, _target != null or _npc != null)
