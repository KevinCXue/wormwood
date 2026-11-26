extends CanvasLayer
## The quick-select wheel: hold Q, time slows, your favourite items (marked
## with F in the inventory screen, up to 8) appear in a ring. Move the mouse
## towards one and let go of Q to use it: a weapon is equipped (or put away
## if it's already in your hand); anything else is taken out of the bag into
## your hand, like holding E on it. Right-click a slot to take it off the
## wheel. A child of Player.
##
## Time slows through Engine.time_scale, a global multiplier on every node's
## delta and on physics. It isn't a pause, so the world keeps moving, just
## slowly, and this node runs as normal.
##
## The mouse stays captured: we add up its movement into a pointer offset
## from the centre, and the slot is whichever direction that points in.
## Mouse events are marked handled so the camera doesn't turn meanwhile.
##
## The ring is drawn in code (_draw_dial, connected to the Dial control's
## `draw` signal); the item names are Labels placed around it. Colours, size
## and fonts are exports or in quick_wheel.tscn.

@export var time_scale := 0.25        # how slow the world runs while the wheel is open
@export var radius := 190.0           # pixels, centre of the ring
@export var ring_width := 90.0        # pixels
@export var dead_zone := 30.0         # pixels of mouse movement before a slot is picked
@export var ring_color := Color(0.08, 0.07, 0.06, 0.78)
@export var highlight_color := Color(0.93, 0.8, 0.55, 0.32)
@export var line_color := Color(0.93, 0.8, 0.55, 0.35)

@onready var _inventory: Node = $"../Inventory"
@onready var _interactor: Node = $"../Interactor"
@onready var _dial: Control = $Root/Dial
@onready var _centre_name: Label = $Root/Dial/CentreName
@onready var _centre_hint: Label = $Root/Dial/CentreHint

var _labels: Array[Label] = []
var _pointer := Vector2.ZERO  # accumulated mouse movement, from the centre
var _slot := -1                # highlighted slot, or -1


func _ready() -> void:
	visible = false
	_dial.draw.connect(_draw_dial)
	for i in _inventory.MAX_FAVOURITES:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size = Vector2(130, 60)
		label.position = _slot_centre(i) - label.size / 2
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dial.add_child(label)
		_labels.append(label)


func _input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("quick_select") and not get_tree().paused and not get_parent().locked:
			_open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released("quick_select"):
		_use_slot()
		_close()
	elif event is InputEventMouseMotion:
		_pointer = (_pointer + event.relative).limit_length(radius)
		_update_slot()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _slot >= 0 and _slot < _inventory.favourites.size():
			_inventory.toggle_favourite(_inventory.favourites[_slot])  # unmark
			_refresh()
	elif not (event is InputEventMouseButton or event.is_action("attack")):
		return  # other keys (movement) still work while the wheel is open
	get_viewport().set_input_as_handled()


func _open() -> void:
	visible = true
	Engine.time_scale = time_scale
	_pointer = Vector2.ZERO
	_slot = -1
	_refresh()


func _close() -> void:
	visible = false
	Engine.time_scale = 1.0


func _use_slot() -> void:
	var favourites: Array = _inventory.favourites
	if _slot < 0 or _slot >= favourites.size():
		return
	var data: ItemData = favourites[_slot]
	if _inventory.count_of(data) == 0:
		return  # a favourite you've run out of
	if data.is_equipable():
		if data == _inventory.equipped:
			_interactor.unequip()
		else:
			_interactor.equip(data)
	else:
		_interactor.hold(data)


## Slot 0 is at the top, then clockwise.
func _slot_angle(i: int) -> float:
	return TAU * i / _inventory.MAX_FAVOURITES


func _slot_centre(i: int) -> Vector2:
	var a := _slot_angle(i)
	return _dial.size / 2 + Vector2(sin(a), -cos(a)) * radius


func _update_slot() -> void:
	var count: int = _inventory.MAX_FAVOURITES
	if _pointer.length() < dead_zone:
		_slot = -1
	else:
		# atan2(x, -y): 0 straight up, increasing clockwise (screen y points down).
		var a := atan2(_pointer.x, -_pointer.y)
		_slot = posmod(roundi(a / (TAU / count)), count)
	_refresh()


func _refresh() -> void:
	var favourites: Array = _inventory.favourites
	for i in _labels.size():
		var label := _labels[i]
		if i < favourites.size():
			var data: ItemData = favourites[i]
			var n: int = _inventory.count_of(data)
			label.text = data.display_name + ("\nx%d" % n if n > 1 else ("\nnone" if n == 0 else ""))
			var gold: bool = data == _inventory.equipped
			label.modulate = Color(0.93, 0.8, 0.55) if gold else Color(0.97, 0.94, 0.87, 1.0 if n > 0 else 0.35)
		else:
			label.text = "—"
			label.modulate = Color(1, 1, 1, 0.25)
	if favourites.is_empty():
		_centre_name.text = "No favourites"
		_centre_hint.text = "Mark items with F\nin the inventory (I)"
	elif _slot >= 0 and _slot < favourites.size():
		var data: ItemData = favourites[_slot]
		_centre_name.text = data.display_name
		var verb := "Put away" if data == _inventory.equipped else ("Equip" if data.is_equipable() else "Hold")
		_centre_hint.text = ("%s: release Q" % verb if _inventory.count_of(data) > 0 else "None in your bag") \
			+ "\nRight click: remove"
	else:
		_centre_name.text = ""
		_centre_hint.text = "Move the mouse to choose"
	_dial.queue_redraw()


func _draw_dial() -> void:
	var count: int = _inventory.MAX_FAVOURITES
	var centre := _dial.size / 2
	var step := TAU / count
	# The ring: one thick arc. draw_arc angles start at +X and run clockwise
	# on screen, so "up" is -PI/2.
	_dial.draw_arc(centre, radius, 0, TAU, 96, ring_color, ring_width, true)
	# A softer disc in the middle, behind the selected item's name.
	_dial.draw_circle(centre, radius - ring_width / 2 - 8, Color(ring_color, ring_color.a * 0.85), true, -1.0, true)
	if _slot >= 0:
		var mid := _slot_angle(_slot) - PI / 2
		_dial.draw_arc(centre, radius, mid - step / 2, mid + step / 2, 24, highlight_color, ring_width, true)
	# Dividers between slots.
	for i in count:
		var a := _slot_angle(i) + step / 2 - PI / 2
		var dir := Vector2(cos(a), sin(a))
		_dial.draw_line(centre + dir * (radius - ring_width / 2), centre + dir * (radius + ring_width / 2), line_color, 1.0, true)
	# Inner and outer edges.
	_dial.draw_arc(centre, radius - ring_width / 2, 0, TAU, 96, line_color, 1.0, true)
	_dial.draw_arc(centre, radius + ring_width / 2, 0, TAU, 96, line_color, 1.0, true)
