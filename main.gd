extends Node2D

# Number of boids
var BOID_COUNT := 60
var NEW_BOID_COUNT := 60
const INIT_SPEED := 80.0

# Flocking parameters
var NEIGHBOR_RADIUS := 60.0
var SEPARATION_WEIGHT := 1.2
var ALIGNMENT_WEIGHT := 1.0
var COHESION_WEIGHT := 1.0
var MAX_SPEED := 140.0
var MAX_FORCE := 40.0

# Box configuration
const BOX_SIZE := 600.0
const WINDOW_SIZE := 800.0
const BOX_TOPLEFT := Vector2((WINDOW_SIZE - BOX_SIZE) / 2, 0)

var positions := PackedVector2Array()
var velocities := PackedVector2Array()

# Spatial partitioning
var grid: Dictionary[Vector2i, Array]= {}  # Dictionary: Vector2i -> Array[int] (cell coords -> boid indices)

@onready var birds := MultiMeshInstance2D.new()

@onready var separation_slider: HSlider = %SeparationSlider
@onready var alignment_slider: HSlider = %AlignmentSlider
@onready var cohesion_slider: HSlider = %CohesionSlider
@onready var force_slider: HSlider = %ForceSlider
@onready var velocity_slider: HSlider = %VelocitySlider
@onready var radius_slider: HSlider = %RadiusSlider

# Label nodes for displaying current values
@onready var separation_label: Label = %SeparationLabel
@onready var alignment_label: Label = %AlignmentLabel
@onready var cohesion_label: Label = %CohesionLabel
@onready var force_label: Label = %ForceLabel
@onready var velocity_label: Label = %VelocityLabel
@onready var number_of_boids_label: Label = %NumberOfBoidsLabel
@onready var radius_label: Label = %RadiusLabel

@onready var number_of_boids: HSlider = %NumberOfBoids
@onready var restart_simulation_button: Button = %RestartSimulationButton

var update_frequency := 2  # Update every frame by default
var frame_counter := 0

func _ready():
	number_of_boids.value = BOID_COUNT
	number_of_boids_label.text = "Boids: %s" % str(BOID_COUNT).lpad(4)
	radius_label.text = "Radius: %s" % str(NEIGHBOR_RADIUS)
	_config_sliders()
	_init_boid_data()
	_init_multimesh()
	_update_rotation_and_position_drawn()

func _init_boid_data():
	for i in BOID_COUNT:
		positions.append(BOX_TOPLEFT + Vector2(
			randf_range(50, BOX_SIZE - 50),
			randf_range(50, BOX_SIZE - 50)
		))
		velocities.append(Vector2.RIGHT.rotated(randf() * TAU) * INIT_SPEED)

func _init_multimesh():
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.instance_count = BOID_COUNT
	mm.mesh = _make_boid_mesh()
	birds.multimesh = mm
	add_child(birds)

func _process(delta):
	frame_counter += 1
	if frame_counter % update_frequency == 0:
		_update_boid_positions_and_velocities(delta)
		_update_rotation_and_position_drawn()

func _build_spatial_grid():
	var cell_size: float = max(NEIGHBOR_RADIUS, 50.0)
	grid.clear()

	for i in range(BOID_COUNT):
		var cell_x: int = int((positions[i].x - BOX_TOPLEFT.x) / cell_size)
		var cell_y: int = int((positions[i].y - BOX_TOPLEFT.y) / cell_size)
		var cell_coord: Vector2i = Vector2i(cell_x, cell_y)

		if not grid.has(cell_coord):
			grid[cell_coord] = []
		grid[cell_coord].append(i)

func _get_nearby_boids(i: int) -> Array:
	var cell_size: float = max(NEIGHBOR_RADIUS, 50.0)
	var cell_x:int = int((positions[i].x - BOX_TOPLEFT.x) / cell_size)
	var cell_y:int = int((positions[i].y - BOX_TOPLEFT.y) / cell_size)

	var nearby: Array[int] = []

	# Check 3x3 grid around the boid's cell
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var check_cell:Vector2i = Vector2i(cell_x + dx, cell_y + dy)
			if grid.has(check_cell):
				nearby.append_array(grid[check_cell])
	return nearby

func _update_boid_positions_and_velocities(delta):
	_build_spatial_grid()

	for i in range(BOID_COUNT):
		var acceleration = _calc_flocking_forces(i)
		velocities[i] += acceleration * delta
		if velocities[i].length() > MAX_SPEED:
			velocities[i] = velocities[i].normalized() * MAX_SPEED
		positions[i] += velocities[i] * delta

		# Boundary handling
		if positions[i].x < BOX_TOPLEFT.x:
			positions[i].x = BOX_TOPLEFT.x + BOX_SIZE
		elif positions[i].x > BOX_TOPLEFT.x + BOX_SIZE:
			positions[i].x = BOX_TOPLEFT.x
		if positions[i].y < BOX_TOPLEFT.y:
			positions[i].y = BOX_TOPLEFT.y + BOX_SIZE
		elif positions[i].y > BOX_TOPLEFT.y + BOX_SIZE:
			positions[i].y = BOX_TOPLEFT.y

