extends Node
## Game-wide settings, available everywhere as `Settings` (an autoload: Godot
## creates this node before the first scene and keeps it for the whole run,
## like a global singleton). Registered in Project Settings > Globals.
##
## Two knobs, both custom project settings in project.godot:
##   wormwood/graphics/character_detail  "detailed" (rigged humanoid) or
##                                        "blocky" (greybox mannequin)
##   wormwood/graphics/quality           "high" or "low" (lighting effects,
##                                        shadows, render resolution)
## Project settings can differ per platform with a feature tag suffix, e.g.
## `wormwood/graphics/quality.macos="low"`: the MacBook Air gets the low preset
## and the Windows PC the high one, with no code involved.
##
## For one run, override from the command line (after `--`):
##   <Godot binary> --path . -- --detail=blocky --quality=high
## In game, F2 flips between blocky and detailed (main.gd).

var character_detail := "detailed"
var quality := "high"


func _init() -> void:
	# get_setting_with_override applies the per-platform (.macos etc.) value.
	character_detail = ProjectSettings.get_setting_with_override("wormwood/graphics/character_detail")
	quality = ProjectSettings.get_setting_with_override("wormwood/graphics/quality")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--detail="):
			character_detail = arg.trim_prefix("--detail=")
		elif arg.begins_with("--quality="):
			quality = arg.trim_prefix("--quality=")


## Switch between the blocky and detailed characters by reloading the level.
## (Swapping bodies mid-game while they hold things isn't worth the bother.)
func toggle_character_detail() -> void:
	character_detail = "blocky" if character_detail == "detailed" else "detailed"
	print("character detail: ", character_detail)
	get_tree().reload_current_scene()


## Apply the quality preset to the world's environment and the window. Called
## by main.gd once the level is loaded.
func apply_quality(env: Environment, viewport: Viewport) -> void:
	var high := quality == "high"
	# "low" is the look the game has always had on the MacBook Air; "high"
	# spends the PC's extra power on sharpness rather than different lighting,
	# so both machines show the same world.
	# Render the 3D view at a fraction of the window's resolution and upscale
	# it (FSR). 0.5 = a quarter of the pixels, which is what the Air needs.
	viewport.scaling_3d_scale = 1.0 if high else 0.5
	# Shadow map resolution: sharper shadow edges.
	RenderingServer.directional_shadow_atlas_set_size(8192 if high else 4096, true)
	# More SDFGI (bounced light) detail near the camera.
	env.sdfgi_min_cell_size = 0.1 if high else 0.2
	print("graphics quality: %s, characters: %s" % [quality, character_detail])
