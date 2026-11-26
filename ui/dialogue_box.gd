extends CanvasLayer
## Conversations with villagers: plays a dialogue script (dialogue/*.txt, the
## format is described in dialogue/dialogue_script.gd) in a box at the
## bottom of the screen. A child of Player; interactor.gd starts it when you
## press E on a villager who has a script.
##
## Lines: Enter, E, Space or a click shows the next one.
## Choices: Up/Down (or W/S) move, Enter/E picks, 1-9 pick directly, or click.
##
## The game keeps running (villagers breathe, the clock ticks), but the player
## can't move, swing or open menus: player.gd checks `in_dialogue`. The
## script's conditions and effects (has, take, gold, start_quest...) are
## carried out here, against the Inventory and the QuestLog.

const DialogueScript := preload("res://dialogue/dialogue_script.gd")
const ITEM_DIR := "res://props/items/"
const MAX_STEPS := 500  # guards against a script that jumps in a loop forever

@onready var _player: CharacterBody3D = get_parent()
@onready var _inventory: Node = $"../Inventory"
@onready var _quests: Node = $"../QuestLog"
@onready var _hud: CanvasLayer = $"../HUD"
@onready var _speaker: Label = $Root/Panel/VBox/Speaker
@onready var _text: Label = $Root/Panel/VBox/Text
@onready var _choices: VBoxContainer = $Root/Panel/VBox/Choices
@onready var _hint: Label = $Root/Panel/VBox/Hint

var _script = null        # the DialogueScript being played
var _npc: Npc = null
var _section := ""
var _step := 0            # index of the next step in the section
var _options: Array = []  # choices on screen (only those whose condition holds)
var _picked := 0          # highlighted choice


func _ready() -> void:
	visible = false


## Begin talking to `npc` (who has a dialogue_file).
func start(npc: Npc) -> void:
	_script = DialogueScript.load_script(npc.dialogue_file)
	if _script.sections.is_empty():
		return  # a broken script; the errors were printed when it loaded
	_npc = npc
	npc.begin_conversation()
	_player.in_dialogue = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # for clicking choices
	_hud.hide_line()
	visible = true
	_jump("start")


func _end() -> void:
	visible = false
	_player.in_dialogue = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _npc:
		_npc.end_conversation()
	_npc = null


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and _options.is_empty():
		_continue()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if key in [KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_SPACE]:
			if _options.is_empty():
				_continue()
			else:
				_choose(_picked)
		elif key in [KEY_UP, KEY_W] and not _options.is_empty():
			_highlight(posmod(_picked - 1, _options.size()))
		elif key in [KEY_DOWN, KEY_S] and not _options.is_empty():
			_highlight(posmod(_picked + 1, _options.size()))
		elif key >= KEY_1 and key <= KEY_9 and key - KEY_1 < _options.size():
			_choose(key - KEY_1)
		elif key == KEY_ESCAPE:
			if _options.is_empty():
				_end()  # Esc skips the rest of the talk (a choice must be made)
		else:
			return  # anything else: not ours
	else:
		return
	get_viewport().set_input_as_handled()  # so E doesn't also reach the interactor


# --- Running the script ------------------------------------------------------------

func _jump(section: String) -> void:
	if section == "END":
		_end()
		return
	_section = section
	_step = 0
	_run()


## Carry out steps until one needs the player (a line or a choice), then wait.
func _run() -> void:
	for guard in MAX_STEPS:
		var steps: Array = _script.sections.get(_section, [])
		if _step >= steps.size():
			_end()  # ran off the end of the section
			return
		var step: Dictionary = steps[_step]
		_step += 1
		match step.type:
			"if":
				if _check(step.cond):
					_jump(step.goto)
					return
			"do":
				_do(step.effect)
			"goto":
				_jump(step.goto)
				return
			"line":
				_show_line(step.speaker, step.text)
				return
			"choose":
				_options = step.options.filter(func(o): return o.cond.is_empty() or _check(o.cond))
				if _options.is_empty():
					continue  # no choice applies: carry on
				_show_choices()
				return
	push_error("%s: too many steps without a line; is there a loop?" % _script.path)
	_end()


func _continue() -> void:
	_run()


func _choose(index: int) -> void:
	var option: Dictionary = _options[index]
	_options = []
	_jump(option.goto)


func _check(cond: Array) -> bool:
	var words := cond.duplicate()
	var negate: bool = words.size() > 0 and words[0] == "not"
	if negate:
		words.pop_front()
	var result := false
	match words[0]:
		"quest_not_started": result = not _quests.is_started(words[1])
		"quest_active": result = _quests.is_active(words[1])
		"quest_ready": result = _quests.is_ready(words[1])
		"quest_done": result = _quests.is_done(words[1])
		"has":
			var data := _item(words[1])
			result = data != null and _inventory.count_of(data) >= _count(words, 2)
	return result != negate


func _do(effect: Array) -> void:
	match effect[0]:
		"start_quest": _quests.start(effect[1])
		"set_stage": _quests.set_stage(effect[1], int(effect[2]))
		"complete_quest": _quests.complete(effect[1])
		"gold":
			_inventory.add_gold(int(effect[1]))
			_hud.show_note("Received %s gold" % effect[1])
		"take":
			var data := _item(effect[1])
			if data:
				var n: int = _inventory.remove(data, _count(effect, 2))
				_hud.show_note("Gave %d %s" % [n, data.display_name])
		"give":
			var data := _item(effect[1])
			if data:
				_inventory.add(data, _count(effect, 2))
				_hud.show_note("Received %d %s" % [_count(effect, 2), data.display_name])


## "mushroom" -> res://props/items/mushroom.tres
func _item(item_name: String) -> ItemData:
	var item_path: String = ITEM_DIR + item_name + ".tres"
	if not ResourceLoader.exists(item_path):
		push_error("%s: no item called \"%s\"" % [_script.path, item_name])
		return null
	return load(item_path)


func _count(words: Array, at: int) -> int:
	return int(words[at]) if words.size() > at else 1


# --- Showing it ------------------------------------------------------------------------

func _show_line(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_text.text = text
	_clear_choices()
	_hint.text = "Enter  continue"


func _show_choices() -> void:
	_clear_choices()
	for i in _options.size():
		# Buttons give mouse hover and click for free; the keyboard is handled
		# in _input so that W/S and number keys work too.
		var button := Button.new()
		button.text = "%d.  %s" % [i + 1, _options[i].text]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		button.mouse_entered.connect(_highlight.bind(i))
		button.pressed.connect(_choose.bind(i))
		_choices.add_child(button)
	_highlight(0)
	_hint.text = "Up / Down  choose      Enter  select"


func _highlight(index: int) -> void:
	_picked = index
	for i in _choices.get_child_count():
		var button: Button = _choices.get_child(i)
		var on := i == index
		button.add_theme_color_override("font_color", Color(0.93, 0.8, 0.55) if on else Color(0.97, 0.94, 0.87, 0.75))
		button.add_theme_color_override("font_hover_color", Color(0.93, 0.8, 0.55))


func _clear_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
