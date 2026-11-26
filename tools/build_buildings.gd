extends SceneTree
## Builds the village's buildings and fixtures, each written to
## res://buildings/<name>.tscn:
##   cottage_a, cottage_b   one-room cottages (7 x 6), two colour schemes
##   house_a, house_b       family houses (9 x 7): two beds, a dining table
##   church                 stone nave (8 x 16) with a bell tower, pews, altar
##   town_hall              tall timber hall (14 x 9) with a porch and bell turret
##   stall_red/blue/green   market stalls with a canopy and goods on the counter
##   well                   the well for the town square
##
## Run from the project folder (after tools/build_props.gd, which makes the
## furniture and items used inside):
##   <Godot binary> --headless --path . -s res://tools/build_buildings.gd
##
## WARNING: overwrites those files. Place and rotate buildings in
## village/village.tscn rather than editing these.
##
## Lighting check: every building with a floor (not stalls or the well) gets
## a pass at the end (_light_rooms). It samples the floor on a grid, estimates
## how much light each spot gets from all the lights inside, and while any
## spot is darker than MIN_LIGHT, mounts a wall lantern on the wall nearest the
## darkest spot (clear of doors and windows). So a new building can't come out
## pitch dark, and the output lists what each building needed.
##
## Conventions: building-local metres, origin = ground centre, door faces +Z.
## Walls are CSG: boxes added and cut away in tree order, with use_collision on
## (so walls, floors and openings are solid). Each root has a "footprint"
## metadata entry (width, depth in metres) that tools/build_village.gd reads to
## flatten and clear the ground.

const OUT_DIR := "res://buildings"
const LANTERN_MESH := "res://assets/models/wooden_lantern_01/wooden_lantern_01_merged.res"

## Lighting check (see _light_rooms). Brightness is estimated the way Godot
## fades an OmniLight3D: energy / distance, faded smoothly to 0 at its range.
## For scale: a candle (energy 1.6) gives 0.8 at 2 m; a lantern (3.5) gives
## 0.9 at 3.5 m.
const MIN_LIGHT := 0.5          # every sampled spot of floor needs at least this
const SAMPLE_STEP := 1.0        # metres between floor samples
const SAMPLE_HEIGHT := 1.0      # metres above the floor (about table height)
const SCONCE_HEIGHT := 2.3      # metres: above the windows' tops and head height
const SCONCE_ENERGY := 3.0
const SCONCE_RANGE := 9.0       # metres
const MAX_SCONCES := 12         # safety stop

# The building being built and its dimensions (set per building).
var root_node: Node3D
var shell: CSGCombiner3D
var w := 7.0   # width (X)
var d := 6.0   # depth (Z)
var t := 0.3   # wall thickness
var timber: StandardMaterial3D
var openings := []  # [face, along, size] of the current building's doors and windows


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# name -> [plaster, timber, roof]
	_cottage("cottage_a", Color(0.82, 0.8, 0.74), Color(0.22, 0.2, 0.2), Color(0.28, 0.32, 0.38))  # pale, slate roof
	_cottage("cottage_b", Color(0.8, 0.68, 0.48), Color(0.3, 0.2, 0.12), Color(0.5, 0.4, 0.22))    # ochre, thatch-coloured roof
	_house("house_a", Color(0.86, 0.83, 0.76), Color(0.26, 0.17, 0.11), Color(0.42, 0.2, 0.15))    # white, red tile roof
	_house("house_b", Color(0.72, 0.74, 0.7), Color(0.2, 0.18, 0.16), Color(0.33, 0.3, 0.27))      # grey-green, dark roof
	_church()
	_town_hall()
	_stall("stall_red", Color(0.62, 0.18, 0.14), ["apple", "apple", "apple", "bowl", "apple"])
	_stall("stall_blue", Color(0.2, 0.3, 0.55), ["jug", "goblet", "goblet", "plate", "jug"])
	_stall("stall_green", Color(0.27, 0.42, 0.22), ["bowl", "plate", "bowl", "candle", "plate"])
	_well()
	quit()


# --- Homes ----------------------------------------------------------------------------

