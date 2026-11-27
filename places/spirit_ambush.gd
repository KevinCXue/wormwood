extends Marker3D
## The forest spirit's ambush outside the mushroom cave. Put this marker
## where the spirit should rise (a child of places/mushroom_cave.tscn's
## instance in village.tscn, just outside the entrance). The first time the
## player takes any of the cave's mushrooms (an Item sibling of this node),
## a forest spirit (enemies/forest_spirit.tscn) climbs out of the ground
## here and comes for them.
##
## It happens once per game: `triggered` and `defeated` are saved. Load a
## save where the spirit was still about and it rises again.

@export var spirit_scene: PackedScene = preload("res://enemies/forest_spirit.tscn")
## Shown on screen when it rises, so the player turns round.
@export var warning := "Something stirs at the mouth of the cave..."

var triggered := false
var defeated := false
var _spirit: Node3D = null


func _ready() -> void:
	add_to_group("persist")
	add_to_group("spirit_ambush")  # for the console's `spirit reset`
	for item in get_parent().get_children():
		if item is Item:
			item.taken.connect(_on_mushroom_taken)


func _on_mushroom_taken() -> void:
	if triggered:
		return
	triggered = true
	spawn()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.get_node("HUD").show_note(warning, 4.0)


## Raise the spirit here (unless one is already about).
func spawn() -> void:
	if _spirit and is_instance_valid(_spirit):
		return
	_spirit = spirit_scene.instantiate()
	_spirit.home = global_position
	# top_level: its position is in world space, whatever its parent; set
	# before adding so its _ready() settles it onto the ground from there.
	_spirit.position = global_position
	add_child(_spirit)
	_spirit.died.connect(func(): defeated = true)


## As if it never happened (console).
func reset() -> void:
	triggered = false
	defeated = false
	if _spirit and is_instance_valid(_spirit):
		_spirit.queue_free()
	_spirit = null


func save_state() -> Dictionary:
	return {"triggered": triggered, "defeated": defeated}


func load_state(state: Dictionary) -> void:
	triggered = state.get("triggered", false)
	defeated = state.get("defeated", false)
	if triggered and not defeated:
		spawn()
