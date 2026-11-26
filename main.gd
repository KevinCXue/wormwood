extends Node3D
## Root of the game world. Applies the graphics preset, hands the world to
## the save system, and handles game-wide hotkeys: Esc quits (autosaving
## first), F2 swaps blocky/detailed characters, F5 saves, F9 opens the list of
## saves (ui/load_menu.gd handles F9 itself).


func _ready() -> void:
	Settings.apply_quality($WorldEnvironment.environment, get_viewport())
	# Restores a save if one is waiting (after a load or F2), or the latest
	# save when the game starts. See save/save_game.gd.
	SaveGame.world_ready(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc is bound to the built-in "ui_cancel" action in every Godot project.
	if event.is_action_pressed("ui_cancel"):
		# Ask the SceneTree (the object that runs the whole game) to shut down
		# at the end of this frame. This closes the window, and when running
		# from the editor it's the same as pressing Stop (F8).
		SaveGame.save("auto")  # so the next start carries on from here
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F2:
		Settings.toggle_character_detail()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F5:
		SaveGame.save("manual")
