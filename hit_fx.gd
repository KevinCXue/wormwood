class_name HitFx
## Small reusable hit effects. All functions are `static`, so you call them
## on the class itself: HitFx.burst(self, position, Color.YELLOW).


## A one-shot puff of little flakes (straw, wood chips) at `pos`, flying out
## mostly along `direction`. Frees itself when done.
static func burst(parent: Node, pos: Vector3, color: Color, direction := Vector3.UP,
		amount := 24, size := 0.04, speed := 3.0) -> void:
	# CPUParticles3D simulates many tiny meshes cheaply. one_shot + explosiveness 1
	# = emit all of them at once, a single time.
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.9
	var flake := BoxMesh.new()
	flake.size = Vector3(size, size * 0.3, size * 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	flake.material = mat
	p.mesh = flake
	p.direction = (direction + Vector3.UP * 0.6).normalized()
	p.spread = 50.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	parent.get_tree().root.add_child(p)  # in the world, not on the (moving) thing that was hit
	p.global_position = pos
	p.emitting = true
	# Free it once the last flake has landed.
	p.get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)
