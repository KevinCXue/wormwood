extends SceneTree
## Generates the starting landscape: terrain heights, ground textures, grass,
## trees, ferns, shrubs and rocks.
##
## Run from the project folder (it takes about a minute):
##   <Godot binary> --headless --path . -s res://tools/build_world.gd
##
## WARNING: this OVERWRITES res://terrain/, so any sculpting, painting or
## instancing you did in the editor will be lost. Treat it as "make me a fresh
## starting point", then hand-edit in the editor with Terrain3D's tools.
## Afterwards, run tools/build_village.gd to paint the roads back on and clear
## the village's ground again.
##
## `extends SceneTree` with `-s` runs this as the whole program, with no main
## scene. _initialize() is our entry point, like main().
##
## Outputs:
##   res://terrain/data/         height/texture/instance data (Terrain3D regions)
##   res://terrain/assets.tres   texture + mesh list used by Terrain3D
##   res://terrain/material.tres terrain shader settings (auto-shader etc.)
##   res://terrain/colliders.scn   collision for trees and rocks
##   res://assets/vegetation/*   generated grass and pine meshes
##   res://assets/models/*/*_x.tscn  single-variant scenes cut from Poly Haven sets

const SEED := WorldShape.SEED
const WORLD_HALF := 256       # terrain spans -256..256 m on X and Z
const CLEARING_RADIUS := WorldShape.CLEARING_RADIUS
const TERRAIN_DIR := "res://terrain"
const DATA_DIR := "res://terrain/data"
const VEG_DIR := "res://assets/vegetation"

# Mesh asset ids, i.e. slots in Terrain3D's mesh list.
enum { GRASS, PINE_A, PINE_B, FERN_A, FERN_B, SHRUB_A, SHRUB_B, ROCK }

# Areas to keep clear of vegetation, as Rect2(x, z, width, depth) in world space.
const KEEP_CLEAR := [
	Rect2(-16.8, -14.3, 11.6, 9.6),  # house (at -11, -9.5; 10x8, plus margin)
	Rect2(-2.0, -2.0, 4.0, 4.0),    # player spawn
	# Tables from props/village_props.tscn (grass would poke through the tops).
	Rect2(-7.5, 1.0, 4.0, 4.0),     # picnic table
	Rect2(1.8, 2.6, 3.4, 2.8),      # market table
	Rect2(-13.5, -2.4, 1.8, 1.6),   # small table by the door
	Rect2(0.0, -11.9, 3.0, 1.8),    # weapons table (props/weapons_table.tscn, at 1.5, -11)
]

var rng := RandomNumberGenerator.new()
var shape := WorldShape.new()  # the land's heights (tools/world_shape.gd)
var forest := FastNoiseLite.new()
var meadow := FastNoiseLite.new()
var terrain: Terrain3D
var colliders: StaticBody3D  # trees and rocks need collision; instancer meshes have none


func _initialize() -> void:
	rng.seed = SEED
	_setup_noise()

	print("1/6 building meshes")
	var mesh_assets := _make_mesh_assets()

	print("2/6 creating terrain")
	terrain = Terrain3D.new()
	_reset_dir(DATA_DIR)
	terrain.data_directory = DATA_DIR
	root.add_child(terrain)
	# Terrain3D finishes initialising on the next frame; `await` pauses this
	# function until the SceneTree emits process_frame, then carries on.
	await process_frame
	terrain.material = _make_material()
	terrain.assets = Terrain3DAssets.new()
	var textures := [
		_texture_asset("Grass", "leafy_grass", 0.15),
		_texture_asset("Rock", "rock_face_03", 0.06),
		_texture_asset("Dirt", "forest_ground_04", 0.15),
	]
	for i in textures.size():
		terrain.assets.set_texture_asset(i, textures[i])
	for i in mesh_assets.size():
		terrain.assets.set_mesh_asset(i, mesh_assets[i])
	await process_frame
	_configure_shader_params(terrain.material)

	print("3/6 sculpting heights")
	_import_heights()

	print("4/6 scattering vegetation")
	colliders = StaticBody3D.new()
	colliders.name = "VegetationColliders"
	_scatter_grass()
	_scatter_trees()
	_scatter_small_plants()
	_scatter_rocks()

	print("5/6 saving terrain")
	terrain.data.save_directory(DATA_DIR)
	_save(terrain.material, TERRAIN_DIR + "/material.tres")
	_save(terrain.assets, TERRAIN_DIR + "/assets.tres")

	print("6/6 saving colliders (%d shapes)" % colliders.get_child_count())
	for c in colliders.get_children():
		c.owner = colliders  # only nodes "owned" by the root get packed into a scene
	var scene := PackedScene.new()
	scene.pack(colliders)
	_save(scene, TERRAIN_DIR + "/colliders.scn")  # binary: ~2000 shapes

	colliders.free()
	terrain.queue_free()
	print("done")
	quit()


