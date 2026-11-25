class_name Plaza
extends Node3D
## A flat open area: the town square, the market. Like Road, it's invisible in
## the game; tools/build_village.gd levels the ground under it to this node's
## height (its Y position), paves it (stone texture) and clears the grass.
##
## Move it, resize it or raise it in the editor, then re-run
## tools/build_village.gd.

@export var size := Vector2(20.0, 16.0)  # metres along X and Z (before rotation)
@export var paved := true
