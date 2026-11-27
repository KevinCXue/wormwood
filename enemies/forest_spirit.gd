extends CharacterBody3D
## A forest spirit: a hunched, legless shape of black wood that hovers over
## the ground trailing smoke, with a crown of antler-like branches, pale
## glowing eyes and long branch arms ending in twig claws. It is hostile on
## sight: it rises out of the ground, comes straight for the player and
## whips them with an arm (`damage`, 18 by default).
##
## Summoned by places/spirit_ambush.gd (outside the mushroom cave); the
## console's `spirit` command spawns one in front of you for testing.
##
## Everything you see is built in code in _build() from tapered cylinders,
## like the blocky mannequin, and animated in _process() by turning pivot
## nodes (shoulders, elbows) towards target poses. Its skin is a shader
## (forest_spirit.gdshader): edge glow, writhing, and a "dissolve" for its
## smoky tail and for crumbling away when it dies.
##
## It's a ghost, so it doesn't collide: it glides through trees and rocks,
## following the terrain's height (no pathfinding needed). It's only on the
## "hittable" physics layer, so swings find it (combat.gd) but nothing
## bumps into it.

signal died

enum State { RISE, CHASE, ATTACK, WAIT, DEAD }

@export var display_name := "Forest Spirit"
@export var max_health := 50
@export var damage := 18              # hit points per branch whip
@export var chase_speed := 6.5        # metres per second (you can outrun it at a sprint)
@export var attack_reach := 1.8       # metres: how close it comes to whip (inside sword range)
@export var windup_time := 0.45       # seconds: the arm draws back (your cue to back off)
@export var whip_time := 0.2          # seconds: the lash
@export var recover_time := 0.55      # seconds before it can move again
@export var attack_cooldown := 0.5    # seconds after recovering before the next whip
@export var hover_height := 0.55      # metres above the ground
@export var rise_time := 2.2          # seconds to climb out of the ground
@export var wake_distance := 30.0     # metres: closer than this and it hunts you
@export var leash_distance := 70.0    # metres from home: beyond this it drifts back
@export var turn_speed := 7.0
@export var glow_color := Color(0.45, 0.95, 0.55)

## Where it waits when it loses you. Set by whoever spawns it.
var home := Vector3.ZERO
var health: Health

var _state := State.RISE
var _player: Node3D = null
var _terrain: Node = null
var _t := 0.0            # seconds alive, drives idle motion
var _state_t := 0.0      # seconds in the current state
var _cooldown := 0.0
var _struck := false     # this whip has already landed (or missed)
var _arm := 0            # which arm whips next: 0 right, 1 left
var _flinch := 0.0       # 1 just hit, decays to 0
var _speed := 0.0        # current horizontal speed, for the lean

var _model: Node3D       # turns to face where it's going
var _body: Node3D        # bobs, leans, rises
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _bark: ShaderMaterial
var _tail_mat: ShaderMaterial
var _light: OmniLight3D
var _smoke: CPUParticles3D
var _eye_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

const RIGHT := 0
const LEFT := 1
const SELF_LAYER := 1 << 2  # render layer 3: the spirit's own meshes


func _init() -> void:
	# Placed in world space whatever its parent is. Set here, when the node is
	# created, so a position given before it's added is already world space.
	top_level = true


func _ready() -> void:
	add_to_group("spirits")
	collision_layer = 1 << 2   # "hittable" only: combat finds it, nothing bumps it
	collision_mask = 0
	health = Health.new()
	health.name = "Health"
	add_child(health)
	health.reset(max_health)
	health.died.connect(func(_attacker): _die())
	if home == Vector3.ZERO:
		home = global_position
	_build()
	_body.position.y = -2.6  # starts underground; RISE brings it up
	_terrain = get_tree().current_scene.find_child("Terrain3D", false, false) if get_tree().current_scene else null
	global_position.y = _ground_y(global_position)
	HitFx.burst(self, global_position + Vector3.UP * 0.2, Color(0.04, 0.05, 0.04), Vector3.UP, 40, 0.06, 3.0)


func is_dead() -> bool:
	return _state == State.DEAD


func is_hostile() -> bool:
	return not is_dead()


# --- Being hit -----------------------------------------------------------------------

