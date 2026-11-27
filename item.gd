class_name Item
extends RigidBody3D
## Something the player can pick up, carry, drop or put in the bag.
##
## A RigidBody3D is moved by the physics engine: gravity, collisions and
## tipping over all happen on their own. (Compare CharacterBody3D, which only
## moves when our code says so, and StaticBody3D, which never moves.)
##
## `class_name Item` registers this script as a global type, so other code can
## write `if body is Item:` or declare `var held: Item`.

## What this is (name, weight, category): shared by every copy of the item,
## and what the inventory stores. See inventory/item_data.gd.
@export var data: ItemData
@export var display_name := "Item"  # fallback name for items without data
## How many of `data` picking this up gives (a pair of mushrooms is worth 2).
@export var amount := 1

## The player took this (into the bag or into their hand). Lets the world
## react to a pickup, e.g. places/spirit_ambush.gd.
signal taken


func _ready() -> void:
	# Groups are tags. Later, the pickup code can find all items with
	# get_tree().get_nodes_in_group("items"), or check is_in_group("items").
	add_to_group("items")
	# Also tag it with collision layer 2 ("items") so combat.gd can find items
	# without wading through everything else. It stays on layer 1 too, so it
	# still collides with the world like before.
	set_collision_layer_value(2, true)


## The name to show: from the data if there is any.
func get_display_name() -> String:
	return data.display_name if data else display_name
