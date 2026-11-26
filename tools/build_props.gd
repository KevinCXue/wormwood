extends SceneTree
## Turns downloaded Poly Haven models into game-ready scenes:
##   res://props/tables/<name>.tscn  StaticBody3D, exact (trimesh) collision
##   res://props/items/<name>.tscn   RigidBody3D + item.gd, convex collision
##   res://props/items/<weapon>.tscn RigidBody3D + equipable.gd (left hand)
##   res://props/items/candle.tscn, lantern.tscn  items with a real flickering light
##   res://props/furniture/<name>.tscn  StaticBody3D furniture (used by build_house.gd)
## and, only if they don't exist yet, starting layouts:
##   res://props/village_props.tscn  tables near the house with items on them
##   res://props/weapons_table.tscn  a table with the axe and sword
##
## Run from the project folder:
##   <Godot binary> --headless --path . -s res://tools/build_props.gd
##
## Layouts are written once, so after that you can move things in the
## editor freely. Delete a layout file to regenerate it.

const TABLE_DIR := "res://props/tables"
const ITEM_DIR := "res://props/items"
const LAYOUT := "res://props/village_props.tscn"
const WEAPONS_LAYOUT := "res://props/weapons_table.tscn"
const FURNITURE_DIR := "res://props/furniture"

# Multi-part models (e.g. a table plus its cloth) merged into one mesh each.
# name -> model id
const FURNITURE := {
	"dining_table": "dining_table",
	"bench": "painted_wooden_bench",
	"cabinet": "painted_wooden_cabinet",
	"nightstand": "painted_wooden_nightstand",
	"chest": "gallinera_table",
}

# name -> [model id, mesh node name in the glTF]
const TABLES := {
	"picnic_table": ["wooden_picnic_table", "wooden_picnic_table"],
	"small_table": ["wooden_table_02", "wooden_table_02"],
	"market_table": ["painted_wooden_table", "painted_wooden_table"],
}

# name -> [model id, mesh node, display name, mass in kg]
const ITEMS := {
	"plate": ["carved_wooden_plate", "carved_wooden_plate", "Wooden Plate", 0.4],
	"bowl": ["wooden_bowl_02", "wooden_bowl_02", "Wooden Bowl", 0.2],
	"goblet": ["brass_goblets", "brass_goblet_01", "Brass Goblet", 0.35],
	"jug": ["jug_01", "jug_01", "Clay Jug", 1.2],
	"apple": ["food_apple_01", "food_apple_01", "Apple", 0.15],
	"candlestick": ["wooden_candlestick", "wooden_candlestick", "Candlestick", 0.5],
}


func _initialize() -> void:
	var item_script: Script = load("res://item.gd")
	for table_name in TABLES:
		var spec: Array = TABLES[table_name]
		var mesh := _extract_mesh(spec[0], spec[1])
		var body := StaticBody3D.new()
		body.name = table_name.to_pascal_case()
		# Trimesh = collision that exactly follows every triangle. Only allowed
		# on static bodies (it's concave), and perfect for tabletops and benches.
		_add_mesh_and_shape(body, mesh, mesh.create_trimesh_shape())
		_pack(body, "%s/%s.tscn" % [TABLE_DIR, table_name])

	for item_name in ITEMS:
		var spec: Array = ITEMS[item_name]
		var mesh := _extract_mesh(spec[0], spec[1])
		var body := RigidBody3D.new()
		body.name = item_name.to_pascal_case()
		body.set_script(item_script)
		body.set("display_name", spec[2])
		body.mass = spec[3]
		# Convex hull = the shape you'd get shrink-wrapping the object. Moving
		# bodies need convex shapes; "simplify" keeps it to a few dozen faces.
		_add_mesh_and_shape(body, mesh, mesh.create_convex_shape(true, true))
		_pack(body, "%s/%s.tscn" % [ITEM_DIR, item_name])

	_build_equipables()
	_build_light_items()
	_build_furniture()

	if FileAccess.file_exists(LAYOUT):
		print("kept existing ", LAYOUT)
	else:
		_build_layout()
	if FileAccess.file_exists(WEAPONS_LAYOUT):
		print("kept existing ", WEAPONS_LAYOUT)
	else:
		_build_weapons_layout()
	print("done")
	quit()


# --- Furniture ----------------------------------------------------------------

func _build_furniture() -> void:
	for furniture_name in FURNITURE:
		var mesh := _merge_model(FURNITURE[furniture_name])
		var body := StaticBody3D.new()
		body.name = furniture_name.to_pascal_case()
		_add_mesh_and_shape(body, mesh, mesh.create_trimesh_shape())
		_pack(body, "%s/%s.tscn" % [FURNITURE_DIR, furniture_name])
	_build_bed()


