extends Node3D
## Root of the game world. Applies the graphics preset and handles game-wide
## hotkeys (Esc quits, F2 swaps blocky/detailed characters; later things like
## quicksave or a pause menu).


func _ready() -> void:
	Settings.apply_quality($WorldEnvironment.environment, get_viewport())


func _unhandled_input(event: InputEvent) -> void:
	# Esc is bound to the built-in "ui_cancel" action in every Godot project.
	if event.is_action_pressed("ui_cancel"):
		# Ask the SceneTree (the object that runs the whole game) to shut down
		# at the end of this frame. This closes the window, and when running
		# from the editor it's the same as pressing Stop (F8).
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F2:
		Settings.toggle_character_detail()
