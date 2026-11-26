extends CanvasLayer
## On-screen overlay: the crosshair, the "E  Take Brass Goblet" prompt, short
## notes ("Apple added"), big banners for quests ("NEW QUEST / Suspicious
## Stew"), subtitles for what villagers say, and combat: your health bar
## (bottom left; it fades away a few seconds after you're back to full), a red
## flash when you're hit, and the health of whoever you're fighting (top).
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
@onready var _banner: Control = $Root/Banner
@onready var _banner_heading: Label = $Root/Banner/Heading
@onready var _banner_title: Label = $Root/Banner/Title
@onready var _banner_hint: Label = $Root/Banner/Hint

@export var banner_fade_in := 0.5   # seconds
@export var banner_hold := 4.0      # seconds fully visible
@export var banner_fade_out := 1.2  # seconds

var _banner_tween: Tween

@onready var _health: Control = $Root/Health
@onready var _health_text: Label = $Root/Health/Text
@onready var _health_fill: ColorRect = $Root/Health/Bar/Fill
@onready var _hurt: ColorRect = $Root/Hurt
@onready var _target: Control = $Root/Target
@onready var _target_name: Label = $Root/Target/Name
@onready var _target_fill: ColorRect = $Root/Target/Bar/Fill

@export var health_linger := 4.0  # seconds the bar stays after you're back to full
@export var target_linger := 5.0  # seconds the enemy's bar stays after the last blow

var _full_for := 0.0
var _target_health: Health = null
var _target_left := 0.0
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


## A big announcement in the upper middle of the screen, e.g. "NEW QUEST" over
## the quest's title. Fades in, stays a few seconds, fades out.
## A Tween animates properties over time: each tween_* call below is a step,
## run one after another, so no timers need managing by hand.
func show_banner(heading: String, title: String, hint := "") -> void:
	_banner_heading.text = heading
	_banner_title.text = title
	_banner_hint.text = hint
	_banner_hint.visible = hint != ""
	if _banner_tween:
		_banner_tween.kill()  # a new banner replaces one still showing
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, banner_fade_in)
	_banner_tween.tween_interval(banner_hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, banner_fade_out)
	_banner_tween.tween_callback(func(): _banner.visible = false)


## Your health changed: update the bar and show it.
func set_health(health: int, max_health: int) -> void:
	_health_text.text = "Health  %d / %d" % [health, max_health]
	_health_fill.anchor_right = float(health) / max_health
	_health.modulate.a = 1.0
	_full_for = 0.0


## A red flash over the screen when you're hit.
func flash_hurt() -> void:
	_hurt.color.a = 0.35
	create_tween().tween_property(_hurt, "color:a", 0.0, 0.5)


## Show who you're fighting and their health, for a few seconds.
func show_target(target_name: String, health: Health) -> void:
	_target_name.text = target_name
	_target_health = health
	_target_left = target_linger
	_target.visible = true


## A short message under the prompt that fades after a moment.
func show_note(text: String) -> void:
	_note.text = text
	_note_time_left = 1.6
	_note.modulate.a = 1.0
	_note.visible = true


func _process(delta: float) -> void:
	_update_combat_bars(delta)
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


func _update_combat_bars(delta: float) -> void:
	# Your bar: fade it away once you've been at full health for a while.
	if _health_fill.anchor_right >= 0.999:
		_full_for += delta
		if _full_for > health_linger:
			_health.modulate.a = maxf(_health.modulate.a - delta * 2.0, 0.0)
	# The enemy's bar follows their health until it times out.
	if _target.visible:
		_target_left -= delta
		if _target_health and is_instance_valid(_target_health):
			_target_fill.anchor_right = float(_target_health.health) / _target_health.max_health
		if _target_left <= 0.0:
			_target.visible = false
