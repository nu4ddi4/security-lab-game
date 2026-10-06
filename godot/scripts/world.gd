class_name LabWorld
extends Node3D

var model: Node3D
var devices: Dictionary = {}
var doors: Dictionary = {}
var protected_nodes: Dictionary = {}
var collider_count = 0
var environment: WorldEnvironment
var player: LabPlayer
var missions: LabMissions
var meshes: Array[MeshInstance3D] = []
var functional: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/functional.json"))

func setup(manager: LabMissions, actor: LabPlayer):
	missions = manager
	player = actor
	model = load("res://assets/models/Interior_07_Godot.glb").instantiate()
	add_child(model)
	collect(model)
	for id in protected_nodes:
		var node = protected_nodes[id]
		if id.begins_with("COLLIDER_") and node is MeshInstance3D:
			node.hide()
			var body = StaticBody3D.new()
			body.name = "NativeCollision"
			body.collision_layer = 5
			if "Upper" in id and "Partition" in id or id in ["COLLIDER_West_Window"]: body.collision_layer = 1
			node.add_child(body)
			box_collision(body, node.mesh.get_aabb())
			collider_count += 1
		elif id.begins_with("DOOR_") and functional[id].get("extras",{}).get("interaction") == "door":
			var door = LabDoor.new()
			door.name = "NativeDoor"
			node.add_child(door)
			var extras = functional[id].extras
			door.setup(node, extras.collisionBounds, player, extras.openAngleDegrees)
			doors[id] = door
		elif id.begins_with("INTERACT_"):
			var device = LabDevice.new()
			device.name = "NativeInteraction"
			node.add_child(device)
			var bounds = node_bounds(node)
			# A readable front face is shared by the ray target and field placard.
			var fronts = {"INTERACT_AdminPC": Vector3(-5,1.8,3.5364), "INTERACT_ServerRack": Vector3(-8,1.6,-4.4238), "INTERACT_Router": Vector3(7,1.45,2.60), "INTERACT_FileCabinet": Vector3(8.5,1.75,-7.3508), "INTERACT_Whiteboard": bounds.get_center()}
			var center = node.to_local(fronts[id])
			device.setup(id, manager, AABB(center-Vector3(.36,.21,.055),Vector3(.72,.42,.11)))
			devices[id] = device
	var floor_body = StaticBody3D.new()
	floor_body.name = "NativeFloorSupport"
	floor_body.collision_layer = 5
	add_child(floor_body)
	box_collision(floor_body, AABB(Vector3(-12.2,-.20,-10.2),Vector3(24.4,.2,23.6)))
	var ceiling = StaticBody3D.new()
	ceiling.name = "NativeCeilingSupport"
	ceiling.collision_layer = 5
	add_child(ceiling)
	box_collision(ceiling, AABB(Vector3(-12.2,3.4,-10.2),Vector3(24.4,.2,20.4)))
	if protected_nodes.has("SPAWN_Player"):
		# The authored anchor is at the feet; the player camera supplies eye height.
		player.global_position = protected_nodes.SPAWN_Player.global_position + Vector3(0,.01,0)
	lighting()
	add_child(preload("res://scripts/exterior.gd").new())

func collect(node: Node):
	if str(node.name) in functional: protected_nodes[str(node.name)] = node
	else:
		for source_id in functional:
			if source_id.replace(".","_") == str(node.name):
				node.set_meta("source_name",source_id)
				protected_nodes[source_id] = node
	if node is MeshInstance3D:
		meshes.append(node)
		for surface in range(node.mesh.get_surface_count()):
			var material = node.mesh.surface_get_material(surface)
			if material is StandardMaterial3D:
				var key = material.resource_name.to_lower()
				if "ceiling" in key or "acoustic" in key:
					material.roughness = .94
					material.metallic_specular = .12
				if "glass" in key:
					var glass = material.duplicate()
					glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					glass.albedo_color = Color(.66,.77,.84,.13)
					glass.roughness = .14
					glass.metallic = .18
					glass.cull_mode = BaseMaterial3D.CULL_DISABLED
					glass.refraction_enabled = false
					node.set_surface_override_material(surface,glass)
	for child in node.get_children(): collect(child)

func node_bounds(node: Node3D) -> AABB:
	var result = AABB()
	var initialized = false
	for mesh in meshes:
		if node == mesh or node.is_ancestor_of(mesh):
			var box = mesh.global_transform * mesh.mesh.get_aabb()
			result = result.merge(box) if initialized else box
			initialized = true
	return result

func box_collision(body: CollisionObject3D, box: AABB):
	var shape = BoxShape3D.new()
	shape.size = box.size.abs().max(Vector3(.005,.005,.005))
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position = box.get_center()
	body.add_child(collision)

func lighting():
	environment = WorldEnvironment.new()
	environment.name = "NativeEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.14,.19,.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.73,.80,.88)
	env.ambient_light_energy = .28
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.name = "WindowSunset"
	sun.light_color = Color(1,.79,.60)
	sun.light_energy = .55
	sun.rotation_degrees = Vector3(-32,-68,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	add_child(sun)
	for spec in [["MainOffice",Vector3(-1,3.1,5),Color(.94,.96,1),2.5,11.0], ["Network",Vector3(7,3.08,2),Color(.83,.92,1),2.7,8.0], ["ServerRoom",Vector3(-7,3.12,-6),Color(.79,.90,1),3.3,9.0], ["SOC",Vector3(-5,2.9,3),Color(.86,.94,1),1.1,5.5], ["Records",Vector3(7,3.12,-6),Color(.97,.95,.89),2.0,7.5]]:
		var light = OmniLight3D.new()
		light.name = spec[0] + "Fill"
		light.position = spec[1]
		light.light_color = spec[2]
		light.light_energy = spec[3]
		light.omni_range = spec[4]
		light.omni_attenuation = 1.1
		light.light_specular = .08
		add_child(light)
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		var probe = ReflectionProbe.new()
		probe.name = "OfficeReflection"
		probe.position = Vector3(0,1.65,1.5)
		probe.size = Vector3(24.4,3.6,23.6)
		probe.intensity = .35
		probe.interior = true
		probe.box_projection = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.max_distance = 60
		add_child(probe)
