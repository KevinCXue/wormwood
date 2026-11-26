extends StaticBody3D
## A pine you can fell with an axe. (The thousands of forest trees are
## Terrain3D instances, which are drawn in bulk and can't react individually;
## these are ordinary nodes, so each one can.)
##
## Each axe hit: the tree shakes, wood chips fly, and a notch is cut into the
## trunk facing you, bigger every hit. The notch is a Decal: a texture
## projected onto whatever surface is inside its box, like a sticker that
## wraps around the trunk. Its texture (made in code, below) is pale fresh
## wood with a dark line where the two cuts meet, so it reads as a cut INTO
## the wood rather than something stuck on. On the last hit it topples
## away from you, speeding up as it falls like a real tree, lies there a
## moment, then sinks away, leaving a stump and a few logs to collect.
## A sword just glances off: a small shake and some bark, no damage.

@export var hits_to_fell := 4
@export var size := 1.0           # overall scale of this tree
@export var variant_b := false    # use the shorter, bushier pine
@export var lie_time := 4.0       # seconds the fallen trunk stays before sinking
@export var wood_color := Color(0.86, 0.71, 0.48)
@export var log_count := 3        # Pine Logs left where the trunk lay (scaled by size)

const LOG_SCENE := preload("res://props/items/log.tscn")

const CUT_HEIGHT := 0.7           # where the notch is cut = stump height; the trunk pivots here as it falls
const STUMP_MESH_HEIGHT := 0.5    # height of the stump mesh in the scene (scaled to CUT_HEIGHT)

static var _notch_texture: ImageTexture  # shared by every tree; built once

@onready var _visual: Node3D = $Visual   # the standing tree; pivots to fall
@onready var _mesh: MeshInstance3D = $Visual/Mesh
@onready var _notch: Decal = $Notch
@onready var _stump: Node3D = $Stump
@onready var _collision: CollisionShape3D = $Collision

var _hits := 0
var _wobble := Vector2.ZERO
var _wobble_vel := Vector2.ZERO
# Falling state
var _falling := false
var _fall_axis := Vector3.RIGHT
var _fall_dir := Vector3.FORWARD  # horizontal direction the top falls towards
var _fall_angle := 0.0
var _fall_speed := 0.0
var _landed_for := -1.0


func _ready() -> void:
	if variant_b:
		_mesh.mesh = load("res://assets/vegetation/pine_b.res")
	_visual.scale = Vector3.ONE * size
	_stump.scale = Vector3(size, CUT_HEIGHT / STUMP_MESH_HEIGHT, size)
	# Shapes and meshes are shared resources between all copies of this scene;
	# duplicate before changing them, or every tree would change together.
	_collision.shape = _collision.shape.duplicate()
	_collision.shape.radius *= size
	_notch.texture_albedo = _get_notch_texture()
	# Collision layer 3 = "hittable": combat.gd looks for targets there.
	set_collision_layer_value(3, true)


## Called by combat.gd. `from` is where the attacker stands, `dir` the swing direction.
func on_hit(weapon: Equipable, from: Vector3, dir: Vector3) -> void:
	if _falling:
		return
	var to_attacker := from - global_position
	to_attacker.y = 0.0
	to_attacker = to_attacker.normalized()
	var bark_point := global_position + Vector3.UP * CUT_HEIGHT + to_attacker * 0.26 * size
	_wobble_vel += Vector2(dir.x, dir.z) * (0.3 if weapon.kind == "axe" else 0.12)

	if weapon.kind != "axe":
		HitFx.burst(self, bark_point, Color(0.3, 0.21, 0.14), to_attacker, 6, 0.03, 2.0)
		return

	_hits += 1
	HitFx.burst(self, bark_point, wood_color, to_attacker, 18, 0.05)
	_cut_notch(to_attacker)
	if _hits >= hits_to_fell:
		_fall(-to_attacker)  # away from whoever chopped it


## Project the notch onto the side facing the attacker, bigger with each hit.
func _cut_notch(to_attacker: Vector3) -> void:
	var depth := float(_hits) / hits_to_fell
	# A decal projects along its own -Y axis, with the texture laid out on its
	# X (across) and Z (up) axes. So: Y points back out at the attacker, Z up.
	var y_axis := to_attacker
	var z_axis := Vector3.UP
	var x_axis := y_axis.cross(z_axis)
	var centre := global_position + Vector3.UP * CUT_HEIGHT + to_attacker * 0.05 * size
	_notch.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), centre)
	# size.y = how deep the projection box reaches: through the front half of
	# the trunk only, so the back of the trunk isn't painted too.
	_notch.size = Vector3((0.32 + 0.2 * depth) * size, 0.5 * size, (0.1 + 0.22 * depth) * size)
	_notch.visible = true


