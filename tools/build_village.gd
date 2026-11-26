extends SceneTree
## Fits the village into the landscape. For everything in
## res://village/village.tscn it:
##   1. shapes the ground: flat pads under buildings and plazas, roads graded
##      to the height of their curve, blended smoothly into the natural hills;
##   2. paints roads with dirt and plazas with stone;
##   3. clears grass, plants, trees and rocks off roads, plazas and building
##      sites, and moves whatever is left up or down with the reshaped ground;
##   4. stands every villager on the (new) ground and saves village.tscn.
##
## The village itself (Road curves, Plaza areas, buildings, villagers) lives in
## res://village/village.tscn, which is the source of truth: move things in the
## editor (including up and down), then re-run this to make the ground match.
## If the scene doesn't exist yet, it's written from tools/village_layout.gd.
##
## Run from the project folder (after build_world.gd and build_buildings.gd):
##   <Godot binary> --headless --path . -s res://tools/build_village.gd
## Add `-- --rewrite-layout` to throw village.tscn away and write it again
## from tools/village_layout.gd (loses edits made in the editor).
##
## This does NOT regenerate the terrain. Heights are only changed near village
## features, computed from the natural land shape (tools/world_shape.gd), so
## re-running gives the same result and your sculpting elsewhere survives.
## It only ever removes vegetation and paints; it never puts trees or grass
## back, so a building moved away leaves a bare patch until you repaint it.
##
## Modifies: res://terrain/data/*, res://terrain/colliders.scn, villagers'
## heights in res://village/village.tscn (written whole if missing)

const VILLAGE := "res://village/village.tscn"
const DATA_DIR := "res://terrain/data"
const COLLIDERS := "res://terrain/colliders.scn"

# Terrain3D mesh ids, as set up in build_world.gd.
enum { GRASS, PINE_A, PINE_B, FERN_A, FERN_B, SHRUB_A, SHRUB_B, ROCK }
const PLANTS := [FERN_A, FERN_B, SHRUB_A, SHRUB_B]

# How far past a road's edge / a building's walls each kind of thing is
# cleared, in metres. Trees need the most room: their branches spread.
const MARGIN := {"grass": 0.6, "plants": 1.5, "big": 3.0, "rock": 4.5}

# Ground shaping, in metres.
const PAD_MARGIN := 1.0   # flat ground around a building's walls
const ROAD_SHOULDER := 1.0  # flat ground either side of a road
const BLEND := 5.0        # distance over which shaped ground eases back into the hills

var terrain: Terrain3D
var shape := WorldShape.new()  # the natural land, before the village
## Pixel (1 m grid) -> [distance from the nearest road's edge (negative = on
## the road), that road's height there]. Only pixels near roads are in here.
var road_info := {}
## [global transform, footprint size, height] for each building.
var buildings: Array = []
## [global transform, size, height, paved] for each plaza.
var plazas: Array = []
## Pixel -> how much its height changed, for moving vegetation with it.
var height_change := {}


func _initialize() -> void:
	if not ResourceLoader.exists(VILLAGE) or "--rewrite-layout" in OS.get_cmdline_user_args():
		print("writing ", VILLAGE, " from tools/village_layout.gd")
		_write_village()

	print("1/5 reading ", VILLAGE)
	var village: Node3D = load(VILLAGE).instantiate()
	root.add_child(village)
	# Nodes added during _initialize join the tree on the next frame; global
	# transforms only work once they're in it.
	await process_frame
	_read_village(village)

	print("2/5 loading terrain")
	terrain = Terrain3D.new()
	terrain.data_directory = DATA_DIR
	terrain.material = load("res://terrain/material.tres")
	terrain.assets = load("res://terrain/assets.tres")
	root.add_child(terrain)
	await process_frame
	await process_frame

	print("3/5 shaping the ground")
	_shape_ground()

	print("4/5 painting roads and plazas")
	_paint()

	print("5/5 clearing vegetation")
	_clear_instances()
	_clear_colliders()
	_place_villagers(village)

	terrain.data.save_directory(DATA_DIR)
	village.queue_free()
	terrain.queue_free()
	print("done")
	quit()


