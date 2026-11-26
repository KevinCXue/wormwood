extends CanvasLayer
## The pause menu (Esc): Resume, Save game, Load game, Controls, New game,
## Quit to title, Quit game. The game is paused while it's open. A child of
## Player.
##
## New game asks first (progress since your last save would be lost; the
## saves themselves are kept). Quit to title and Quit game autosave on the
## way out, so they don't need asking.

@onready var _player: CharacterBody3D = get_parent()
@onready var _buttons: VBoxContainer = $Root/Panel/VBox/Buttons
@onready var _status: Label = $Root/Panel/VBox/Status
@onready var _confirm: VBoxContainer = $Root/Panel/VBox/Confirm
@onready var _resume: Button = $Root/Panel/VBox/Buttons/Resume
@onready var _confirm_yes: Button = $Root/Panel/VBox/Confirm/Yes

const MenuFocus := preload("res://ui/menu_focus.gd")


func _ready() -> void:
	visible = false
	_resume.pressed.connect(_resume_game)
	$Root/Panel/VBox/Buttons/Save.pressed.connect(_save)
	$Root/Panel/VBox/Buttons/Load.pressed.connect(func():
		visible = false
		_player.get_node("LoadMenu").open(_open))
	$Root/Panel/VBox/Buttons/Controls.pressed.connect(func():
		visible = false
		_player.get_node("HelpMenu").open(_open))
	$Root/Panel/VBox/Buttons/NewGame.pressed.connect(_ask_new_game)
	$Root/Panel/VBox/Buttons/QuitToTitle.pressed.connect(func():
		await _autosave()
		SaveGame.to_title())
	$Root/Panel/VBox/Buttons/Quit.pressed.connect(func():
		await _autosave()
		get_tree().quit())
	_confirm_yes.pressed.connect(func(): SaveGame.new_game())
	$Root/Panel/VBox/Confirm/No.pressed.connect(_show_buttons)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not visible:
		# Not while something else has the game paused (another menu closes
		# itself on Esc), while talking or on the title screen, or while the
		# favourites wheel is open.
		if get_tree().paused or _player.locked or _player.get_node("QuickWheel").visible:
			return
		_open()
	elif _confirm.visible:
		_show_buttons()  # Esc backs out of the question
	else:
		_resume_game()
	get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	_show_buttons()


func _resume_game() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_buttons() -> void:
	_confirm.visible = false
	_buttons.visible = true
	MenuFocus.loop(_buttons.get_children())  # Up from Resume wraps to Quit game
	_resume.grab_focus()


func _ask_new_game() -> void:
	_buttons.visible = false
	_confirm.visible = true
	MenuFocus.loop([_confirm_yes, $Root/Panel/VBox/Confirm/No])
	$Root/Panel/VBox/Buttons/NewGame.release_focus()
	$Root/Panel/VBox/Confirm/No.grab_focus()  # the safe answer is the default


func _save() -> void:
	await _hidden_for_a_frame(func(): SaveGame.save("manual"))
	_status.text = "Game saved."


func _autosave() -> void:
	await _hidden_for_a_frame(func(): SaveGame.save("auto"))


## Saves take a thumbnail of the screen, so hide the menu and let one frame
## render without it first. (await pauses this function until the frame is
## drawn, like awaiting a promise; the game itself stays paused.)
func _hidden_for_a_frame(action: Callable) -> void:
	visible = false
	await RenderingServer.frame_post_draw
	action.call()
	visible = true
