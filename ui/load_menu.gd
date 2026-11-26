extends CanvasLayer
## The list of saves (F9): newest first, each with its thumbnail, when it was
## saved and the in-game time. Enter (or double-click) loads it; Delete twice
## removes it; Esc or F9 closes. The game is paused while it's open, like the
## inventory screen. A child of Player; the saving itself is SaveGame
## (save/save_game.gd).
##
## The list is an ItemList: Godot's ready-made list widget, where each row can
## have an icon (the thumbnail) and text, with selection and keyboard
## navigation built in.

@onready var _list: ItemList = $Root/Panel/VBox/List
@onready var _hint: Label = $Root/Panel/VBox/Footer/Hint
@onready var _empty: Label = $Root/Panel/VBox/Empty

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const HINT := "Enter  load      Delete  delete      Esc  close"

var _saves: Array = []
var _confirm_delete := -1  # row waiting for a second Delete press


func _ready() -> void:
	_list.item_activated.connect(func(index: int): SaveGame.load_save(_saves[index].path))
	_list.item_selected.connect(func(_index: int):
		_confirm_delete = -1
		_hint.text = HINT)


func _input(event: InputEvent) -> void:
	var f9: bool = event is InputEventKey and event.pressed and not event.echo \
		and event.physical_keycode == KEY_F9
	if not visible:
		if f9 and not get_tree().paused:
			_open()
			get_viewport().set_input_as_handled()
		return
	if f9 or event.is_action_pressed("ui_cancel"):
		_close()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_DELETE, KEY_BACKSPACE]:
		_delete_selected()
	else:
		return  # arrows and Enter: the ItemList handles them
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
	_saves = SaveGame.list_saves()
	_list.clear()
	_confirm_delete = -1
	_hint.text = HINT
	_empty.visible = _saves.is_empty()
	_list.visible = not _saves.is_empty()
	for save in _saves:
		var label := "%s   ·   %s   ·   %s in the game" % [
			"Autosave" if save.kind == "auto" else "Save",
			_format_date(save.created), _format_clock(save.game_time)]
		var index := _list.add_item(label, _load_thumbnail(save.thumbnail))
		_list.set_item_tooltip_enabled(index, false)
	if not _saves.is_empty():
		_list.select(0)  # the newest
		_list.ensure_current_is_visible()


func _delete_selected() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	if _confirm_delete != index:
		_confirm_delete = index
		_hint.text = "Press Delete again to delete this save"
		return
	SaveGame.delete_save(_saves[index].path)
	_refresh()
	if not _saves.is_empty():
		_list.select(mini(index, _saves.size() - 1))


func _load_thumbnail(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image else null


## "25 Nov, 14:32" in the computer's local time.
func _format_date(unix: float) -> String:
	var bias_seconds: int = Time.get_time_zone_from_system().bias * 60
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias_seconds)
	return "%d %s, %02d:%02d" % [d.day, MONTHS[d.month - 1], d.hour, d.minute]


## In-game hours as "21:05".
func _format_clock(hours: float) -> String:
	var minutes := int(hours * 60.0) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
