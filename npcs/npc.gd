class_name Npc
extends CharacterBody3D
## A villager. For now they stand in one spot, breathe, turn their head to
## watch you when you come near, and say a line when you talk to them (E).
##
## The body is the same greybox mannequin as the player (mannequin.tscn),
## re-coloured and given hair (and optionally a skirt) in _ready(). Everything
## that makes one villager different from another is an @export below, so a
## new villager is just another instance of npc.tscn with different values in
## the Inspector.
##
## Why CharacterBody3D? It's the body type for things that move under their
## own control (like the player). These villagers don't walk yet, but when
## they do, the node type is already right. Until then it's a solid capsule
## the player bumps into.

@export var display_name := "Villager"
@export_multiline var lines: PackedStringArray = ["Hello there."]

@export_group("Look")
@export var skin_color := Color(0.78, 0.62, 0.5)
@export var tunic_color := Color(0.4, 0.4, 0.4)
@export var trousers_color := Color(0.25, 0.2, 0.16)
@export var boots_color := Color(0.14, 0.1, 0.08)
@export var hair_color := Color(0.25, 0.16, 0.1)
@export_enum("short", "long") var hair_style := "short"
@export var skirt := false
@export_range(0.8, 1.2) var height_scale := 1.0

@export_group("Behaviour")
@export var notice_range := 7.0  # metres: closer than this and they watch you
@export var turn_speed := 4.0    # how quickly head and body turn

## Mannequin meshes grouped by what they're made of, so each group can be
## given this villager's colour. (Names match the nodes in mannequin.tscn.)
const PARTS := {
	"skin": ["Head", "Nose", "Forearm", "Hand"],
	"tunic": ["Torso", "UpperArm"],
	"trousers": ["Pelvis", "Thigh", "Shin"],
	"boots": ["Foot"],
}
const MAX_HEAD_TURN := 1.2  # radians (~70°): necks don't turn further
const ATTENTION_TIME := 6.0 # seconds they keep facing you after you talk

@onready var _model: Node3D = $Model
@onready var _head: Node3D = $Model/Hips/Spine/Head

var _player: Node3D = null
var _line := 0
var _home_yaw := 0.0       # the way the model faced when the game started
var _attention := 0.0      # seconds left of turning to face the player


func _ready() -> void:
	add_to_group("npcs")
	_home_yaw = _model.rotation.y
	_model.scale = Vector3.ONE * height_scale
	_dress()
	# The player adds itself to the "player" group (player.gd). Looking it up
	# by group means this scene doesn't need a hard-coded path to the player.
	_player = get_tree().get_first_node_in_group("player")


## Next line of dialogue. Steps through `lines` and then repeats the last
## one, the way a villager runs out of new things to say.
func talk() -> String:
	_attention = ATTENTION_TIME
	var text := lines[mini(_line, lines.size() - 1)] if lines.size() > 0 else "..."
	_line += 1
	return text


func _physics_process(delta: float) -> void:
	# Standing still: speed 0 gives the idle pose with its slow breathing.
	_model.update_pose(0.0, true, delta)
	var k := 1.0 - exp(-turn_speed * delta)

	var to_player := Vector3.ZERO
	var near := false
	if _player:
		to_player = _player.global_position - global_position
		to_player.y = 0.0
		near = to_player.length() < notice_range

	# Body: after you talk to them, turn to face you; otherwise drift back to
	# the way they were placed in the editor.
	_attention = maxf(_attention - delta, 0.0)
	var body_target := _home_yaw
	if _attention > 0.0 and near:
		# The model's rotation is relative to this node, so subtract our own.
		body_target = _yaw_towards(to_player) - global_rotation.y
	_model.rotation.y = lerp_angle(_model.rotation.y, body_target, k)

	# Head: follow the player while they're nearby and not behind us.
	var head_target := 0.0
	if near:
		var relative := wrapf(_yaw_towards(to_player) - _model.global_rotation.y, -PI, PI)
		if absf(relative) < MAX_HEAD_TURN + 0.4:
			head_target = clampf(relative, -MAX_HEAD_TURN, MAX_HEAD_TURN)
	_head.rotation.y = lerp_angle(_head.rotation.y, head_target, k * 1.5)


## The Y rotation at which a node's forward (-Z) points along `dir`.
func _yaw_towards(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


# --- Appearance -------------------------------------------------------------------

func _dress() -> void:
	var colours := {
		"skin": skin_color, "tunic": tunic_color,
		"trousers": trousers_color, "boots": boots_color,
	}
	for group in PARTS:
		var mat := _mat(colours[group])
		for part in PARTS[group]:
			for mi in _model.find_children(part, "MeshInstance3D", true, false):
				# The mannequin's meshes (and their materials) are shared by
				# everyone who uses mannequin.tscn, including the player.
				# surface_override_material changes just this one node.
				mi.set_surface_override_material(0, mat)

	# The player's mannequin puts its body on render layer 2 so the
	# first-person camera can hide it. A villager must stay visible to that
	# camera, so move every mesh back to layer 1.
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1

	var hair := _mat(hair_color)
	# Short hair: a cap over the top half of the head (a hemisphere).
	var cap := SphereMesh.new()
	cap.radius = 0.118
	cap.height = 0.125
	cap.is_hemisphere = true
	_attach(_head, cap, hair, Vector3(0, 0.005, 0.008), Vector3(1.0, 1.15, 1.05))
	if hair_style == "long":
		# Long hair: a curtain down the back to the shoulders, plus a fringe
		# of it framing each side of the face.
		var back := BoxMesh.new()
		back.size = Vector3(0.22, 0.3, 0.07)
		_attach(_head, back, hair, Vector3(0, -0.1, 0.075))
		for side in [-1, 1]:
			var lock := BoxMesh.new()
			lock.size = Vector3(0.04, 0.2, 0.09)
			_attach(_head, lock, hair, Vector3(side * 0.1, -0.06, 0.01))

	if skirt:
		# A flared cylinder hanging from the hips to just below the knees.
		var cone := CylinderMesh.new()
		cone.top_radius = 0.175
		cone.bottom_radius = 0.3
		cone.height = 0.55
		_attach($Model/Hips, cone, _mat(tunic_color.darkened(0.15)), Vector3(0, -0.22, 0))


func _attach(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scale := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)


func _mat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	return m