## The hittable contract (see combat.gd).
func on_hit(weapon: Equipable, _from: Vector3, dir: Vector3, attacker: Node3D = null) -> void:
	if is_dead():
		return
	health.damage(Health.damage_from(weapon), attacker)
	if attacker and attacker.is_in_group("player"):
		attacker.get_node("HUD").show_target(display_name, health)
	var chest := global_position + Vector3.UP * (hover_height + 1.4)
	HitFx.burst(self, chest, Color(0.05, 0.04, 0.03), dir, 18, 0.05, 3.0)  # splinters
	HitFx.burst(self, chest, glow_color, dir, 8, 0.02, 2.0)                # sparks
	_flinch = 1.0
	if _state == State.WAIT or _state == State.RISE and _state_t > rise_time * 0.5:
		_set_state(State.CHASE)


func _die() -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	_smoke.emitting = false
	HitFx.burst(self, global_position + Vector3.UP * 1.5, Color(0.04, 0.04, 0.03), Vector3.UP, 60, 0.07, 4.0)
	HitFx.burst(self, global_position + Vector3.UP * 1.5, glow_color, Vector3.UP, 24, 0.025, 3.0)
	died.emit()


# --- Behaviour (physics frames) -------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	_state_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	match _state:
		State.RISE:
			if _state_t >= rise_time:
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_attack(delta)
		State.WAIT:
			_wait(delta)
		State.DEAD:
			if _state_t > 2.5:
				queue_free()


func _set_state(s: State) -> void:
	_state = s
	_state_t = 0.0


## Is there a player it can go after? Not dead, not on the title screen or
## in a conversation (`locked`), and not too far from its home.
func _prey() -> Node3D:
	if _player == null or _player.get("locked") or _player.get_node("Health").is_dead():
		return null
	if _player.global_position.distance_to(home) > leash_distance:
		return null
	return _player


func _chase(delta: float) -> void:
	var prey := _prey()
	if prey == null:
		_set_state(State.WAIT)
		return
	var to := _flat(prey.global_position - global_position)
	if to.length() <= attack_reach:
		# Nothing stops a ghost gliding into you, so it keeps a little room.
		_glide(-to.normalized() * 1.5 if to.length() < 1.0 else Vector3.ZERO, delta)
		_face(to, delta)
		if _cooldown <= 0.0:
			_struck = false
			_set_state(State.ATTACK)
	else:
		_glide(to.normalized() * chase_speed, delta)
		_face(to, delta)


## Windup, whip, recover. The hit is checked once, partway through the whip.
func _attack(delta: float) -> void:
	var prey := _prey()
	var lunge := Vector3.ZERO
	if prey:
		var to := _flat(prey.global_position - global_position)
		if _state_t < windup_time:
			_face(to, delta)  # it tracks you while it winds up, then commits
		elif _state_t < windup_time + whip_time and to.length() > 1.2:
			lunge = -_model.global_basis.z * 2.0  # a little lunge into the lash
	_glide(lunge, delta)
	if not _struck and _state_t >= windup_time + whip_time * 0.5:
		_struck = true
		_try_hit(prey)
	if _state_t >= windup_time + whip_time + recover_time:
		_arm = 1 - _arm
		_cooldown = attack_cooldown
		_set_state(State.CHASE)


func _try_hit(prey: Node3D) -> void:
	if prey == null:
		return
	var to := _flat(prey.global_position - global_position)
	var facing := -_model.global_basis.z
	if to.length() <= attack_reach + 0.5 and facing.dot(to.normalized()) > 0.2:
		prey.on_hit(null, global_position, to.normalized(), self, damage)


## Lost its prey: drift home and hover there until someone comes close.
func _wait(delta: float) -> void:
	var to_home := _flat(home - global_position)
	_glide(to_home.normalized() * 2.0 if to_home.length() > 1.0 else Vector3.ZERO, delta)
	if to_home.length() > 1.0:
		_face(to_home, delta)
	var prey := _prey()
	if prey and prey.global_position.distance_to(global_position) < wake_distance:
		_set_state(State.CHASE)


## Move horizontally, ignoring obstacles, and settle onto the ground's height.
func _glide(horizontal: Vector3, delta: float) -> void:
	var pos := global_position + horizontal * delta
	pos.y = lerpf(global_position.y, _ground_y(pos), 1.0 - exp(-10.0 * delta))
	global_position = pos
	_speed = horizontal.length()


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-turn_speed * delta))


