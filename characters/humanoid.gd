extends Node3D
## The "detailed" body: a rigged, skinned character assembled from Quaternius
## assets (all CC0): an outfit (Modular Character Outfits - Fantasy) for the
## body, the head from a Universal Base Character, a hairstyle, and clips from
## the Universal Animation Library. Implements the body contract in
## characters/body_slot.gd, the same as the blocky mannequin.
##
## Assembly (see _build): the outfit file is a complete clothed body on its own
## skeleton, so it becomes the character. Base characters are full bodies, so
## we cut out just their head (_head_only) and bind it, the eyes, eyebrows and
## hair to the outfit's skeleton. All these files share one 65-bone skeleton,
## and a skinned mesh is placed relative to its bones, so parts made for
## slightly different proportions still line up.
##
## How a rigged character works, compared with the mannequin:
##   - The mesh is one piece of "skin" bound to a Skeleton3D: 65 bones
##     (pelvis, spine_01, upperarm_l, hand_r, ...). Moving a bone bends the
##     part of the mesh weighted to it, like a puppet's wires.
##   - Animations are recorded clips: per-bone rotations over time. Ours all
##     use the same skeleton, so any clip plays on any of these characters.
##   - An AnimationTree mixes clips together every frame. Ours is a small
##     graph (built in _setup_tree, below):
##
##       move (idle/walk/jog/sprint by speed) -> move_rate
##         -> air      (blend in the jump loop while off the ground)
##         -> carry    (left arm only: hold it out, from "Idle_Torch")
##         -> ready    (right arm only: weapon held ready, "Sword_Idle")
##         -> swing    (upper body only: one-shot "Sword_Attack")
##         -> output
##
##     "Filters" restrict a node to some bones. That's how the swing plays on
##     the arms and spine while the legs keep running.
##   - Things the clips don't know about (where to look) are layered on top
##     by a SkeletonModifier3D (LookAtModifier3D turns the head).
##
## The model files face +Z; the game's convention is -Z, so the model is
## turned 180° inside this node.

## Where the heads come from (only the head of these is used).
const HEADS := {
	"male": "res://assets/characters/quaternius/Superhero_Male_FullBody.gltf",
	"female": "res://assets/characters/quaternius/Superhero_Female_FullBody.gltf",
}
const OUTFIT_DIR := "res://assets/characters/outfits/"
## outfit -> file name (without the Male_/Female_ prefix).
const OUTFITS := {"peasant": "Peasant", "ranger": "Ranger"}
## Bones whose skin counts as "head" when cutting the head off a base body.
const HEAD_BONES := ["Head", "neck_01"]
## The peasant outfit textures; the dye shader recolours the linen.
const DYE_TEXTURES := {
	"albedo": "res://assets/characters/outfits/T_Peasant_BaseColor.png",
	"normal": "res://assets/characters/outfits/T_Peasant_Normal.png",
	"orm": "res://assets/characters/outfits/T_Peasant_ORM.png",
}
## Light and dark skin textures for each body.
const SKIN_TEXTURES := {
	"male": ["res://assets/characters/quaternius/T_Superhero_Male_Ligh.png",
		"res://assets/characters/quaternius/T_Superhero_Male_Dark.png"],
	"female": ["res://assets/characters/quaternius/T_Superhero_Female_Light_BaseColor.png",
		"res://assets/characters/quaternius/T_Superhero_Female_Dark_BaseColor.png"],
}
## hair_style -> model, per body type.
const HAIR := {
	"male": {"short": "Hair_SimpleParted", "long": "Hair_Long", "buzzed": "Hair_Buzzed"},
	"female": {"short": "Hair_Buns", "long": "Hair_Long", "buzzed": "Hair_BuzzedFemale"},
}
const HAIR_DIR := "res://assets/characters/quaternius/"
const ANIMATIONS := "res://assets/animations/UAL1_Standard.glb"

