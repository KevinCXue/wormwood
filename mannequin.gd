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
## Carried items attach to the right palm, the equipped weapon to the left.
@onready var hand_socket: Node3D = $Hips/Spine/ShoulderR/ElbowR/HandSocket
@onready var hand_socket_l: Node3D = $Hips/Spine/ShoulderL/ElbowL/HandSocketL

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

var _phase := 0.0       # where we are in the walk cycle, in radians (one cycle = TAU)
var _move_blend := 0.0  # 0 = standing still, 1 = full run (smoothed)
var _air_blend := 0.0   # 0 = on the ground, 1 = airborne (smoothed)
var _time := 0.0
var _hips_rest_y := 0.0


func _ready() -> void:
	_hips_rest_y = _hips.position.y


## Start a swing with the left arm (ignored if one is already in progress).
func start_swing() -> void:
	if not is_swinging():
		_swing_t = 0.0


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


## Ease a joint's X rotation (its forward/back swing) towards `target`.
func _ease(joint: Node3D, target: float, k: float) -> void:
	joint.rotation.x = lerpf(joint.rotation.x, target, k)
