extends SceneTree
## Fits the village into the landscape: paints its roads onto the terrain and
## clears grass, plants, trees and rocks off the roads and away from buildings.
##
## The village itself lives in res://village/village.tscn: Road curves
## (village/road.gd), cottages and villagers. That scene is the source of
## truth. Move things around in the editor, then re-run this to make the
## ground match. If the scene doesn't exist yet, this writes a starting one.
##
## Run from the project folder (after build_world.gd and build_cottages.gd):
##   <Godot binary> --headless --path . -s res://tools/build_village.gd
##
## Unlike build_world.gd this does NOT regenerate the terrain. It edits what's
## there, so your own sculpting and painting elsewhere survives. It only ever
## removes vegetation and paints dirt; it never puts trees or grass back. So
## if you move a cottage, the old spot stays bare until you repaint it with the
## Terrain3D tools.
##
## Modifies: res://terrain/data/*, res://terrain/colliders.scn
## Writes once: res://village/village.tscn

const VILLAGE := "res://village/village.tscn"
const DATA_DIR := "res://terrain/data"
const COLLIDERS := "res://terrain/colliders.scn"

# Terrain3D mesh ids, as set up in build_world.gd.
enum { GRASS, PINE_A, PINE_B, FERN_A, FERN_B, SHRUB_A, SHRUB_B, ROCK }
const PLANTS := [FERN_A, FERN_B, SHRUB_A, SHRUB_B]
const BIG := [PINE_A, PINE_B, ROCK]

# How far past a road's edge / a building's walls each kind of thing is
# cleared, in metres. Trees need the most room: their branches spread.
const MARGIN := {"grass": 0.6, "plants": 1.5, "big": 3.0, "rock": 4.5}

var terrain: Terrain3D
## Pixel (1 m grid) -> how far it is from the nearest road's edge (negative
## = on the road). Only pixels near roads are in here.
var road_edge_dist := {}
## [global transform, footprint size] for each building.
var buildings: Array = []


func _initialize() -> void:
	if not ResourceLoader.exists(VILLAGE):
		print("no village scene yet: writing a starting one")
		_write_default_village()

	print("1/4 reading ", VILLAGE)
	var village: Node3D = load(VILLAGE).instantiate()
	root.add_child(village)
	# Nodes added during _initialize join the tree on the next frame; global
	# transforms only work once they're in it.
	await process_frame
	_read_village(village)

	print("2/4 loading terrain")
	terrain = Terrain3D.new()
	terrain.data_directory = DATA_DIR
	terrain.material = load("res://terrain/material.tres")
	terrain.assets = load("res://terrain/assets.tres")
	root.add_child(terrain)
	await process_frame
	await process_frame

	print("3/4 painting roads (%d pixels)" % road_edge_dist.size())
	_paint_roads()

	print("4/4 clearing vegetation")
	_clear_instances()
	_clear_colliders()

	terrain.data.save_directory(DATA_DIR)
	village.queue_free()
	terrain.queue_free()
	print("done")
	quit()


# --- Reading the village ----------------------------------------------------------

func _read_village(village: Node) -> void:
	for road in village.find_children("*", "Road", true, false):
		_rasterise_road(road)
	for node in village.find_children("*", "Node3D", true, false):
		if node.has_meta("footprint"):
			buildings.append([node.global_transform, node.get_meta("footprint")])
	print("   roads: %d, buildings: %d" % [village.find_children("*", "Road", true, false).size(), buildings.size()])


## Work out, for every terrain pixel near the road, how far it is from the
## road's edge. A curve's "baked points" are points every ~0.2 m along it.
func _rasterise_road(road: Road) -> void:
	var pts: Array[Vector2] = []
	for p in road.curve.get_baked_points():
		var g: Vector3 = road.global_transform * p
		pts.append(Vector2(g.x, g.z))
	if pts.size() < 2:
		return
	var reach := road.width / 2.0 + MARGIN["big"] + 1.0
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	for x in range(floori(lo.x - reach), ceili(hi.x + reach) + 1):
		for z in range(floori(lo.y - reach), ceili(hi.y + reach) + 1):
			var here := Vector2(x, z)
			var d := INF
			for i in pts.size() - 1:
				d = minf(d, here.distance_to(Geometry2D.get_closest_point_to_segment(here, pts[i], pts[i + 1])))
			d -= road.width / 2.0
			if d < reach:
				var key := Vector2i(x, z)
				road_edge_dist[key] = minf(road_edge_dist.get(key, INF), d)


# --- Painting ---------------------------------------------------------------------

