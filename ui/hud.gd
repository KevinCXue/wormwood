extends CanvasLayer
## On-screen overlay: the crosshair, the "E  Take Brass Goblet" prompt, short
## notes ("Apple added") and subtitles for what villagers say.
##
## A CanvasLayer draws 2D UI on top of the 3D view, unaffected by the camera.
## The layout lives in hud.tscn (open it to tweak positions, sizes and colours
## in the editor). This script only shows, hides and fills it in.

@onready var _crosshair: Control = $Root/Crosshair
@onready var _prompt: Control = $Root/Prompt
@onready var _verb: Label = $Root/Prompt/Verb
@onready var _name: Label = $Root/Prompt/ItemName
@onready var _hint: Label = $Root/Prompt/Hint
@onready var _note: Label = $Root/Note
@onready var _subtitle: Control = $Root/Subtitle
@onready var _speaker: Label = $Root/Subtitle/Speaker
@onready var _line: Label = $Root/Subtitle/Line

var _line_time_left := 0.0  # seconds until the subtitle fades away
var _note_time_left := 0.0  # seconds until the note fades away


## "E  <verb> <item name>  (hint)". `dim` fades it (e.g. "Drop" while carrying).
func show_prompt(verb: String, item_name: String, dim: bool, hint := "") -> void:
	_verb.text = verb
	_name.text = item_name
	_hint.text = "(%s)" % hint if hint else ""
	_hint.visible = hint != ""
	# modulate tints a node and all its children; alpha < 1 fades them.
	_prompt.modulate.a = 0.6 if dim else 1.0
	_prompt.visible = true


func hide_prompt() -> void:
	_prompt.visible = false


func set_crosshair(visible_now: bool, focused: bool) -> void:
	_crosshair.visible = visible_now
	_crosshair.focused = focused


## Show a line of dialogue at the bottom of the screen. It stays up for
## longer the more there is to read, then fades out.
func show_line(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_line.text = text
	_line_time_left = 2.5 + text.length() * 0.06
	_subtitle.modulate.a = 1.0
	_subtitle.visible = true


func hide_line() -> void:
	_line_time_left = minf(_line_time_left, 0.4)  # quick fade rather than a pop


## A short message under the prompt that fades after a moment.
func show_note(text: String) -> void:
	_note.text = text
	_note_time_left = 1.6
	_note.modulate.a = 1.0
	_note.visible = true


func _process(delta: float) -> void:
	if _subtitle.visible:
		_line_time_left -= delta
		# Fade over the last 0.4 seconds.
		_subtitle.modulate.a = clampf(_line_time_left / 0.4, 0.0, 1.0)
		if _line_time_left <= 0.0:
			_subtitle.visible = false
	if _note.visible:
		_note_time_left -= delta
		_note.modulate.a = clampf(_note_time_left / 0.4, 0.0, 1.0)
		if _note_time_left <= 0.0:
			_note.visible = false