## Copy every mesh in a glTF (with its offset inside the model) into one
## ArrayMesh, keeping each part's material as its own surface.
func _merge_model(model: String) -> ArrayMesh:
	var src: Node3D = load("res://assets/models/%s/%s.gltf" % [model, model]).instantiate()
	var merged := ArrayMesh.new()
	for node in src.find_children("*", "MeshInstance3D"):
		var mi := node as MeshInstance3D
		# The part's transform relative to the model root (it may be nested).
		var xf := Transform3D()
		var n: Node = mi
		while n != src:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for surface in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.append_from(mi.mesh, surface, xf)
			st.set_material(mi.mesh.surface_get_material(surface))
			st.commit(merged)
	src.free()
	var path := "res://assets/models/%s/%s_merged.res" % [model, model]
	_save(merged, path)
	return load(path)


## A simple wooden bed, 2.05 x 1.05 m, headboard at +X. Built from boxes.
func _build_bed() -> void:
	var wood := _mat(Color(0.33, 0.22, 0.14), 0.9)
	var linen := _mat(Color(0.86, 0.82, 0.72), 1.0)
	var wool := _mat(Color(0.55, 0.14, 0.11), 1.0)
	var body := StaticBody3D.new()
	body.name = "Bed"
	var parts := [
		# [size, centre, material]
		[Vector3(2.05, 0.22, 1.05), Vector3(0, 0.2, 0), wood],          # frame
		[Vector3(1.95, 0.16, 0.97), Vector3(-0.02, 0.39, 0), linen],     # mattress
		[Vector3(1.3, 0.18, 1.01), Vector3(-0.35, 0.40, 0), wool],       # blanket over the foot end
		[Vector3(0.38, 0.12, 0.7), Vector3(0.72, 0.52, 0), linen],       # pillow
		[Vector3(0.08, 1.0, 1.05), Vector3(0.99, 0.5, 0), wood],         # headboard
		[Vector3(0.08, 0.55, 1.05), Vector3(-0.99, 0.28, 0), wood],      # footboard
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		box.material = p[2]
		mi.mesh = box
		mi.position = p[1]
		body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2.05, 0.6, 1.05)
	shape.position = Vector3(0, 0.3, 0)
	body.add_child(shape)
	_pack(body, FURNITURE_DIR + "/bed.tscn")


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


# --- Items that give light -----------------------------------------------------

func _build_light_items() -> void:
	var candle_mesh := _extract_mesh("wooden_candlestick", "wooden_candlestick")
	_make_light_item("candle", "Lit Candle", 0.5, candle_mesh,
		candle_mesh.get_aabb().end.y + 0.018, 0.012, 1.6, 6.0, false)
	_make_light_item("lantern", "Lantern", 1.0, _merge_model("wooden_lantern_01"),
		0.14, 0.016, 3.5, 10.0, true)


## An Item with a glowing flame mesh and a flickering OmniLight at flame_y.
func _make_light_item(item_name: String, display: String, mass: float, mesh: Mesh,
		flame_y: float, flame_r: float, energy: float, light_range: float, shadows: bool) -> void:
	var body := RigidBody3D.new()
	body.name = item_name.to_pascal_case()
	body.set_script(load("res://item.gd"))
	body.set("display_name", display)
	body.mass = mass
	_add_mesh_and_shape(body, mesh, mesh.create_convex_shape(true, true))
	if shadows:
		# The light sits inside the lantern's cage. If the cage cast shadows,
		# its panes would block the light in every direction and the lantern
		# would light nothing but itself.
		(body.get_node("Mesh") as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# The visible flame: a small teardrop that glows (emission) and ignores
	# lighting (unshaded), so it always looks bright.
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var drop := SphereMesh.new()
	drop.radius = flame_r
	drop.height = flame_r * 3.5
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.78, 0.4)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.55, 0.15)
	fire.emission_energy_multiplier = 6.0
	drop.material = fire
	flame.mesh = drop
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = Vector3(0, flame_y, 0)
	body.add_child(flame)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.set_script(load("res://lights/flicker.gd"))
	light.light_color = Color(1.0, 0.66, 0.36)
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	light.position = Vector3(0, flame_y + 0.03, 0)  # just above, so the flame doesn't shadow itself
	body.add_child(light)
	_pack(body, "%s/%s.tscn" % [ITEM_DIR, item_name])


# --- Equipables (left hand) ---------------------------------------------------

