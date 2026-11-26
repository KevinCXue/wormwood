extends Node3D
## Greybox humanoid (~1.8 m) animated from code.
##
## The body is a hierarchy of pivot nodes (Hips, Spine, ShoulderL, ElbowL,
## HipL, KneeL, ...) with simple meshes hanging off them. Rotating a pivot
## swings everything below it, like a joint, so rotating HipL swings the whole
## left leg, and KneeL then bends just the shin and foot. That's the same idea
## as a skeleton in a rigged model, built from ordinary nodes.
##
## Conventions: the root sits at the feet and the model faces -Z. A positive
## X rotation swings a hanging limb forward (towards -Z).
##
## Each physics frame, player.gd calls update_pose(). We compute a target angle
## for every joint and ease towards it, so switching between idle, running and
## jumping blends smoothly instead of snapping.
##
## This is the "blocky" body. It implements the body contract described in
## characters/body_slot.gd, like the detailed one (characters/humanoid.gd).

@export var stride_length := 1.5    # metres covered per full walk cycle (two steps)
@export var leg_swing_deg := 38.0   # how far legs swing forward/back at full speed
@export var arm_swing_deg := 32.0
@export var run_speed := 6.0        # speed at which the run pose is at full strength
@export var bob_height := 0.05      # body bounce per step, in metres
@export var pose_smoothing := 14.0  # higher = joints follow their targets more tightly
@export var hold_shoulder_deg := 57.0  # right arm raised forward while carrying
@export var hold_elbow_deg := 34.0     # forearm bent up to level, palm to the sky

@export var ready_shoulder_deg := 20.0 # left arm with a weapon: a little forward...
@export var ready_elbow_deg := 55.0    # ...and bent, "at the ready"

## Set by the interactor when carrying an item: the right arm holds it out.
var holding := false
## Set by the interactor when a weapon/tool is equipped in the left hand.
var equipped := false

@export_group("Swing")
@export var swing_duration := 0.55  # seconds, wind-up to back at the ready
@export var strike_time := 0.24     # seconds in, when the blade connects (combat.gd waits this long)
@export_group("")

## Extra forward/back tilt for the equipped item during a swing (radians,
## positive = back over the shoulder). interactor.gd applies it to the weapon.
var swing_tilt := 0.0
var _swing_t := -1.0  # seconds since the swing started; negative = not swinging
var _dead := false
## Carried items attach to the right palm, the equipped weapon to the left.
@onready var carry_socket: Node3D = $Hips/Spine/ShoulderR/ElbowR/HandSocket
@onready var weapon_socket: Node3D = $Hips/Spine/ShoulderL/ElbowL/HandSocketL

@onready var _hips: Node3D = $Hips
@onready var _spine: Node3D = $Hips/Spine
@onready var _shoulder_l: Node3D = $Hips/Spine/ShoulderL
@onready var _shoulder_r: Node3D = $Hips/Spine/ShoulderR
@onready var _elbow_l: Node3D = $Hips/Spine/ShoulderL/ElbowL
@onready var _elbow_r: Node3D = $Hips/Spine/ShoulderR/ElbowR
@onready var _hip_l: Node3D = $Hips/HipL
@onready var _hip_r: Node3D = $Hips/HipR
@onready var _knee_l: Node3D = $Hips/HipL/KneeL
@onready var _knee_r: Node3D = $Hips/HipR/KneeR
@onready var _head: Node3D = $Hips/Spine/Head

## Meshes grouped by what they're made of, so apply_look() can recolour each
## group. (Names match the MeshInstance3D nodes in mannequin.tscn.)
const PARTS := {
	"skin": ["Head", "Nose", "Forearm", "Hand"],
	"tunic": ["Torso", "UpperArm"],
	"trousers": ["Pelvis", "Thigh", "Shin"],
	"boots": ["Foot"],
}
const MAX_HEAD_TURN := 1.2  # radians (~70°): necks don't turn further
var _look_target: Variant = null  # global position to look at, or null

