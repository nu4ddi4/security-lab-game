extends Node

var game: Node
var directory = "user://qa/Review"

func pose(position: Vector3, target: Vector3):
	game.player.global_position = position-Vector3(0,1.65,0)
	game.player.rotation = Vector3.ZERO
	game.player.camera.position = Vector3(0,1.65,0)
	game.player.camera.look_at(target)
	await get_tree().create_timer(.8).timeout

func run(root: Node):
	game = root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-output="): directory = argument.trim_prefix("--qa-output=")
	DirAccess.make_dir_recursive_absolute(directory)
	for role in game.equipment.screens:
		await RenderingServer.frame_post_draw
		game.equipment.screens[role].viewport.get_texture().get_image().save_png(directory.path_join("Screen-"+role+".png"))
	game.ui.modal.hide()
	game.ui.modal_open = false
	game.player.set_enabled(false)
	var points = [
		["MainOffice",Vector3(0,1.65,8.7),Vector3(-2,1.4,1)],
		["Workstation",Vector3(1.4,1.65,6.7),Vector3(3.8,1.2,4.6)],
		["SOC",Vector3(-6.9,1.65,5.3),Vector3(-5,2.05,3)],
		["Network",Vector3(5.2,1.65,3.5),Vector3(7,1.2,2)],
		["ServerRoom",Vector3(-7,1.65,-3.4),Vector3(-8.4,1.4,-6.2)],
		["Ceiling",Vector3(0,1.65,5),Vector3(1.2,3.3,1)],
		["SharedFacility",Vector3(8.5,1.65,7),Vector3(10.9,1.2,6)],
		["Glass",Vector3(-4,1.65,.2),Vector3(-6.3,1.6,-3.5)],
		["Window",Vector3(-9.9,1.65,5),Vector3(-30,2,1)]]
	var metrics = []
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	for point in points:
		await pose(point[1],point[2])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join(point[0]+".png"))
		if point[0] not in ["MainOffice","SOC","Network","ServerRoom","Window"]: continue
		var samples = []
		var cpu = []
		var gpu = []
		var calls = []
		var triangles = []
		var previous = Time.get_ticks_usec()
		for i in range(240):
			await RenderingServer.frame_post_draw
			var now = Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous = now
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			triangles.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		samples.sort()
		metrics.append({"view":point[0],"frame_ms_mean":average(samples),"frame_ms_p95":samples[int(samples.size()*.95)],"render_cpu_ms":average(cpu),"render_gpu_ms":average(gpu),"fps_uncapped":1000.0/average(samples),"draw_calls":average(calls),"primitives":average(triangles),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"render_video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
	game.ui.open_tool("Notes")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join("NativeTools.png"))
	var report = {"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"resolution":DisplayServer.window_get_size(),"preset":game.settings.values.quality,"vsync":false,"frame_cap":0,"samples_per_view":240,"load_ms":game.loaded_ms,"metrics":metrics}
	var file = FileAccess.open(directory.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("NATIVE_REVIEW ",JSON.stringify(report))
	get_tree().quit()

func average(values: Array) -> float:
	return values.reduce(func(sum,value): return sum+value,0.0)/values.size()
