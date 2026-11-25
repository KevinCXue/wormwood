class_name WorldShape
extends RefCounted
## The natural shape of the land: a flat clearing in the middle, rolling hills
## around it and a ring of mountains near the edge, so the world feels like a
## valley. Shared by tools/build_world.gd (which sculpts the terrain from it)
## and tools/build_village.gd (which reshapes the town area and needs to know
## what the ground looked like before, so re-running it gives the same result).
##
## RefCounted = a plain object that frees itself when nothing uses it (not a
## node in the scene tree). Use: `var shape := WorldShape.new()` then
## `shape.height_at(x, z)`.

const SEED := 1337
const CLEARING_RADIUS := 28.0  # flat village area around the origin

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ridges := FastNoiseLite.new()


func _init() -> void:
	# FastNoiseLite gives smooth pseudo-random values in -1..1. Frequency is
	# "features per metre"; fractal octaves layer finer detail on top.
	hills.seed = SEED
	hills.frequency = 0.008
	hills.fractal_octaves = 4
	detail.seed = SEED + 1
	detail.frequency = 0.05
	ridges.seed = SEED + 2
	ridges.frequency = 0.006
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED  # sharp mountain crests
	ridges.fractal_octaves = 5


## Height of the natural ground at a world position, in metres.
func height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var rolling := (hills.get_noise_2d(x, z) * 0.5 + 0.5) * 16.0 + detail.get_noise_2d(x, z) * 1.2
	var settle := smoothstep(CLEARING_RADIUS, CLEARING_RADIUS + 50.0, r)  # 0 inside the clearing
	var mountains := (ridges.get_noise_2d(x, z) * 0.5 + 0.5) * 110.0 * smoothstep(130.0, 240.0, r)
	return rolling * settle + mountains