var _phase := 0.0       # where we are in the walk cycle, in radians (one cycle = TAU)
var _move_blend := 0.0  # 0 = standing still, 1 = full run (smoothed)
var _air_blend := 0.0   # 0 = on the ground, 1 = airborne (smoothed)
var _time := 0.0
var _hips_rest_y := 0.0


func _ready() -> void:
	_hips_rest_y = _hips.position.y


## Start a swing with the left arm (ignored if one is already in progress).
## A punch uses the same motion (the blocky body is for testing mechanics).
func start_swing(_punch := false) -> void:
	if not is_swinging() and not _dead:
		_swing_t = 0.0


## Hit reaction: nothing for the blocky body.
func flinch() -> void:
	pass


## Topple over backwards and stay down. `instant` (restoring a save) skips
## the fall.
func die(instant := false) -> void:
	_dead = true
	var lying := Vector3(deg_to_rad(80.0), rotation.y, 0.0)
	if instant:
		rotation = lying
	else:
		create_tween().tween_property(self, "rotation", lying, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func is_swinging() -> bool:
	return _swing_t >= 0.0


## The swing as keyframes: [time, shoulder, elbow, arm out, weapon tilt, spine twist]
## (angles in radians; positive shoulder = arm forward/up, positive tilt =
## weapon back). Wind-up over the shoulder, a fast diagonal strike forward and
## down across the body, then a slower recovery to the ready pose.
func _swing_keys() -> Array:
	var rs := deg_to_rad(ready_shoulder_deg)
	var re := deg_to_rad(ready_elbow_deg)
	return [
		[0.0, rs, re, 0.06, 0.0, 0.0],
		[0.16, 2.5, 1.4, 0.5, 1.0, 0.35],    # wound up: hand behind the head
		[0.27, 0.45, 0.1, -0.3, -1.3, -0.3], # struck: arm forward-down, across
		[swing_duration, rs, re, 0.06, 0.0, 0.0],
	]


## Interpolate the keyframes at time t, easing in and out of each one.
func _swing_pose(t: float) -> Array:
	var keys := _swing_keys()
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var f := smoothstep(a[0], b[0], t)
			var out := []
			for ch in range(1, a.size()):
				out.append(lerpf(a[ch], b[ch], f))
			return out
	return keys[-1].slice(1)


func update_pose(horizontal_speed: float, on_floor: bool, delta: float) -> void:
	if _dead:
		return
	_time += delta
	var k := 1.0 - exp(-pose_smoothing * delta)  # frame-rate-independent easing factor
	_move_blend = lerpf(_move_blend, clampf(horizontal_speed / run_speed, 0.0, 1.0), k)
	_air_blend = lerpf(_air_blend, 0.0 if on_floor else 1.0, k * 0.6)

	# Advance the cycle by distance travelled, so feet don't "skate":
	# one full cycle (TAU) per stride_length metres.
	if on_floor:
		_phase = fmod(_phase + TAU * horizontal_speed / stride_length * delta, TAU)

	var s := sin(_phase)
	var c := cos(_phase)
	var m := _move_blend
	var leg := deg_to_rad(leg_swing_deg) * m
	var arm := deg_to_rad(arm_swing_deg) * m

	# --- Ground pose: walk/run cycle, fading to an idle stance as m -> 0. ---
	# Legs swing in opposite phase. Knees bend most while the leg swings
	# forward (when cos > 0 for the left leg) and always bend backward (negative).
	var hip_l := s * leg
	var hip_r := -s * leg
	var knee_l := -(0.1 + 1.1 * maxf(0.0, c)) * m
	var knee_r := -(0.1 + 1.1 * maxf(0.0, -c)) * m
	# Arms swing opposite to the legs on the same side; elbows bend more when running.
	var shoulder_l := -s * arm
	var shoulder_r := s * arm
	var elbow := 0.15 + 0.6 * m
	# Two bounces per cycle (one per step), a forward lean when running, and
	# slow "breathing" that only shows when standing still.
	var bob := -absf(c) * bob_height * m + sin(_time * 2.0) * 0.006 * (1.0 - m)
	var lean := -0.12 * m
	var arm_out := 0.06  # arms hang slightly away from the body (rotation.z)

	# --- Air pose: one knee up, arms raised and out. Blended in by _air_blend. ---
	var a := _air_blend
	hip_l = lerpf(hip_l, 0.7, a)
	hip_r = lerpf(hip_r, -0.15, a)
	knee_l = lerpf(knee_l, -1.2, a)
	knee_r = lerpf(knee_r, -0.4, a)
	shoulder_l = lerpf(shoulder_l, 0.3, a)
	shoulder_r = lerpf(shoulder_r, -0.2, a)
	arm_out = lerpf(arm_out, 0.45, a)
	elbow = lerpf(elbow, 0.5, a)
	bob = lerpf(bob, 0.0, a)

	# --- Carrying: the right arm ignores the cycle and holds still. ---
	var elbow_l := elbow
	var elbow_r := elbow
	var arm_out_r := arm_out
	# --- Weapon in the left hand: arm held ready, swinging only a little. ---
	if equipped:
		shoulder_l = deg_to_rad(ready_shoulder_deg) + shoulder_l * 0.25
		elbow_l = deg_to_rad(ready_elbow_deg)
	if holding:
		shoulder_r = deg_to_rad(hold_shoulder_deg)
		elbow_r = deg_to_rad(hold_elbow_deg)
		arm_out_r = 0.0

	# --- Swing: the keyframes take over the left arm and twist the torso. ---
	var arm_out_l := arm_out
	var twist := 0.0
	var k_left := k
	if is_swinging():
		_swing_t += delta
		var pose := _swing_pose(_swing_t)
		shoulder_l = pose[0]
		elbow_l = pose[1]
		arm_out_l = pose[2]
		swing_tilt = pose[3]
		twist = pose[4]
		k_left = 1.0  # follow the keyframes exactly; easing would soften the strike
		if _swing_t >= swing_duration:
			_swing_t = -1.0
			swing_tilt = 0.0

	# --- Apply, easing each joint towards its target. ---
	_ease(_hip_l, hip_l, k)
	_ease(_hip_r, hip_r, k)
	_ease(_knee_l, knee_l, k)
	_ease(_knee_r, knee_r, k)
	_ease(_shoulder_l, shoulder_l, k_left)
	_ease(_shoulder_r, shoulder_r, k)
	_ease(_elbow_l, elbow_l, k_left)
	_ease(_elbow_r, elbow_r, k)
	_ease(_spine, lean, k)
	_spine.rotation.y = lerpf(_spine.rotation.y, twist, k_left)
	# Mirror the outward arm angle: left arm rotates -Z, right arm +Z.
	_shoulder_l.rotation.z = lerpf(_shoulder_l.rotation.z, -arm_out_l, k_left)
	_shoulder_r.rotation.z = lerpf(_shoulder_r.rotation.z, arm_out_r, k)
	_hips.position.y = lerpf(_hips.position.y, _hips_rest_y + bob, k)

	# Head: turn towards the look target, if it isn't behind us.
	var head_yaw := 0.0
	if _look_target != null:
		var to_target: Vector3 = _look_target - global_position
		var relative := wrapf(atan2(-to_target.x, -to_target.z) - global_rotation.y, -PI, PI)
		if absf(relative) < MAX_HEAD_TURN + 0.4:
			head_yaw = clampf(relative, -MAX_HEAD_TURN, MAX_HEAD_TURN)
	_head.rotation.y = lerp_angle(_head.rotation.y, head_yaw, 1.0 - exp(-6.0 * delta))


## Ease a joint's X rotation (its forward/back swing) towards `target`.
func _ease(joint: Node3D, target: float, k: float) -> void:
	joint.rotation.x = lerpf(joint.rotation.x, target, k)



# --- Body contract (see characters/body_slot.gd) --------------------------------------

## Turn the head towards a global position, or back to straight ahead (null).
func set_look_target(target: Variant) -> void:
	_look_target = target


## Nothing to do: the mannequin's weapon arm is always held up in front,
## where the first-person camera can see it.
func set_first_person(_on: bool) -> void:
	pass


## The player's body sits on render layer 2 (set per mesh in mannequin.tscn,
## all but the arms) so the first-person camera can hide it. Anyone else must
## stay visible to that camera, so their meshes go back to layer 1.
func use_as_player(is_player: bool) -> void:
	if not is_player:
		for mi in find_children("*", "MeshInstance3D", true, false):
			mi.layers = 1


## Right hand: keep the item sitting upright on the palm, facing the way the
## body faces, whatever angle the arm is at.
func place_carried(item: Item) -> void:
	var aabb: AABB = (item.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
	var basis := Basis(Vector3.UP, global_rotation.y)
	# Offset so the bottom-centre of the item rests on top of the hand.
	var bottom_centre := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	var palm_top: Vector3 = carry_socket.global_position + Vector3.UP * 0.04
	item.global_transform = Transform3D(basis, palm_top - basis * bottom_centre)


## Left hand: the grip point sits in the fist, angled as the item asks
## (hold_rotation_deg), relative to the direction the body faces.
func place_equipped(item: Equipable) -> void:
	var body := Basis(Vector3.UP, global_rotation.y)
	# swing_tilt pitches the weapon back (wind-up) and forward (strike) while
	# we swing; it's 0 the rest of the time.
	var swing := Basis(Vector3.RIGHT, swing_tilt)
	var basis := body * swing * Basis.from_euler(item.hold_rotation_deg * (PI / 180.0))
	var fist: Vector3 = weapon_socket.global_position
	item.global_transform = Transform3D(basis, fist - basis * item.grip)


## Dress the mannequin as a villager. Keys (all optional): skin, tunic,
## trousers, boots, hair (Colors), hair_style ("short"/"long"), skirt (bool),
## height_scale (float). body_type is ignored: the mannequin has one build.
func apply_look(look: Dictionary) -> void:
	scale = Vector3.ONE * look.get("height_scale", 1.0)
	for group in PARTS:
		if not look.has(group):
			continue
		var mat := _mat(look[group])
		for part in PARTS[group]:
			for mi in find_children(part, "MeshInstance3D", true, false):
				# The meshes (and their materials) are shared by everyone who
				# uses mannequin.tscn, including the player.
				# surface_override_material changes just this one node.
				mi.set_surface_override_material(0, mat)

	var hair := _mat(look.get("hair", Color(0.25, 0.16, 0.1)))
	# Short hair: a cap over the top half of the head (a hemisphere).
	var cap := SphereMesh.new()
	cap.radius = 0.118
	cap.height = 0.125
	cap.is_hemisphere = true
	_attach(_head, cap, hair, Vector3(0, 0.005, 0.008), Vector3(1.0, 1.15, 1.05))
	if look.get("hair_style", "short") == "long":
		# Long hair: a curtain down the back to the shoulders, plus a lock
		# of it framing each side of the face.
		var back := BoxMesh.new()
		back.size = Vector3(0.22, 0.3, 0.07)
		_attach(_head, back, hair, Vector3(0, -0.1, 0.075))
		for side in [-1, 1]:
			var lock := BoxMesh.new()
			lock.size = Vector3(0.04, 0.2, 0.09)
			_attach(_head, lock, hair, Vector3(side * 0.1, -0.06, 0.01))

	if look.get("skirt", false):
		# A flared cylinder hanging from the hips to just below the knees.
		var cone := CylinderMesh.new()
		cone.top_radius = 0.175
		cone.bottom_radius = 0.3
		cone.height = 0.55
		var tunic: Color = look.get("tunic", Color(0.4, 0.4, 0.4))
		_attach(_hips, cone, _mat(tunic.darkened(0.15)), Vector3(0, -0.22, 0))


func _attach(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, mesh_scale := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = mesh_scale
	mi.layers = _head.layers  # same render layer as the rest of the body
	parent.add_child(mi)


func _mat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	return m
