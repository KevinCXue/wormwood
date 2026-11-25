class_name Equipable
extends Item
## An item worn in the left hand: weapons and tools (sword, axe, ...).
##
## `extends Item` means an Equipable IS an Item: it has display_name, is in
## the "items" group, and is a RigidBody3D. It only adds how to hold it.
##
## Models follow one convention: the long axis is +Y, with the business end
## (blade, axe head) towards +Y.

## Point on the model (in its own coordinates) that sits in the fist.
@export var grip := Vector3.ZERO
## How it's held, relative to the body, in degrees (X tilts it forward/back,
## Y spins it around its length). (0, 0, 0) = pointing straight up.
@export var hold_rotation_deg := Vector3(-35.0, 0.0, 0.0)
## What it's good for. Things that get hit decide how to react: trees only
## take damage from "axe"; straw dummies take damage from anything.
@export_enum("blade", "axe") var kind := "blade"