## The terrain's height here (Terrain3D answers directly, no physics needed).
func _ground_y(pos: Vector3) -> float:
	if _terrain and _terrain.get("data"):
		var h: float = _terrain.data.get_height(pos)
		if not is_nan(h):
			return h
	return pos.y


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Animation (render frames) --------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_flinch = maxf(_flinch - delta * 3.0, 0.0)
	var k := 1.0 - exp(-9.0 * delta)

	# Body: rise out of the ground, bob, lean into the chase, recoil when hit.
	var rise := 1.0
	if _state == State.RISE:
		rise = ease(clampf(_state_t / rise_time, 0.0, 1.0), 0.4)  # fast, then slowing
	var sink := 0.0
	if _state == State.DEAD:
		sink = _state_t * 0.4
	_body.position.y = lerpf(-2.6, hover_height + sin(_t * 1.6) * 0.07, rise) - sink
	var lean := -0.35 * clampf(_speed / chase_speed, 0.0, 1.0)
	_body.rotation.x = lerpf(_body.rotation.x, lean + _flinch * 0.45, k)
	_body.rotation.z = sin(_t * 0.9) * 0.04

	# Arms.
	for side in [RIGHT, LEFT]:
		var pose := _arm_pose(side)
		var s := 1.0 if side == RIGHT else -1.0  # mirror the outward angle
		var sh := _shoulders[side]
		var attacking: bool = _state == State.ATTACK and side == _arm
		var w := 1.0 if attacking else k  # the whip is posed exactly, the rest eased
		sh.rotation.x = lerpf(sh.rotation.x, pose.x, w)
		sh.rotation.z = lerpf(sh.rotation.z, pose.y * s, w)
		_elbows[side].rotation.x = lerpf(_elbows[side].rotation.x, pose.z, w)

	# Glow: brighter eyes and skin as it winds up or gets hit; fades when dying.
	var windup := 0.0
	if _state == State.ATTACK and _state_t < windup_time + whip_time:
		windup = clampf(_state_t / windup_time, 0.0, 1.0)
	var alive := 1.0 if _state != State.DEAD else clampf(1.0 - _state_t / 2.0, 0.0, 1.0)
	_bark.set_shader_parameter("flicker", maxf(_flinch, windup * 0.6))
	_eye_mat.emission_energy_multiplier = (4.0 + windup * 6.0 + _flinch * 4.0) * alive * rise
	_light.light_energy = (0.7 + windup * 0.8) * alive * rise
	if _state == State.DEAD:
		var d := clampf(_state_t / 2.0, 0.0, 1.0)
		_bark.set_shader_parameter("dissolve", d)
		_tail_mat.set_shader_parameter("dissolve", d)


## Target (shoulder forward swing, shoulder outward swing, elbow bend) in
## radians for one arm this frame. Positive forward swings the hanging arm
## to the front; positive outward lifts it out to the side.
func _arm_pose(side: int) -> Vector3:
	var sway := Vector3(sin(_t * 1.3 + side * 2.0), sin(_t * 0.8 + side), sin(_t * 1.7 + side * 1.3)) * 0.12
	match _state:
		State.RISE:
			# Clawing up out of the ground, then arms flung wide.
			var r := clampf(_state_t / rise_time, 0.0, 1.0)
			return Vector3(2.4, 0.3, 0.9).lerp(Vector3(0.6, 1.3, 0.5), r) + sway
		State.DEAD:
			return Vector3(0.1, 0.05, 0.0)
		State.ATTACK:
			if side != _arm:
				return Vector3(1.0, 0.25, 0.3) + sway
			var a := _state_t
			var windup_pose := Vector3(-0.4, 1.9, 1.1)  # drawn up and back, out to the side
			var whip_pose := Vector3(1.5, -0.4, 0.05)   # lashed across the front, arm straight
			var rest := Vector3(1.0, 0.25, 0.3)
			if a < windup_time:
				return rest.lerp(windup_pose, ease(a / windup_time, 0.5))
			if a < windup_time + whip_time:
				return windup_pose.lerp(whip_pose, ease((a - windup_time) / whip_time, 2.0))
			return whip_pose.lerp(rest, ease((a - windup_time - whip_time) / recover_time, 0.6))
		State.CHASE:
			# Reaching for you, claws first.
			return Vector3(1.15, 0.28, 0.25) + sway
	return Vector3(0.35, 0.2, 0.35) + sway * 1.5  # WAIT: hanging, swaying


# --- Building the body ----------------------------------------------------------------