## One-storey, one-room cottage: bed, table, chest, lantern.
func _cottage(file: String, plaster_color: Color, timber_color: Color, roof_color: Color) -> void:
	_begin(file, 7.0, 6.0, timber_color)
	var plaster := _mat(plaster_color, 0.95)
	var h := 3.3
	_walls(h, plaster)
	_opening("Door", "front", 0.0, 1.2, Vector2(1.4, 2.3))
	var win := Vector2(0.9, 1.0)
	for x in [-2.2, 2.2]:
		_opening("Window", "front", x, 1.6, win)
	_opening("Window", "back", 0.0, 1.6, win)
	_opening("Window", "left", 0.0, 1.6, win)
	_opening("Window", "right", 0.6, 1.6, win)
	_gable_roof(h, 2.2, _mat(roof_color, 0.9))
	_floor_boards()
	# Bed in the back-right corner, headboard (+X) against the right wall.
	_place("res://props/furniture/bed.tscn", Vector3(w / 2 - t - 1.04, 0, -d / 2 + t + 0.55))
	var nightstand := _place("res://props/furniture/nightstand.tscn", Vector3(w / 2 - t - 0.3, 0, -d / 2 + t + 1.45))
	_place("res://props/items/lantern.tscn", nightstand.position + Vector3(0, _top(nightstand) + 0.02, 0))  # lights the windows at night
	var table := _place("res://props/tables/small_table.tscn", Vector3(-w / 2 + t + 0.9, 0, -0.3))
	_place("res://props/items/candle.tscn", table.position + Vector3(0.1, _top(table) + 0.02, 0.05))
	_place("res://props/items/bowl.tscn", table.position + Vector3(-0.15, _top(table) + 0.02, -0.1))
	_place("res://props/furniture/chest.tscn", Vector3(-w / 2 + t + 0.6, 0, -d / 2 + t + 0.45), 90.0)
	_light_rooms(file)
	_finish(file)


## Family house: bigger, with two beds along the back and a dining table.
func _house(file: String, plaster_color: Color, timber_color: Color, roof_color: Color) -> void:
	_begin(file, 9.0, 7.0, timber_color)
	var plaster := _mat(plaster_color, 0.95)
	var h := 3.6
	_walls(h, plaster)
	_opening("Door", "front", -1.2, 1.2, Vector2(1.4, 2.4))
	var win := Vector2(1.0, 1.1)
	for x in [-3.3, 1.4, 3.3]:
		_opening("Window", "front", x, 1.7, win)
	for x in [-2.0, 2.0]:
		_opening("Window", "back", x, 1.7, win)
	_opening("Window", "left", 0.0, 1.7, win)
	_opening("Window", "right", 0.0, 1.7, win)
	_gable_roof(h, 2.6, _mat(roof_color, 0.9))
	_floor_boards()
	for x in [w / 2 - t - 1.04, w / 2 - t - 1.04 - 2.4]:
		_place("res://props/furniture/bed.tscn", Vector3(x, 0, -d / 2 + t + 0.55))
	var table := _place("res://props/furniture/dining_table.tscn", Vector3(-1.6, 0, 0.0))
	for side in [-1, 1]:
		_bench(Vector3(-1.6, 0, side * 1.0), side)
	_place("res://props/items/candle.tscn", table.position + Vector3(0, _top(table) + 0.02, 0))
	_place("res://props/items/jug.tscn", table.position + Vector3(0.35, _top(table) + 0.02, 0.1))
	var cabinet := _place("res://props/furniture/cabinet.tscn", Vector3(-w / 2 + t + 0.5, 0, -d / 2 + t + 0.4), 90.0)
	_place("res://props/items/lantern.tscn", cabinet.position + Vector3(0, 1.22, 0))
	_light_rooms(file)
	_finish(file)


# --- Church -----------------------------------------------------------------------------

