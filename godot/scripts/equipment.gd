class_name LabEquipment
extends Node

var missions: LabMissions
var screens: Dictionary = {}
var leds: Array = []
var screen_bindings = 0
var bindings: Array = []
var Screen = preload("res://scripts/screen.gd")

func setup(world: LabWorld, manager: LabMissions):
	missions = manager
	for mesh in world.meshes:
		for surface in range(mesh.mesh.get_surface_count()):
			var original = mesh.mesh.surface_get_material(surface)
			if original == null: continue
			var key = original.resource_name
			if key in ["LAB_LED","CORP_Amber_Status_LED"] and equipment_parent(mesh):
				var material = original.duplicate()
				material.emission_enabled = true
				material.emission_energy_multiplier = .5
				mesh.set_surface_override_material(surface,material)
				bindings.append({"mesh":mesh,"surface":surface,"material":material})
				leds.append({"material":material,"port":"443" if key == "LAB_LED" else "8080"})
			if key.begins_with("CORP_Display_") or key in ["CORP_SOC_Status_Display","CORP_SOC_Upper_Display_1","CORP_SOC_Upper_Display_2","EX07_Network_Console_Screen"] or "Forensics_Display" in key:
				var node_name = str(mesh.name)
				var role = "case" if node_name == "CORP_SOC_Status_Display" else "queue" if "Upper_Display_1" in node_name else "health" if "Upper_Display_2" in node_name else "network" if node_name == "EX07_Network_Console_Screen" else "logs" if node_name == "CORP_Display_ADMIN_Monitor_03" else "timeline" if "Extra_01" in node_name else "case" if anchor_parent(mesh) == "INTERACT_AdminPC" else ["response","analysis","operations","forensics"][screen_bindings%4]
				var texture = screen_texture(role)
				var material = StandardMaterial3D.new()
				material.resource_name = "NativeScreen_" + role
				material.albedo_texture = texture
				material.emission_enabled = true
				material.emission_texture = texture
				material.emission = Color.WHITE
				material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				material.emission_energy_multiplier = .5
				material.roughness = .65
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				normalize_uv(mesh,surface)
				mesh.set_surface_override_material(surface,material)
				bindings.append({"mesh":mesh,"surface":surface,"material":material})
				screen_bindings += 1
	manager.state_changed.connect(update)
	update()

func equipment_parent(node: Node) -> bool:
	var current = node
	while current != null:
		if str(current.name).begins_with("ServerRack_") or str(current.name) in ["Router_Switch_Firewall","NETWORK_Switch_Firewall_PatchPanel"]: return true
		current = current.get_parent()
	return false

func anchor_parent(node: Node) -> String:
	var current = node
	while current != null:
		if str(current.name).begins_with("INTERACT_"): return str(current.name)
		current = current.get_parent()
	return ""

func normalize_uv(node: MeshInstance3D, surface: int):
	# Own the copied UV buffers; imported geometry and protected assets stay immutable.
	var source = node.mesh
	var copy = ArrayMesh.new()
	for i in range(source.get_surface_count()):
		var arrays = source.surface_get_arrays(i)
		if i == surface and arrays[Mesh.ARRAY_TEX_UV] != null:
			var uv = arrays[Mesh.ARRAY_TEX_UV].duplicate()
			var low = Vector2(INF,INF)
			var high = Vector2(-INF,-INF)
			for p in uv: low = low.min(p); high = high.max(p)
			var span = high-low
			if span.x > .00001 and span.y > .00001:
				for j in range(uv.size()): uv[j] = Vector2((uv[j].x-low.x)/span.x,(uv[j].y-low.y)/span.y)
				arrays[Mesh.ARRAY_TEX_UV] = uv
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		copy.surface_set_material(i,source.surface_get_material(i))
	node.mesh = copy

func screen_texture(role: String) -> ViewportTexture:
	if not screens.has(role):
		var viewport = SubViewport.new()
		viewport.size = Vector2i(1024,576)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		viewport.disable_3d = true
		add_child(viewport)
		var canvas = Screen.new()
		canvas.size = Vector2(1024,576)
		canvas.profile = role
		viewport.add_child(canvas)
		screens[role] = {"viewport":viewport,"canvas":canvas}
	return screens[role].viewport.get_texture()

func update():
	var snapshot = missions.equipment()
	for role in screens:
		screens[role].canvas.snapshot = snapshot
		screens[role].canvas.queue_redraw()
		screens[role].viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for led in leds:
		var color = Color("77ad95") if led.port == "443" and snapshot.ports["443"] or led.port == "8080" and not snapshot.ports["8080"] else Color("c5a26e") if led.port == "8080" else Color("b77370")
		led.material.albedo_color = color
		led.material.emission = color

func _exit_tree():
	for binding in bindings:
		binding.material.albedo_texture = null
		binding.material.emission_texture = null
		if is_instance_valid(binding.mesh): binding.mesh.set_surface_override_material(binding.surface,null)
	bindings.clear()
	leds.clear()
	screens.clear()