# --- Heights ------------------------------------------------------------------

func _setup_noise() -> void:
	# FastNoiseLite gives smooth pseudo-random values in -1..1. (The height
	# noise lives in tools/world_shape.gd.)
	forest.seed = SEED + 3
	forest.frequency = 0.012
	meadow.seed = SEED + 4
	meadow.frequency = 0.03


## Height of the ground at a world position, in metres (tools/world_shape.gd).
func height_at(x: float, z: float) -> float:
	return shape.height_at(x, z)


func _import_heights() -> void:
	# One pixel per metre. FORMAT_RF = one 32-bit float per pixel: the height.
	var size := WORLD_HALF * 2
	var img := Image.create_empty(size, size, false, Image.FORMAT_RF)
	for pz in size:
		for px in size:
			img.set_pixel(px, pz, Color(height_at(px - WORLD_HALF, pz - WORLD_HALF), 0, 0, 1))
	# [height, control (texture painting), color]. null = defaults, which
	# means the auto-shader picks grass/rock by slope everywhere.
	terrain.data.import_images([img, null, null], Vector3(-WORLD_HALF, 0, -WORLD_HALF), 0.0, 1.0)


# --- Terrain material and textures --------------------------------------------

func _make_material() -> Terrain3DMaterial:
	var mat := Terrain3DMaterial.new()
	mat.show_checkered = false
	mat.world_background = Terrain3DMaterial.FLAT  # flat ground beyond the edges
	# Auto-shader: picks grass or rock by slope (configured in _configure_shader_params).
	mat.auto_shader_enabled = true
	# Large-scale colour variation so the grass doesn't look like one repeating tile.
	mat.macro_variation_enabled = true
	return mat


## Shader parameters only exist once the terrain has compiled its shader, so
## this runs after the terrain is in the tree (see _initialize).
func _configure_shader_params(mat: Terrain3DMaterial) -> void:
	mat.set_shader_param("auto_slope", 2.0)          # higher = rock appears on gentler slopes
	mat.set_shader_param("auto_height_reduction", 0.05)  # more rock higher up
	# Terrain3D's auto-shader puts the OVERLAY texture on flat ground and the
	# BASE texture on slopes (see auto_blend in its shader).
	mat.set_shader_param("auto_base_texture", 1)     # rock on slopes
	mat.set_shader_param("auto_overlay_texture", 0)  # grass on flat ground
	mat.set_shader_param("blend_sharpness", 0.9)


func _texture_asset(asset_name: String, id: String, uv_scale: float) -> Terrain3DTextureAsset:
	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = load("res://assets/textures/terrain/%s_alb_ht.png" % id)
	ta.normal_texture = load("res://assets/textures/terrain/%s_nrm_rgh.png" % id)
	ta.uv_scale = uv_scale            # repeats per metre; 0.15 = one tile per ~6.7 m
	ta.detiling_rotation = 0.15       # randomly rotate tiles to hide repetition
	return ta


# --- Meshes -------------------------------------------------------------------

func _make_mesh_assets() -> Array[Terrain3DMeshAsset]:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VEG_DIR))
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load(VEG_DIR + "/grass_wind.gdshader")
	_save(grass_mat, VEG_DIR + "/grass_material.tres")

	var assets: Array[Terrain3DMeshAsset] = []
	assets.resize(ROCK + 1)
	# (name, scene, visible range in metres, casts shadows)
	assets[GRASS] = _mesh_asset("Grass", _mesh_scene(_make_grass_clump(grass_mat), "grass_clump"), 45.0, false)
	assets[PINE_A] = _mesh_asset("Pine A", _mesh_scene(_make_pine(11, 9.0), "pine_a"), 450.0, true)
	assets[PINE_B] = _mesh_asset("Pine B", _mesh_scene(_make_pine(23, 7.0), "pine_b"), 450.0, true)
	assets[FERN_A] = _mesh_asset("Fern A", _variant_scene("fern_02", "fern_02_b"), 50.0, false)
	assets[FERN_B] = _mesh_asset("Fern B", _variant_scene("fern_02", "fern_02_c"), 50.0, false)
	assets[SHRUB_A] = _mesh_asset("Shrub A", _variant_scene("shrub_03", "shrub_03_a"), 40.0, false)
	assets[SHRUB_B] = _mesh_asset("Shrub B", _variant_scene("shrub_03", "shrub_03_b"), 40.0, false)
	assets[ROCK] = _mesh_asset("Rock", _variant_scene("rock_07", "rock_07"), 250.0, true)
	return assets