## How fast each locomotion clip moves the body, in metres per second
## (measured from the library's root-motion version). Playing a clip at the
## speed the character actually moves keeps the feet from sliding.
const WALK_SPEED := 0.97
const JOG_SPEED := 5.36
const SPRINT_SPEED := 8.25

@export_group("Swing")
@export var attack_speed := 1.4   # Sword_Attack is slow and showy; play it faster
@export var strike_point := 0.4   # seconds into Sword_Attack (at speed 1) when the blade passes in front

@export_group("Hands")
## How the equipped item sits in the right hand, relative to the hand bone.
## The bone's +Y runs along the fingers; with the default rotation the
## item's +Y (the blade, by our convention) points out of the thumb side.
@export var weapon_rotation_deg := Vector3(90.0, 0.0, 0.0)
@export var weapon_offset := Vector3(-0.03, 0.08, 0.0)
@export_range(0.0, 1.0) var carry_pose_strength := 0.85

@export_group("First person")
## Where the weapon hand sits in first person, relative to the camera
## (metres: right, up, back; the camera looks along -Z).
@export var fp_hand_offset := Vector3(0.24, -0.25, -0.45)
## How the weapon is angled in first person, relative to the camera, in
## degrees: X tips the top forward (negative), Z leans it in towards the
## middle of the screen (positive, for the right hand).
@export var fp_weapon_tilt_deg := Vector3(-25.0, 0.0, 15.0)

var holding := false
var equipped := false
var strike_time: float:
	get: return strike_point / attack_speed
var carry_socket: BoneAttachment3D   # left hand
var weapon_socket: BoneAttachment3D  # right hand

## All characters share one copy of the animation clips (static = one per
## class, not one per character).
static var _library: AnimationLibrary
## Head-only meshes cut from the base bodies, one per body type, shared.
static var _head_meshes := {}

var _character: Node3D   # the imported model
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _look: LookAtModifier3D
var _look_marker: Marker3D
var _look_target: Variant = null
var _hair: MeshInstance3D
var _body_type := ""
var _outfit := ""
var _is_player := false
var _air := 0.0
var _carry := 0.0
var _ready_pose := 0.0
var _ground_offset := 0.0  # how far the model is lifted to keep its feet on the ground
var _first_person := false
var _fp := 0.0             # 0..1: how much the first-person weapon hold is applied
var _ik: TwoBoneIK3D
var _ik_target: Marker3D
var _ik_pole: Marker3D

## Height of the ball-of-foot bones above the sole of the shoe, in metres.
const SOLE := 0.02


## The model is built lazily: villagers call apply_look() straight away and
## get built once, as themselves. Anyone who doesn't (the player) gets the
## default look on their first frame: a ranger with the hood down.
func _build_default() -> void:
	_build("male", "ranger")
	_remove_hood()
	_set_hair("short", Color(0.22, 0.14, 0.09))


# --- Body contract (see characters/body_slot.gd) --------------------------------------

func update_pose(speed: float, on_floor: bool, delta: float) -> void:
	if _character == null:
		_build_default()
	var k := 1.0 - exp(-10.0 * delta)
	# Between the clips' speeds the blend itself moves at the right speed;
	# beyond a sprint, play the sprint faster.
	_tree.set("parameters/move/blend_position", minf(speed, SPRINT_SPEED))
	_tree.set("parameters/move_rate/scale", maxf(1.0, speed / SPRINT_SPEED))
	_air = lerpf(_air, 0.0 if on_floor else 1.0, k * 0.6)
	_tree.set("parameters/air/blend_amount", _air)
	_carry = lerpf(_carry, carry_pose_strength if holding else 0.0, k)
	_tree.set("parameters/carry/blend_amount", _carry)
	_ready_pose = lerpf(_ready_pose, 1.0 if equipped else 0.0, k)
	_tree.set("parameters/ready/blend_amount", _ready_pose)
	_update_look(delta)
	_update_first_person_hold(delta)
	_keep_feet_on_ground(on_floor, delta)


