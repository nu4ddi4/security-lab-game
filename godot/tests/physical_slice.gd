extends Node

var game: Node
var failures: Array = []
var grid = AStarGrid2D.new()
var origin = Vector2(-12,-10)
var step = .10
var screenshots = "user://qa"

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found != null: return found
	return null

func choose(index: int):
	game.ui.open_tool("Notes")
	game.ui.answers.get_child(index).pressed.emit()
	await get_tree().process_frame

func verify_via_ui():
	find_button(game.ui.root,"현재 상태 재검증").pressed.emit()
	await get_tree().process_frame

func check(value: bool, message: String):
	if not value: failures.append(message); push_error(message)

func key(action: String):
	var event = InputEventKey.new()
	event.physical_keycode = {"inspect":KEY_E,"tool":KEY_F,"jump":KEY_SPACE,"pause":KEY_ESCAPE}[action]
	event.keycode = event.physical_keycode
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().create_timer(.08).timeout
	event = InputEventKey.new()
	event.physical_keycode = {"inspect":KEY_E,"tool":KEY_F,"jump":KEY_SPACE,"pause":KEY_ESCAPE}[action]
	event.keycode = event.physical_keycode
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().physics_frame

func aim(point: Vector3):
	var direction = point-game.player.camera.global_position
	game.player.rotation.y = atan2(-direction.x,-direction.z)
	game.player.camera.rotation.x = asin(direction.normalized().y)
	await get_tree().physics_frame
	await get_tree().physics_frame

func snapshot(name: String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshots.path_join(name+".png"))

func build_grid():
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0,0,240,240)
	grid.cell_size = Vector2(step,step)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for id in game.world.protected_nodes:
		if not id.begins_with("COLLIDER_"): continue
		var node = game.world.protected_nodes[id]
		var box = node.global_transform * node.mesh.get_aabb()
		if box.end.y <= .04 or box.position.y >= 1.79: continue
		mark_box(box)
	for id in game.world.doors:
		var door = game.world.doors[id]
		mark_box(door.pivot.global_transform * door.local_bounds)

func mark_box(box: AABB):
	var low = Vector2i(ceili((box.position.x-.31-origin.x)/step),ceili((box.position.z-.31-origin.y)/step))
	var high = Vector2i(floori((box.end.x+.31-origin.x)/step),floori((box.end.z+.31-origin.y)/step))
	for x in range(maxi(0,low.x),mini(239,high.x)+1):
		for z in range(maxi(0,low.y),mini(239,high.y)+1): grid.set_point_solid(Vector2i(x,z))

func dump_grid(destination: Vector3):
	var image = Image.create(480,480,false,Image.FORMAT_RGB8)
	for x in range(240):
		for z in range(240):
			var color = Color(.10,.13,.15) if grid.is_point_solid(Vector2i(x,z)) else Color(.68,.76,.77)
			image.fill_rect(Rect2i(x*2,z*2,2,2),color)
	var start = cell(game.player.global_position)
	var finish = cell(destination)
	image.fill_rect(Rect2i(start.x*2-3,start.y*2-3,7,7),Color.GREEN)
	image.fill_rect(Rect2i(finish.x*2-3,finish.y*2-3,7,7),Color.RED)
	image.save_png("user://qa/navigation.png")
	var bounds = {}
	for id in game.world.protected_nodes:
		var node = game.world.protected_nodes[id]
		if node is MeshInstance3D and id.begins_with("COLLIDER_"):
			var box = node.global_transform * node.mesh.get_aabb()
			bounds[id] = [box.position.x,box.position.y,box.position.z,box.end.x,box.end.y,box.end.z]
	var file = FileAccess.open("user://qa/navigation-bounds.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(bounds,"\t"))
	file.close()

func cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi((point.x-origin.x)/step),roundi((point.z-origin.y)/step))

