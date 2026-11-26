extends SkeletonModifier3D
## First person: turns the right hand so the weapon stands upright in its
## fist, instead of the fist pointing forward and the handle poking out
## through the fingers. Used by humanoid.gd, which adds it to the skeleton
## right after the arm's TwoBoneIK3D.
##
## A SkeletonModifier3D runs after the animation has posed the skeleton (and
## after the modifiers before it, like the IK that brings the arm into view),
## and may change bone poses. `influence` (0..1) blends its result in; the
## humanoid fades it with the first-person hold.
##
## It also measures the fist from the finger bones every frame, in the hand
## bone's own coordinates, so the humanoid can seat the weapon exactly in it:
##   channel   the tunnel the curled fingers make (little finger -> index)
##   centre    the middle of that tunnel
##   knuckles  wrist -> knuckles direction (where a punch would go)

## The direction the weapon should point (world space) and which way its
## edge should face. Set by the humanoid each frame from the camera.
var target_basis := Basis.IDENTITY

var channel := Vector3.UP        # hand space, unit length
var centre := Vector3.ZERO       # hand space
var knuckles := Vector3.FORWARD  # hand space, unit, at right angles to channel

const HAND := "hand_r"
const FINGERS := ["index", "middle", "ring", "pinky"]


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var hand := skeleton.find_bone(HAND)
	var hand_pose := skeleton.get_bone_global_pose(hand)  # skeleton space
	_measure_fist(skeleton, hand_pose)
	# The hand's orientation that maps the fist frame onto target_basis:
	# world = skeleton.global_basis * hand_basis * fist_frame  must equal  target_basis.
	var wanted := skeleton.global_basis.inverse() * target_basis * fist_frame().inverse()
	wanted = wanted.orthonormalized().scaled_local(hand_pose.basis.get_scale())
	skeleton.set_bone_global_pose(hand, Transform3D(wanted, hand_pose.origin))


## The fist as a basis in hand space: Y along the channel, -Z towards the
## knuckles. A weapon given this basis (then its own spin) sits in the fist
## with its business end out of the thumb side and its edge facing forward.
func fist_frame() -> Basis:
	var y := channel
	var z := -knuckles
	return Basis(y.cross(z).normalized(), y, z)


func _measure_fist(skeleton: Skeleton3D, hand_pose: Transform3D) -> void:
	var to_hand := hand_pose.affine_inverse()
	var local := func(bone: String) -> Vector3:
		return to_hand * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	var sum := Vector3.ZERO
	var knuckle_sum := Vector3.ZERO
	for finger in FINGERS:
		for joint in ["_01_r", "_02_r", "_03_r"]:
			sum += local.call(finger + joint)
		knuckle_sum += local.call(finger + "_01_r")
	centre = sum / 12.0
	channel = (local.call("index_01_r") - local.call("pinky_01_r")).normalized()
	var k: Vector3 = knuckle_sum / 4.0  # from the wrist (the hand bone's origin) to the knuckles
	knuckles = (k - channel * k.dot(channel)).normalized()
