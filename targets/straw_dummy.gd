extends StaticBody3D
## A straw training dummy. Hit it with anything.
##
## Damage you can see:
##   every hit:   it wobbles (a spring), straw bursts out
##   each hit:    the straw browns a bit more and it leans further away from you
##   last hit:    the head pops off and the body slumps over
##   then:        after reset_after seconds it stands back up as new
##
## The wobble is a damped spring, the classic "game feel" tool: acceleration
## pulls back towards rest (stiffness) and is slowed by friction (damping).

@export var max_health := 3
@export var reset_after := 6.0  # seconds after being destroyed
@export var lean_per_hit_deg := 9.0
@export var fresh_color := Color(0.86, 0.74, 0.40)
@export var worn_color := Color(0.47, 0.36, 0.19)
@export var stiffness := 60.0
@export var damping := 6.0

@onready var _body: Node3D = $Body  # pivot that leans and wobbles
@onready var _head: MeshInstance3D = $Body/Head
var _straw: StandardMaterial3D      # this dummy's own copy of the straw colour
var _health := 0
var _rest_lean := Vector2.ZERO      # lasting lean: direction on the ground * angle (radians)
var _lean := Vector2.ZERO           # current lean, easing towards _rest_lean
var _wobble := Vector2.ZERO         # springy extra lean on top
var _wobble_vel := Vector2.ZERO
var _loose_head: RigidBody3D = null


func _ready() -> void:
	# Each dummy gets its own material, so browning one doesn't brown them all.
	_straw = StandardMaterial3D.new()
	_straw.roughness = 1.0
	for part in [$Body/Torso, $Body/Arms]:
		part.material_override = _straw
	_reset()
	# Collision layer 3 = "hittable": combat.gd looks for targets there.
	set_collision_layer_value(3, true)


## Called by combat.gd. `from` is where the attacker stands, `dir` the swing direction.
func on_hit(_weapon: Equipable, from: Vector3, dir: Vector3) -> void:
	if _health <= 0:
		return  # already in pieces, waiting to reset
	_health -= 1
	var away := Vector2(dir.x, dir.z).normalized()
	_wobble_vel += away * 4.0
	_rest_lean += away * deg_to_rad(lean_per_hit_deg)
	_straw.albedo_color = worn_color.lerp(fresh_color, float(_health) / max_health)

	var toward_attacker := (from - global_position)
	toward_attacker.y = 0.0
	var chest := _body.global_position + Vector3.UP * 0.35 + toward_attacker.normalized() * 0.25
	HitFx.burst(self, chest, fresh_color.lerp(worn_color, 0.3), dir, 30)

	if _health == 0:
		_destroy(away)


func _destroy(away: Vector2) -> void:
	# The body slumps right over...
	_rest_lean = away * deg_to_rad(70.0)
	HitFx.burst(self, _head.global_position, fresh_color, Vector3.UP, 60, 0.05, 4.0)
	# ...and the head comes off: swap the mesh for a physics copy and throw it.
	_head.visible = false
	_loose_head = RigidBody3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = _head.mesh
	_loose_head.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.16
	_loose_head.add_child(shape)
	_loose_head.mass = 1.0
	get_tree().root.add_child(_loose_head)
	_loose_head.global_position = _head.global_position
	_loose_head.apply_impulse(Vector3(away.x, 0.0, away.y) * 2.5 + Vector3.UP * 3.0)
	# Stand back up later. The timer is a one-shot; we connect a function to its signal.
	get_tree().create_timer(reset_after).timeout.connect(_reset)


func _reset() -> void:
	if _loose_head:
		_loose_head.queue_free()
		_loose_head = null
	_head.visible = true
	_health = max_health
	_rest_lean = Vector2.ZERO
	_straw.albedo_color = fresh_color


func _physics_process(delta: float) -> void:
	# Damped spring: accelerate back towards 0, minus friction.
	_wobble_vel += (-_wobble * stiffness - _wobble_vel * damping) * delta
	_wobble += _wobble_vel * delta
	_lean = _lean.lerp(_rest_lean, 1.0 - exp(-6.0 * delta))
	var total := _lean + _wobble
	var angle := total.length()
	if angle < 0.0001:
		_body.basis = Basis()
		return
	# Tip over towards `total`: rotating around UP x direction moves the top
	# of the dummy along that direction.
	var dir := Vector3(total.x, 0.0, total.y) / angle
	_body.basis = Basis(Vector3.UP.cross(dir).normalized(), angle)
