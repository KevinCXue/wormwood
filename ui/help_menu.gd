extends CanvasLayer
## The help screen (H): every control, grouped into Player and System
## columns. The game is paused while it's open, like the inventory. H or Esc
## closes it. A child of Player; the HUD shows a small book + H hint in the
## corner (ui/hud.tscn).
##
## The list below is the single place to describe controls: add a row when
## you add a key. (The keys themselves are registered in player.gd, main.gd
## and the menus; a settings menu with rebinding would read them from the
## InputMap instead.)
##
## Each row is [keys, description]. Keys are drawn as key caps; "hold" before
## a key adds a small "hold" label, and "/" shows as "or".

const PLAYER := {
	"Moving": [
		["W A S D", "Move (arrow keys work too)"],
		["hold Shift", "Run"],
		["Space", "Jump"],
		["Mouse", "Look around"],
		["Wheel", "Zoom (all the way in for first person)"],
		["F", "Switch first / third person"],
	],
	"Items and combat": [
		["E", "Take into your bag, or talk to someone"],
		["hold E", "Carry by hand (a weapon: equip it)"],
		["E", "Drop what you're carrying"],
		["Click", "Swing your weapon"],
		["I / Tab", "Inventory"],
		["hold Q", "Favourites wheel"],
	],
}

const SYSTEM := {
	"Game": [
		["F5", "Save (the newest 50 are kept)"],
		["F9", "Load a save"],
		["H", "This help"],
		["Esc", "Close a menu, or quit (autosaves first)"],
	],
	"In menus": [
		["E", "Inventory: equip or put away a weapon"],
		["F", "Inventory: add to or remove from the wheel"],
		["R", "Inventory: drop one"],
		["Mouse", "Wheel: point at a slot, let go of Q to use"],
		["Click", "Wheel: right click removes a slot"],
	],
	"Settings and testing": [
		["F2", "Switch blocky / detailed characters"],
		["hold T", "Fast-forward time"],
	],
}

@onready var _player_column: VBoxContainer = $Root/Panel/VBox/Columns/Player
@onready var _system_column: VBoxContainer = $Root/Panel/VBox/Columns/System
@onready var _keycap_style: StyleBox = preload("res://ui/keycap_style.tres")


func _ready() -> void:
	_fill(_player_column, "Player", PLAYER)
	_fill(_system_column, "System", SYSTEM)


func _input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("help") and not get_tree().paused:
			_open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("help") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Build a column: a big heading, then each group's small heading and a grid
## of [key caps | description] rows.
func _fill(column: VBoxContainer, title: String, groups: Dictionary) -> void:
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", Color(0.93, 0.8, 0.55))
	column.add_child(heading)
	for group in groups:
		var group_label := Label.new()
		group_label.text = group
		group_label.add_theme_font_size_override("font_size", 16)
		group_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 0.6))
		column.add_child(group_label)
		# GridContainer lays children out left-to-right, wrapping every
		# `columns` children: here, key caps then description.
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 3)
		column.add_child(grid)
		for row in groups[group]:
			grid.add_child(_keys(row[0]))
			var text := Label.new()
			text.text = row[1]
			text.custom_minimum_size.x = 330
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(text)


## "hold Shift" -> small "hold" + [Shift]; "I / Tab" -> [I] or [Tab].
func _keys(spec: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = 120
	for token in spec.split(" "):
		if token == "hold" or token == "/":
			var word := Label.new()
			word.text = "hold" if token == "hold" else "or"
			word.add_theme_font_size_override("font_size", 15)
			word.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 0.6))
			box.add_child(word)
		else:
			var cap := PanelContainer.new()
			cap.add_theme_stylebox_override("panel", _keycap_style)
			var label := Label.new()
			label.text = token
			label.add_theme_font_size_override("font_size", 16)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.custom_minimum_size.x = 14
			cap.add_child(label)
			cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(cap)
	return box
