extends Node
## The player's quests: which are under way, at what stage, and which are
## done. A child of Player. Dialogue scripts change it (start_quest,
## set_stage, complete_quest); the journal (ui/journal.gd) and the villagers'
## markers (npcs/quest_marker.gd) read it.
##
## Quest definitions are the QuestData files in res://quests/, loaded once by
## id (file name). The progress is saved with the game (the "persist" group).

signal changed

const QUEST_DIR := "res://quests/"

var _quests := {}  # id -> QuestData, every quest in the game
var _state := {}   # id -> {"stage", "done", "order", and "failed" if it failed}, quests you've started
var _started := 0  # counts up, so the journal can list quests in the order you got them

@onready var _inventory: Node = $"../Inventory"
@onready var _hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	add_to_group("persist")  # saved by save/save_game.gd
	for file_name in DirAccess.get_files_at(QUEST_DIR):
		# Exported games list resources as "name.tres.remap"; strip that.
		file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var quest: QuestData = load(QUEST_DIR + file_name)
			_quests[quest.id()] = quest


## Every quest id in the game (for the console's tab completion).
func all_ids() -> Array:
	return _quests.keys()


## Forget a quest entirely, as if never started (console: quest reset).
func reset(id: String) -> void:
	if _state.erase(id):
		changed.emit()


func quest(id: String) -> QuestData:
	if not _quests.has(id):
		push_warning("unknown quest: " + id)
	return _quests.get(id)


func is_started(id: String) -> bool:
	return _state.has(id)


func is_active(id: String) -> bool:
	return _state.has(id) and not _state[id].done


func is_done(id: String) -> bool:
	return _state.has(id) and _state[id].done


func stage(id: String) -> int:
	return _state[id].stage if _state.has(id) else -1


## Active and the gathering goal (if any) is met: time to go back to the giver.
func is_ready(id: String) -> bool:
	var q := quest(id)
	return is_active(id) and q != null and q.gather_item != null \
		and _inventory.count_of(q.gather_item) >= q.gather_count


func start(id: String) -> void:
	if is_started(id) or quest(id) == null:
		return
	_started += 1
	_state[id] = {"stage": 0, "done": false, "order": _started}
	_hud.show_banner("NEW QUEST", quest(id).title, "J  open journal")
	changed.emit()


func set_stage(id: String, new_stage: int) -> void:
	if is_active(id):
		_state[id].stage = new_stage
		_hud.show_note("Journal updated: %s" % quest(id).title)
		changed.emit()


func complete(id: String) -> void:
	if not is_started(id):
		start(id)
	if is_done(id):
		return
	_state[id].done = true
	_hud.show_banner("QUEST COMPLETE", quest(id).title)
	changed.emit()


## The quest can't be finished any more (its giver died). Shown under
## Completed, marked as failed. Quests you hadn't started fail too, so the
## journal says why they're gone.
func fail(id: String, because_of := "") -> void:
	if is_done(id) or quest(id) == null:
		return
	var was_started := is_started(id)
	if not was_started:
		_started += 1
		_state[id] = {"stage": 0, "done": false, "order": _started}
	_state[id].done = true
	_state[id].failed = true
	_state[id].why = "%s is dead." % because_of if because_of else ""
	if was_started:
		_hud.show_banner("QUEST FAILED", quest(id).title)
	changed.emit()


func is_failed(id: String) -> bool:
	return _state.has(id) and _state[id].get("failed", false)


## Quests in the order you got them. `done` picks finished or unfinished
## ones; `category` (QuestData.Category) narrows it down, -1 for any.
func quests(done: bool, category := -1) -> Array:
	var ids := _state.keys().filter(func(id): return _state[id].done == done and _quests.has(id) \
		and (category == -1 or _quests[id].category == category))
	ids.sort_custom(func(a, b): return _state[a].order < _state[b].order)
	return ids.map(func(id): return _quests[id])


## The current objective, with gathering progress: "Find five ... (3/5)".
func objective(id: String) -> String:
	var q := quest(id)
	if q == null:
		return ""
	if is_failed(id):
		return "Failed. " + _state[id].get("why", "")
	if is_done(id):
		return q.completed_text
	var s := stage(id)
	var text: String = q.objectives[s] if s >= 0 and s < q.objectives.size() else ""
	if q.gather_item:
		text += "  (%d/%d)" % [mini(_inventory.count_of(q.gather_item), q.gather_count), q.gather_count]
	return text


func save_state() -> Dictionary:
	return {"quests": _state, "started": _started}


func load_state(state: Dictionary) -> void:
	_state.clear()
	var saved: Dictionary = state.get("quests", {})
	for id in saved:
		var entry: Dictionary = saved[id]
		_state[id] = {"stage": int(entry.get("stage", 0)), "done": bool(entry.get("done", false)),
			"order": int(entry.get("order", 0)), "failed": bool(entry.get("failed", false)),
			"why": String(entry.get("why", ""))}
	_started = int(state.get("started", _state.size()))
	changed.emit()
