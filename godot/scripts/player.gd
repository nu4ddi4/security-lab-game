class_name LabPlayer
extends CharacterBody3D

signal inspect_requested(target: Node)
signal tool_requested(target: Node)
signal pause_requested
var camera: Camera3D
var ray: RayCast3D
var shape: CollisionShape3D
var target: Node
var enabled = false
var touch_controls_enabled = false
var touch_axes = Vector2.ZERO
var settings_input_blocked = false
var release_keys: Array = []
var crouched = false
var sensitivity = 0.0018
var body_height = 1.8
var movement_seconds = 0.0
var jump_peak = 0.0
var jump_count = 0
var standing_shape = CapsuleShape3D.new()
var unified_interaction = false
var interaction_reach = 3.4
var aim_assist: ShapeCast3D
var aim_screen_point = Vector2(-1,-1)
var application_focused = true
var capture_suspended = false

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		application_focused = false
		capture_suspended = not OS.has_feature("mobile") and not touch_controls_enabled
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		velocity = Vector3.ZERO
		touch_axes = Vector2.ZERO
		for action in LabInputBindings.ACTIONS: Input.action_release(action.id)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		application_focused = true
		# Returning from the taskbar must leave the cursor free until a field click.
		if capture_suspended: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func restore_mouse_mode(mode):
	Input.mouse_mode = mode if application_focused and not capture_suspended else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and enabled and application_focused and capture_suspended and not settings_input_blocked:
		capture_suspended = false
		set_enabled(true)
		get_viewport().set_input_as_handled()
		return
	if input_blocked(): return
	if event.is_action_pressed("pause"):
		pause_requested.emit()
		get_viewport().set_input_as_handled()
	if not enabled: return
	if event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		look(event.relative)
	if not unified_interaction and event.is_action_pressed("inspect") and target != null: inspect_requested.emit(target)
	if event.is_action_pressed("tool") and target != null: interact()

func _ready():
	collision_layer = 8
	collision_mask = 1
	floor_snap_length = 0.12
	standing_shape.radius = 0.305
	standing_shape.height = 1.8
	shape = CollisionShape3D.new()
	shape.shape = standing_shape.duplicate()
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 72
	camera.far = 1600
	add_child(camera)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.65)
	ray.collision_mask = 6
	ray.collide_with_areas = true
	ray.add_exception(self)
	camera.add_child(ray)
	aim_assist = ShapeCast3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = .16
	aim_assist.shape = sphere
	aim_assist.collision_mask = 6
	aim_assist.collide_with_areas = true
	aim_assist.add_exception(self)
	aim_assist.enabled = false
	camera.add_child(aim_assist)

func set_enabled(value: bool):
	enabled = value
	restore_mouse_mode(Input.MOUSE_MODE_CAPTURED if value and not touch_controls_enabled and not OS.has_feature("mobile") else Input.MOUSE_MODE_VISIBLE)
	if not value:
		velocity = Vector3.ZERO
		touch_axes = Vector2.ZERO

func look(relative: Vector2):
	if not enabled or input_blocked(): return
	rotate_y(-relative.x * sensitivity)
	camera.rotation.x = clampf(camera.rotation.x - relative.y * sensitivity, -1.42, 1.42)

func interact():
	if not enabled or input_blocked() or target == null: return
	if target.has_method("open_tool"): tool_requested.emit(target)
	elif unified_interaction and target.has_method("inspect"): inspect_requested.emit(target)

func update_target():
	if unified_interaction:
		var direction = -camera.global_basis.z
		if aim_screen_point.x >= 0:
			direction = camera.project_ray_normal(aim_screen_point)
		elif DisplayServer.get_name() != "headless" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not OS.has_feature("mobile") and not touch_controls_enabled:
			direction = camera.project_ray_normal(get_viewport().get_mouse_position())
		ray.target_position = camera.global_basis.inverse() * direction * interaction_reach
	ray.force_raycast_update()
	target = ray.get_collider() if ray.is_colliding() else null
	if target != null and target.has_method("get_interaction_prompt"): return
	target = null
	if not unified_interaction: return
	# Screen-edge tolerance without enlarging or overlapping equipment volumes.
	aim_assist.target_position = ray.target_position
	aim_assist.force_shapecast_update()
	var best = INF
	for i in range(aim_assist.get_collision_count()):
		var candidate = aim_assist.get_collider(i)
		if candidate == null or not candidate.has_method("get_interaction_prompt"): continue
		var point = aim_assist.get_collision_point(i)
		var offset = point - camera.global_position
		if offset.length() > interaction_reach: continue
		var query = PhysicsRayQueryParameters3D.create(camera.global_position,point + offset.normalized()*.025,6,[get_rid()])
		query.collide_with_areas = true
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider != candidate: continue
		var score = offset.length_squared()
		if score < best:
			best = score
			target = candidate

func _physics_process(delta):
	update_target()
	if not enabled or input_blocked(): velocity = Vector3.ZERO; return
	var wants_crouch = Input.is_action_pressed("crouch")
	if crouched and not wants_crouch:
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = standing_shape
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.91, 0))
		query.collision_mask = 1
		query.exclude = [get_rid()]
		wants_crouch = not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	crouched = wants_crouch
	body_height = 1.1 if crouched else 1.8
	shape.shape.height = body_height
	shape.position.y = body_height / 2.0
	camera.position.y = lerpf(camera.position.y, 0.95 if crouched else 1.65, 1.0 - exp(-delta * 18.0))
	var axes = (Input.get_vector("left", "right", "forward", "back") + touch_axes).limit_length()
	var direction = global_basis * Vector3(axes.x, 0, axes.y)
	var speed = 1.35 if crouched else 4.2 if Input.is_action_pressed("sprint") else 2.6
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if axes.length() > 0: movement_seconds += delta
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = 4.3
		jump_count += 1
	elif not is_on_floor(): velocity.y -= 12.5 * delta
	else: velocity.y = 0
	move_and_slide()
	jump_peak = maxf(jump_peak, global_position.y)
	if global_position.y < -3: respawn()

func respawn():
	global_position = Vector3(0, 0.01, 11.7)
	rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	velocity = Vector3.ZERO

func input_blocked() -> bool:
	release_keys = release_keys.filter(func(key): return Input.is_physical_key_pressed(key))
	return settings_input_blocked or not release_keys.is_empty() or not application_focused or capture_suspended