func _write_village() -> void:
	var village: Node3D = load("res://tools/village_layout.gd").new().build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VILLAGE.get_base_dir()))
	_set_owner(village, village)
	var scene := PackedScene.new()
	scene.pack(village)
	var err := ResourceSaver.save(scene, VILLAGE)
	assert(err == OK, "failed to save " + VILLAGE)
	village.free()


# --- Reading the village ----------------------------------------------------------

func _read_village(village: Node) -> void:
	var roads := village.find_children("*", "Road", true, false)
	for road in roads:
		_rasterise_road(road)
	for node in village.find_children("*", "Node3D", true, false):
		if node.has_meta("footprint"):
			buildings.append([node.global_transform, node.get_meta("footprint"), node.global_position.y])
	for plaza: Plaza in village.find_children("*", "Plaza", true, false):
		plazas.append([plaza.global_transform, plaza.size, plaza.global_position.y, plaza.paved])
	print("   roads: %d, plazas: %d, buildings: %d" % [roads.size(), plazas.size(), buildings.size()])


## For every terrain pixel near the road: how far it is from the road's edge,
## and how high the road is at the nearest point. A curve's "baked points" are
## points every half metre along it, heights included.
func _rasterise_road(road: Road) -> void:
	var pts: Array[Vector3] = []
	for p in road.curve.get_baked_points():
		pts.append(road.global_transform * p)
	if pts.size() < 2:
		return
	var reach := road.width / 2.0 + maxf(MARGIN["rock"], ROAD_SHOULDER + BLEND) + 1.0
	var lo := Vector2(pts[0].x, pts[0].z)
	var hi := lo
	for p in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	for x in range(floori(lo.x - reach), ceili(hi.x + reach) + 1):
		for z in range(floori(lo.y - reach), ceili(hi.y + reach) + 1):
			var here := Vector2(x, z)
			var best := INF
			var best_y := 0.0
			for i in pts.size() - 1:
				var a := Vector2(pts[i].x, pts[i].z)
				var b := Vector2(pts[i + 1].x, pts[i + 1].z)
				var closest := Geometry2D.get_closest_point_to_segment(here, a, b)
				var dist := here.distance_to(closest)
				if dist < best:
					best = dist
					var along := 0.0 if a.is_equal_approx(b) else a.distance_to(closest) / a.distance_to(b)
					best_y = lerpf(pts[i].y, pts[i + 1].y, along)
			var edge := best - road.width / 2.0
			if edge < reach:
				var key := Vector2i(x, z)
				if not road_info.has(key) or edge < road_info[key][0]:
					road_info[key] = [edge, best_y]


# --- Shaping the ground -------------------------------------------------------------

## Every village feature wants the ground at some height, fully inside its
## flat area and less and less over the BLEND distance beyond it. Each pixel
## takes the weighted average of what the nearby features want, mixed with
## the natural ground by the strongest feature's weight. Starting from the
## natural ground (not the current terrain) is what makes re-runs repeatable.
func _shape_ground() -> void:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for key in road_info:
		lo = lo.min(Vector2(key))
		hi = hi.max(Vector2(key))
	for area in buildings + plazas:
		var c: Vector3 = area[0].origin
		var r: float = (area[1] as Vector2).length() / 2.0 + PAD_MARGIN + BLEND + 1.0
		lo = lo.min(Vector2(c.x - r, c.z - r))
		hi = hi.max(Vector2(c.x + r, c.z + r))
	var data := terrain.data
	var changed := 0
	for x in range(floori(lo.x), ceili(hi.x) + 1):
		for z in range(floori(lo.y), ceili(hi.y) + 1):
			var key := Vector2i(x, z)
			var wants: Array = []  # [weight, height]
			if road_info.has(key):
				var edge: float = road_info[key][0]
				wants.append([1.0 - smoothstep(ROAD_SHOULDER, ROAD_SHOULDER + BLEND, edge), road_info[key][1]])
			for b in buildings:
				wants.append([_area_weight(b[0], b[1], PAD_MARGIN, x, z), b[2]])
			for p in plazas:
				wants.append([_area_weight(p[0], p[1], 0.0, x, z), p[2]])
			var strongest := 0.0
			var total := 0.0
			var sum := 0.0
			for want in wants:
				strongest = maxf(strongest, want[0])
				total += want[0]
				sum += want[0] * want[1]
			if strongest <= 0.0:
				continue
			var pos := Vector3(x, 0, z)
			var natural := shape.height_at(x, z)
			var target := lerpf(natural, sum / total, strongest)
			# Under a building (and its margin) the floor height wins outright.
			# Averaging it with a road or plaza that ends nearby would tilt the
			# pad, and the ground would poke up through the floorboards.
			for b in buildings:
				if _area_weight(b[0], b[1], PAD_MARGIN, x, z) >= 1.0:
					target = b[2]
			var old := data.get_height(pos)
			if absf(target - old) > 0.001:
				data.set_height(pos, target)
				height_change[key] = target - old
				changed += 1
	data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
	data.calc_height_range(true)
	print("   %d pixels reshaped" % changed)


