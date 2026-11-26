extends CanvasLayer
## The title screen, shown when the game starts: the game's name and a menu
## (Continue, New game, Load game, Controls, Quit) over the live world, seen
## from a camera slowly circling high above the town. A child of main.tscn's
## root.
##
## The world behind is the real one, already loaded, so "New game" simply
## hides the title and hands control to the player. While it's up the player
## is locked (no moving or menus), the HUD is hidden, and nothing is saved:
## SaveGame.on_title stops autosaves, so an untouched world can't overwrite
## your progress. "Continue" and "Load game" load a save, which reloads the
## world without the title.
##
## Whether to show it is decided by SaveGame.world_ready() (first start, or
## "Quit to title"); see save/save_game.gd.

@export var orbit_centre := Vector3(8, 4, 34)  # what the camera circles: the town square
@export var orbit_radius := 75.0               # metres
@export var orbit_height := 32.0               # metres above the centre
@export var orbit_speed := 0.025               # radians per second (a lap every ~4 minutes)

@onready var _world: Node3D = get_parent()
@onready var _player: CharacterBody3D = _world.get_node("Player")
@onready var _camera: Camera3D = $Camera
@onready var _continue: Button = $Root/Box/Buttons/Continue
@onready var _continue_detail: Label = $Root/Box/Buttons/ContinueDetail
@onready var _new_game: Button = $Root/Box/Buttons/NewGame
@onready var _load: Button = $Root/Box/Buttons/Load
@onready var _controls: Button = $Root/Box/Buttons/Controls
@onready var _quit: Button = $Root/Box/Buttons/Quit

const MenuFocus := preload("res://ui/menu_focus.gd")

var _angle := 0.0
var _newest := {}  # the save Continue loads


func _ready() -> void:
	visible = false
	_continue.pressed.connect(func(): SaveGame.load_save(_newest.path))
	_new_game.pressed.connect(_start_new_game)
	_load.pressed.connect(func():
		visible = false
		_player.get_node("LoadMenu").open(_show))
	_controls.pressed.connect(func():
		visible = false
		_player.get_node("HelpMenu").open(_show))
	_quit.pressed.connect(func(): get_tree().quit())
	# main.gd's _ready (which asks SaveGame whether to show the title) runs
	# after ours, since parents are ready after their children; so check
	# once the frame's setup is done.
	_check.call_deferred()


func _check() -> void:
	if SaveGame.on_title:
		_angle = randf() * TAU
		_show()


func _show() -> void:
	visible = true
	get_tree().paused = false  # coming back from the load list or controls
	_player.locked = true
	_player.get_node("HUD").visible = false
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var saves := SaveGame.list_saves()
	_newest = saves[0] if not saves.is_empty() else {}
	_continue.disabled = saves.is_empty()
	_load.disabled = saves.is_empty()
	_continue_detail.text = _describe(_newest) if not saves.is_empty() else "No saves yet"
	MenuFocus.loop([_continue, _new_game, _load, _controls, _quit])  # Up from the top wraps to Quit
	(_new_game if saves.is_empty() else _continue).grab_focus()


func _process(delta: float) -> void:
	if not visible:
		return
	_angle += orbit_speed * delta
	_camera.global_position = orbit_centre + Vector3(cos(_angle) * orbit_radius, orbit_height, sin(_angle) * orbit_radius)
	_camera.look_at(orbit_centre)


func _start_new_game() -> void:
	visible = false
	SaveGame.leave_title()
	_player.locked = false
	_player.get_node("HUD").visible = true
	_player.get_node("CameraRig").camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## "Autosave · 25 Nov, 14:32 · 21:05 in the game", as in the load list.
func _describe(save: Dictionary) -> String:
	var menu = _player.get_node("LoadMenu")
	return "%s  ·  %s  ·  %s in the game" % ["Autosave" if save.kind == "auto" else "Save",
		menu._format_date(save.created), menu._format_clock(save.game_time)]
