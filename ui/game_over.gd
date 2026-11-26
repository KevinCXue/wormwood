extends CanvasLayer
## The death screen: "You died", then Load last save, Quit to title or Quit
## game. A child of Player; player.gd shows it a moment after you fall.
##
## Nothing is saved from here: SaveGame.blocked is set when you die, so
## neither quitting nor closing the window autosaves a dead player over your
## progress.

const MenuFocus := preload("res://ui/menu_focus.gd")

@onready var _load: Button = $Root/Box/Buttons/Load
@onready var _detail: Label = $Root/Box/Buttons/LoadDetail
@onready var _to_title: Button = $Root/Box/Buttons/ToTitle
@onready var _quit: Button = $Root/Box/Buttons/Quit
@onready var _fade: ColorRect = $Root/Fade

var _newest := {}


func _ready() -> void:
	visible = false
	_load.pressed.connect(func(): SaveGame.load_save(_newest.path))
	_to_title.pressed.connect(func(): SaveGame.to_title())
	_quit.pressed.connect(func(): get_tree().quit())


func show_screen() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var saves := SaveGame.list_saves()
	_newest = saves[0] if not saves.is_empty() else {}
	_load.disabled = saves.is_empty()
	_detail.text = _describe()
	MenuFocus.loop([_load, _to_title, _quit])
	(_to_title if saves.is_empty() else _load).grab_focus()
	# Fade in from nothing.
	_fade.modulate.a = 0.0
	create_tween().tween_property(_fade, "modulate:a", 1.0, 1.2)


func _describe() -> String:
	if _newest.is_empty():
		return "No saves yet"
	var menu = get_parent().get_node("LoadMenu")
	return "%s  ·  %s  ·  %s in the game" % ["Autosave" if _newest.kind == "auto" else "Save",
		menu._format_date(_newest.created), menu._format_clock(_newest.game_time)]