func _build() -> void:
	_rng.seed = 7  # the same gnarled shape every time
	_bark = ShaderMaterial.new()
	_bark.shader = preload("res://enemies/forest_spirit.gdshader")
	_bark.set_shader_parameter("glow_color", glow_color)
	_tail_mat = _bark.duplicate()
	_tail_mat.set_shader_parameter("tail_fade", 1.1)
	_tail_mat.set_shader_parameter("writhe", 0.06)

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_body = Node3D.new()
	_body.name = "Body"
	_model.add_child(_body)

	# Spine: hunched forward (-Z), thick at the chest, thin at the neck.
	var spine: Array[Vector3] = [Vector3(0, 0.5, 0.02), Vector3(0, 1.1, -0.06),
		Vector3(0, 1.55, -0.2), Vector3(0, 1.8, -0.36), Vector3(0, 1.93, -0.48)]
	var radii := [0.17, 0.23, 0.21, 0.11, 0.07]
	_braid(_body, spine, radii, 6, 1.1)
	# Shoulder bar and knotted bark spikes along the back.
	_segment(_body, Vector3(-0.34, 1.68, -0.26), Vector3(0.34, 1.68, -0.26), 0.085, 0.085, _bark)
	for i in 4:
		var at: Vector3 = spine[1].lerp(spine[3], i / 3.0) + Vector3(0, 0, 0.12)
		_branch(_body, at, Vector3(_rng.randf_range(-0.4, 0.4), 0.6, 1.0), 0.28 - i * 0.04, 0.03, 0)
	# Ribs: thin twigs curling round the chest.
	for i in 3:
		for s: float in [1.0, -1.0]:
			var y := 1.2 + i * 0.13
			_branch(_body, Vector3(0.12 * s, y, 0.05), Vector3(s, -0.15, -0.9), 0.3, 0.018, 0)

	# The tail: no legs, the body tapers into smoke.
	var tail := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.02
	cone.height = 1.1
	cone.radial_segments = 8
	tail.mesh = cone
	tail.material_override = _tail_mat
	tail.position = Vector3(0, 0.0, 0.02)
	_body.add_child(tail)

	# Head: a long, narrow skull hanging forward on the neck.
	var head := Node3D.new()
	head.name = "Head"
	head.position = spine[-1] + Vector3(0, 0.04, -0.06)
	head.rotation.x = -0.35
	_body.add_child(head)
	var skull := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.42
	sphere.radial_segments = 12
	sphere.rings = 8
	skull.mesh = sphere
	skull.scale = Vector3(0.9, 1.0, 1.15)
	skull.material_override = _bark
	head.add_child(skull)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(0.85, 1.0, 0.85)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.75, 1.0, 0.8)
	_eye_mat.emission_energy_multiplier = 4.0
	for s: float in [1.0, -1.0]:
		var eye := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.03
		ball.height = 0.035  # narrow slits
		eye.mesh = ball
		eye.material_override = _eye_mat
		eye.position = Vector3(0.058 * s, 0.03, -0.172)
		eye.rotation.z = 0.35 * s  # slanted
		head.add_child(eye)
		# Antlers: crooked branches forking twice.
		_branch(head, Vector3(0.06 * s, 0.13, 0.0), Vector3(1.0 * s, 0.75, 0.4), 0.38, 0.032, 3)
	# Roots hanging from the jaw like a beard.
	for i in 5:
		var x := (i - 2) * 0.03
		_branch(head, Vector3(x, -0.17, -0.08), Vector3(x, -1.0, 0.1), _rng.randf_range(0.2, 0.4), 0.011, 0)

	# Arms: shoulder pivot → upper arm → elbow pivot → forearm → twig claws.
	for side in [RIGHT, LEFT]:
		var s := 1.0 if side == RIGHT else -1.0
		var shoulder := Node3D.new()
		shoulder.name = "Shoulder" + ("R" if side == RIGHT else "L")
		shoulder.position = Vector3(0.36 * s, 1.68, -0.26)
		_body.add_child(shoulder)
		_braid(shoulder, [Vector3.ZERO, Vector3(0.04 * s, -0.4, 0.03), Vector3(0, -0.72, 0)], [0.08, 0.065, 0.05], 3, 1.4)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.72, 0)
		shoulder.add_child(elbow)
		_braid(elbow, [Vector3.ZERO, Vector3(-0.03 * s, -0.42, -0.02), Vector3(0, -0.78, 0)], [0.05, 0.038, 0.026], 3, 1.6)
		_branch(elbow, Vector3(0, -0.3, 0), Vector3(s, -0.3, 0.4), 0.3, 0.014, 1)  # a twig off the forearm
		for c in 5:
			var spread := (c - 2) * 0.35
			var dir := Vector3(sin(spread) * 0.6, -1.0, -0.25 - cos(spread) * 0.2)
			_branch(elbow, Vector3(0, -0.78, 0), dir, _rng.randf_range(0.35, 0.5), 0.02, 1)
		_shoulders.append(shoulder)
		_elbows.append(elbow)

	# A sickly light in its chest, and smoke pouring off the tail.
	_light = OmniLight3D.new()
	_light.light_color = glow_color
	_light.light_energy = 0.7
	_light.omni_range = 4.0
	_light.position = Vector3(0, 1.5, -0.5)
	_body.add_child(_light)
	_smoke = _make_smoke()
	_smoke.position = Vector3(0, 0.1, 0)
	_body.add_child(_smoke)

	# Its own light shouldn't wash its body green: the body goes on render
	# layer 3 and the light lights every layer but that one. (Cameras draw
	# layer 3 as normal; the player's first-person trick only hides layer 2.)
	for mi in _body.find_children("*", "MeshInstance3D", true, false):
		mi.layers = SELF_LAYER
	_light.light_cull_mask = ~SELF_LAYER


