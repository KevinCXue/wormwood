extends RefCounted
## Keyboard focus for button menus (title screen, pause menu): link the
## buttons in a loop, so Up on the first one goes to the last and Down on the
## last goes back to the first. Disabled or hidden buttons are skipped and
## can't take focus.
##
## Each Control can name its neighbours for keyboard navigation
## (focus_neighbor_top / _bottom, as node paths). Without them Godot picks the
## nearest control in that direction, which stops at the edges.
##
## Usage: MenuFocus.loop([button_a, button_b, ...]) after showing the menu
## (and again whenever a button is enabled, disabled, shown or hidden).


static func loop(controls: Array) -> void:
	var usable := []
	for c: Control in controls:
		var off: bool = not c.is_visible_in_tree() or (c is BaseButton and c.disabled)
		c.focus_mode = Control.FOCUS_NONE if off else Control.FOCUS_ALL
		if not off:
			usable.append(c)
	for i in usable.size():
		var c: Control = usable[i]
		var previous: Control = usable[i - 1]  # [-1] is the last one
		var next: Control = usable[(i + 1) % usable.size()]
		c.focus_neighbor_top = c.get_path_to(previous)
		c.focus_neighbor_bottom = c.get_path_to(next)
		c.focus_previous = c.focus_neighbor_top  # Tab and Shift+Tab too
		c.focus_next = c.focus_neighbor_bottom