func _build_equipables() -> void:
	var script: Script = load("res://equipable.gd")
	# Axe: Poly Haven model. Haft along +Y, head at the top, edge facing +Z.
	# Held head-up and tilted forward, spun 180 degrees so the edge faces forward.
	var axe_mesh := _extract_mesh("wooden_axe_02", "wooden_axe_02")
	_make_equipable("axe", "Woodcutter's Axe", 1.3, axe_mesh, script,
		Vector3(0, -0.19, 0), Vector3(30, 180, 0), "axe")
	# Sword: Poly Haven has none, so we build one (see _make_sword_mesh).
	var sword_mesh := _make_sword_mesh()
	_save(sword_mesh, "res://assets/models/generated/sword.res")
	_make_equipable("sword", "Iron Sword", 1.2, load("res://assets/models/generated/sword.res"), script,
		Vector3(0, 0.12, 0), Vector3(-35, 0, 0), "blade")


func _make_equipable(item_name: String, display: String, mass: float, mesh: Mesh,
		script: Script, grip: Vector3, hold_deg: Vector3, kind: String) -> void:
	var body := RigidBody3D.new()
	body.name = item_name.to_pascal_case()
	body.set_script(script)
	body.set("display_name", display)
	body.set("grip", grip)
	body.set("hold_rotation_deg", hold_deg)
	body.set("kind", kind)
	body.mass = mass
	_add_mesh_and_shape(body, mesh, mesh.create_convex_shape(true, true))
	_pack(body, "%s/%s.tscn" % [ITEM_DIR, item_name])


## A one-handed arming sword, ~1 m long, built along +Y:
## pommel (y 0-0.04), leather grip (to 0.2), crossguard, then the blade to 1.0.
func _make_sword_mesh() -> ArrayMesh:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.73, 0.75)
	steel.metallic = 1.0
	steel.roughness = 0.28
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.42, 0.39, 0.35)
	iron.metallic = 1.0
	iron.roughness = 0.5
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.24, 0.14, 0.08)
	leather.roughness = 0.85

	var mesh := ArrayMesh.new()
	# Blade: a flattened diamond cross-section (wide along Z, thin along X),
	# tapering slightly, then to a point. Flat-shaded so the bevels catch light.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # -1 = flat shading (no smoothing between faces)
	var rings := [[0.23, 0.026], [0.88, 0.022]]  # [y, half width]
	var thick := 0.005                          # half thickness at the centre ridge
	var ring_pts := func(y: float, hw: float) -> Array:
		return [Vector3(0, y, hw), Vector3(thick, y, 0), Vector3(0, y, -hw), Vector3(-thick, y, 0)]
	var r0: Array = ring_pts.call(rings[0][0], rings[0][1])
	var r1: Array = ring_pts.call(rings[1][0], rings[1][1])
	var tip := Vector3(0, 1.0, 0)
	for i in 4:
		var j := (i + 1) % 4
		_tri(st, r0[i], r1[i], r1[j]); _tri(st, r0[i], r1[j], r0[j])  # blade sides
		_tri(st, r1[i], tip, r1[j])                                    # point
		_tri(st, r0[j], Vector3(0, rings[0][0], 0), r0[i])  # base cap (hidden by the guard)
	st.generate_normals()
	st.set_material(steel)
	st.commit(mesh)

	# Crossguard and pommel (iron), from ready-made primitives.
	st = SurfaceTool.new()
	var guard := BoxMesh.new()
	guard.size = Vector3(0.03, 0.025, 0.2)
	st.append_from(guard, 0, Transform3D(Basis(), Vector3(0, 0.215, 0)))
	var pommel := SphereMesh.new()
	pommel.radius = 0.026
	pommel.height = 0.052
	st.append_from(pommel, 0, Transform3D(Basis(), Vector3(0, 0.025, 0)))
	st.set_material(iron)
	st.commit(mesh)

	# Grip (leather-wrapped).
	st = SurfaceTool.new()
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.015
	grip_mesh.bottom_radius = 0.017
	grip_mesh.height = 0.16
	grip_mesh.radial_segments = 10
	st.append_from(grip_mesh, 0, Transform3D(Basis(), Vector3(0, 0.125, 0)))
	st.set_material(leather)
	st.commit(mesh)
	return mesh


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)