## A limb woven from `strands` thinner roots twisting round each other (and
## a dark core), following `points` with the given overall `radii`. `twist` =
## radians each strand turns per point. Reads as wood far more than one
## smooth cylinder.
func _braid(parent: Node3D, points: Array, radii: Array, strands: int, twist: float) -> void:
	for i in points.size() - 1:
		_segment(parent, points[i], points[i + 1], radii[i] * 0.6, radii[i + 1] * 0.6, _bark)
	for k in strands:
		var start := TAU * k / strands + _rng.randf_range(-0.3, 0.3)
		var path: Array[Vector3] = []
		for i in points.size():
			var along: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
			var across := along.cross(Vector3.FORWARD if absf(along.z) < 0.9 else Vector3.RIGHT).normalized()
			var off: Vector3 = across.rotated(along, start + twist * i) * float(radii[i]) * 0.62
			path.append(points[i] + off)
		for i in path.size() - 1:
			# Each strand is a bit thicker in the middle of its run (knotted).
			_segment(parent, path[i], path[i + 1], radii[i] * 0.45, radii[i + 1] * 0.45, _bark)


## A tapered cylinder from `a` to `b` (radius r0 at a, r1 at b) under `parent`.
func _segment(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	var mesh := CylinderMesh.new()
	mesh.height = length
	mesh.bottom_radius = r0
	mesh.top_radius = r1
	mesh.radial_segments = 6
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	# A cylinder mesh stands along +Y; turn +Y to point from a to b.
	var dir := (b - a) / length
	var axis := Vector3.UP.cross(dir)
	var basis := Basis.IDENTITY
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	elif dir.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	mi.transform = Transform3D(basis, (a + b) / 2.0)
	parent.add_child(mi)


## A crooked branch: two kinked segments tapering to a point, forking into
## two smaller branches `depth` more times.
func _branch(parent: Node3D, from: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var d := dir.normalized()
	var p := from
	var tip := 0.004 if depth == 0 else radius * 0.6
	for i in 2:
		d = (d + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.4).normalized()
		var q := p + d * length / 2.0
		_segment(parent, p, q, lerpf(radius, tip, i / 2.0), lerpf(radius, tip, (i + 1) / 2.0), _bark)
		p = q
	if depth > 0:
		var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		for s: float in [1.0, -1.0]:
			var fork := d.rotated(side, 0.6 * s).rotated(d, _rng.randf_range(-0.6, 0.6))
			_branch(parent, p, fork, length * 0.75, tip, depth - 1)


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 48
	p.lifetime = 1.8
	p.local_coords = false  # left behind as it moves
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.gravity = Vector3(0, 0.25, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.25, Color(1, 1, 1, 1.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.015, 0.02, 0.015, 0.5)
	var puff := GradientTexture2D.new()  # a soft round blob
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = g
	mat.albedo_texture = puff
	quad.material = mat
	p.mesh = quad
	return p
