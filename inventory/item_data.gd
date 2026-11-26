class_name ItemData
extends Resource
## What an item IS, as opposed to one particular copy lying in the world.
##
## A Resource is a plain data object that Godot can save as a file (.tres) and
## edit in the Inspector, like a typed config record. Every apple in the game
## points at the same apple.tres; the inventory stores "Apple x3" as this
## resource plus a count, not three nodes.
##
## Each item's data lives next to its scene: props/items/apple.tres beside
## props/items/apple.tscn. The scene's Item node has `data` set to it.

enum Category { WEAPONS, MATERIALS, FOOD, MISC }

@export var display_name := "Item"
@export var category := Category.MISC
@export var weight := 0.5      # kilograms, counted against the player's carry limit
@export_multiline var description := ""
## Hit points eating one restores (food); 0 = can't be eaten.
@export var heal := 0
## The scene to spawn when this is dropped, equipped or previewed. A file path
## rather than a PackedScene reference, because the scene also refers back to
## this resource and Godot can't load two resources that point at each other.
@export_file("*.tscn") var scene_path := ""


## Display names for Category, in order (for the inventory screen's tabs).
const CATEGORY_NAMES := ["Weapons", "Materials", "Food", "Misc"]


func spawn() -> Item:
	return load(scene_path).instantiate()


## True for things that go in the weapon hand (axe, sword).
func is_equipable() -> bool:
	return category == Category.WEAPONS