func _mesh_asset(asset_name: String, scene: PackedScene, visible_range: float, shadows: bool) -> Terrain3DMeshAsset:
	var ma := Terrain3DMeshAsset.new()
	ma.name = asset_name
	ma.scene_file = scene
	ma.lod0_range = visible_range
	ma.fade_margin = visible_range * 0.15  # fade out instead of popping
	ma.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_ON if shadows else RenderingServer.SHADOW_CASTING_SETTING_OFF
	return ma


## Wrap a mesh in a one-node scene, because Terrain3D mesh assets take scenes.
func _mesh_scene(mesh: Mesh, file_name: String) -> PackedScene:
	_save(mesh, "%s/%s.res" % [VEG_DIR, file_name])  # .res = binary, compact for big meshes
	return _pack_mesh_instance(mesh, "%s/%s.tscn" % [VEG_DIR, file_name], file_name)


## Poly Haven files hold several variants side by side. Terrain3D would read
## several meshes in one scene as LOD levels, so cut out a single variant.
func _variant_scene(model: String, variant: String) -> PackedScene:
	var src: Node = load("res://assets/models/%s/%s.gltf" % [model, model]).instantiate()
	var mi := src.find_child(variant) as MeshInstance3D
	var mesh := mi.mesh.duplicate() as Mesh  # copy, so it can be saved on its own
	src.free()
	_save(mesh, "res://assets/models/%s/%s.res" % [model, variant])
	return _pack_mesh_instance(load("res://assets/models/%s/%s.res" % [model, variant]),
		"res://assets/models/%s/%s.tscn" % [model, variant], variant)


func _pack_mesh_instance(mesh: Mesh, path: String, node_name: String) -> PackedScene:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = load(mesh.resource_path) if mesh.resource_path != "" else mesh
	var scene := PackedScene.new()
	scene.pack(mi)
	mi.free()
	_save(scene, path)
	return load(path)


## A clump of ~14 curved grass blades, ~0.3-0.7 m tall. UV.y = height along
## the blade (the wind shader uses it).
func _make_grass_clump(mat: Material) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 4
	for b in 14:
		var base := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		var height := rng.randf_range(0.3, 0.7)
		var width := rng.randf_range(0.03, 0.05)
		var facing := rng.randf() * TAU
		var side := Vector3(cos(facing), 0.0, sin(facing))    # blade's width direction
		var lean := Vector3(-side.z, 0.0, side.x) * rng.randf_range(0.1, 0.3)  # bends forward
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for s in SEGMENTS + 1:
			var t := float(s) / SEGMENTS
			var centre := base + Vector3(0.0, t * height, 0.0) + lean * height * t * t
			var half_w := width * (1.0 - t)  # tapers to a point
			var l := centre - side * half_w
			var r := centre + side * half_w
			if s > 0:
				var t0 := float(s - 1) / SEGMENTS
				_quad(st, prev_l, prev_r, r, l, t0, t)
			prev_l = l
			prev_r = r
	st.generate_normals()  # overwritten by the shader, but keeps the mesh valid
	st.set_material(mat)
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, v0: float, v1: float) -> void:
	for p in [[a, v0], [b, v0], [c, v1], [a, v0], [c, v1], [d, v1]]:
		st.set_uv(Vector2(0.0, p[1]))
		st.add_vertex(p[0])


