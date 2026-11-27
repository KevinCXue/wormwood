extends CanvasLayer
## Developer console: press ` (backtick, left of 1) to type commands that
## change the game state, for testing (reset a quest, give items, teleport,
## set the time...). Type `help` for the list. Documented for humans in
## docs/console.md.
##
## An autoload scene (Project Settings > Globals), so it's there in every
## scene. It only exists in development runs (the editor, or `godot --path
## .`): OS.is_debug_build() is false in a release export, and then it removes
## itself.
##
## While open, the game is paused and the mouse is free; closing it puts
## both back as they were. Enter runs a command, Up/Down step through earlier
## ones, Tab completes command names and their arguments.
##
## Adding a command: add an entry to the table in _ready() (name -> [method,
## usage, description]) and a method taking `args: PackedStringArray`, and
## list it in docs/console.md. Methods print with _say()/_error().

const ITEM_DIR := "res://props/items/"

@onready var _output: RichTextLabel = $Root/Panel/VBox/Output
@onready var _input_line: LineEdit = $Root/Panel/VBox/Input

var _commands := {}           # name -> [Callable, usage, description]
var _history: PackedStringArray = []
var _history_at := 0
var _was_paused := false
var _was_mouse := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()  # no console in release builds
		return
	visible = false
	_commands = {
		"help": [_help, "help [command]", "List the commands, or explain one."],
		"quest": [_quest, "quest [list | start ID | stage ID N | complete ID | reset ID]",
			"Show quests and their state, or change one. reset = as if never started."],
		"give": [_give, "give ITEM [COUNT]", "Put items in your bag (item names: see `items`)."],
		"take": [_take, "take ITEM [COUNT]", "Remove items from your bag."],
		"items": [_items, "items", "List every item name, and what's in your bag."],
		"gold": [_gold, "gold AMOUNT", "Add gold (negative to take some away)."],
		"tp": [_tp, "tp PLACE | tp VILLAGER | tp X Y Z", "Teleport. `tp` alone lists the places."],
		"time": [_time, "time HH[:MM]", "Set the time of day (24-hour clock)."],
		"heal": [_heal, "heal [AMOUNT]", "Restore your health (all of it, without an amount)."],
		"hurt": [_hurt, "hurt AMOUNT", "Damage yourself (to test the health bar or dying)."],
		"god": [_god, "god", "Toggle invulnerability."],
		"kill": [_kill, "kill VILLAGER", "Kill a villager (their quests fail)."],
		"spirit": [_spirit, "spirit [kill | reset]",
			"Raise a forest spirit 8 m in front of you. kill = destroy every spirit; reset = undo the cave ambush so it can happen again."],
		"save": [_save, "save", "Save the game (like F5)."],
		"load": [_load, "load", "Load the newest save."],
		"newgame": [_newgame, "newgame", "Start a new game. Saves are kept."],
		"clear": [_clear, "clear", "Clear this window."],
	}
	_input_line.text_submitted.connect(_run)
	_say("Developer console. Type [b]help[/b] for commands. ` or Esc closes it.")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key: Key = event.physical_keycode
	if key == KEY_QUOTELEFT and not event.echo:
		if visible:
			_close()
		else:
			_open()
	elif not visible:
		return
	elif key == KEY_ESCAPE:
		_close()
	elif key == KEY_UP or key == KEY_DOWN:
		_browse_history(-1 if key == KEY_UP else 1)
	elif key == KEY_TAB:
		_complete()
	else:
		return  # typing: let the text box have it
	get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	_was_paused = get_tree().paused
	_was_mouse = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_input_line.clear()
	_input_line.grab_focus()


func _close() -> void:
	visible = false
	_input_line.release_focus()
	get_tree().paused = _was_paused
	Input.mouse_mode = _was_mouse


func _run(line: String) -> void:
	_input_line.clear()
	line = line.strip_edges()
	if line == "":
		return
	_history.append(line)
	_history_at = _history.size()
	_say("[color=#d9c28a]> %s[/color]" % line)
	var words := line.split(" ", false)
	var command := words[0].to_lower()
	if not _commands.has(command):
		_error("unknown command \"%s\". Try help." % command)
		return
	words.remove_at(0)
	_commands[command][0].call(words)


