extends Node
## Swinging the equipped weapon/tool (left mouse button). A child of Player.
##
## A swing is: play the mannequin's swing animation, wait until the blade
## would connect (strike_time), then look for things in a sphere in front of
## the chest. Anything there with an on_hit() method gets told it was hit;
## loose items get knocked about.
##
## "Duck typing": we don't care what class a thing is, only whether it has
## on_hit(). Straw dummies and trees each implement it their own way.

@export var hit_radius := 0.75    # size of the hit sphere, metres
@export var hit_distance := 1.1   # how far in front of the chest it sits
@export var knock_impulse := 2.5  # push given to loose items that get hit

# Collision layers (named in Project Settings > Layer Names > 3D Physics).
# Every solid thing is on layer 1; items and targets are also tagged with
# their own layer so a swing can ask for just those.
const ITEMS_LAYER := 2     # set by item.gd
const HITTABLE_LAYER := 3  # set by straw_dummy.gd and choppable_tree.gd

@onready var _player: CharacterBody3D = get_parent()
@onready var _rig: Node3D = $"../CameraRig"
@onready var _model: Node3D = $"../Model"
@onready var _interactor: Node = $"../Interactor"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_swing()


func _swing() -> void:
	var weapon: Equipable = _interactor.get_equipped()
	if weapon == null or _model.is_swinging():
		return
	# Swing where you're looking: in third person the body may be facing
	# elsewhere (it faces the way it last walked), so turn it first.
	_model.rotation.y = _rig.rotation.y
	_model.start_swing()
	# `await` pauses this function until the timer fires, without blocking
	# the game. Everything else keeps running meanwhile.
	await get_tree().create_timer(_model.strike_time).timeout
	if _interactor.get_equipped() == weapon:  # still holding it?
		_strike(weapon)


func _strike(weapon: Equipable) -> void:
	var forward := -_model.global_basis.z
	var centre := _player.global_position + Vector3.UP * 1.1 + forward * hit_distance

	# Loose items in the way get knocked about.
	for body in _overlapping(centre, ITEMS_LAYER):
		if body is RigidBody3D and not body.freeze:
			body.apply_impulse(forward * knock_impulse + Vector3.UP * 1.0)

	# The nearest target that can react (dummy, tree) gets hit.
	var best: Object = null
	var best_dist := INF
	for body in _overlapping(centre, HITTABLE_LAYER):
		var d: float = centre.distance_to(body.global_position)
		if body.has_method("on_hit") and d < best_dist:
			best = body
			best_dist = d
	if best:
		best.on_hit(weapon, _player.global_position, forward)


## Physics bodies on the given collision layer that overlap the hit sphere.
## A shape query asks the physics engine "what overlaps this shape here?".
## The layer mask keeps the answer short: without it, a detailed table could
## report one result per triangle and crowd out what we actually want.
func _overlapping(centre: Vector3, layer: int) -> Array:
	var sphere := SphereShape3D.new()
	sphere.radius = hit_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), centre)
	query.collision_mask = 1 << (layer - 1)  # layer N is bit N-1
	query.exclude = [_player.get_rid()]
	var bodies := {}  # used as a set: each body once
	for hit in _player.get_world_3d().direct_space_state.intersect_shape(query, 64):
		bodies[hit.collider] = true
	return bodies.keys()
