extends Node
## Saving and loading the game. An autoload, available everywhere as
## `SaveGame` (like `Settings`), so it survives the world being reloaded.
##
## Saves are JSON files in user://saves (on the Mac:
## ~/Library/Application Support/Wormwood/saves), each with a small JPG
## thumbnail beside it. JSON rather than Godot resource files because it's
## readable when something goes wrong, and because loading a resource file can
## run code from it, which a save file should never be able to do.
##
## Two kinds of save:
##   manual  F5 (main.gd). A new file every time; past MAX_SAVES the oldest goes.
##   auto    every AUTOSAVE_MINUTES of play and when quitting, in MAX_AUTOSAVES
##           rotating files, so they never push out your own saves.
## Starting the game loads the newest save of either kind (unless run with
## `-- --new-game`).
##
## What gets saved:
##   - every node in the "persist" group that has save_state() -> Dictionary
##     and load_state(state: Dictionary): the player, the clock, the bag, the
##     hands, the trees. Duck typing, like on_hit(): to make something new
##     saveable, add it to the group and give it those two methods. Keyed by
##     its path from the world root, e.g. "TestGrove/Tree1".
##   - every Item in the world: where it is, or that it's gone. Items placed
##     in a scene are identified by their path ("VillageProps/Plate2"); ones
##     created while playing (dropped, logs from trees) are re-created from
##     their ItemData. Renaming a node in the editor makes old saves forget it
##     (it goes back to where it was placed); that's accepted for now.
##
## Loading reloads the world from scratch and then applies the save, so
## nothing from before the load can linger. The state waits here, in
## _pending, while the scene reloads; main.gd calls world_ready() when the new
## world is up. F2 (blocky/detailed swap) uses the same trick to keep your
## progress through its reload.

const VERSION := 1             # bump when the format changes; old saves can then be upgraded
const MAX_SAVES := 50
const MAX_AUTOSAVES := 3
const AUTOSAVE_MINUTES := 5.0  # of play (the timer stops while a menu has the game paused)
const ITEM_DATA_DIR := "res://props/items/"

var save_dir := "user://saves"  # tests point this elsewhere: -- --save-dir=user://test_saves

var _world: Node = null
var _pending := {}         # a save waiting for the world to finish (re)loading
var _first_world := true   # the first world of this run loads the latest save
var _autosave_left := AUTOSAVE_MINUTES * 60.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-dir="):
			save_dir = arg.trim_prefix("--save-dir=")


## main.gd calls this from its _ready(): the world exists and can be saved,
## or has a save to restore.
func world_ready(world: Node) -> void:
	_world = world
	_autosave_left = AUTOSAVE_MINUTES * 60.0
	var state := _pending
	_pending = {}
	# Only a real start of the game continues: tool and test scripts run with
	# `-s`, which gives the SceneTree itself a script.
	var real_game: bool = get_tree().get_script() == null
	if state.is_empty() and _first_world and real_game \
			and not "--new-game" in OS.get_cmdline_user_args():
		var saves := list_saves()
		if not saves.is_empty():
			print("continuing from ", saves[0].path)
			state = read_save(saves[0].path)
	_first_world = false
	if not state.is_empty():
		_apply(state)


func _process(delta: float) -> void:
	# Autoloads pause with the tree, so menus stop this clock.
	if _world == null or not is_instance_valid(_world):
		return
	_autosave_left -= delta / maxf(Engine.time_scale, 0.01)  # real seconds, even under the wheel's slow motion
	if _autosave_left <= 0.0:
		save("auto")


func _notification(what: int) -> void:
	# Closing the window: autosave on the way out.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _world and is_instance_valid(_world):
		save("auto")


# --- Saving ----------------------------------------------------------------------------

## Write a new save of `kind` ("manual" or "auto"). Returns its path, or "".
func save(kind := "manual") -> String:
	if _world == null or not is_instance_valid(_world):
		return ""
	_autosave_left = AUTOSAVE_MINUTES * 60.0
	var state := capture(_world)
	state["kind"] = kind
	state["created"] = Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(save_dir)
	var base := "%s/%s_%d" % [save_dir, kind, int(state.created * 1000.0)]
	var file := FileAccess.open(base + ".json", FileAccess.WRITE)
	if file == null:
		push_error("could not write save %s: %s" % [base, error_string(FileAccess.get_open_error())])
		return ""
	# sort_keys = false keeps the order things were captured in (tree order).
	file.store_string(JSON.stringify(state, "\t", false))
	file.close()
	_save_thumbnail(base + ".jpg")
	_prune(kind, MAX_AUTOSAVES if kind == "auto" else MAX_SAVES)
	var hud := _world.get_node_or_null("Player/HUD")
	if hud:
		hud.show_note("Autosaved" if kind == "auto" else "Game saved")
	return base + ".json"


## Everything worth saving about `world`, as plain data (no Godot objects).
func capture(world: Node) -> Dictionary:
	var nodes := {}
	for node in get_tree().get_nodes_in_group("persist"):
		if world.is_ancestor_of(node) and node.has_method("save_state"):
			nodes[str(world.get_path_to(node))] = node.save_state()
	var items := []
	for item in _world_items(world):
		items.append({
			# Placed in a scene (has an owner): remembered by path. Made while
			# playing: "" = spawn a new one from its data.
			"id": str(world.get_path_to(item)) if item.owner else "",
			"data": item.data.resource_path,
			"transform": transform_to_array(item.global_transform),
		})
	var clock := world.find_child("DayNight", true, false)
	return {
		"version": VERSION,
		"game_time": clock.time_of_day if clock else 0.0,
		"nodes": nodes,
		"items": items,
	}