## The notch picture, drawn pixel by pixel: a lens shape (wide in the middle,
## pinched at the sides, like a wedge cut seen from the front), fresh pale
## wood at the rim darkening to a shadowed line at the centre.
static func _get_notch_texture() -> ImageTexture:
	if _notch_texture:
		return _notch_texture
	var w := 128
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var light := Color(0.9, 0.76, 0.54)   # upper cut, facing the sky
	var lower := Color(0.78, 0.62, 0.42)  # lower cut, a bit darker
	var shadow := Color(0.2, 0.13, 0.08)  # deep in the notch
	for py in h:
		for px in w:
			var u := (px + 0.5) / w * 2.0 - 1.0  # -1..1 across the trunk
			var v := (py + 0.5) / h * 2.0 - 1.0  # -1..1 up the trunk
			var half_height := 1.0 - u * u      # the lens outline
			var e := absf(v) / maxf(half_height, 0.001)  # 0 at the centre line, 1 at the rim
			if e >= 1.0:
				continue  # outside the notch: stays transparent
			var wood := light if v > 0.0 else lower
			var col := shadow.lerp(wood, smoothstep(0.0, 0.7, e))
			img.set_pixel(px, py, Color(col, smoothstep(1.0, 0.85, e)))
	img.generate_mipmaps()
	_notch_texture = ImageTexture.create_from_image(img)
	return _notch_texture


func _fall(away: Vector3) -> void:
	_falling = true
	_notch.visible = false  # the cut is now the stump's top
	_stump.visible = true
	# Swap the tall trunk collider for a stump-sized one.
	var stump_shape := CylinderShape3D.new()
	stump_shape.radius = 0.28 * size
	stump_shape.height = CUT_HEIGHT
	_collision.shape = stump_shape
	_collision.position.y = CUT_HEIGHT / 2.0
	# Pivot the falling part at the cut: raise the pivot, lower the mesh.
	_visual.position.y = CUT_HEIGHT
	_mesh.position.y = -CUT_HEIGHT / size
	# Rotating around (UP x away) tips the top of the tree towards `away`.
	_fall_dir = away
	_fall_axis = Vector3.UP.cross(away).normalized()


func _physics_process(delta: float) -> void:
	if not _falling:
		# Shake: the same damped spring as the straw dummy, but stiffer.
		_wobble_vel += (-_wobble * 120.0 - _wobble_vel * 8.0) * delta
		_wobble += _wobble_vel * delta
		var angle := _wobble.length()
		if angle > 0.0001:
			var dir := Vector3(_wobble.x, 0.0, _wobble.y) / angle
			_visual.basis = Basis(Vector3.UP.cross(dir).normalized(), angle) * Basis.from_scale(Vector3.ONE * size)
		return

	if _landed_for < 0.0:
		# Falling: a toppling tree accelerates (gravity has more leverage the
		# further it leans), so increase the spin rate as the angle grows.
		_fall_speed += (0.6 + 3.0 * sin(_fall_angle)) * delta
		_fall_angle += _fall_speed * delta
		if _fall_angle >= PI / 2.0 - 0.04:
			_fall_angle = PI / 2.0 - 0.04
			_landed_for = 0.0
			# A puff of needles where the crown hits the ground.
			var crown := global_position + _fall_dir * 5.0 * size + Vector3.UP * 0.5
			HitFx.burst(self, crown, Color(0.3, 0.42, 0.22), Vector3.UP, 40, 0.08, 3.0)
		_visual.basis = Basis(_fall_axis, _fall_angle) * Basis.from_scale(Vector3.ONE * size)
	else:
		_landed_for += delta
		if _landed_for > lie_time:
			if _landed_for - delta <= lie_time:
				_leave_logs()  # the first frame of sinking
			_visual.position.y -= 0.5 * delta  # sink into the ground...
			if _landed_for > lie_time + 3.0:
				_visual.queue_free()            # ...and it's gone
				set_physics_process(false)


## As the trunk sinks away, leave logs lying along where it fell, with a puff
## of wood chips at each. They're ordinary Items: E puts them in the bag.
func _leave_logs() -> void:
	# The log model lies along X; turn it so X points along the fallen trunk.
	var along := Basis(Vector3.UP, atan2(-_fall_dir.z, _fall_dir.x))
	for i in maxi(1, roundi(log_count * size)):
		var log_item: Item = LOG_SCENE.instantiate()
		get_parent().add_child(log_item)
		# Every 1.3 m from 1.5 m out, a little above the ground so they drop
		# and settle (the trunk lies on uneven ground).
		var pos := global_position + _fall_dir * (1.5 + i * 1.3) + Vector3.UP * 0.6
		log_item.global_transform = Transform3D(along, pos)
		HitFx.burst(self, pos, wood_color, Vector3.UP, 12, 0.03, 1.5)
