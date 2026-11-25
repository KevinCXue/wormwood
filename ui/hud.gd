extends CanvasLayer
## On-screen overlay: the crosshair and the "E  Take Brass Goblet" prompt.
##
## A CanvasLayer draws 2D UI on top of the 3D view, unaffected by the camera.
## The layout lives in hud.tscn (open it to tweak positions, sizes and colours
## in the editor). This script only shows, hides and fills it in.

@onready var _crosshair: Control = $Root/Crosshair
@onready var _prompt: Control = $Root/Prompt
@onready var _verb: Label = $Root/Prompt/Verb
@onready var _name: Label = $Root/Prompt/ItemName


func show_prompt(verb: String, item_name: String, dim: bool) -> void:
	_verb.text = verb
	_name.text = item_name
	# modulate tints a node and all its children; alpha < 1 fades them.
	_prompt.modulate.a = 0.6 if dim else 1.0
	_prompt.visible = true


func hide_prompt() -> void:
	_prompt.visible = false


func set_crosshair(visible_now: bool, focused: bool) -> void:
	_crosshair.visible = visible_now
	_crosshair.focused = focused
