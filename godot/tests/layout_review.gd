extends Node

var game: Node
var directory = "user://qa/Layout"
var results: Array = []

func pose(position: Vector3, target: Vector3):
	game.player.set_enabled(false)
	game.player.global_position = position-Vector3(0,1.65,0)
	game.player.rotation = Vector3.ZERO
	game.player.camera.position = Vector3(0,1.65,0)
	game.player.camera.look_at(target)
	await get_tree().create_timer(.25).timeout

func shot(label: String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(label+".png"))
	var frames = []; var cpu = []; var gpu = []; var calls = []; var primitives = []
	var last = Time.get_ticks_usec()
	for i in range(60):
		await RenderingServer.frame_post_draw
		var now = Time.get_ticks_usec()
		if i>=10:
			frames.append((now-last)/1000.0)
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		last = now
	results.append({"view":label,"frame_ms":mean(frames),"cpu_ms":mean(cpu),"gpu_ms":mean(gpu),"draw_calls":mean(calls),"primitives":mean(primitives),"camera":game.player.camera.global_position})

func mean(values: Array) -> float:
	return values.reduce(func(sum,v):return sum+v,0.0)/values.size()

func run(scene: Node):
	game = scene
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-output="): directory = argument.trim_prefix("--qa-output=")
	await get_tree().create_timer(.7).timeout
	DirAccess.make_dir_recursive_absolute(directory)
	game.ui.root.hide()
	game.ui.modal_open = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	await pose(Vector3(-11.25,1.85,5),Vector3(-120,-15,5)); await shot("City_Window")
	await pose(Vector3(-9.9,1.65,5),Vector3(-30,2,1)); await shot("Window_Office")
	for spec in [["Desk_Coffee_Laptop","CORP_Staff_Seat_19"],["Desk_Keyboard","CORP_Staff_Seat_14"],["Desk_Narrow","CORP_Staff_Seat_17"],["Desk_Notebook","CORP_Staff_Seat_18"],["Desk_Training","TRAIN_Workstation_06"],["Desk_Forensics","CORP_Staff_Seat_22"],["Desk_Admin","INTERACT_AdminPC"]]:
		var station = game.world.model.find_child(spec[1],true,false)
		await pose(station.to_global(Vector3(.1,1.80,1.16)),station.to_global(Vector3(0,.82,0)))
		await shot(spec[0])
	await pose(Vector3(0,1.65,8.7),Vector3(-2,1.4,1)); await shot("Main_Office")
	var report = {"resolution":DisplayServer.window_get_size(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"load_ms":game.loaded_ms,"samples":results}
	var file = FileAccess.open(directory.path_join("visual-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("LAYOUT_REVIEW ",JSON.stringify(report))
	get_tree().quit()