func _calc_flocking_forces(i: int) -> Vector2:
	var separation := Vector2.ZERO
	var alignment := Vector2.ZERO
	var cohesion := Vector2.ZERO
	var count := 0

	# Only check nearby boids using spatial partitioning
	for j in _get_nearby_boids(i):
		if i == j:
			continue
		var dist_sq: float = positions[i].distance_squared_to(positions[j])
		if dist_sq < NEIGHBOR_RADIUS * NEIGHBOR_RADIUS and dist_sq > 0:
			var dist: float = sqrt(dist_sq)
			separation += (positions[i] - positions[j]) / max(dist, 0.01)
			alignment += velocities[j]
			cohesion += positions[j]
			count += 1

	var steer = Vector2.ZERO
	if count > 0:
		# Process all three at once
		separation = (separation / count).normalized() * MAX_SPEED - velocities[i]
		alignment = ((alignment / count).normalized() * MAX_SPEED - velocities[i])
		cohesion = (((cohesion / count) - positions[i]).normalized() * MAX_SPEED - velocities[i])

		separation = separation.limit_length(MAX_FORCE)
		alignment = alignment.limit_length(MAX_FORCE)
		cohesion = cohesion.limit_length(MAX_FORCE)

		steer = separation * SEPARATION_WEIGHT + alignment * ALIGNMENT_WEIGHT + cohesion * COHESION_WEIGHT

	return steer

func _update_rotation_and_position_drawn():
	var transforms: MultiMesh = birds.multimesh
	for i in range(BOID_COUNT):
		var xform = Transform2D(velocities[i].angle(), positions[i])
		transforms.set_instance_transform_2d(i, xform)
	birds.multimesh = transforms

func _draw():
	draw_rect(Rect2(BOX_TOPLEFT, Vector2(BOX_SIZE, BOX_SIZE)), Color.RED, false, 2.0)

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

func _config_sliders() -> void:
	separation_slider.min_value = 1.0
	separation_slider.max_value = 2.0
	separation_slider.step = 0.1
	separation_slider.value = SEPARATION_WEIGHT

	alignment_slider.min_value = 1.0
	alignment_slider.max_value = 2.0
	alignment_slider.step = 0.1
	alignment_slider.value = ALIGNMENT_WEIGHT

	cohesion_slider.min_value = 1.0
	cohesion_slider.max_value = 2.0
	cohesion_slider.step = 0.1
	cohesion_slider.value = COHESION_WEIGHT

	force_slider.min_value = 40.0
	force_slider.max_value = 80.0
	force_slider.step = 1.0
	force_slider.value = MAX_FORCE

	velocity_slider.min_value = 140.0
	velocity_slider.max_value = 280.0
	velocity_slider.step = 10.0
	velocity_slider.value = MAX_SPEED

func _on_separation_slider_value_changed(value: float) -> void:
	SEPARATION_WEIGHT = value
	separation_label.text = "Separation: %.2f" % value


func _on_alignment_slider_value_changed(value: float) -> void:
	ALIGNMENT_WEIGHT = value
	alignment_label.text = "Alignment: %.2f" % value


func _on_cohesion_slider_value_changed(value: float) -> void:
	COHESION_WEIGHT = value
	cohesion_label.text = "Cohesion: %.2f" % value


func _on_force_slider_value_changed(value: float) -> void:
	MAX_FORCE = value
	force_label.text = "Force: %.0f" % value


func _on_velocity_slider_value_changed(value: float) -> void:
	MAX_SPEED = value
	velocity_label.text = "Speed: %.0f" % value


func _on_restart_simulation_button_pressed() -> void:
	positions.clear()
	velocities.clear()
	BOID_COUNT = NEW_BOID_COUNT
	if birds.multimesh:
		birds.multimesh.instance_count = BOID_COUNT
	_init_boid_data()
	_update_rotation_and_position_drawn()


func _on_number_of_boids_value_changed(value: float) -> void:
	NEW_BOID_COUNT = int(value)
	number_of_boids_label.text = "Boids: %s" % str(NEW_BOID_COUNT).lpad(4)


func _on_radius_slider_value_changed(value: float) -> void:
	NEIGHBOR_RADIUS = value
	radius_label.text = "Radius: %s" % str(NEIGHBOR_RADIUS)