# --- Commands ---------------------------------------------------------------------

func _help(args: PackedStringArray) -> void:
	if args.size() > 0 and _commands.has(args[0]):
		var c: Array = _commands[args[0]]
		_say("[b]%s[/b]\n  %s" % [c[1], c[2]])
		return
	for command in _commands:
		_say("[b]%s[/b]  %s" % [_commands[command][1], _commands[command][2]])


func _quest(args: PackedStringArray) -> void:
	var quest_log := _player_node("QuestLog")
	if quest_log == null:
		return
	var action := args[0] if args.size() > 0 else "list"
	if action == "list":
		for id in quest_log.all_ids():
			var state := "not started"
			if quest_log.is_done(id):
				state = "done"
			elif quest_log.is_active(id):
				state = "active, stage %d%s" % [quest_log.stage(id), ", ready to hand in" if quest_log.is_ready(id) else ""]
			_say("%s  (%s): %s" % [id, quest_log.quest(id).title, state])
		return
	if args.size() < 2 or not id_known(quest_log, args[1]):
		_error("usage: " + _commands.quest[1])
		return
	var id := args[1]
	match action:
		"start": quest_log.start(id)
		"complete": quest_log.complete(id)
		"reset": quest_log.reset(id)
		"stage":
			if args.size() < 3:
				_error("usage: quest stage ID N")
				return
			if not quest_log.is_active(id):
				quest_log.start(id)
			quest_log.set_stage(id, int(args[2]))
		_:
			_error("usage: " + _commands.quest[1])
			return
	_say("%s is now %s." % [id, "done" if quest_log.is_done(id) else ("active" if quest_log.is_active(id) else "not started")])


func id_known(quest_log: Node, id: String) -> bool:
	if id in quest_log.all_ids():
		return true
	_error("no quest \"%s\". `quest list` shows them." % id)
	return false


func _give(args: PackedStringArray) -> void:
	var data := _item(args)
	var bag := _player_node("Inventory")
	if data and bag:
		var n := int(args[1]) if args.size() > 1 else 1
		bag.add(data, n)
		_say("Gave %d %s." % [n, data.display_name])


func _take(args: PackedStringArray) -> void:
	var data := _item(args)
	var bag := _player_node("Inventory")
	if data and bag:
		var n: int = bag.remove(data, int(args[1]) if args.size() > 1 else 1)
		_say("Took %d %s." % [n, data.display_name])


func _items(_args: PackedStringArray) -> void:
	_say("Items: " + ", ".join(_item_names()))
	var bag := _player_node("Inventory")
	if bag:
		var held: Array = bag.stacks().map(func(s): return "%s x%d" % [s[0].resource_path.get_file().get_basename(), s[1]])
		_say("In your bag: " + (", ".join(held) if not held.is_empty() else "nothing") + ". Gold: %d." % bag.gold)


func _gold(args: PackedStringArray) -> void:
	var bag := _player_node("Inventory")
	if bag == null:
		return
	if args.is_empty() or not args[0].is_valid_int():
		_error("usage: gold AMOUNT")
		return
	bag.add_gold(int(args[0]))
	_say("Gold: %d." % bag.gold)


func _tp(args: PackedStringArray) -> void:
	var world := SaveGame.world()
	var player := _player()
	if world == null or player == null:
		return
	var places := _places(world)
	if args.is_empty():
		_say("Places: " + ", ".join(places.keys()))
		return
	var target: Variant = null   # [where to stand, what to look at]
	if args.size() >= 3 and args[0].is_valid_float():
		var at := Vector3(float(args[0]), float(args[1]), float(args[2]))
		target = [at, at + Vector3.FORWARD]
	else:
		target = places.get(args[0].to_lower())
	if target == null:
		_error("unknown place \"%s\". `tp` alone lists them." % args[0])
		return
	_teleport(player, target[0], target[1])
	_say("Teleported to %s." % " ".join(args))