func walk(destination: Vector3) -> bool:
	var start = cell(game.player.global_position)
	var finish = cell(destination)
	if grid.is_point_solid(start) or grid.is_point_solid(finish):
		check(false,"Blocked navigation endpoint " + str(destination))
		return false
	var path = grid.get_id_path(start,finish)
	if path.is_empty(): check(false,"No aisle route " + str(destination)); return false
	for index in range(1,path.size()):
		var point = Vector3(origin.x+path[index].x*step,0,origin.y+path[index].y*step)
		var deadline = Time.get_ticks_msec()+2000
		while Vector2(game.player.global_position.x-point.x,game.player.global_position.z-point.z).length() > .09:
			if Time.get_ticks_msec() > deadline: stop(); check(false,"Walking stuck at " + str(game.player.global_position)); return false
			var direction = (point-game.player.global_position).normalized()
			direction.y = 0
			var local = game.player.global_basis.inverse()*direction
			Input.action_press("right",maxf(local.x,0))
			Input.action_press("left",maxf(-local.x,0))
			Input.action_press("back",maxf(local.z,0))
			Input.action_press("forward",maxf(-local.z,0))
			await get_tree().physics_frame
	stop()
	return true

func stop():
	for action in ["forward","back","left","right"]: Input.action_release(action)