## Terrain3D's control map stores, per pixel, two texture ids (base and
## overlay), how much of the overlay shows (blend), and an "auto" flag that
## hands the pixel to the auto-shader (grass on flat ground, rock on slopes).
## Road pixels switch auto off: bare dirt in the middle, dirt blending into
## grass over the last metre at the edges.
func _paint_roads() -> void:
	var dirt := _texture_id("Dirt")
	var grass := _texture_id("Grass")
	var data := terrain.data
	for key in road_edge_dist:
		var d: float = road_edge_dist[key]
		if d > 1.0:
			continue
		var pos := Vector3(key.x, 0, key.y)
		var amount := clampf(0.5 - d, 0.0, 1.0)  # 1 on the road, fading to 0 a metre out
		if amount <= 0.0:
			continue
		# Don't weaken a pixel another road already made more dirty.
		var current := 0.0
		if not data.get_control_auto(pos):
			if data.get_control_base_id(pos) == dirt:
				current = 1.0
			elif data.get_control_overlay_id(pos) == dirt:
				current = data.get_control_blend(pos)
		if amount <= current:
			continue
		data.set_control_auto(pos, false)
		if amount >= 0.999:
			data.set_control_base_id(pos, dirt)
			data.set_control_overlay_id(pos, dirt)
			data.set_control_blend(pos, 0.0)
		else:
			data.set_control_base_id(pos, grass)
			data.set_control_overlay_id(pos, dirt)
			data.set_control_blend(pos, amount)
	data.update_maps(Terrain3DRegion.TYPE_CONTROL)


func _texture_id(asset_name: String) -> int:
	# Read the list from the saved file: once the terrain is running headless,
	# its live copy of the list can be empty.
	var assets: Terrain3DAssets = load("res://terrain/assets.tres")
	for asset in assets.get_texture_list():
		if asset.name == asset_name:
			return asset.id
	assert(false, "no terrain texture named " + asset_name)
	return -1


# --- Clearing ---------------------------------------------------------------------

## Should something of this kind ("grass", "plants", "big") at this world
## position be removed?
func _cleared(p: Vector3, kind: String) -> bool:
	var margin: float = MARGIN[kind]
	var key := Vector2i(roundi(p.x), roundi(p.z))
	if road_edge_dist.has(key) and road_edge_dist[key] < margin:
		return true
	for b in buildings:
		var local: Vector3 = b[0].affine_inverse() * p
		var half: Vector2 = b[1] / 2.0 + Vector2(margin, margin)
		if absf(local.x) < half.x and absf(local.z) < half.y:
			return true
	return false


## Instances (the grass, trees and rocks Terrain3D draws in bulk) are stored
## per region (256 x 256 m), then per 32 m cell, as lists of transforms
## relative to the region's corner.
func _clear_instances() -> void:
	var removed := {}
	var region_size := float(terrain.region_size) * terrain.vertex_spacing
	for loc in terrain.data.get_region_locations():
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		var corner := Vector3(loc.x, 0, loc.y) * region_size
		var instances: Dictionary = region.get_instances()
		var changed := false
		for mesh_id in instances:
			var kind := "grass" if mesh_id == GRASS else ("plants" if mesh_id in PLANTS else "big")
			if mesh_id == ROCK:
				# A rock's collider sits up to a metre or so from the rock's
				# origin, so clear rocks a little wider than their colliders
				# (which use "big"): a rock never loses its collider but stays.
				kind = "rock"
			var cells: Dictionary = instances[mesh_id]
			for cell in cells:
				var entry: Array = cells[cell]  # [transforms, colours, modified flag]
				var xforms: Array = entry[0]
				var colours: PackedColorArray = entry[1]
				var keep_x: Array[Transform3D] = []
				var keep_c := PackedColorArray()
				for i in xforms.size():
					if _cleared(corner + xforms[i].origin, kind):
						removed[mesh_id] = removed.get(mesh_id, 0) + 1
						continue
					keep_x.append(xforms[i])
					if i < colours.size():
						keep_c.append(colours[i])
				if keep_x.size() != xforms.size():
					entry[0] = keep_x
					entry[1] = keep_c
					entry[2] = true
					changed = true
		if changed:
			region.set_instances(instances)
			terrain.data.set_region_modified(loc, true)
	print("   removed: grass %d, plants %d, trees %d, rocks %d" % [
		removed.get(GRASS, 0),
		removed.get(FERN_A, 0) + removed.get(FERN_B, 0) + removed.get(SHRUB_A, 0) + removed.get(SHRUB_B, 0),
		removed.get(PINE_A, 0) + removed.get(PINE_B, 0), removed.get(ROCK, 0)])


## Trees and rocks have invisible collision shapes in a separate scene
## (instanced meshes have none). Remove the ones whose tree was removed.
func _clear_colliders() -> void:
	var body: Node = load(COLLIDERS).instantiate()
	var count := 0
	for shape in body.get_children():
		if _cleared((shape as Node3D).position, "big"):
			body.remove_child(shape)
			shape.free()
			count += 1
	var scene := PackedScene.new()
	scene.pack(body)
	var err := ResourceSaver.save(scene, COLLIDERS)
	assert(err == OK, "failed to save " + COLLIDERS)
	body.free()
	print("   removed %d tree/rock colliders" % count)


