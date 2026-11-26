extends Node
## The player's bag: stacks of items, gold, and a weight limit. A child of
## Player. Pure data: it doesn't spawn or show anything. interactor.gd puts
## things in and takes them out of the world; ui/inventory_menu.gd shows it.
##
## Every identical item stacks ("Pine Log x7", "Iron Sword x2"): the bag is a
## list of [ItemData, count]. Gold is a plain counter, weightless, outside
## the stacks.
##
## Other nodes react to changes through the `changed` signal (Godot's
## observer pattern: connect a function to it and it's called on emit).

signal changed

@export var carry_limit := 60.0  # kilograms; above this the player is slowed and can't run

var gold := 0
var equipped: ItemData = null   # what's in the weapon hand (still counted in the bag)
var favourites: Array[ItemData] = []  # the quick-select wheel's slots, in order (ui/quick_wheel.gd)

const MAX_FAVOURITES := 8  # slots on the wheel

var _stacks: Array = []  # of [ItemData, count], in the order they were picked up


func _ready() -> void:
	add_to_group("persist")  # saved by save/save_game.gd


## Items are stored by their data file's path (res://props/items/axe.tres).
## What's in the hands is saved by interactor.gd, restored after this.
func save_state() -> Dictionary:
	return {
		"stacks": _stacks.map(func(s): return [s[0].resource_path, s[1]]),
		"gold": gold,
		"favourites": favourites.map(func(d): return d.resource_path),
	}


func load_state(state: Dictionary) -> void:
	_stacks.clear()
	favourites.clear()
	equipped = null
	for s in state.get("stacks", []):
		var data := _load_data(s[0])
		if data:
			_stacks.append([data, int(s[1])])
	for path in state.get("favourites", []):
		var data := _load_data(path)
		if data and favourites.size() < MAX_FAVOURITES:
			favourites.append(data)
	gold = int(state.get("gold", 0))
	changed.emit()


func _load_data(path: String) -> ItemData:
	return SaveGame._item_data(path)


func add(data: ItemData, count := 1) -> void:
	var stack := _find(data)
	if stack.is_empty():
		_stacks.append([data, count])
	else:
		stack[1] += count
	changed.emit()


## Take up to `count` out of the bag. Returns how many were actually removed.
func remove(data: ItemData, count := 1) -> int:
	var stack := _find(data)
	if stack.is_empty():
		return 0
	var taken := mini(count, stack[1])
	stack[1] -= taken
	if stack[1] == 0:
		_stacks.erase(stack)
		# Favourites stay marked when you run out, so the wheel's slots don't
		# shift around (it shows the slot dimmed until you have one again).
		if equipped == data:
			equipped = null
	changed.emit()
	return taken


func count_of(data: ItemData) -> int:
	var stack := _find(data)
	return 0 if stack.is_empty() else stack[1]


## [[ItemData, count], ...]. Pass a category (ItemData.Category) to filter,
## or -1 for everything. Sorted by name, so the list doesn't jump around.
func stacks(category := -1) -> Array:
	var result := _stacks.filter(func(s): return category == -1 or s[0].category == category)
	result.sort_custom(func(a, b): return a[0].display_name < b[0].display_name)
	return result


func total_weight() -> float:
	var total := 0.0
	for s in _stacks:
		total += s[0].weight * s[1]
	return total


func is_overloaded() -> bool:
	return total_weight() > carry_limit


## Mark or unmark an item for the wheel. Returns false if the wheel is full.
func toggle_favourite(data: ItemData) -> bool:
	if data in favourites:
		favourites.erase(data)
	elif favourites.size() >= MAX_FAVOURITES:
		return false
	else:
		favourites.append(data)
	changed.emit()
	return true


func add_gold(amount: int) -> void:
	gold += amount
	changed.emit()


func _find(data: ItemData) -> Array:
	for s in _stacks:
		if s[0] == data:
			return s
	return []
