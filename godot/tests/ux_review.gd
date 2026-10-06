extends Node

# Local visual review only. CI retains its one short, headless scene smoke.
# Fixed review positions exercise real raycasts, E/F and native UI controls.
var game: Node
var failures: Array = []
var shots: Array = []
var directory = "user://qa/UX"

func check(value: bool, message: String):
	if not value: failures.append(message); push_error(message)

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found != null: return found
	return null

func key(code: int):
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events()
	await get_tree().process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	Input.parse_input_event(event); Input.flush_buffered_events()
	await get_tree().physics_frame

func aim(id: String):
	var device = game.world.devices[id]
	var point = device.to_global(device.get_child(0).position)
	game.player.global_position = Vector3(point.x,.01,point.z+(.5 if id == "INTERACT_Router" else 1.5))
	game.player.rotation = Vector3.ZERO
	game.player.camera.rotation = Vector3.ZERO
	game.player.camera.look_at(point)
	await get_tree().create_timer(.15).timeout
	check(game.player.target == device,"Real raycast reaches " + id)

func inspect(id: String):
	await aim(id); await key(KEY_E)
	await get_tree().process_frame
	check(not game.ui.modal_open and game.ui.observation_panel.visible,"E inspection is nonmodal and contextual")

func tool(id: String):
	await aim(id); await key(KEY_F)
	check(game.ui.modal_open and not game.player.enabled,"F opens native detail tools")
	check(game.ui.tool_source.text.contains(game.world.devices[id].display_name),"Tool keeps originating device context")

func close():
	var position = game.player.global_position
	game.ui.close_tool()
	await get_tree().process_frame
	check(game.player.global_position.distance_to(position) < .03,"Detail tool returns to same position")
	check(not game.ui.onboarding.visible,"Onboarding does not repeat on F return")

func verify(expected: bool):
	find_button(game.ui.root,"현재 상태 재검증").pressed.emit()
	await get_tree().process_frame
	check(game.missions.progress().verified == expected,"Verification respects field gate and normal functionality")

func next():
	find_button(game.ui.root,"다음 미션").pressed.emit()
	await get_tree().process_frame
	await close()

func shot(name: String):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(name+".png"))
	shots.append(name)
	check(game.ui.hud.get_parent().get_global_rect().end.y < 600,"HUD stays compact")
	if game.ui.observation_panel.visible:
		check(game.ui.observation_panel.get_global_rect().end.y < 850,"Observation fits viewport")

func run(root: Node):
	game = root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-output="): directory = argument.trim_prefix("--qa-output=")
	DirAccess.make_dir_recursive_absolute(directory)
	await get_tree().create_timer(.5).timeout
	game.ui.close_tool()
	await get_tree().create_timer(.1).timeout
	check(game.player.global_position.y >= 0 and game.player.camera.global_position.y >= 1.6,"First exploration starts above the floor")
	check(game.ui.onboarding.visible and game.ui.onboarding_goal.text.contains("관제"),"First exploration has short E/F cue and current goal")
	await shot("First_Entry")
	await tool("INTERACT_AdminPC")
	check(game.missions.progress().clues.is_empty(),"F alone earns no field clues")
	await close(); await inspect("INTERACT_AdminPC"); await shot("Tutorial")
	await tool("INTERACT_AdminPC"); game.ui.answers.get_child(0).pressed.emit(); await verify(true); await next()

	await inspect("INTERACT_Router")
	check(game.ui.observation_status.text.contains("현재 사건 조사 대상 아님") and game.ui.observation_next.text.contains("자료 서버"),"Unrelated E explains current destination")
	await inspect("INTERACT_ServerRack"); await shot("Services_Before")
	check(game.ui.action_reason.text.contains("방화벽은 접근 정책 변경"),"Server-to-network purpose is explicit")
	await tool("INTERACT_Router"); game.ui.answers.get_child(1).pressed.emit()
	find_button(game.ui.tab_body("Settings"),"443 · 필수 HTTPS 자료 서비스 접근 허용").button_pressed = false
	await get_tree().process_frame
	find_button(game.ui.tab_body("Settings"),"8080 · 사용하지 않는 관리 서비스 접근 허용").button_pressed = false
	await get_tree().process_frame
	check(game.ui.recheck_notice.visible and game.ui.recheck_notice.text.contains("자료 서버"),"Changed policy names recheck equipment")
	await verify(false); await close(); await aim("INTERACT_ServerRack"); await shot("Services_Pending")
	check(game.ui.prompt.text.contains("변경 결과 재확인"),"Prompt and placard agree on pending E")
	await inspect("INTERACT_ServerRack"); await shot("Services_Wrong")
	check(game.ui.observation_text.text.contains("자료 열람 불가"),"Wrong defense reports normal-service impact")
	await tool("INTERACT_Router"); await verify(false)
	find_button(game.ui.tab_body("Settings"),"443 · 필수 HTTPS 자료 서비스 접근 허용").button_pressed = true
	await get_tree().process_frame
	await verify(false); await close(); await inspect("INTERACT_ServerRack"); await shot("Services_After")
	await tool("INTERACT_Router"); await verify(true); await next()

	await inspect("INTERACT_AdminPC"); await shot("Login_Before")
	await tool("INTERACT_AdminPC"); game.ui.answers.get_child(2).pressed.emit()
	var body = game.ui.tab_body("Settings")
	for child in body.get_children():
		if child is OptionButton: child.select(2)
		if child is CheckBox: child.button_pressed = true
	find_button(body,"로그인 정책 적용").pressed.emit()
	await get_tree().process_frame
	await verify(false); await close(); await inspect("INTERACT_AdminPC"); await shot("Login_After")
	check(game.ui.observation_text.text.contains("무제한 → 제한됨"),"Login before/after readable")
	await tool("INTERACT_AdminPC"); await verify(true); await next()

	await inspect("INTERACT_FileCabinet"); await shot("Integrity_Source")
	await inspect("INTERACT_AdminPC"); await shot("Integrity_Before")
	await tool("INTERACT_AdminPC"); game.ui.answers.get_child(1).pressed.emit()
	find_button(game.ui.tab_body("Files"),"budget.csv · 승인된 원본으로 복구").pressed.emit()
	await get_tree().process_frame
	await verify(false); await close(); await inspect("INTERACT_AdminPC"); await shot("Integrity_After")
	check(game.ui.observation_text.text.contains("불일치 → 승인 기준과 일치"),"Integrity restored comparison readable")
	await tool("INTERACT_AdminPC"); await verify(true)
	game.saves.save(game.missions)
	var restored = LabMissions.new()
	game.saves.load_into(restored)
	check(restored.progress().verified and restored.progress().spatial.rechecked,"Final save restores field validation")
	restored.free()
	var report = {"passed":failures.is_empty(),"failures":failures,"screenshots":shots,"scores":[game.missions.score(0),game.missions.score(1),game.missions.score(2),game.missions.score(3)],"method":"Native EXE fixed review camera positions; real raycast/E/F and native UI policy, answer, restore, recheck, verify, save/reload. No map tour or long walking."}
	var file = FileAccess.open(directory.path_join("ux-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("UX_REVIEW ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