func start_swing() -> void:
	if _tree and not is_swinging():
		_tree.set("parameters/swing/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_swinging() -> bool:
	return _tree != null and _tree.get("parameters/swing/active")


func set_look_target(target: Variant) -> void:
	_look_target = target


## The player's meshes go on render layer 2, which the first-person camera
## hides (shadows still show), except the arms: sleeves, bracers and hands
## stay on layer 1, so in first person you see your own arms holding things,
## animated exactly as in third person. (Shoulder armour is hidden: it would
## sit right beside the camera.) Everyone else is all on layer 1.
func use_as_player(is_player: bool) -> void:
	_is_player = is_player
	if _character == null:
		return  # applied when the model is built
	for mi in _character.find_children("*", "MeshInstance3D", true, false):
		var arm := mi.name.contains("Arms")  # *_Arms, *_Arms_Bracer
		mi.layers = 2 if is_player and not arm else 1


## Left hand: keep the item upright on top of the hand, facing the way the
## body faces (the arm moves with the animation; the item shouldn't tumble).
func place_carried(item: Item) -> void:
	var aabb: AABB = (item.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
	var basis := Basis(Vector3.UP, global_rotation.y)
	var bottom_centre := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	# The hand bone's origin is the wrist; the palm is ~8 cm along the fingers.
	var palm_top: Vector3 = carry_socket.global_transform * Vector3(0.0, 0.08, 0.0) + Vector3.UP * 0.05
	item.global_transform = Transform3D(basis, palm_top - basis * bottom_centre)


## Right hand: the item is a child of the hand bone's attachment, so it
## follows every frame of the swing on its own. Just set where it sits.
## The item's own hold_rotation_deg.y spins it around its length (the axe
## uses 180° so its blade faces away from you, knuckles-forward); the rest of
## hold_rotation_deg is tuned for the mannequin's arm and doesn't apply here.
##
## In first person the weapon is instead angled relative to the camera (held
## up in view, like a sword at the ready), still sitting in the hand; _fp
## blends between the two so swings ease in and out of it.
func place_equipped(item: Equipable) -> void:
	var spin := Basis(Vector3.UP, deg_to_rad(item.hold_rotation_deg.y))
	var basis := Basis.from_euler(weapon_rotation_deg * (PI / 180.0)) * spin
	item.transform = Transform3D(basis, weapon_offset - basis * item.grip)
	var camera := get_viewport().get_camera_3d()
	if _fp > 0.001 and camera:
		var fp_basis := camera.global_basis * Basis.from_euler(fp_weapon_tilt_deg * (PI / 180.0)) * spin
		var palm := weapon_socket.global_transform * weapon_offset
		var fp_transform := Transform3D(fp_basis, palm - fp_basis * item.grip)
		item.global_transform = item.global_transform.interpolate_with(fp_transform, _fp)


func set_first_person(on: bool) -> void:
	_first_person = on


## Keys (all optional): body_type ("male"/"female"), outfit ("peasant"/
## "ranger"), tunic (Color: the peasant outfit's dye), hood (bool, ranger),
## height_scale, skin, hair (Colors), hair_style ("short"/"long"/"buzzed").
func apply_look(look: Dictionary) -> void:
	var body_type: String = look.get("body_type", "male")
	var outfit: String = look.get("outfit", "peasant")
	if not HEADS.has(body_type) or not OUTFITS.has(outfit):
		push_warning("unknown body_type/outfit: %s/%s" % [body_type, outfit])
		return
	if body_type != _body_type or outfit != _outfit:
		_build(body_type, outfit)
	if not look.get("hood", false):
		_remove_hood()
	scale = Vector3.ONE * look.get("height_scale", 1.0)
	if look.has("skin"):
		_set_skin(look["skin"])
	if outfit == "peasant" and look.has("tunic"):
		_dye(look["tunic"])
	_set_hair(look.get("hair_style", "short"), look.get("hair", Color(0.22, 0.14, 0.09)))
	if look.get("beard", false) and _body_type == "male":
		_add_hair_mesh("Hair_Beard", look.get("hair", Color(0.22, 0.14, 0.09)))
	if look.has("idle"):
		var idle: AnimationNodeAnimation = (_tree.tree_root as AnimationNodeBlendTree).get_node("move").get_blend_point_node(0)
		idle.animation = look["idle"]
	# Start each character at a different point in its animations, so a
	# crowd doesn't breathe and gesture in lockstep.
	_tree.advance(randf() * 3.0)


# --- Building -------------------------------------------------------------------------

func _build(body_type: String, outfit: String) -> void:
	if _character:
		_character.free()  # sockets, tree, head, hair and look modifier go with it
		_hair = null
	_body_type = body_type
	_outfit = outfit
	var prefix := "Male_" if body_type == "male" else "Female_"
	_character = load(OUTFIT_DIR + prefix + OUTFITS[outfit] + ".gltf").instantiate()
	_character.rotation.y = PI  # model faces +Z; ours face -Z
	add_child(_character)
	_skeleton = _character.find_child("Skeleton3D", true, false)
	_add_head(body_type)
	carry_socket = _socket("CarrySocket", "hand_l")
	weapon_socket = _socket("WeaponSocket", "hand_r")
	_setup_look()
	_setup_ik()
	_setup_tree()
	use_as_player(_is_player)


## A BoneAttachment3D follows one bone around; children of it move with the
## hand as the animation plays.
func _socket(socket_name: String, bone: String) -> BoneAttachment3D:
	var attach := BoneAttachment3D.new()
	attach.name = socket_name
	attach.bone_name = bone
	_skeleton.add_child(attach)
	return attach


static func _animations() -> AnimationLibrary:
	if _library == null:
		var scene: Node = load(ANIMATIONS).instantiate()
		_library = scene.get_node("AnimationPlayer").get_animation_library("")
		scene.free()
		# Imported as play-once; we hold this pose as long as a weapon is out.
		_library.get_animation("Sword_Idle").loop_mode = Animation.LOOP_LINEAR
	return _library


func _setup_tree() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_character.add_child(_tree)
	# Track paths in the clips look like "Armature/Skeleton3D:hand_r",
	# relative to the model's root, so that's the tree's root node.
	_tree.root_node = NodePath("..")
	_tree.add_animation_library("", _animations())

	var graph := AnimationNodeBlendTree.new()
	var move := AnimationNodeBlendSpace1D.new()
	for point in [["Idle", 0.0], ["Walk", WALK_SPEED], ["Jog_Fwd", JOG_SPEED], ["Sprint", SPRINT_SPEED]]:
		move.add_blend_point(_clip(point[0]), point[1], -1, point[0])
	move.min_space = 0.0
	move.max_space = SPRINT_SPEED
	graph.add_node("move", move)
	graph.add_node("move_rate", AnimationNodeTimeScale.new())
	graph.connect_node("move_rate", 0, "move")

	graph.add_node("jump", _clip("Jump"))
	graph.add_node("air", AnimationNodeBlend2.new())
	graph.connect_node("air", 0, "move_rate")
	graph.connect_node("air", 1, "jump")

	graph.add_node("torch", _clip("Idle_Torch"))
	var carry := AnimationNodeBlend2.new()
	_filter(carry, _side_bones("_l"))
	graph.add_node("carry", carry)
	graph.connect_node("carry", 0, "air")
	graph.connect_node("carry", 1, "torch")

	graph.add_node("sword_idle", _clip("Sword_Idle"))
	var ready := AnimationNodeBlend2.new()
	_filter(ready, _side_bones("_r"))
	graph.add_node("ready", ready)
	graph.connect_node("ready", 0, "carry")
	graph.connect_node("ready", 1, "sword_idle")

	graph.add_node("attack", _clip("Sword_Attack"))
	graph.add_node("attack_rate", AnimationNodeTimeScale.new())
	graph.connect_node("attack_rate", 0, "attack")
	var swing := AnimationNodeOneShot.new()
	swing.fadein_time = 0.08
	swing.fadeout_time = 0.25
	_filter(swing, ["spine_01", "spine_02", "spine_03", "neck_01"] + _side_bones("_l") + _side_bones("_r"))
	graph.add_node("swing", swing)
	graph.connect_node("swing", 0, "ready")
	graph.connect_node("swing", 1, "attack_rate")

	graph.connect_node("output", 0, "swing")
	_tree.tree_root = graph
	_tree.set("parameters/attack_rate/scale", attack_speed)
	_tree.active = true


func _clip(clip_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


## Arm and finger bones on one side ("_l" or "_r"), not the legs.
func _side_bones(suffix: String) -> Array:
	var bones := []
	for i in _skeleton.get_bone_count():
		var bone := _skeleton.get_bone_name(i)
		if bone.ends_with(suffix) and not (bone.begins_with("thigh") or bone.begins_with("calf")
				or bone.begins_with("foot") or bone.begins_with("ball")):
			bones.append(bone)
	return bones


func _filter(node: AnimationNode, bones: Array) -> void:
	node.filter_enabled = true
	for bone in bones:
		node.set_filter_path(NodePath("Armature/Skeleton3D:" + bone), true)


## The animation clips were recorded on a skeleton with slightly shorter legs,
## so they hold the pelvis a few centimetres too low for these bodies and the
## toes sink into the ground (by an amount that differs per clip). Each frame,
## find the lower of the two feet and lift the whole model until that foot's
## sole touches the ground. Smoothed, so the gait doesn't make it bob, and only
## on the floor (in the air the feet are meant to be off the ground).
func _keep_feet_on_ground(on_floor: bool, delta: float) -> void:
	if not on_floor:
		return
	# Bone poses are relative to the skeleton, whose Y is up (the model is
	# only turned around Y), so .y is the foot's height before our lift.
	var lowest := minf(_skeleton.get_bone_global_pose(_skeleton.find_bone("ball_l")).origin.y,
		_skeleton.get_bone_global_pose(_skeleton.find_bone("ball_r")).origin.y)
	var target := clampf(SOLE - lowest, -0.05, 0.15)
	_ground_offset = lerpf(_ground_offset, target, 1.0 - exp(-8.0 * delta))
	_character.position.y = _ground_offset


# --- First-person arms ------------------------------------------------------------------

## In third person the weapon arm just plays its animation. In first person
## that leaves the hand down by your hip, out of view, so inverse kinematics
## (IK) takes over: you say where the hand should be, and TwoBoneIK3D bends
## the shoulder and elbow to put it there, the way your brain does when you
## reach for something. The "pole" is a point the elbow bends towards
## (down and out, like a relaxed arm).
func _setup_ik() -> void:
	if _ik_target == null:
		_ik_target = Marker3D.new()
		_ik_target.name = "FirstPersonHand"
		add_child(_ik_target)
		_ik_pole = Marker3D.new()
		_ik_pole.name = "FirstPersonElbow"
		add_child(_ik_pole)
	_ik = TwoBoneIK3D.new()
	_ik.setting_count = 1
	_ik.set_root_bone_name(0, "upperarm_r")
	_ik.set_middle_bone_name(0, "lowerarm_r")
	_ik.set_end_bone_name(0, "hand_r")
	_skeleton.add_child(_ik)
	_ik.set_target_node(0, _ik.get_path_to(_ik_target))
	_ik.set_pole_node(0, _ik.get_path_to(_ik_pole))
	_ik.influence = 0.0


## Fade the first-person hold in while the player is in first person with a
## weapon out, and out while swinging (so the attack animation shows).
func _update_first_person_hold(delta: float) -> void:
	var want := 1.0 if _first_person and equipped and not is_swinging() else 0.0
	_fp = lerpf(_fp, want, 1.0 - exp(-12.0 * delta))
	_ik.influence = _fp
	var camera := get_viewport().get_camera_3d()
	if _fp > 0.001 and camera:
		_ik_target.global_position = camera.global_transform * fp_hand_offset
		_ik_pole.global_position = camera.global_transform * Vector3(0.7, -0.9, 0.1)


# --- Looking --------------------------------------------------------------------------

## LookAtModifier3D turns a bone towards a target node after the animation
## has posed the skeleton, within angle limits. We move a marker to whatever
## we're looking at and fade the modifier's influence in and out.
func _setup_look() -> void:
	if _look_marker == null:
		_look_marker = Marker3D.new()
		_look_marker.name = "LookTarget"
		add_child(_look_marker)
	_look = LookAtModifier3D.new()
	_look.bone_name = "Head"
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z  # the head bone faces +Z
	_look.primary_rotation_axis = Vector3.AXIS_Y              # turn left/right first
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(140.0)    # 70° each way
	_look.secondary_limit_angle = deg_to_rad(60.0)   # 30° up/down
	_look.duration = 0.35                            # seconds to swing round to a new target
	_look.influence = 0.0
	_skeleton.add_child(_look)
	_look.target_node = _look.get_path_to(_look_marker)


func _update_look(delta: float) -> void:
	var want := 0.0
	if _look_target != null:
		_look_marker.global_position = _look_target
		var to_target: Vector3 = _look_target - global_position
		var relative := wrapf(atan2(-to_target.x, -to_target.z) - global_rotation.y, -PI, PI)
		if absf(relative) < deg_to_rad(110.0):  # don't try to look behind us
			want = 1.0
	_look.influence = lerpf(_look.influence, want, 1.0 - exp(-4.0 * delta))


# --- Looks ----------------------------------------------------------------------------

## The ranger outfit's hood hides the hair; we show faces by default.
func _remove_hood() -> void:
	for mi in _character.find_children("*Hood*", "MeshInstance3D", true, false):
		mi.free()


## Light or dark skin, whichever texture is nearer the colour. The head has
## both; the outfits only come with the dark body texture, so lighter-skinned
## characters borrow the base character's light texture for their arms too
## (the kit shares one UV layout).
func _set_skin(colour: Color) -> void:
	var texture: Texture2D = load(SKIN_TEXTURES[_body_type][0 if colour.get_luminance() > 0.55 else 1])
	for mi in _skeleton.find_children("*", "MeshInstance3D", false, false):
		for surface in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(surface) as StandardMaterial3D
			if mat and (mat.resource_name.begins_with("MI_Superhero") or mat.resource_name.begins_with("MI_Regular")):
				mat = mat.duplicate()
				mat.albedo_texture = texture
				mi.set_surface_override_material(surface, mat)


## Swap the peasant outfit's material for the dye shader (characters/
## dye.gdshader), which recolours its cloth to `colour`.
func _dye(colour: Color) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://characters/dye.gdshader")
	mat.set_shader_parameter("albedo_texture", load(DYE_TEXTURES["albedo"]))
	mat.set_shader_parameter("normal_texture", load(DYE_TEXTURES["normal"]))
	mat.set_shader_parameter("orm_texture", load(DYE_TEXTURES["orm"]))
	mat.set_shader_parameter("dye_color", colour)
	for mi in _skeleton.find_children("*", "MeshInstance3D", false, false):
		for surface in mi.mesh.get_surface_count():
			var current: Material = mi.get_active_material(surface)
			if current and current.resource_name == "MI_Peasant":
				mi.set_surface_override_material(surface, mat)


## Take the face, eyes and eyebrows from a base character and bind them to
## our skeleton.
func _add_head(body_type: String) -> void:
	var base: Node = load(HEADS[body_type]).instantiate()
	var base_skeleton: Skeleton3D = base.find_child("Skeleton3D", true, false)
	for mi: MeshInstance3D in base.find_children("*", "MeshInstance3D", true, false):
		var mat := mi.get_active_material(0)
		if mat and mat.resource_name.begins_with("MI_Superhero"):
			# The full body: swap in just its head.
			if not _head_meshes.has(body_type):
				_head_meshes[body_type] = _head_only(mi.mesh, mi.skin, base_skeleton)
			mi.mesh = _head_meshes[body_type]
		mi.owner = null  # it belonged to the base scene, which we're about to free
		mi.get_parent().remove_child(mi)
		_skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
	base.free()


## A copy of a skinned mesh keeping only the triangles whose vertices are
## mostly weighted to the head and neck bones. (Each vertex lists up to 4 or 8
## bones and how much each one moves it; we look at the strongest.)
static func _head_only(mesh: Mesh, skin: Skin, skeleton: Skeleton3D) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var vertex_count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var per_vertex := bones.size() / vertex_count  # 4 or 8 influences per vertex
	# Mesh bone indices point into the Skin's bind list, not the skeleton.
	var is_head_bind := []
	for b in skin.get_bind_count():
		var bone_name := skin.get_bind_name(b)
		if bone_name == "":
			bone_name = skeleton.get_bone_name(skin.get_bind_bone(b))
		is_head_bind.append(bone_name in HEAD_BONES)
	var is_head_vertex := PackedByteArray()
	is_head_vertex.resize(vertex_count)
	for v in vertex_count:
		var strongest := 0
		for j in per_vertex:
			if weights[v * per_vertex + j] > weights[v * per_vertex + strongest]:
				strongest = j
		is_head_vertex[v] = 1 if is_head_bind[bones[v * per_vertex + strongest]] else 0
	var old_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array()
	for t in range(0, old_indices.size(), 3):
		if is_head_vertex[old_indices[t]] and is_head_vertex[old_indices[t + 1]] and is_head_vertex[old_indices[t + 2]]:
			indices.append_array([old_indices[t], old_indices[t + 1], old_indices[t + 2]])
	arrays[Mesh.ARRAY_INDEX] = indices
	# Some exports carry extra custom per-vertex channels we don't render;
	# they'd need their exact format flags to rebuild, so drop them.
	for channel in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[channel] = null
	var head := ArrayMesh.new()
	var flags: int = mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	head.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	head.surface_set_material(0, mesh.surface_get_material(0))
	return head


func _set_hair(style: String, colour: Color) -> void:
	_tint_eyebrows(colour)
	if _hair:
		_hair.free()
		_hair = null
	var styles: Dictionary = HAIR[_body_type]
	if styles.has(style):
		_hair = _add_hair_mesh(styles[style], colour)


## Each hair file (hairstyles, the beard) contains the same skeleton plus a
## mesh skinned to its head bone. Take just the mesh, bind it to our skeleton
## and tint it (the texture is a neutral colour meant to be multiplied).
func _add_hair_mesh(file: String, colour: Color) -> MeshInstance3D:
	var scene: Node = load(HAIR_DIR + file + ".gltf").instantiate()
	var mesh: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	mesh.owner = null
	mesh.get_parent().remove_child(mesh)
	scene.free()
	_skeleton.add_child(mesh)
	mesh.skeleton = NodePath("..")
	mesh.layers = 2 if _is_player else 1
	var mat := (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = colour.lightened(0.35)
	mesh.set_surface_override_material(0, mat)
	return mesh


## The eyebrows share the hair texture, which is a neutral grey-brown meant to
## be tinted; give them the same colour as the hair.
func _tint_eyebrows(colour: Color) -> void:
	for mi in _skeleton.find_children("*Eyebrows*", "MeshInstance3D", false, false):
		var mat := (mi.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.albedo_color = colour.lightened(0.2)
		mi.set_surface_override_material(0, mat)