## A stone nave with a square bell tower over the door. Inside: rows of pews
## facing an altar at the far (-Z) end.
func _church() -> void:
	_begin("church", 8.0, 16.0, Color(0.3, 0.27, 0.24))
	var stone := _mat(Color(0.62, 0.6, 0.56), 0.95)
	var h := 6.0
	_walls(h, stone, false)  # no timber framing on stone
	# Bell tower: half in front of the nave, door through its base.
	var tower := 3.6
	var tower_z := d / 2 + 0.4
	_csg_box("Tower", Vector3(tower, 12.0, tower), Vector3(0, 6.0, tower_z), stone)
	_csg_box("TowerHollow", Vector3(tower - 0.6, 11.0, tower - 0.6), Vector3(0, 5.3, tower_z), stone, true)
	_csg_box("Door", Vector3(1.8, 3.2, tower + 2.0), Vector3(0, 1.55, tower_z), stone, true)
	openings.append(["front", 0.0, Vector2(1.8, 3.2)])  # cut by hand, so tell the lighting check
	# Belfry openings near the top, through all four sides.
	_csg_box("Belfry", Vector3(0.9, 1.6, tower + 1.0), Vector3(0, 10.3, tower_z), stone, true)
	_csg_box("Belfry", Vector3(tower + 1.0, 1.6, 0.9), Vector3(0, 10.3, tower_z), stone, true)
	var spire := CSGMesh3D.new()
	spire.name = "Spire"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = tower * 0.75
	cone.height = 4.0
	cone.radial_segments = 4  # a four-sided cone = a pyramid
	spire.mesh = cone
	spire.material = _mat(Color(0.25, 0.27, 0.3), 0.85)
	spire.position = Vector3(0, 14.0, tower_z)
	spire.rotation.y = PI / 4
	_add(shell, spire)
	# Tall windows down both sides, a round-ish one over the altar.
	for z in [-4.5, -1.0, 2.5]:
		_opening("Window", "left", z, 3.2, Vector2(0.9, 2.6))
		_opening("Window", "right", z, 3.2, Vector2(0.9, 2.6))
	_opening("Window", "back", 0.0, 4.2, Vector2(1.4, 1.4))
	_gable_roof(h, 3.6, _mat(Color(0.25, 0.27, 0.3), 0.85))
	_floor_boards(_mat(Color(0.48, 0.46, 0.43), 0.9))  # flagstones
	# Pews: two columns of benches, backs towards the door.
	for row in 5:
		for x in [-1.9, 1.9]:
			_bench(Vector3(x, 0, 3.5 - row * 1.6), 1)  # backs towards the door
	var altar := _place("res://props/tables/small_table.tscn", Vector3(0, 0, -d / 2 + t + 1.6))
	for x in [-0.35, 0.35]:
		_place("res://props/items/candlestick.tscn", altar.position + Vector3(x, _top(altar) + 0.02, 0))
	_place("res://props/items/lantern.tscn", altar.position + Vector3(0, _top(altar) + 0.02, 0))
	_light_rooms("church")
	_finish("church", Vector2(w, d + 2.4))  # the tower sticks out at the front


# --- Town hall ------------------------------------------------------------------------