func _time(args: PackedStringArray) -> void:
	var clock := SaveGame.world().find_child("DayNight", true, false) if SaveGame.world() else null
	if clock == null or args.is_empty():
		_error("usage: time HH[:MM]")
		return
	var parts := args[0].split(":")
	var hours := float(parts[0]) + (float(parts[1]) / 60.0 if parts.size() > 1 else 0.0)
	clock.time_of_day = fposmod(hours, 24.0)
	_say("Time: %s." % args[0])


func _heal(args: PackedStringArray) -> void:
	var h: Health = _player_node("Health")
	if h:
		h.heal(int(args[0]) if args.size() > 0 else h.max_health)
		_say("Health: %d / %d." % [h.health, h.max_health])


func _hurt(args: PackedStringArray) -> void:
	var h: Health = _player_node("Health")
	if h and args.size() > 0 and args[0].is_valid_int():
		h.damage(int(args[0]))
		_say("Health: %d / %d." % [h.health, h.max_health])
	else:
		_error("usage: hurt AMOUNT")


func _god(_args: PackedStringArray) -> void:
	var h: Health = _player_node("Health")
	if h:
		h.invulnerable = not h.invulnerable
		_say("God mode %s." % ("on" if h.invulnerable else "off"))


func _kill(args: PackedStringArray) -> void:
	if args.is_empty():
		_error("usage: kill VILLAGER")
		return
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.display_name.to_lower() == args[0].to_lower():
			npc.health.damage(npc.health.health)
			_say("%s is dead." % npc.display_name)
			return
	_error("no villager called \"%s\"." % args[0])


func _spirit(args: PackedStringArray) -> void:
	var what := args[0].to_lower() if args.size() > 0 else ""
	match what:
		"":
			var player := _player()
			if player == null:
				return
			var spirit: Node3D = load("res://enemies/forest_spirit.tscn").instantiate()
			var forward: Vector3 = -player.get_node("CameraRig").global_basis.z
			forward.y = 0.0
			var at: Vector3 = player.global_position + forward.normalized() * 8.0
			spirit.home = at
			spirit.position = at  # top_level, so this is world space
			SaveGame.world().add_child(spirit)
			_say("A forest spirit rises. (Close the console to face it.)")
		"kill":
			var spirits := get_tree().get_nodes_in_group("spirits")
			for s in spirits:
				if not s.is_dead():
					s.health.damage(s.health.health)
			_say("%d spirit(s) destroyed." % spirits.size())
		"reset":
			for a in get_tree().get_nodes_in_group("spirit_ambush"):
				a.reset()
			_say("Cave ambush reset: taking a cave mushroom raises the spirit again.")
		_:
			_error("usage: spirit [kill | reset]")


func _save(_args: PackedStringArray) -> void:
	var path := SaveGame.save("manual")
	_say("Saved to %s." % path if path else "Nothing to save here.")


func _load(_args: PackedStringArray) -> void:
	var saves := SaveGame.list_saves()
	if saves.is_empty():
		_error("no saves yet.")
		return
	_close()
	SaveGame.load_save(saves[0].path)


func _newgame(_args: PackedStringArray) -> void:
	_close()
	SaveGame.new_game()


func _clear(_args: PackedStringArray) -> void:
	_output.clear()


# --- Helpers ----------------------------------------------------------------------

func _player() -> Node3D:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		_error("no player here.")
	return player


func _player_node(child: String) -> Node:
	var player := _player()
	return player.get_node_or_null(child) if player else null


## args[0] as an item, e.g. "mushroom" -> props/items/mushroom.tres.
func _item(args: PackedStringArray) -> ItemData:
	if args.is_empty():
		_error("which item? `items` lists them.")
		return null
	var path := ITEM_DIR + args[0] + ".tres"
	if not ResourceLoader.exists(path):
		_error("no item \"%s\". `items` lists them." % args[0])
		return null
	return load(path)


func _item_names() -> Array:
	var names := []
	for file_name in DirAccess.get_files_at(ITEM_DIR):
		file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			names.append(file_name.get_basename())
	return names