## 1 inside a rectangular area (plus margin), easing to 0 over BLEND beyond it.
func _area_weight(xform: Transform3D, size: Vector2, margin: float, x: float, z: float) -> float:
	var local := xform.affine_inverse() * Vector3(x, xform.origin.y, z)
	var dx := maxf(absf(local.x) - (size.x / 2.0 + margin), 0.0)
	var dz := maxf(absf(local.z) - (size.y / 2.0 + margin), 0.0)
	return 1.0 - smoothstep(0.0, BLEND, Vector2(dx, dz).length())


func _in_area(xform: Transform3D, size: Vector2, margin: float, p: Vector3) -> bool:
	var local := xform.affine_inverse() * Vector3(p.x, xform.origin.y, p.z)
	return absf(local.x) < size.x / 2.0 + margin and absf(local.z) < size.y / 2.0 + margin


# --- Painting ---------------------------------------------------------------------

## Terrain3D's control map stores, per pixel, two texture ids (base and
## overlay), how much of the overlay shows (blend), and an "auto" flag that
## hands the pixel to the auto-shader (grass on flat ground, rock on slopes).
## Painted pixels switch auto off. Roads: bare dirt in the middle, blending
## into grass over the last metre. Plazas: stone, with a dirt border.
func _paint() -> void:
	var dirt := _texture_id("Dirt")
	var grass := _texture_id("Grass")
	var stone := _texture_id("Rock")
	var data := terrain.data
	for key in road_info:
		var amount := clampf(0.5 - float(road_info[key][0]), 0.0, 1.0)  # 1 on the road, 0 a metre out
		if amount > 0.0:
			_paint_pixel(Vector3(key.x, 0, key.y), grass, dirt, amount)
	for p in plazas:
		if not p[3]:
			continue
		var xform: Transform3D = p[0]
		var size: Vector2 = p[1]
		var r := size.length() / 2.0 + 2.0
		for x in range(floori(xform.origin.x - r), ceili(xform.origin.x + r) + 1):
			for z in range(floori(xform.origin.z - r), ceili(xform.origin.z + r) + 1):
				var pos := Vector3(x, 0, z)
				if _in_area(xform, size, -0.5, pos):
					data.set_control_auto(pos, false)
					data.set_control_base_id(pos, stone)
					data.set_control_overlay_id(pos, stone)
					data.set_control_blend(pos, 0.0)
				elif _in_area(xform, size, 1.0, pos):
					_paint_pixel(pos, grass, dirt, 1.0)  # a worn edge round the paving
	data.update_maps(Terrain3DRegion.TYPE_CONTROL)


## Paint `amount` (0..1) of `top` over `under`, unless the pixel is already
## at least that much `top` (or is paving).
func _paint_pixel(pos: Vector3, under: int, top: int, amount: float) -> void:
	var data := terrain.data
	var current := 0.0
	if not data.get_control_auto(pos):
		if data.get_control_base_id(pos) == top or data.get_control_base_id(pos) == _texture_id("Rock"):
			current = 1.0
		elif data.get_control_overlay_id(pos) == top:
			current = data.get_control_blend(pos)
	if amount <= current:
		return
	data.set_control_auto(pos, false)
	if amount >= 0.999:
		data.set_control_base_id(pos, top)
		data.set_control_overlay_id(pos, top)
		data.set_control_blend(pos, 0.0)
	else:
		data.set_control_base_id(pos, under)
		data.set_control_overlay_id(pos, top)
		data.set_control_blend(pos, amount)


var _texture_ids := {}