## Tall hall with a covered porch, two banners and a little bell turret on
## the ridge. Inside: a long council table.
func _town_hall() -> void:
	_begin("town_hall", 14.0, 9.0, Color(0.24, 0.16, 0.1))
	var plaster := _mat(Color(0.88, 0.82, 0.66), 0.95)
	var h := 6.5
	_walls(h, plaster)
	_csg_box("Beam", Vector3(w + 0.1, 0.25, 0.12), Vector3(0, 3.3, d / 2 + 0.01), timber)
	_opening("Door", "front", 0.0, 1.5, Vector2(2.2, 3.0))
	for x in [-4.6, -2.6, 2.6, 4.6]:
		_opening("Window", "front", x, 1.8, Vector2(1.0, 1.4))
		_opening("Window", "front", x, 4.9, Vector2(1.0, 1.4))
	_opening("Window", "front", 0.0, 4.9, Vector2(1.4, 1.4))
	for x in [-4.0, 0.0, 4.0]:
		_opening("Window", "back", x, 3.0, Vector2(1.0, 2.0))
	for z in [-2.0, 2.0]:
		_opening("Window", "left", z, 3.0, Vector2(1.0, 2.0))
		_opening("Window", "right", z, 3.0, Vector2(1.0, 2.0))
	var roof_mat := _mat(Color(0.45, 0.18, 0.12), 0.9)
	_gable_roof(h, 3.2, roof_mat)
	# Porch: two posts holding a little roof over the door.
	for x in [-1.8, 1.8]:
		_csg_box("PorchPost", Vector3(0.25, 3.4, 0.25), Vector3(x, 1.7, d / 2 + 1.6), timber)
	_csg_box("PorchRoof", Vector3(4.4, 0.18, 2.2), Vector3(0, 3.45, d / 2 + 0.95), roof_mat)
	# Bell turret on the ridge.
	_csg_box("Turret", Vector3(1.4, 1.6, 1.4), Vector3(0, h + 3.2 + 0.4, 0), timber)
	_csg_box("TurretOpening", Vector3(2.0, 0.9, 0.8), Vector3(0, h + 3.2 + 0.5, 0), timber, true)
	var cap := CSGMesh3D.new()
	cap.name = "TurretCap"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.2
	cone.height = 1.4
	cone.radial_segments = 4
	cap.mesh = cone
	cap.material = roof_mat
	cap.position = Vector3(0, h + 3.2 + 1.9, 0)
	cap.rotation.y = PI / 4
	_add(shell, cap)
	# Banners either side of the door: plain cloth quads, not solid.
	var cloth := _mat(Color(0.55, 0.12, 0.12), 1.0)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	for x in [-3.6, 3.6]:
		var banner := MeshInstance3D.new()
		banner.name = "Banner"
		var quad := QuadMesh.new()
		quad.size = Vector2(0.6, 2.2)
		banner.mesh = quad
		banner.material_override = cloth
		banner.position = Vector3(x, 4.6, d / 2 + 0.2)
		_add(root_node, banner)
	_floor_boards()
	var table := _place("res://props/furniture/dining_table.tscn", Vector3(0, 0, -0.8))
	for side in [-1, 1]:
		_bench(Vector3(0, 0, -0.8 + side * 1.0), side)
	for x in [-0.6, 0.6]:
		_place("res://props/items/candlestick.tscn", table.position + Vector3(x, _top(table) + 0.02, 0))
	for x in [-5.5, 5.5]:
		var cabinet := _place("res://props/furniture/cabinet.tscn", Vector3(x, 0, -d / 2 + t + 0.4))
		_place("res://props/items/lantern.tscn", cabinet.position + Vector3(0, 1.22, 0))
	_light_rooms("town_hall")
	_finish("town_hall", Vector2(w, d + 3.0))  # the porch sticks out at the front


# --- Market and square -------------------------------------------------------------------

## A trader's stall: a counter under a sloping cloth canopy on four posts, with
## goods (ordinary items you can pick up) on the counter. Front = +Z.
func _stall(file: String, canopy_color: Color, goods: Array) -> void:
	_begin(file, 2.6, 1.6, Color(0.35, 0.24, 0.15))
	var wood := _mat(Color(0.42, 0.3, 0.19), 0.9)
	_csg_box("Counter", Vector3(2.4, 0.08, 1.0), Vector3(0, 0.9, 0.1), wood)
	_csg_box("CounterFront", Vector3(2.4, 0.86, 0.06), Vector3(0, 0.45, 0.58), wood)
	for x in [-1.15, 1.15]:
		_csg_box("Post", Vector3(0.1, 2.1, 0.1), Vector3(x, 1.05, 0.7), timber)
		_csg_box("Post", Vector3(0.1, 2.5, 0.1), Vector3(x, 1.25, -0.7), timber)
	var canopy := CSGBox3D.new()
	canopy.name = "Canopy"
	canopy.size = Vector3(2.8, 0.04, 1.9)
	canopy.position = Vector3(0, 2.32, 0.0)
	canopy.rotation.x = 0.2  # slopes down towards the front
	var cloth := _mat(canopy_color, 1.0)
	canopy.material = cloth
	_add(shell, canopy)
	for i in goods.size():
		var x := -0.9 + i * (1.8 / maxf(goods.size() - 1, 1))
		_place("res://props/items/%s.tscn" % goods[i], Vector3(x, 0.96, 0.1 + (0.12 if i % 2 else -0.12)))
	_finish(file)


