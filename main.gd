extends Node3D
## Root of the game world. Applies the graphics preset, hands the world to
## the save system (which decides whether the title screen shows), and
## handles game-wide hotkeys: F2 swaps blocky/detailed characters, F5 saves.
## (Esc opens the pause menu, ui/pause_menu.gd; F9 the list of saves,
## ui/load_menu.gd.)


func _ready() -> void:
	Settings.apply_quality($WorldEnvironment.environment, get_viewport())
	# Restores a save if one is waiting (after a load or F2), or flags the
	# title screen on a fresh start. See save/save_game.gd.
	SaveGame.world_ready(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F2:
		Settings.toggle_character_detail()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F5:
		SaveGame.save("manual")
