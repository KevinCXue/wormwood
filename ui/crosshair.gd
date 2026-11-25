extends Control
## A small, soft dot in the centre of the screen.
##
## Controls can draw themselves: override _draw() and call draw_* functions.
## Godot only calls _draw() when told to (queue_redraw()), so it costs nothing
## while nothing changes.

@export var color := Color(0.96, 0.93, 0.85, 0.55)  # warm off-white, see-through
@export var outline := Color(0.0, 0.0, 0.0, 0.25)   # faint edge so it shows on bright sky
@export var radius := 2.0          # pixels, when idle
@export var focused_radius := 3.0  # pixels, when over something you can take
@export var focused_alpha := 0.85

var focused := false:
	set(value):
		# A property setter: runs whenever `focused` is assigned.
		if value != focused:
			focused = value
			queue_redraw()


func _draw() -> void:
	var centre := size / 2.0
	var r := focused_radius if focused else radius
	var c := color
	if focused:
		c.a = focused_alpha
	draw_circle(centre, r + 1.0, outline)
	draw_circle(centre, r, c, true, -1.0, true)  # filled, antialiased