# --- The starting village -----------------------------------------------------------

## The first layout: a main street running south from the spawn point, a path
## to the player's house, and two cottages along the street with their owners
## standing outside. After this file exists, edit it in the editor instead.
func _write_default_village() -> void:
	var village := Node3D.new()
	village.name = "Village"
	village.editor_description = "Roads, cottages and villagers. Edit freely, then re-run tools/build_village.gd so the terrain (dirt paint, cleared grass and trees) matches."

	var roads := _group(village, "Roads")
	# Points are (x, z) on the ground. The player spawns at (0, 0) and the
	# big house's door is at (-11, -5.5).
	_road(roads, "MainStreet", 3.2, [Vector2(0.5, -1.0), Vector2(0.8, 8.0), Vector2(-0.6, 18.0),
		Vector2(-0.3, 28.0), Vector2(1.5, 40.0), Vector2(4.0, 55.0), Vector2(6.0, 72.0)])
	_road(roads, "HousePath", 2.2, [Vector2(0.5, -1.0), Vector2(-5.0, -2.6), Vector2(-9.2, -3.7), Vector2(-11.0, -5.4)])
	_road(roads, "MiraPath", 1.6, [Vector2(-0.6, 16.0), Vector2(-3.5, 16.0), Vector2(-6.1, 16.0)])
	_road(roads, "TobinPath", 1.6, [Vector2(-0.5, 22.0), Vector2(3.5, 22.0), Vector2(6.9, 22.0)])

	var houses := _group(village, "Buildings")
	# Cottage doors face their local +Z; yaw 90 turns that to +X (east).
	_instance(houses, "res://buildings/cottage_a.tscn", "MiraCottage", Vector3(-9, 0, 16), 90.0)
	_instance(houses, "res://buildings/cottage_b.tscn", "TobinCottage", Vector3(10, 0, 22), -90.0)

	var people := _group(village, "Villagers")
	# Villagers face their local -Z; yaw -90 turns that to +X.
	var mira := _instance(people, "res://npcs/npc.tscn", "Mira", Vector3(-4.6, 0, 14.7), -90.0)
	mira.display_name = "Mira"
	mira.tunic_color = Color(0.22, 0.38, 0.72)
	mira.trousers_color = Color(0.2, 0.2, 0.26)
	mira.skin_color = Color(0.86, 0.69, 0.57)
	mira.hair_color = Color(0.55, 0.3, 0.14)
	mira.hair_style = "long"
	mira.skirt = true
	mira.height_scale = 0.95
	mira.lines = PackedStringArray([
		"Oh! You're the one from the big house up the road, aren't you? I'm Mira.",
		"Most mornings I'm at the market table, if you're after apples. Don't tell Tobin where they came from.",
		"The forest gets dark early this time of year. Keep a lantern close.",
	])
	var tobin := _instance(people, "res://npcs/npc.tscn", "Tobin", Vector3(5.6, 0, 23.0), 90.0)
	tobin.display_name = "Tobin"
	tobin.tunic_color = Color(0.25, 0.45, 0.22)
	tobin.trousers_color = Color(0.32, 0.25, 0.17)
	tobin.skin_color = Color(0.68, 0.5, 0.38)
	tobin.hair_color = Color(0.15, 0.1, 0.07)
	tobin.height_scale = 1.03
	tobin.lines = PackedStringArray([
		"Name's Tobin. I cut wood for the village. Saw you hacking at the pines past the yard.",
		"Swing from the side, not straight down. Let the axe do the work.",
		"More folk are moving in, they say. We'll need a lot more timber.",
	])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VILLAGE.get_base_dir()))
	_set_owner(village, village)
	var scene := PackedScene.new()
	scene.pack(village)
	var err := ResourceSaver.save(scene, VILLAGE)
	assert(err == OK, "failed to save " + VILLAGE)
	village.free()


func _group(parent: Node, group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	parent.add_child(n)
	return n


func _road(parent: Node, road_name: String, width: float, points: Array) -> void:
	var road := Road.new()
	road.name = road_name
	road.width = width
	var curve := Curve3D.new()
	for p in points:
		curve.add_point(Vector3(p.x, 0, p.y))
	# Smooth corners: give each inner point handles along the line from its
	# previous to its next neighbour (a Catmull-Rom style curve).
	for i in range(1, curve.point_count - 1):
		var tangent := (curve.get_point_position(i + 1) - curve.get_point_position(i - 1)) * 0.2
		curve.set_point_in(i, -tangent)
		curve.set_point_out(i, tangent)
	road.curve = curve
	parent.add_child(road)


func _instance(parent: Node, path: String, node_name: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var node: Node3D = load(path).instantiate()
	node.name = node_name
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(node)
	return node


func _set_owner(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_set_owner(c, owner_node)
