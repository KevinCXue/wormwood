extends OmniLight3D
## A warm light that flickers like a candle or lantern flame.
##
## OmniLight3D shines in all directions from a point, fading out by `range`.
## We wobble its brightness with smooth noise (not random jumps, which look
## like a broken bulb) and scale the visible flame mesh along with it.

@export var flicker_amount := 0.18  # +/- fraction of the base brightness
@export var flicker_speed := 9.0
@export var flame_path: NodePath = ^"../Flame"  # the little glowing mesh, if any

var _base_energy := 1.0
var _noise := FastNoiseLite.new()
var _t := 0.0
@onready var _flame: Node3D = get_node_or_null(flame_path)


func _ready() -> void:
	_base_energy = light_energy
	_noise.frequency = 1.0
	_noise.seed = randi()  # so neighbouring flames don't flicker in sync


func _process(delta: float) -> void:
	_t += delta * flicker_speed
	var n := _noise.get_noise_1d(_t)  # smooth value in about -1..1
	light_energy = _base_energy * (1.0 + n * flicker_amount)
	if _flame:
		# Flames stretch taller as they brighten.
		_flame.scale = Vector3(1.0, 1.0 + n * 0.25, 1.0)