func run(root: Node):
	game = root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-output="): screenshots = argument.trim_prefix("--qa-output=")
	DirAccess.make_dir_recursive_absolute(screenshots)
	await get_tree().create_timer(.5).timeout
	game.ui.close_tool()
	if "--qa-nav" in OS.get_cmdline_user_args():
		game.player.global_position = Vector3(5.3,.01,-.7)
		game.world.doors.DOOR_RecordsRoom.inspect()
		await get_tree().create_timer(.6).timeout
		build_grid()
		dump_grid(Vector3(7.9,0,-6.451))
		await walk(Vector3(7.9,0,-6.451))
		print("NAV_RESULT ",failures)
		get_tree().quit()
		return
	build_grid()
	await aim(Vector3(0,1.35,9.86))
	check(game.player.target is LabDoor,"Main doorway raycast")
	await key("inspect")
	await get_tree().create_timer(.6).timeout
	check(abs(game.world.doors.DOOR_Main.pivot.rotation.y) > 1.6,"Main door opens around preserved hinge")
	if not failures.is_empty(): get_tree().quit(1); return
	build_grid()
	await walk(Vector3(0,0,6.5))
	check(game.player.global_position.z < 7,"Spawn can walk through entry")
	Input.action_press("crouch")
	await get_tree().create_timer(.25).timeout
	check(game.player.crouched and game.player.body_height == 1.1,"Native crouch")
	Input.action_release("crouch")
	await key("jump")
	await get_tree().create_timer(.8).timeout
	check(game.player.jump_peak > .4 and game.player.is_on_floor(),"Native jump and landing")
	await walk(Vector3(-5,0,5.04))
	await aim(Vector3(-5,1.8,3.5364))
	check(game.player.target is LabDevice,"Admin PC reachable by ray")
	await key("inspect")
	check("approval" in game.missions.progress().clues,"E collected field evidence")
	await key("tool")
	check(game.ui.modal_open and not game.player.enabled,"F opens native Control tool")
	await choose(0)
	await verify_via_ui()
	check(game.missions.progress().verified,"Tutorial physically played")
	game.missions.next_mission()
	game.ui.close_tool()
	await walk(Vector3(-5.3,0,-.7))
	await aim(Vector3(-5.3,1.35,-2.12))
	check(game.player.target is LabDoor,"Server door raycast")
	await key("inspect")
	await get_tree().create_timer(.6).timeout
	build_grid()
	await walk(Vector3(-8,0,-2.924))
	await aim(Vector3(-8,1.6,-4.4238))
	check(game.player.target is LabDevice,"Server rack reachable")
	await key("inspect")
	await snapshot("Services-Before")
	await walk(Vector3(7,0,3.1))
	await aim(Vector3(7,1.45,2.6))
	check(game.player.target is LabDevice,"Network appliance reachable")
	await key("tool")
	await choose(1)
	game.ui.open_tool("Settings")
	find_button(game.ui.root,"8080 · 사용하지 않는 관리 서비스 접근 허용").button_pressed = false
	await verify_via_ui()
	check(not game.missions.progress().verified,"Cannot skip server revisit")
	game.ui.close_tool()
	await walk(Vector3(-8,0,-2.924))
	await aim(Vector3(-8,1.6,-4.4238))
	await key("inspect")
	await snapshot("Services-After")
	game.ui.open_tool("Notes")
	await verify_via_ui()
	check(game.missions.progress().verified,"Services physical loop complete")
	game.missions.next_mission()
	game.ui.close_tool()
	await walk(Vector3(-5,0,5.04))
	await aim(Vector3(-5,1.8,3.5364))
	await key("inspect")
	await snapshot("Login-Before")
	await key("tool")
	await choose(2)
	game.ui.open_tool("Settings")
	var settings_body = game.ui.tab_body("Settings")
	settings_body.get_child(2).selected = 2
	find_button(game.ui.root,"흔한 값 차단").button_pressed = true
	find_button(game.ui.root,"연속 실패 3회 후 제한").button_pressed = true
	find_button(game.ui.root,"로그인 정책 적용").pressed.emit()
	await verify_via_ui()
	check(not game.missions.progress().verified,"Login requires E recheck")
	game.ui.close_tool()
	await key("inspect")
	await snapshot("Login-After")
	game.ui.open_tool("Notes")
	await verify_via_ui()
	check(game.missions.progress().verified,"Login physical policy loop complete")
	game.missions.next_mission()
	game.ui.close_tool()
	await walk(Vector3(5.3,0,-.7))
	await aim(Vector3(5.3,1.35,-2.12))
	check(game.player.target is LabDoor,"Records door reachable")
	await key("inspect")
	await get_tree().create_timer(.6).timeout
	print("RECORDS_DOOR ",game.world.doors.DOOR_RecordsRoom.pivot.rotation.y," target ",game.world.doors.DOOR_RecordsRoom.desired_angle," blocked ",game.world.doors.DOOR_RecordsRoom.blocked)
	build_grid()
	await walk(Vector3(7.9,0,-6.451))
	await aim(Vector3(8.5,1.75,-7.3508))
	check(game.player.target is LabDevice,"Approved file cabinet accessible")
	await key("inspect")
	check("baseline" in game.missions.progress().clues,"Physical approved baseline")
	await walk(Vector3(-5,0,5.04))
	await aim(Vector3(-5,1.8,3.5364))
	await key("inspect")
	await snapshot("Integrity-Mismatch")
	await key("tool")
	await choose(1)
	game.ui.open_tool("Files")
	find_button(game.ui.root,"budget.csv · 승인된 원본으로 복구").pressed.emit()
	check(game.missions.equipment().hashes.is_empty(),"Recovery screen stays pending until scan")
	await verify_via_ui()
	check(not game.missions.progress().verified,"Integrity requires new hash and E recheck")
	game.ui.close_tool()
	await key("inspect")
	await snapshot("Integrity-Restored")
	game.ui.open_tool("Notes")
	await verify_via_ui()
	check(game.missions.progress().verified,"Integrity physical recovery loop complete")
	game.saves.save(game.missions)
	var saved = LabMissions.new()
	var load_message = game.saves.load_into(saved)
	check(saved.state.active == 3 and saved.progress().verified and saved.progress().spatial.rechecked,"Saved final progress reloads")
	saved.free()
	var report = {"passed":failures.is_empty(),"failures":failures,"movement_seconds":game.player.movement_seconds,"jump_peak":game.player.jump_peak,"scores":[game.missions.score(0),game.missions.score(1),game.missions.score(2),game.missions.score(3)],"save_reload":load_message,"renderer":RenderingServer.get_current_rendering_method()}
	var file = FileAccess.open(screenshots.path_join("physical-slice.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PHYSICAL_SLICE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
