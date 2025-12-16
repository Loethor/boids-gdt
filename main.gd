extends Node2D

const BOID_COUNT := 20
const BOX_SIZE := 600.0

var positions := PackedVector2Array()
var velocities := PackedVector2Array()

@onready var birds := MultiMeshInstance2D.new()

func _ready():
	_init_boid_data()
	_init_multimesh()
	update_boids()

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
	update_boids()

func _update_boid_positions_and_velocities(delta):
	for i in range(BOID_COUNT):
		positions[i] += velocities[i] * delta
		_handle_boundaries(i)

func _handle_boundaries(i):
	if positions[i].x < 0:
		positions[i].x = BOX_SIZE
	elif positions[i].x > BOX_SIZE:
		positions[i].x = 0
	if positions[i].y < 0:
		positions[i].y = BOX_SIZE
	elif positions[i].y > BOX_SIZE:
		positions[i].y = 0

func update_boids():
	for i in BOID_COUNT:
		var xform = Transform2D(velocities[i].angle(), positions[i])
		birds.multimesh.set_instance_transform_2d(i, xform)

func _draw():
	draw_rect(Rect2(Vector2.ZERO, Vector2(BOX_SIZE, BOX_SIZE)), Color.RED, false, 2.0)

func _make_boid_mesh() -> ArrayMesh:
	# Create a simple triangle mesh for the boid
	var mesh := ArrayMesh.new()
	var vertices = PackedVector2Array([
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