## The town well: a stone ring with a little roof on two posts.
func _well() -> void:
	_begin("well", 2.6, 2.6, Color(0.3, 0.21, 0.13))
	var stone := _mat(Color(0.55, 0.53, 0.5), 0.95)
	var ring := CSGCylinder3D.new()
	ring.name = "Ring"
	ring.radius = 1.0
	ring.height = 0.9
	ring.sides = 16
	ring.position.y = 0.45
	ring.material = stone
	_add(shell, ring)
	var hole := CSGCylinder3D.new()
	hole.name = "Hole"
	hole.radius = 0.75
	hole.height = 1.2
	hole.sides = 16
	hole.position.y = 0.6
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	_add(shell, hole)
	var water := MeshInstance3D.new()  # dark water a little way down
	water.name = "Water"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.76
	disc.bottom_radius = 0.76
	disc.height = 0.02
	water.mesh = disc
	water.material_override = _mat(Color(0.05, 0.08, 0.1), 0.1)
	water.position.y = 0.25
	_add(root_node, water)
	for x in [-0.9, 0.9]:
		_csg_box("Post", Vector3(0.14, 2.2, 0.14), Vector3(x, 1.1, 0), timber)
	_csg_box("Beam", Vector3(2.1, 0.12, 0.12), Vector3(0, 2.0, 0), timber)
	var roof_mat := _mat(Color(0.42, 0.2, 0.15), 0.9)
	for side in [-1, 1]:
		var plank := CSGBox3D.new()
		plank.name = "Roof"
		plank.size = Vector3(2.4, 0.06, 1.0)
		plank.position = Vector3(0, 2.35, side * 0.42)
		plank.rotation.x = -side * 0.6
		plank.material = roof_mat
		_add(shell, plank)
	_finish("well")


# --- Lighting check ---------------------------------------------------------------------

## Add wall lanterns until every spot of the floor gets at least MIN_LIGHT.
## Treats the interior as one open room (no walls inside to block light), which
## holds for everything this script builds.
func _light_rooms(label: String) -> void:
	var added := 0
	var darkest := _darkest_spot()
	var before: float = darkest[1]
	while darkest[1] < MIN_LIGHT and added < MAX_SCONCES:
		_add_sconce_near(darkest[0])
		added += 1
		darkest = _darkest_spot()
	print("  lighting %-12s darkest spot %.2f -> %.2f, %d wall lantern(s) added%s" % [label, before, darkest[1], added,
		"" if darkest[1] >= MIN_LIGHT else "  WARNING: still below MIN_LIGHT"])


## [position, brightness] of the darkest floor sample.
func _darkest_spot() -> Array:
	var lights := []
	for light in root_node.find_children("*", "OmniLight3D", true, false):  # false: include lights inside instanced props
		lights.append([_local_transform(light).origin, light.light_energy, light.omni_range])
	var worst := [Vector3.ZERO, INF]
	var half := Vector2(w / 2 - t - 0.4, d / 2 - t - 0.4)  # stay off the walls
	var x := -half.x
	while x <= half.x + 0.001:
		var z := -half.y
		while z <= half.y + 0.001:
			var p := Vector3(x, SAMPLE_HEIGHT, z)
			var lit := 0.0
			for l in lights:
				lit += _light_from(l[0], l[1], l[2], p)
			if lit < worst[1]:
				worst = [p, lit]
			z += SAMPLE_STEP
		x += SAMPLE_STEP
	return worst


## Godot's OmniLight3D falloff with the default attenuation of 1: brightness
## falls off as 1 / distance, multiplied by a window that eases it to exactly
## 0 at the light's range.
func _light_from(light_pos: Vector3, energy: float, light_range: float, p: Vector3) -> float:
	var dist := maxf(light_pos.distance_to(p), 0.3)
	var window := maxf(1.0 - pow(dist / light_range, 4.0), 0.0)
	return energy * window * window / dist


