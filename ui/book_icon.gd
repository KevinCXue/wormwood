@tool
extends Control
## A small open book, drawn in code (there's no icon art): two pages with a
## few lines of "text" and a spine. Used by the HUD's help hint above the H
## key. @tool makes it draw in the editor too, so you can see it while
## arranging hud.tscn.

@export var color := Color(0.97, 0.94, 0.87, 1.0):
	set(value):
		color = value
		queue_redraw()  # redraw when changed in the Inspector


func _draw() -> void:
	var w := size.x
	var h := size.y
	var mid := w / 2.0
	var dip := h * 0.12   # how much the pages sag towards the spine
	var fill := Color(color, color.a * 0.35)
	for side: float in [-1.0, 1.0]:
		var outer := mid + side * (w / 2.0 - 1.0)
		# A page: a quad from the spine out to the edge, lower at the spine.
		var page := PackedVector2Array([
			Vector2(mid, dip), Vector2(outer, 0.0), Vector2(outer, h - dip), Vector2(mid, h)])
		draw_colored_polygon(page, fill)
		draw_polyline(PackedVector2Array([page[0], page[1], page[2], page[3]]), color, 1.5, true)
		# Three lines of writing on each page.
		for i in 3:
			var t := 0.3 + i * 0.18
			var inner_x := mid + side * w * 0.08
			var outer_x := mid + side * w * 0.38
			draw_line(Vector2(inner_x, lerpf(dip, h, t) - dip * 0.4), Vector2(outer_x, h * t),
				Color(color, color.a * 0.7), 1.0, true)
	draw_line(Vector2(mid, dip), Vector2(mid, h), color, 1.5, true)  # the spine