## A table in front of the spawn point with the axe and sword laid on it.
func _build_weapons_layout() -> void:
	var root_node := Node3D.new()
	root_node.name = "WeaponsTable"
	var table: Node3D = load(TABLE_DIR + "/market_table.tscn").instantiate()
	table.name = "Table"
	root_node.add_child(table)
	var top := _top_of(table)
	# Lay each weapon flat along the table: rotating -90 degrees around Z turns
	# the weapon's long axis (+Y) to point along +X.
	for w in [["axe", Vector3(-0.55, 0, 0.15)], ["sword", Vector3(0.05, 0, -0.2)]]:
		var item: Node3D = load("%s/%s.tscn" % [ITEM_DIR, w[0]]).instantiate()
		item.rotation = Vector3(0, 0, deg_to_rad(-90))
		item.position = w[1] + Vector3(0, top + 0.06, 0)
		root_node.add_child(item)
	_pack(root_node, WEAPONS_LAYOUT)


## Copy one mesh out of a glTF and save it as a standalone .res.
func _extract_mesh(model: String, node_name: String) -> Mesh:
	var src: Node = load("res://assets/models/%s/%s.gltf" % [model, model]).instantiate()
	var mi := src.find_child(node_name) as MeshInstance3D
	var mesh := mi.mesh.duplicate() as Mesh
	src.free()
	var path := "res://assets/models/%s/%s.res" % [model, node_name]
	_save(mesh, path)
	return load(path)


func _add_mesh_and_shape(body: Node3D, mesh: Mesh, shape: Shape3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	cs.shape = shape
	body.add_child(cs)


## Layout around the village clearing. The house is at (-9, -6) with its door
## facing +Z; the player spawns at the origin.
func _build_layout() -> void:
	var root_node := Node3D.new()
	root_node.name = "VillageProps"
	var table_list: Array[Node3D] = []
	# [table, position, yaw in degrees]
	for t in [
		["picnic_table", Vector3(-5.5, 0, 3.0), 15.0],
		["market_table", Vector3(3.5, 0, 4.0), -20.0],
		["small_table", Vector3(-12.6, 0, -1.6), 0.0],  # beside the house door
		["small_table", Vector3(-9.0, 0, -8.2), 0.0],   # inside, against the back wall
	]:
		var inst: Node3D = load("%s/%s.tscn" % [TABLE_DIR, t[0]]).instantiate()
		inst.position = t[1]
		inst.rotation.y = deg_to_rad(t[2])
		root_node.add_child(inst, true)  # true = auto-number duplicate names
		table_list.append(inst)

	# Items: [table index in the list above, item, offset on the tabletop (x, z), yaw]
	var placements := [
		[0, "plate", Vector2(0.0, -0.6), 0], [0, "goblet", Vector2(0.15, -0.35), 0],
		[0, "plate", Vector2(0.0, 0.6), 40], [0, "apple", Vector2(0.05, 0.62), 0],
		[0, "jug", Vector2(-0.05, 0.05), 70], [0, "bowl", Vector2(0.15, 0.25), 0],
		[1, "apple", Vector2(-0.7, 0.1), 0], [1, "apple", Vector2(-0.6, -0.05), 0],
		[1, "apple", Vector2(-0.75, -0.15), 0], [1, "bowl", Vector2(-0.2, 0.0), 0],
		[1, "goblet", Vector2(0.3, 0.15), 0], [1, "goblet", Vector2(0.45, -0.1), 0],
		[1, "candlestick", Vector2(0.85, 0.0), 0],
		[2, "candlestick", Vector2(0.25, 0.0), 0], [2, "plate", Vector2(-0.2, 0.0), 0],
		[3, "jug", Vector2(-0.25, 0.0), 0], [3, "goblet", Vector2(0.2, 0.05), 0],
	]
	for p in placements:
		var table: Node3D = table_list[p[0]]
		var top := _top_of(table)
		var item: Node3D = load("%s/%s.tscn" % [ITEM_DIR, p[1]]).instantiate()
		# Offsets are in the table's own frame, so they rotate with it.
		var local := Vector3(p[2].x, 0.0, p[2].y)
		item.position = table.position + local.rotated(Vector3.UP, table.rotation.y) + Vector3(0, top + 0.01, 0)
		item.rotation.y = deg_to_rad(p[3])
		root_node.add_child(item, true)

	for child in root_node.get_children():
		child.owner = root_node
	_pack(root_node, LAYOUT)


## Height of a table's top surface: highest point of its mesh's bounding box.
func _top_of(table: Node3D) -> float:
	var mi := table.get_node("Mesh") as MeshInstance3D
	return mi.mesh.get_aabb().end.y


func _pack(node: Node, path: String) -> void:
	for c in node.get_children():
		if c.owner == null:
			c.owner = node
	var scene := PackedScene.new()
	scene.pack(node)
	_save(scene, path)
	node.free()


func _save(res: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "failed to save %s" % path)
	res.take_over_path(path)