## Keep a copy of the current state in memory to restore after a reload
## (F2's blocky/detailed swap).
func carry_over() -> void:
	if _world and is_instance_valid(_world):
		_pending = capture(_world)


func _save_thumbnail(path: String) -> void:
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture else null
	if image == null or image.is_empty():
		return  # headless runs have nothing to show
	image.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	image.save_jpg(path, 0.8)


## Delete the oldest saves of `kind` beyond `keep`.
func _prune(kind: String, keep: int) -> void:
	var saves := list_saves().filter(func(s): return s.kind == kind)
	for i in range(keep, saves.size()):
		delete_save(saves[i].path)


# --- Loading ----------------------------------------------------------------------------

## All saves, newest first: [{path, kind, created, game_time, thumbnail}, ...].
func list_saves() -> Array:
	var saves := []
	if not DirAccess.dir_exists_absolute(save_dir):
		return saves  # nothing saved yet
	for file_name in DirAccess.get_files_at(save_dir):
		if not file_name.ends_with(".json"):
			continue
		var path := save_dir.path_join(file_name)
		var state := read_save(path)
		if state.is_empty():
			continue
		saves.append({
			"path": path,
			"kind": state.get("kind", "manual"),
			"created": float(state.get("created", 0.0)),
			"game_time": float(state.get("game_time", 0.0)),
			"thumbnail": path.get_basename() + ".jpg",
		})
	saves.sort_custom(func(a, b): return a.created > b.created)
	return saves


## The save's contents, or {} if it's missing, broken or from a newer game.
func read_save(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var state = JSON.parse_string(text) if text else null
	if not state is Dictionary or not state.has("version"):
		push_warning("ignoring unreadable save " + path)
		return {}
	if int(state.version) > VERSION:
		push_warning("save %s is from a newer version of the game" % path)
		return {}
	return state


## Start a new game: reload the world without restoring any save. Existing
## saves are kept (they're still in the F9 list).
func new_game() -> void:
	_pending = {}
	_first_world = false  # so world_ready() doesn't continue from the latest
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


## The current world (main.tscn's root), or null. Used by the console.
func world() -> Node:
	return _world if _world and is_instance_valid(_world) else null


## Reload the world and restore `path` into it.
func load_save(path: String) -> void:
	var state := read_save(path)
	if state.is_empty():
		return
	_pending = state
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func delete_save(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_basename() + ".jpg")


func _apply(state: Dictionary) -> void:
	# Let the world settle for a couple of physics frames first: the player's
	# body is built on its first frame, and equipping needs its hands.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _world
	if world == null or not is_instance_valid(world):
		return
	_apply_items(world, state.get("items", []))
	var nodes: Dictionary = state.get("nodes", {})
	# Tree order (not file order): the bag is restored before the hands.
	for node in get_tree().get_nodes_in_group("persist"):
		var key := str(world.get_path_to(node))
		if nodes.has(key) and node.has_method("load_state"):
			node.load_state(nodes[key])


func _apply_items(world: Node, saved: Array) -> void:
	var placed := {}  # id -> entry, for items that were placed in a scene
	for entry in saved:
		if entry.id != "":
			placed[entry.id] = entry
	for item in _world_items(world):
		if item.owner == null:
			continue  # only scene-placed items are matched by path
		var id := str(world.get_path_to(item))
		if placed.has(id):
			_put(item, placed[id].transform)
		else:
			item.queue_free()  # taken (or carried) when the game was saved
	for entry in saved:
		if entry.id == "":
			var data := _item_data(entry.data)
			if data:
				var item := data.spawn()
				world.add_child(item)
				_put(item, entry.transform)


func _put(item: Item, transform_array: Array) -> void:
	item.global_transform = array_to_transform(transform_array)
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO


## Only load item data from the items folder: a save file names it, and a
## save shouldn't be able to make the game load anything else.
func _item_data(path: String) -> ItemData:
	if not (path.begins_with(ITEM_DATA_DIR) and path.ends_with(".tres") and ResourceLoader.exists(path)):
		push_warning("save refers to unknown item " + path)
		return null
	return load(path) as ItemData


## Items lying in the world: not in the player's hands or menus.
func _world_items(world: Node) -> Array:
	var player := world.get_node_or_null("Player")
	var result := []
	for item in get_tree().get_nodes_in_group("items"):
		if world.is_ancestor_of(item) and not (player and player.is_ancestor_of(item)) \
				and not item.is_queued_for_deletion() and item.data:
			result.append(item)
	return result


# --- Helpers for save_state()/load_state() ----------------------------------------------

## JSON has no vectors or transforms, so they're stored as lists of numbers.
static func transform_to_array(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func array_to_transform(a: Array) -> Transform3D:
	return Transform3D(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]),
		Vector3(a[6], a[7], a[8]), Vector3(a[9], a[10], a[11]))


static func vector_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vector(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