## Named places: name -> [where to stand, what to face]. Villagers are added
## by name: you appear in front of them, facing them.
func _places(world: Node) -> Dictionary:
	var places := {"spawn": [Vector3.ZERO, Vector3(0, 1.5, 10)]}
	var spots := {  # node name -> [stand at, look at], in the node's own space (+Z = its front)
		"House": ["house", Vector3(0, 0, 7), Vector3(0, 1.5, 0)],
		"MushroomCave": ["cave", Vector3(0, 0, 15), Vector3(0, 1.5, 0)],
		"Church": ["church", Vector3(0, 0, 14), Vector3(0, 3, 0)],
		"TownHall": ["townhall", Vector3(0, 0, 10), Vector3(0, 2, 0)],
		"TownSquare": ["square", Vector3(0, 0, 0), Vector3(0, 1.5, -8)],
		"Market": ["market", Vector3(0, 0, 0), Vector3(0, 1.5, -6)],
	}
	for node_name in spots:
		var node := world.find_child(node_name, true, false) as Node3D
		if node:
			var spot: Array = spots[node_name]
			places[spot[0]] = [node.global_transform * spot[1], node.global_transform * spot[2]]
	for npc in get_tree().get_nodes_in_group("npcs"):
		var front: Vector3 = npc.get_node("Model").global_basis * Vector3.FORWARD
		places[npc.display_name.to_lower()] = [npc.global_position + front * 1.8,
			npc.global_position + Vector3.UP * 1.5]
	return places


func _teleport(player: Node3D, at: Vector3, look_at: Vector3) -> void:
	# Stand on whatever is below (or above, if `at` is underground).
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		at.y = hit.position.y
	player.global_position = at + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	var to := look_at - at
	var rig: Node3D = player.get_node("CameraRig")
	rig.rotation.y = atan2(-to.x, -to.z)  # the yaw at which forward (-Z) points at it
	player.get_node("Model").rotation.y = rig.rotation.y
	rig.global_position = rig._target_position()


func _browse_history(step: int) -> void:
	if _history.is_empty():
		return
	_history_at = clampi(_history_at + step, 0, _history.size())
	_input_line.text = _history[_history_at] if _history_at < _history.size() else ""
	_input_line.caret_column = _input_line.text.length()


## Tab: finish the word being typed, from commands or that command's
## arguments. With several matches, finish what they share and list them.
func _complete() -> void:
	var text := _input_line.text
	var words := text.split(" ", true)
	var options: Array = []
	if words.size() == 1:
		options = _commands.keys()
	else:
		var command := words[0].to_lower()
		var arg := words.size() - 2  # which argument is being typed (0 = first)
		var quest_log := _player_node("QuestLog")
		match command:
			"quest":
				options = ["list", "start", "stage", "complete", "reset"] if arg == 0 \
					else (quest_log.all_ids() if quest_log and arg == 1 else [])
			"give", "take":
				options = _item_names() if arg == 0 else []
			"tp":
				options = _places(SaveGame.world()).keys() if SaveGame.world() and arg == 0 else []
			"help":
				options = _commands.keys() if arg == 0 else []
			"spirit":
				options = ["kill", "reset"] if arg == 0 else []
			"kill":
				options = get_tree().get_nodes_in_group("npcs").map(func(n): return n.display_name.to_lower()) if arg == 0 else []
	var partial: String = words[-1]
	var matches := options.filter(func(o): return String(o).begins_with(partial))
	if matches.is_empty():
		return
	var common: String = matches[0]
	for m in matches:
		while not String(m).begins_with(common):
			common = common.left(-1)
	words[-1] = common + (" " if matches.size() == 1 else "")
	_input_line.text = " ".join(words)
	_input_line.caret_column = _input_line.text.length()
	if matches.size() > 1:
		_say("  " + ", ".join(matches))


func _say(text: String) -> void:
	_output.append_text(text + "\n")


func _error(text: String) -> void:
	_say("[color=#e07a6a]%s[/color]" % text)