func _texture_id(asset_name: String) -> int:
	if _texture_ids.has(asset_name):
		return _texture_ids[asset_name]
	# Read the list from the saved file: once the terrain is running headless,
	# its live copy of the list can be empty.
	var assets: Terrain3DAssets = load("res://terrain/assets.tres")
	for asset in assets.get_texture_list():
		if asset.name == asset_name:
			_texture_ids[asset_name] = asset.id
			return asset.id
	assert(false, "no terrain texture named " + asset_name)
	return -1


# --- Clearing ---------------------------------------------------------------------

## Should something of this kind ("grass", "plants", "big", "rock") at this
## world position be removed?
func _cleared(p: Vector3, kind: String) -> bool:
	var margin: float = MARGIN[kind]
	var key := Vector2i(roundi(p.x), roundi(p.z))
	if road_info.has(key) and road_info[key][0] < margin:
		return true
	for b in buildings:
		if _in_area(b[0], b[1], margin, p):
			return true
	for pl in plazas:
		if _in_area(pl[0], pl[1], margin, p):
			return true
	return false


## How much the ground moved under a point (nearest pixel).
func _lift(p: Vector3) -> float:
	return height_change.get(Vector2i(roundi(p.x), roundi(p.z)), 0.0)


## Instances (the grass, trees and rocks Terrain3D draws in bulk) are stored
## per region (256 x 256 m), then per 32 m cell, as lists of transforms
## relative to the region's corner. Remove the ones in the way; move the rest
## up or down with the ground.
func _clear_instances() -> void:
	var removed := {}
	var moved := 0
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
				var cell_changed := false
				for i in xforms.size():
					var xf: Transform3D = xforms[i]
					var world := corner + xf.origin
					if _cleared(world, kind):
						removed[mesh_id] = removed.get(mesh_id, 0) + 1
						cell_changed = true
						continue
					var lift := _lift(world)
					if lift != 0.0:
						xf.origin.y += lift
						moved += 1
						cell_changed = true
					keep_x.append(xf)
					if i < colours.size():
						keep_c.append(colours[i])
				if cell_changed:
					entry[0] = keep_x
					entry[1] = keep_c
					entry[2] = true
					changed = true
		if changed:
			region.set_instances(instances)
			terrain.data.set_region_modified(loc, true)
	print("   removed: grass %d, plants %d, trees %d, rocks %d; moved with the ground: %d" % [
		removed.get(GRASS, 0),
		removed.get(FERN_A, 0) + removed.get(FERN_B, 0) + removed.get(SHRUB_A, 0) + removed.get(SHRUB_B, 0),
		removed.get(PINE_A, 0) + removed.get(PINE_B, 0), removed.get(ROCK, 0), moved])


## Trees and rocks have invisible collision shapes in a separate scene
## (instanced meshes have none). Remove the ones whose tree was removed; move
## the rest with the ground.
func _clear_colliders() -> void:
	var body: Node = load(COLLIDERS).instantiate()
	var count := 0
	for shape_node: Node3D in body.get_children():
		if _cleared(shape_node.position, "big"):
			body.remove_child(shape_node)
			shape_node.free()
			count += 1
		else:
			shape_node.position.y += _lift(shape_node.position)
	var scene := PackedScene.new()
	scene.pack(body)
	var err := ResourceSaver.save(scene, COLLIDERS)
	assert(err == OK, "failed to save " + COLLIDERS)
	body.free()
	print("   removed %d tree/rock colliders" % count)


## Villagers don't fall (they don't move yet), so put each one's feet on the
## ground where they stand, then save the scene with the new heights. (They
## also snap to the ground when the game starts, as a safety net.)
func _place_villagers(village: Node) -> void:
	var count := 0
	for npc: Node3D in village.find_children("*", "Npc", true, false):
		var p := npc.global_position
		var ground := terrain.data.get_height(p)
		if not is_nan(ground) and absf(ground - p.y) > 0.01:
			npc.global_position.y = ground
			count += 1
	var scene := PackedScene.new()
	scene.pack(village)
	var err := ResourceSaver.save(scene, VILLAGE)
	assert(err == OK, "failed to save " + VILLAGE)
	print("   %d villagers stood on the ground" % count)


func _set_owner(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_set_owner(c, owner_node)
