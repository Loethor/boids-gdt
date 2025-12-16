extends Node2D


const BOID_COUNT := 60
const BOX_SIZE := 600.0

# Flocking parameters
const NEIGHBOR_RADIUS := 60.0
const SEPARATION_WEIGHT := 1.2
const ALIGNMENT_WEIGHT := 1.0
const COHESION_WEIGHT := 1.0
const MAX_SPEED := 140.0
const MAX_FORCE := 40.0

var positions := PackedVector2Array()
var velocities := PackedVector2Array()

@onready var birds := MultiMeshInstance2D.new()

func _ready():
	_init_boid_data()
	_init_multimesh()
	_update_rotation_and_position_drawn()

func _init_boid_data():
	for i in BOID_COUNT:
		positions.append(Vector2(
			randf_range(50, BOX_SIZE - 50),
			randf_range(50, BOX_SIZE - 50)
		))
		velocities.append(Vector2.RIGHT.rotated(randf() * TAU) * 80.0)

func _init_multimesh():
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.instance_count = BOID_COUNT
	mm.mesh = _make_boid_mesh()
	birds.multimesh = mm
	add_child(birds)

func _process(delta):
	_update_boid_positions_and_velocities(delta)
	_update_rotation_and_position_drawn()

func _update_boid_positions_and_velocities(delta):
	for i in range(BOID_COUNT):
		var separation := _calc_separation(i)
		var alignment := _calc_alignment(i)
		var cohesion := _calc_cohesion(i)
		var acceleration = (
			separation * SEPARATION_WEIGHT +
			alignment * ALIGNMENT_WEIGHT +
			cohesion * COHESION_WEIGHT
		)
		velocities[i] += acceleration * delta
		if velocities[i].length() > MAX_SPEED:
			velocities[i] = velocities[i].normalized() * MAX_SPEED
		positions[i] += velocities[i] * delta
		_handle_boundaries(i)

func _calc_separation(i: int) -> Vector2:
	var steer := Vector2.ZERO
	var count := 0
	for j in range(BOID_COUNT):
		if i == j:
			continue
		var dist = positions[i].distance_to(positions[j])
		if dist < NEIGHBOR_RADIUS and dist > 0:
			steer += (positions[i] - positions[j]) / max(dist, 0.01)
			count += 1
	if count > 0:
		steer /= count
		steer = steer.normalized() * MAX_SPEED - velocities[i]
		steer = steer.limit_length(MAX_FORCE)
	return steer

func _calc_alignment(i: int) -> Vector2:
	var avg_vel := Vector2.ZERO
	var count := 0
	for j in range(BOID_COUNT):
		if i == j:
			continue
		var dist = positions[i].distance_to(positions[j])
		if dist < NEIGHBOR_RADIUS:
			avg_vel += velocities[j]
			count += 1
	if count > 0:
		avg_vel /= count
		var steer = avg_vel.normalized() * MAX_SPEED - velocities[i]
		steer = steer.limit_length(MAX_FORCE)
		return steer
	return Vector2.ZERO

func _calc_cohesion(i: int) -> Vector2:
	var center := Vector2.ZERO
	var count := 0
	for j in range(BOID_COUNT):
		if i == j:
			continue
		var dist = positions[i].distance_to(positions[j])
		if dist < NEIGHBOR_RADIUS:
			center += positions[j]
			count += 1
	if count > 0:
		center /= count
		var steer = (center - positions[i]).normalized() * MAX_SPEED - velocities[i]
		steer = steer.limit_length(MAX_FORCE)
		return steer
	return Vector2.ZERO

func _handle_boundaries(i):
	if positions[i].x < 0:
		positions[i].x = BOX_SIZE
	elif positions[i].x > BOX_SIZE:
		positions[i].x = 0
	if positions[i].y < 0:
		positions[i].y = BOX_SIZE
	elif positions[i].y > BOX_SIZE:
		positions[i].y = 0

func _update_rotation_and_position_drawn():
	for i in BOID_COUNT:
		var xform = Transform2D(velocities[i].angle(), positions[i])
		birds.multimesh.set_instance_transform_2d(i, xform)

func _draw():
	draw_rect(Rect2(Vector2.ZERO, Vector2(BOX_SIZE, BOX_SIZE)), Color.RED, false, 2.0)

func _make_boid_mesh() -> ArrayMesh:
	# Create a simple triangle mesh for the boid
	var mesh := ArrayMesh.new()
	var vertices := PackedVector2Array([
		Vector2(0, -8),
		Vector2(16, 0),
		Vector2(0, 8)
	])
	var indices = PackedInt32Array([0, 1, 2])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