## A node's transform relative to the building root. (global_transform only
## works for nodes in the scene tree, and these are built off-tree.)
func _local_transform(node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent and parent != root_node:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


## Mount a lantern on the wall closest to `spot`, slid sideways off any door or
## window on that wall.
func _add_sconce_near(spot: Vector3) -> void:
	var inner := Vector2(w / 2 - t, d / 2 - t)  # inside faces of the walls
	# Distance from the spot to each wall, and the spot's position along it.
	var walls := [
		["front", inner.y - spot.z, spot.x, inner.x],
		["back", spot.z + inner.y, spot.x, inner.x],
		["right", inner.x - spot.x, spot.z, inner.y],
		["left", spot.x + inner.x, spot.z, inner.y],
	]
	walls.sort_custom(func(a, b): return a[1] < b[1])
	var face: String = walls[0][0]
	var limit: float = walls[0][3] - 0.6  # keep out of the corners
	var along := clampf(walls[0][2], -limit, limit)
	# Slide off openings (a couple of passes, in case that lands on the next one).
	for _pass in 3:
		for o in openings:
			var gap: float = o[2].x / 2 + 0.35
			if o[0] == face and absf(along - o[1]) < gap:
				var left_spot: float = o[1] - gap
				var right_spot: float = o[1] + gap
				along = left_spot if absf(along - left_spot) < absf(along - right_spot) else right_spot
		along = clampf(along, -limit, limit)
	# Position on the wall face, and the direction pointing into the room.
	var pos: Vector3
	var inward: Vector3
	match face:
		"front":
			pos = Vector3(along, SCONCE_HEIGHT, inner.y)
			inward = Vector3.FORWARD  # -Z
		"back":
			pos = Vector3(along, SCONCE_HEIGHT, -inner.y)
			inward = Vector3.BACK     # +Z
		"right":
			pos = Vector3(inner.x, SCONCE_HEIGHT, along)
			inward = Vector3.LEFT
		"left":
			pos = Vector3(-inner.x, SCONCE_HEIGHT, along)
			inward = Vector3.RIGHT
	_sconce(pos, inward)


## A lantern on a timber bracket, fixed to the wall at `pos` and sticking out
## along `inward`. Part of the building, not a pickable Item, so the room stays
## lit whatever the player carries off.
func _sconce(pos: Vector3, inward: Vector3) -> void:
	var sconce := Node3D.new()
	sconce.name = "WallLantern"
	sconce.position = pos
	# Turn it so its local +Z (the bracket's length) points into the room.
	# Basis.looking_at aims -Z at a direction, so aim it away from the room.
	sconce.basis = Basis.looking_at(-inward)
	_add(root_node, sconce)
	var bracket := MeshInstance3D.new()
	bracket.name = "Bracket"
	var arm := BoxMesh.new()
	arm.size = Vector3(0.06, 0.06, 0.3)
	arm.material = timber
	bracket.mesh = arm
	bracket.position = Vector3(0, 0, 0.15)
	_add(sconce, bracket)
	var lantern := MeshInstance3D.new()
	lantern.name = "Lantern"
	lantern.mesh = load(LANTERN_MESH)
	lantern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.position = Vector3(0, -0.5, 0.28)  # hangs below the end of the arm
	_add(sconce, lantern)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var drop := SphereMesh.new()
	drop.radius = 0.016
	drop.height = 0.056
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.78, 0.4)
	drop.material = fire
	flame.mesh = drop
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = lantern.position + Vector3(0, 0.14, 0)
	_add(sconce, flame)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.set_script(load("res://lights/flicker.gd"))
	light.light_color = Color(1.0, 0.66, 0.36)
	light.light_energy = SCONCE_ENERGY
	light.omni_range = SCONCE_RANGE
	light.shadow_enabled = false  # cheaper; the item lanterns already cast shadows
	light.position = flame.position + Vector3(0, 0.03, 0)
	_add(sconce, light)


# --- Building blocks ----------------------------------------------------------------------

func _begin(file: String, width: float, depth: float, timber_color: Color) -> void:
	w = width
	d = depth
	timber = _mat(timber_color, 0.9)
	openings = []
	root_node = Node3D.new()
	root_node.name = file.to_pascal_case()
	root_node.editor_description = "Generated by tools/build_buildings.gd (re-running it overwrites this file). Door faces +Z. The 'footprint' metadata (width, depth in metres) tells tools/build_village.gd how much ground to flatten and clear."
	shell = CSGCombiner3D.new()
	shell.name = "Shell"
	shell.use_collision = true
	_add(root_node, shell)


func _finish(file: String, footprint := Vector2.ZERO) -> void:
	# Metadata: arbitrary key/value data stored on any node (Inspector >
	# Metadata). The village tool reads this instead of guessing sizes.
	root_node.set_meta("footprint", footprint if footprint != Vector2.ZERO else Vector2(w, d))
	_pack(root_node, "%s/%s.tscn" % [OUT_DIR, file])
	print("wrote %s/%s.tscn" % [OUT_DIR, file])


