extends CanvasLayer
## The inventory screen (I or Tab): a list of what's in the bag, grouped by
## category tabs, with a turning 3D preview of the selected item, its
## description, the total weight and your gold. A child of Player.
##
## While it's open the game is paused: get_tree().paused = true stops every
## node except those whose process_mode is "Always", like this one (set on
## the root in inventory_menu.tscn). So the world, the player and the clock
## freeze, but this menu keeps running and receiving input.
##
## The layout lives in inventory_menu.tscn (open it to restyle). This script
## fills it in from inventory.gd and asks interactor.gd to equip or drop.
##
## Keys while open: E (or Enter / double-click) equip or unequip,
## F favourite (for the quick-select wheel), R drop one, Esc / I / Tab close.

@export var preview_spin_speed := 0.6  # radians per second
@export var preview_size := 0.9        # metres: the item is scaled so its longest side is this

@onready var _inventory: Node = $"../Inventory"
@onready var _interactor: Node = $"../Interactor"
@onready var _weight: Label = $Root/Panel/VBox/Header/Weight
@onready var _tabs: HBoxContainer = $Root/Panel/VBox/Tabs
@onready var _list: Tree = $Root/Panel/VBox/Body/List
@onready var _pivot: Node3D = $Root/Panel/VBox/Body/Side/Preview/Viewport/Pivot
@onready var _item_name: Label = $Root/Panel/VBox/Body/Side/ItemName
@onready var _stats: Label = $Root/Panel/VBox/Body/Side/Stats
@onready var _description: Label = $Root/Panel/VBox/Body/Side/Description
@onready var _keys: Label = $Root/Panel/VBox/Footer/Keys
@onready var _gold: Label = $Root/Panel/VBox/Footer/Gold

var _category := -1               # tab shown: -1 = all, else ItemData.Category
var _selected: ItemData = null
var _previewing: ItemData = null  # what the 3D preview currently shows


func _ready() -> void:
	_build_tabs()
	_list.set_column_title(0, "Item")
	_list.set_column_title(1, "Count")
	_list.set_column_title(2, "Weight")
	_list.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	_list.set_column_expand(1, false)
	_list.set_column_expand(2, false)
	_list.set_column_custom_minimum_width(1, 70)
	_list.set_column_custom_minimum_width(2, 90)
	# Signals: the Tree calls these when you click or press Enter on a row.
	_list.item_selected.connect(_on_row_selected)
	_list.item_activated.connect(func(): _toggle_equip())
	_inventory.changed.connect(_refresh)


func _input(event: InputEvent) -> void:
	# _input sees keys before the UI does, so E/F/R work whatever has focus.
	if not visible:
		if event.is_action_pressed("inventory") and not get_tree().paused and not get_parent().locked:
			_open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel"):
		_close()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				_toggle_equip()
			KEY_F:
				if _selected and not _inventory.toggle_favourite(_selected):
					_keys.text = "The wheel is full (%d favourites). Unmark one first." % _inventory.MAX_FAVOURITES
			KEY_R:
				if _selected:
					_interactor.drop(_selected)
			_:
				return  # not ours: let the Tree have it (arrow keys)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if visible:
		_pivot.rotate_y(preview_spin_speed * delta)


func _open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_list.grab_focus()


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_show_preview(null)


func _build_tabs() -> void:
	# A ButtonGroup makes toggle buttons behave like radio buttons.
	var group := ButtonGroup.new()
	var names := ["All"] + ItemData.CATEGORY_NAMES
	for i in names.size():
		var tab := Button.new()
		tab.text = names[i]
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE  # keep keyboard focus on the list
		tab.button_pressed = i == 0
		var category := i - 1  # "All" = -1, then the Category values in order
		tab.pressed.connect(func():
			_category = category
			_refresh())
		_tabs.add_child(tab)


## Rebuild everything from the inventory. Cheap enough to do on every change.
func _refresh() -> void:
	if not visible:
		return
	var total: float = _inventory.total_weight()
	_weight.text = "%.1f / %d kg" % [total, _inventory.carry_limit]
	var over: bool = _inventory.is_overloaded()
	_weight.modulate = Color(1.0, 0.45, 0.35) if over else Color.WHITE
	_gold.text = "Gold  %d" % _inventory.gold

	_list.clear()
	var root := _list.create_item()  # hidden (hide_root), the rows hang off it
	var keep: TreeItem = null
	for stack in _inventory.stacks(_category):
		var data: ItemData = stack[0]
		var row := _list.create_item(root)
		var label := data.display_name
		if data in _inventory.favourites:
			label = "* " + label
		if data == _inventory.equipped:
			label += "   (equipped)"
			row.set_custom_color(0, Color(0.93, 0.8, 0.55))
		row.set_text(0, label)
		row.set_text(1, "x%d" % stack[1] if stack[1] > 1 else "")
		row.set_text(2, "%.1f" % (data.weight * stack[1]))
		row.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		row.set_text_alignment(2, HORIZONTAL_ALIGNMENT_RIGHT)
		row.set_metadata(0, data)  # remember which item the row is
		if data == _selected:
			keep = row
	# Keep the same item selected after a change, or select the first row.
	if keep == null:
		keep = root.get_first_child()
	if keep:
		keep.select(0)  # fires item_selected -> _on_row_selected
	else:
		_select(null)


func _on_row_selected() -> void:
	var row := _list.get_selected()
	_select(row.get_metadata(0) if row else null)


func _select(data: ItemData) -> void:
	_selected = data
	_item_name.text = data.display_name if data else ""
	_description.text = data.description if data else "Your bag is empty."
	_stats.text = "%s  ·  %.1f kg" % [ItemData.CATEGORY_NAMES[data.category], data.weight] if data else ""
	var verb := "unequip" if data and data == _inventory.equipped else "equip"
	if data and data.heal > 0:
		verb = "eat (+%d health)" % data.heal
	_keys.text = ("E  %s      " % verb if data and (data.is_equipable() or data.heal > 0) else "") \
		+ "F  favourite      R  drop      Esc  close"
	_show_preview(data)


## E: equip or put away a weapon, or eat food.
func _toggle_equip() -> void:
	if _selected and _selected.heal > 0:
		get_parent().eat(_selected)
		return
	if _selected == null or not _selected.is_equipable():
		return
	if _selected == _inventory.equipped:
		_interactor.unequip()
	else:
		_interactor.equip(_selected)


## Put a copy of the item on the preview turntable, centred and scaled so its
## longest side is preview_size.
func _show_preview(data: ItemData) -> void:
	if data == _previewing:
		return
	_previewing = data
	for child in _pivot.get_children():
		child.queue_free()
	if data == null:
		return
	var item := data.spawn()
	item.freeze = true  # a RigidBody: don't let it fall out of view
	var box := AABB()
	var first := true
	for mi in item.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Flame":
			continue
		var b: AABB = mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var longest := maxf(box.size[box.get_longest_axis_index()], 0.01)
	var holder := Node3D.new()  # scale and centre via a parent, so the item keeps its own transform
	holder.scale = Vector3.ONE * (preview_size / longest)
	holder.position = -box.get_center() * holder.scale
	holder.add_child(item)
	_pivot.add_child(holder)
	_pivot.rotation = Vector3.ZERO
