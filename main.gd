extends Node3D
## Root of the game world. Home for game-wide hotkeys (quit now; later
## things like quicksave or a pause menu).


func _unhandled_input(event: InputEvent) -> void:
	# Esc is bound to the built-in "ui_cancel" action in every Godot project.
	if event.is_action_pressed("ui_cancel"):
		# Ask the SceneTree (the object that runs the whole game) to shut down
		# at the end of this frame. This closes the window, and when running
		# from the editor it's the same as pressing Stop (F8).
		get_tree().quit()