## Hollow box walls of height h, with timber corner posts and eave beams.
func _walls(h: float, material: Material, framed := true) -> void:
	_csg_box("Outer", Vector3(w, h, d), Vector3(0, h / 2, 0), material)
	# Hollow from just below the ground to 0.2 below the top (the ceiling).
	_csg_box("Hollow", Vector3(w - 2 * t, h - 0.1, d - 2 * t), Vector3(0, (h - 0.3) / 2, 0), material, true)
	if not framed:
		return
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_csg_box("Post", Vector3(0.3, h, 0.3), Vector3(sx * (w / 2 - 0.1), h / 2, sz * (d / 2 - 0.1)), timber)
	for sz in [-1, 1]:
		_csg_box("Beam", Vector3(w + 0.1, 0.22, 0.12), Vector3(0, h - 0.15, sz * (d / 2 + 0.01)), timber)


## A pitched roof: a triangular prism whose ridge runs front to back.
func _gable_roof(wall_h: float, roof_h: float, material: Material) -> void:
	var roof := CSGMesh3D.new()
	roof.name = "Roof"
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 0.8, roof_h, d + 0.8)
	roof.mesh = prism
	roof.material = material
	roof.position = Vector3(0, wall_h + roof_h / 2 - 0.01, 0)
	_add(shell, roof)


func _floor_boards(material: Material = null) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(w - 2 * t, d - 2 * t)
	plane.material = material if material else _mat(Color(0.45, 0.32, 0.2), 0.85)
	var mi := MeshInstance3D.new()
	mi.name = "FloorBoards"
	mi.mesh = plane
	mi.position.y = 0.01
	_add(root_node, mi)


## A framed opening in one wall. `along` is the position along that wall
## (X for front/back, Z for left/right), `y` the centre height.
func _opening(kind: String, face: String, along: float, y: float, size: Vector2) -> void:
	openings.append([face, along, size])
	var on_x := face == "left" or face == "right"  # wall runs along Z
	var sign := 1.0 if face == "front" or face == "right" else -1.0
	var centre := Vector3(sign * w / 2, y, along) if on_x else Vector3(along, y, sign * d / 2)
	var frame := Vector3(t + 0.12, size.y + 0.16, size.x + 0.16) if on_x else Vector3(size.x + 0.16, size.y + 0.16, t + 0.12)
	var hole := Vector3(t + 0.6, size.y, size.x) if on_x else Vector3(size.x, size.y, t + 0.6)
	if kind == "Door":
		centre.y = size.y / 2 - 0.05  # down to (just below) the ground
		hole.y += 0.1
	_csg_box(kind + "Frame", frame, centre + Vector3(0, 0.03 if kind == "Door" else 0.0, 0), timber)
	_csg_box(kind, hole, centre, timber, true)


func _csg_box(box_name: String, size: Vector3, pos: Vector3, material: Material, subtract := false) -> void:
	var box := CSGBox3D.new()
	box.name = box_name
	box.size = size
	box.position = pos
	box.material = material
	if subtract:
		box.operation = CSGShape3D.OPERATION_SUBTRACTION
	_add(shell, box)


func _place(scene_path: String, pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var node: Node3D = load(scene_path).instantiate()
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)
	_add(root_node, node)
	return node


## A bench with its backrest towards `back` (+1 = +Z, -1 = -Z). The model's
## backrest side is found from its mesh (where the high vertices are), as in
## tools/build_house.gd.
func _bench(pos: Vector3, back: int) -> void:
	var mesh: Mesh = load("res://assets/models/painted_wooden_bench/painted_wooden_bench_merged.res")
	var z_sum := 0.0
	var count := 0
	for surface in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			if v.y > 0.6:
				z_sum += v.z
				count += 1
	var back_is_plus_z: bool = z_sum / maxi(count, 1) > 0.0
	_place("res://props/furniture/bench.tscn", pos, 0.0 if back_is_plus_z == (back > 0) else 180.0)


## Height of a piece of furniture's top surface above its base.
func _top(node: Node3D) -> float:
	var mi := node.get_node_or_null("Mesh") as MeshInstance3D
	if mi:
		return mi.mesh.get_aabb().end.y
	return 0.6


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child, true)  # true = number duplicate names (Window2, Window3...)


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _pack(node: Node, path: String) -> void:
	_set_owner(node, node)
	var scene := PackedScene.new()
	scene.pack(node)
	var err := ResourceSaver.save(scene, path)
	assert(err == OK, "failed to save " + path)
	node.free()


## Every node we created must be "owned" by the root to be saved in the scene.
## Nodes inside instanced scenes (furniture, items) belong to those scenes.
func _set_owner(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_set_owner(c, owner_node)