## Stand-in conifer: a tapered trunk with stacked, star-shaped cones of
## "branches". Two surfaces (trunk + needles) with their own materials.
func _make_pine(seed_value: int, height: float) -> Mesh:
	var prng := RandomNumberGenerator.new()
	prng.seed = seed_value
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.28, 0.19, 0.13)
	bark.roughness = 1.0
	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.17, 0.29, 0.15)
	needles.roughness = 0.95
	needles.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := ArrayMesh.new()
	# Trunk: a CylinderMesh is a ready-made primitive; we copy its arrays in.
	var trunk := CylinderMesh.new()
	trunk.top_radius = height * 0.012
	trunk.bottom_radius = height * 0.03
	trunk.height = height * 0.9
	trunk.radial_segments = 8
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, trunk.height / 2.0, 0)))
	st.set_material(bark)
	st.commit(mesh)

	# Needles: 5 tiers, each a jagged cone, smaller towards the top.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const TIERS := 5
	const SIDES := 14
	for tier in TIERS:
		var f := float(tier) / TIERS
		# Lowest branches start ~1/3 up: real pines are bare near the base, and
		# it keeps your head out of the needles when you walk up to chop one.
		var y0 := height * (0.32 + f * 0.52)
		var tier_h := height * (0.36 - f * 0.1)
		var radius := height * (0.27 - f * 0.2)
		var apex := Vector3(prng.randf_range(-0.1, 0.1), y0 + tier_h, prng.randf_range(-0.1, 0.1))
		var inner := Vector3(0, y0 + tier_h * 0.2, 0)  # underside rises: branches droop
		var ring: Array[Vector3] = []
		for i in SIDES:
			var a := TAU * i / SIDES + prng.randf_range(-0.1, 0.1)
			var r := radius * (1.0 if i % 2 == 0 else 0.72) * prng.randf_range(0.85, 1.1)
			ring.append(Vector3(cos(a) * r, y0 - prng.randf_range(0.0, 0.25), sin(a) * r))
		for i in SIDES:
			var p := ring[i]
			var q := ring[(i + 1) % SIDES]
			st.add_vertex(p); st.add_vertex(apex); st.add_vertex(q)   # top
			st.add_vertex(q); st.add_vertex(inner); st.add_vertex(p)  # underside
	st.generate_normals()
	st.set_material(needles)
	st.commit(mesh)
	return mesh


# --- Scattering ---------------------------------------------------------------

func _blocked(x: float, z: float) -> bool:
	for rect in KEEP_CLEAR:
		if rect.has_point(Vector2(x, z)):
			return true
	return false


## Ground point + whether its slope is gentle enough (normal.y = cos(slope)).
func _ground(x: float, z: float, max_slope_deg: float) -> Variant:
	var pos := Vector3(x, 0.0, z)
	pos.y = terrain.data.get_height(pos)
	if is_nan(pos.y):
		return null
	if terrain.data.get_normal(pos).y < cos(deg_to_rad(max_slope_deg)):
		return null
	return pos


func _xform(pos: Vector3, scale: float, tilt: float = 0.0) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU)  # random spin around Y
	if tilt > 0.0:
		basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0, tilt)) * basis
	return Transform3D(basis.scaled(Vector3.ONE * scale), pos)


func _scatter_grass() -> void:
	# A jittered grid within 120 m of the middle, thinned by a "meadow" noise
	# so there are dense meadows and sparser patches.
	var xforms: Array[Transform3D] = []
	var spacing := 0.6
	var limit := 120.0
	var n := int(limit / spacing)
	for gx in range(-n, n):
		for gz in range(-n, n):
			var x := gx * spacing + rng.randf_range(-0.3, 0.3)
			var z := gz * spacing + rng.randf_range(-0.3, 0.3)
			if Vector2(x, z).length() > limit or _blocked(x, z):
				continue
			var keep := 0.45 + 0.55 * (meadow.get_noise_2d(x, z) * 0.5 + 0.5)
			# The village clearing is trampled: sparse, short grass so items
			# and paths stay visible. Ramps up to full meadow by ~45 m out.
			var wild := smoothstep(12.0, 45.0, Vector2(x, z).length())
			keep *= lerpf(0.2, 1.0, wild)
			if rng.randf() > keep:
				continue
			var p = _ground(x, z, 30.0)
			if p != null:
				var height := rng.randf_range(0.7, 1.3) * lerpf(0.6, 1.0, wild)
				xforms.append(_xform(p, height))
	terrain.instancer.add_transforms(GRASS, xforms)
	print("   grass clumps: ", xforms.size())


## Is there a forest here? Forests are noise blobs, absent in the clearing
## and thinning out up the mountains.
func _forest_density(x: float, z: float, y: float) -> float:
	var r := Vector2(x, z).length()
	var d := smoothstep(0.0, 0.35, forest.get_noise_2d(x, z) + 0.1)
	d *= smoothstep(CLEARING_RADIUS + 5.0, CLEARING_RADIUS + 25.0, r)
	d *= 1.0 - smoothstep(45.0, 75.0, y)  # treeline
	return d


