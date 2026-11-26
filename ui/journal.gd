extends CanvasLayer
## The quest journal (J): main quests, side quests and completed ones on the
## left, the selected quest's details on the right (who gave it, what it's
## about, and what to do next, with gathering progress like "(3/5)"). The
## game is paused while it's open. A child of Player; the quests themselves
## are in quests/quest_log.gd.

@onready var _log: Node = $"../QuestLog"
@onready var _list: Tree = $Root/Panel/VBox/Body/List
@onready var _title: Label = $Root/Panel/VBox/Body/Details/Title
@onready var _giver: Label = $Root/Panel/VBox/Body/Details/Giver
@onready var _summary: Label = $Root/Panel/VBox/Body/Details/Summary
@onready var _objective_heading: Label = $Root/Panel/VBox/Body/Details/ObjectiveHeading
@onready var _objective: Label = $Root/Panel/VBox/Body/Details/Objective

var _selected: QuestData = null


func _ready() -> void:
	visible = false
	_list.item_selected.connect(func():
		var row := _list.get_selected()
		_show(row.get_metadata(0) if row else null))


func _input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("journal") and not get_tree().paused and not get_parent().locked:
			_open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("journal") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_list.grab_focus()


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	_list.clear()
	var root := _list.create_item()
	var first: TreeItem = null
	var keep: TreeItem = null
	var groups := [
		["Main quests", _log.quests(false, QuestData.Category.MAIN), "No main quest yet."],
		["Side quests", _log.quests(false, QuestData.Category.SIDE), "Talk to people around town."],
		["Completed", _log.quests(true), "Nothing finished yet."],
	]
	for group in groups:
		# Section headings are rows too, just not selectable.
		var heading := _list.create_item(root)
		heading.set_text(0, group[0])
		heading.set_selectable(0, false)
		heading.set_custom_color(0, Color(0.93, 0.8, 0.55))
		if group[1].is_empty():
			var empty := _list.create_item(heading)
			empty.set_text(0, group[2])
			empty.set_selectable(0, false)
			empty.set_custom_color(0, Color(0.85, 0.82, 0.75, 0.45))
		for quest: QuestData in group[1]:
			var row := _list.create_item(heading)
			row.set_text(0, quest.title)
			row.set_metadata(0, quest)
			if group[0] == "Completed":
				var failed: bool = _log.is_failed(quest.id())
				row.set_text(0, quest.title + ("   (failed)" if failed else ""))
				row.set_custom_color(0, Color(0.88, 0.5, 0.45, 0.8) if failed else Color(0.85, 0.82, 0.75, 0.6))
			if first == null:
				first = row
			if quest == _selected:
				keep = row
	var pick := keep if keep else first
	if pick:
		pick.select(0)
	else:
		_show(null)


func _show(quest: QuestData) -> void:
	_selected = quest
	var has := quest != null
	_title.text = quest.title if has else "No quests yet"
	_giver.text = ("From %s" % quest.giver if quest.giver else "") if has else ""
	_summary.text = quest.summary if has else "People around town may need a hand. Look for a speech bubble over their heads."
	_objective_heading.visible = has
	_objective_heading.text = ("Failed" if _log.is_failed(quest.id()) else "Done") \
		if has and _log.is_done(quest.id()) else "Objective"
	_objective.text = _log.objective(quest.id()) if has else ""
