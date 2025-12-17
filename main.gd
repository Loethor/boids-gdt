extends Node2D

# Number of boids
var BOID_COUNT := 60
var NEW_BOID_COUNT := 60
const INIT_SPEED := 80.0

# Flocking parameters
var NEIGHBOR_RADIUS := 60.0
var NEIGHBOR_RADIUS_SQ := 3600.0
var SEPARATION_WEIGHT := 1.2
var ALIGNMENT_WEIGHT := 1.0
var COHESION_WEIGHT := 1.0
var MAX_SPEED := 140.0
var MAX_FORCE := 40.0

# Box configuration
const BOX_SIZE := 600.0
const WINDOW_SIZE := 800.0
var BOX_TOPLEFT := Vector2.ZERO

var positions := PackedVector2Array()
var velocities := PackedVector2Array()

# Spatial partitioning
var grid: Dictionary[Vector2i, Array] = {}

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
var is_debug_enabled := false

var last_update_frame := -1

func _ready():
	_update_box_position()
	number_of_boids.value = BOID_COUNT
	number_of_boids_label.text = "Boids: %s" % str(BOID_COUNT).lpad(4)
	radius_label.text = "Radius: %s" % str(NEIGHBOR_RADIUS)
	_config_sliders()
	_init_boid_data()
	_init_multimesh()
	_update_rotation_and_position_drawn()
	queue_redraw()

func _update_box_position():
	var viewport_size = get_viewport_rect().size
	BOX_TOPLEFT = Vector2(
		(viewport_size.x - BOX_SIZE) / 2,
		0
	)

func _init_boid_data():
	positions.resize(BOID_COUNT)
	velocities.resize(BOID_COUNT)

	for i in BOID_COUNT:
		positions[i] = BOX_TOPLEFT + Vector2(
			randf_range(50, BOX_SIZE - 50),
			randf_range(50, BOX_SIZE - 50)
		)
		velocities[i] = Vector2.RIGHT.rotated(randf() * TAU) * INIT_SPEED

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
		if is_debug_enabled:
			queue_redraw()

func _build_spatial_grid():
	var cell_size: float = max(NEIGHBOR_RADIUS, 50.0)

	for key in grid:
		grid[key].clear()

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

		# Boundary wrapping
		positions[i].x = fposmod(positions[i].x - BOX_TOPLEFT.x, BOX_SIZE) + BOX_TOPLEFT.x
		positions[i].y = fposmod(positions[i].y - BOX_TOPLEFT.y, BOX_SIZE) + BOX_TOPLEFT.y

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
		if dist_sq < NEIGHBOR_RADIUS_SQ and dist_sq > 0:
			# Separation: inverse square for more natural repulsion
			var diff = positions[i] - positions[j]
			separation += diff / max(dist_sq, 0.01)

			# Alignment: average velocity
			alignment += velocities[j]

			# Cohesion: average position
			cohesion += positions[j]
			count += 1

	var steer = Vector2.ZERO
	if count > 0:
		# Separation: separate from neighbors
		if separation.length_squared() > 0:
			separation = separation.normalized() * MAX_SPEED - velocities[i]
			separation = separation.limit_length(MAX_FORCE)

		# Alignment: steer towards average velocity
		alignment = (alignment / count).normalized() * MAX_SPEED - velocities[i]
		alignment = alignment.limit_length(MAX_FORCE)

		# Cohesion: steer towards average position
		cohesion = ((cohesion / count) - positions[i]).normalized() * MAX_SPEED - velocities[i]
		cohesion = cohesion.limit_length(MAX_FORCE)

		steer = separation * SEPARATION_WEIGHT + alignment * ALIGNMENT_WEIGHT + cohesion * COHESION_WEIGHT

	return steer

func _update_rotation_and_position_drawn():

	if last_update_frame == frame_counter:
		return  # Already updated this frame
	last_update_frame = frame_counter

	var transforms: MultiMesh = birds.multimesh
	for i in range(BOID_COUNT):
		var xform = Transform2D(velocities[i].angle(), positions[i])
		transforms.set_instance_transform_2d(i, xform)
	birds.multimesh = transforms

func _draw():
	draw_rect(Rect2(BOX_TOPLEFT, Vector2(BOX_SIZE, BOX_SIZE)), Color.RED, false, 2.0)

	if is_debug_enabled and BOID_COUNT > 0:
		# Draw neighbor radius circle around first boid
		draw_circle(positions[0], NEIGHBOR_RADIUS, Color(1, 0, 0, 0.3))
		draw_arc(positions[0], NEIGHBOR_RADIUS, 0, TAU, 32, Color(1, 0, 0, 0.8), 2.0)

		# Draw spatial grid partitioning
		var cell_size: float = max(NEIGHBOR_RADIUS, 50.0)
		var cols: int = int(BOX_SIZE / cell_size) + 1
		var rows: int = int(BOX_SIZE / cell_size) + 1

		# Draw vertical grid lines
		for i in range(cols):
			var x: float = BOX_TOPLEFT.x + i * cell_size
			draw_line(Vector2(x, BOX_TOPLEFT.y), Vector2(x, BOX_TOPLEFT.y + BOX_SIZE), Color(0, 1, 0, 0.3), 1.0)

		# Draw horizontal grid lines
		for i in range(rows):
			var y: float = BOX_TOPLEFT.y + i * cell_size
			draw_line(Vector2(BOX_TOPLEFT.x, y), Vector2(BOX_TOPLEFT.x + BOX_SIZE, y), Color(0, 1, 0, 0.3), 1.0)

		# Highlight cells that contain boids
		for cell_coord in grid:
			if grid[cell_coord].size() > 0:
				var cell_x: float = BOX_TOPLEFT.x + cell_coord.x * cell_size
				var cell_y: float = BOX_TOPLEFT.y + cell_coord.y * cell_size
				draw_rect(Rect2(cell_x, cell_y, cell_size, cell_size), Color(0, 1, 0, 0.1), true)

func _make_boid_mesh() -> ArrayMesh:

	# Create a simple triangle mesh for the boid
	var mesh := ArrayMesh.new()
	var vertices := PackedVector2Array([
		Vector2(0, -8),
		Vector2(16, 0),
		Vector2(0, 8)
	])
	var indices = PackedInt32Array([0, 1, 2])
	var arrays: Array = []
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

	# Adjust update frequency based on boid count for performance
	if BOID_COUNT > 1000:
		update_frequency = 3
	elif BOID_COUNT > 500:
		update_frequency = 2
	else:
		update_frequency = 1

	if birds.multimesh:
		birds.multimesh.instance_count = BOID_COUNT
	_init_boid_data()
	_update_rotation_and_position_drawn()


func _on_number_of_boids_value_changed(value: float) -> void:
	NEW_BOID_COUNT = int(value)
	number_of_boids_label.text = "Boids: %s" % str(NEW_BOID_COUNT).lpad(4)


func _on_radius_slider_value_changed(value: float) -> void:
	NEIGHBOR_RADIUS = value
	NEIGHBOR_RADIUS_SQ = value * value
	radius_label.text = "Radius: %s" % str(NEIGHBOR_RADIUS)
	if is_debug_enabled:
		queue_redraw()  # Update debug circle radius


func _on_debug_button_toggled(toggled_on: bool) -> void:
	is_debug_enabled = toggled_on
	queue_redraw()  # Redraw to show/hide debug circle immediately