func _scatter_trees() -> void:
	var placed: Array[Vector2] = []
	var cell := {}  # spatial hash: Vector2i -> positions, for fast spacing checks
	var xforms_a: Array[Transform3D] = []
	var xforms_b: Array[Transform3D] = []
	for i in 40000:
		var x := rng.randf_range(-WORLD_HALF + 4, WORLD_HALF - 4)
		var z := rng.randf_range(-WORLD_HALF + 4, WORLD_HALF - 4)
		if _blocked(x, z):
			continue
		var p = _ground(x, z, 28.0)
		if p == null:
			continue
		var density := _forest_density(x, z, p.y)
		# A few lone trees outside forests too, but never in the clearing.
		var outside_clearing := smoothstep(CLEARING_RADIUS + 2.0, CLEARING_RADIUS + 12.0, Vector2(x, z).length())
		if rng.randf() > max(density, 0.04 * outside_clearing):
			continue
		if _too_close(Vector2(x, z), cell, 3.2):
			continue
		var key := Vector2i(floori(x / 4.0), floori(z / 4.0))
		cell[key] = cell.get(key, []) + [Vector2(x, z)]
		var s := rng.randf_range(0.75, 1.5)
		var xf := _xform(p - Vector3(0, 0.2, 0), s, 0.06)
		var tall := rng.randf() < 0.55
		(xforms_a if tall else xforms_b).append(xf)
		var trunk_h := (9.0 if tall else 7.0) * 0.9 * s
		var shape := CylinderShape3D.new()
		shape.radius = (9.0 if tall else 7.0) * 0.03 * s + 0.1
		shape.height = trunk_h
		_add_collider(shape, Transform3D(Basis(), p + Vector3(0, trunk_h / 2.0, 0)))
	terrain.instancer.add_transforms(PINE_A, xforms_a)
	terrain.instancer.add_transforms(PINE_B, xforms_b)
	print("   trees: ", xforms_a.size() + xforms_b.size())


func _too_close(p: Vector2, cell: Dictionary, min_dist: float) -> bool:
	var key := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q in cell.get(key + Vector2i(dx, dz), []):
				if p.distance_to(q) < min_dist:
					return true
	return false


func _scatter_small_plants() -> void:
	var lists := {FERN_A: [], FERN_B: [], SHRUB_A: [], SHRUB_B: []}
	for i in 60000:
		var x := rng.randf_range(-150, 150)
		var z := rng.randf_range(-150, 150)
		if _blocked(x, z):
			continue
		var p = _ground(x, z, 32.0)
		if p == null:
			continue
		var density := _forest_density(x, z, p.y)
		if density > 0.3 and rng.randf() < 0.06 * density:
			# Ferns live in the forests.
			lists[FERN_A if rng.randf() < 0.5 else FERN_B].append(_xform(p, rng.randf_range(0.9, 1.6)))
		elif density < 0.2 and rng.randf() < 0.012:
			# Small flowering shrubs dot the open meadows (scaled up a bit).
			lists[SHRUB_A if rng.randf() < 0.5 else SHRUB_B].append(_xform(p, rng.randf_range(1.6, 2.6)))
	for id in lists:
		var xforms: Array[Transform3D] = []
		xforms.assign(lists[id])
		terrain.instancer.add_transforms(id, xforms)
	print("   ferns: ", lists[FERN_A].size() + lists[FERN_B].size(), "  shrubs: ", lists[SHRUB_A].size() + lists[SHRUB_B].size())


func _scatter_rocks() -> void:
	# rock_07 is a 32 cm stone; scaled 7-18x it reads as a boulder.
	var rock_aabb: AABB = (load("res://assets/models/rock_07/rock_07.res") as Mesh).get_aabb()
	var xforms: Array[Transform3D] = []
	var tries := 0
	while xforms.size() < 140 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-WORLD_HALF + 8, WORLD_HALF - 8)
		var z := rng.randf_range(-WORLD_HALF + 8, WORLD_HALF - 8)
		if _blocked(x, z) or Vector2(x, z).length() < CLEARING_RADIUS - 6.0:
			continue
		var p = _ground(x, z, 40.0)
		if p == null:
			continue
		var s := rng.randf_range(7.0, 18.0)
		var xf := _xform(p - Vector3(0, 0.25 * s * rock_aabb.size.y, 0), s, 0.4)  # sink into the ground
		xforms.append(xf)
		var shape := BoxShape3D.new()
		shape.size = rock_aabb.size * s * 0.85
		_add_collider(shape, xf.orthonormalized().translated_local(rock_aabb.get_center() * s))
	terrain.instancer.add_transforms(ROCK, xforms)
	print("   rocks: ", xforms.size())


func _add_collider(shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	colliders.add_child(cs)


# --- Helpers ------------------------------------------------------------------

func _save(res: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "failed to save %s: %s" % [path, error_string(err)])
	res.take_over_path(path)


func _reset_dir(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path)
	for f in DirAccess.get_files_at(abs_path):
		if f.begins_with("terrain3d") and f.ends_with(".res"):
			DirAccess.remove_absolute(abs_path.path_join(f))
