class_name InvestigationPrototype
extends Node3D

var content: Dictionary
var engine: InvestigationEngine
var state: Dictionary
var store = InvestigationStore.new()
var player: LabPlayer
var ui: InvestigationUI
var controls: InvestigationControls
var updates: InvestigationUpdates
var updater: InvestigationInstallerUpdates
var diagnostics: InvestigationDiagnostics
var settings = null
var bindings = LabInputBindings.new()
var qa_mode = false
var world: LabWorld
var investigation_environment: InvestigationEnvironment
var detailed_world = false
var context = ""
var blocked_save = false
var save_timer: Timer
var targets = {}
var dialogue_camera_fov = 72.0
var dialogue_camera_active = false
var dialogue_camera_tween: Tween
var office_scene: PackedScene
var loading: CanvasLayer
var loading_text: Label
var loading_bar: ProgressBar
var load_timings = {}
var load_started = Time.get_ticks_msec()
var objective_marker: Node3D
var marker_target = ""
var marker_phase = 0.0

func _ready():
	if "--prototype-services" in OS.get_cmdline_user_args():
		add_child(load("res://prototype/tests/services.gd").new())
		return
	if OS.has_feature("Android"): get_tree().quit_on_go_back = false
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	get_window().size_changed.connect(_fit_screen)
	_fit_screen()
	_show_loading()
	await _loading_step("업무 자료를 준비하고 있습니다",5)
	content = InvestigationContent.load_case()
	if content.has("error"):
		push_error(content.error)
		loading_text.text = "업무 자료를 읽지 못했습니다. 게임을 다시 시작해 주세요."
		return
	engine = InvestigationEngine.new(content)
	var testing = "--prototype-smoke" in OS.get_cmdline_user_args()
	qa_mode = testing
	if testing: store.directory = "user://investigation-qa"
	var loaded = {"new":true} if testing else store.load_state(content)
	blocked_save = loaded.has("error")
	state = loaded.get("state",engine.create_state())
	_setup_input()
	player = LabPlayer.new()
	player.unified_interaction = true
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(-6,.01,5.6)
	if "--prototype-dummy" not in OS.get_cmdline_user_args():
		var path = "res://assets/models/Interior_07_Godot.glb"
		var requested = ResourceLoader.load_threaded_request(path,"PackedScene")
		if requested != OK:
			loading_text.text = "사무실을 준비하지 못했습니다. 게임을 다시 시작해 주세요."
			return
		var progress = []
		while ResourceLoader.load_threaded_get_status(path,progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await _loading_step("사무실을 불러오고 있습니다",10+progress[0]*55 if not progress.is_empty() else 10)
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
			loading_text.text = "사무실을 읽지 못했습니다. 게임을 다시 시작해 주세요."
			return
		office_scene = ResourceLoader.load_threaded_get(path)
	load_timings.resources_ms = Time.get_ticks_msec()-load_started
	await _loading_step("장비와 출입문을 배치하고 있습니다",70)
	var world_started = Time.get_ticks_msec()
	_build_world()
	office_scene = null
	load_timings.world_ms = Time.get_ticks_msec()-world_started
	_build_marker()
	await _loading_step("화면과 조작을 준비하고 있습니다",90)
	controls = InvestigationControls.new()
	add_child(controls)
	updates = InvestigationUpdates.new()
	add_child(updates)
	ui = InvestigationUI.new()
	add_child(ui)
	ui.setup(self)
	controls.setup(self)
	settings = LabSettings.new()
	settings.values.quality = 2
	add_child(settings)
	settings.setup(self)
	diagnostics = InvestigationDiagnostics.new()
	add_child(diagnostics)
	diagnostics.setup(self)
	diagnostics.mark_ready()
	if OS.get_name()=="Windows" and not testing and FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("securitylab.install.json")):
		updater = InvestigationInstallerUpdates.new()
		add_child(updater)
		updater.status_changed.connect(func(text):
			updates.status = text
			ui.refresh_settings()
			if not ui.modal_open: ui.notice(text))
		updater.progress_changed.connect(ui.update_progress)
		updater.setup(self)
	updates.changed.connect(ui.refresh_settings)
	controls.changed.connect(ui.refresh_settings)
	bindings.changed.connect(ui.refresh_input_hints)
	player.inspect_requested.connect(func(target): target.inspect())
	player.tool_requested.connect(func(target): _use(target.logical_id,target.kind,true))
	player.pause_requested.connect(ui.toggle)
	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = .4
	save_timer.timeout.connect(save_now)
	add_child(save_timer)
	get_window().focus_exited.connect(save_now)
	# Persist a fresh investigation before Android can suspend its render loop.
	if not loaded.has("state") and not blocked_save: save_now()
	if blocked_save: ui.notice(loaded.error + "\n새 조사를 시작하기 전 원본을 보존합니다.")
	await _loading_step("준비 완료",100)
	load_timings.ready_ms = Time.get_ticks_msec()-load_started
	print("PROTOTYPE_LOADING ",JSON.stringify(load_timings))
	loading.queue_free()
	print("PROTOTYPE_READY ",JSON.stringify({"day":state.day,"dummy":not detailed_world,"devices":content.case.devices.size(),"npcs":content.case.npcs.size(),"isolatedSave":store.directory}))
	if DisplayServer.get_name() != "headless": _report_first_frame.call_deferred()
	if testing:
		var smoke = load("res://tests/input_review.gd" if "--prototype-input-review" in OS.get_cmdline_user_args() else "res://prototype/tests/smoke.gd").new()
		add_child(smoke)
		smoke.run.call_deferred(self)
	elif controls.automatic_updates and updater==null: check_updates.call_deferred()

func _show_loading():
	loading = CanvasLayer.new()
	loading.layer = 100
	add_child(loading)
	var background = ColorRect.new()
	background.color = InvestigationTheme.BACKDROP
	background.theme = InvestigationTheme.build(false)
	loading.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center = CenterContainer.new()
	background.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var body = VBoxContainer.new()
	body.custom_minimum_size.x = 360
	body.add_theme_constant_override("separation",18)
	center.add_child(body)
	var brand = HBoxContainer.new()
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation",14)
	brand.add_child(InvestigationTheme.brand_mark())
	var title = Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "SECURITY LAB"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.add_child(title)
	body.add_child(brand)
	loading_text = Label.new()
	loading_text.theme_type_variation = "CaptionLabel"
	loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(loading_text)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size.y = 8
	loading_bar.show_percentage = false
	body.add_child(loading_bar)

func _loading_step(text: String, progress: float):
	loading_text.text = text
	loading_bar.value = progress
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	if progress == 5:
		load_timings.loading_screen_ms = Time.get_ticks_msec()-load_started
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--prototype-capture-dir=") and DisplayServer.get_name() != "headless":
				var path = argument.trim_prefix("--prototype-capture-dir=")
				DirAccess.make_dir_recursive_absolute(path)
				get_viewport().get_texture().get_image().save_png(path.path_join("00-loading.png"))

func _fit_screen():
	var size = Vector2(get_window().size)
	if DisplayServer.get_name() == "headless" and size == Vector2(64,64): size = Vector2(1600,900)
	var mobile = OS.has_feature("mobile") or "--mobile-qa" in OS.get_cmdline_user_args()
	var base = 540.0 if mobile else 720.0
	get_window().content_scale_size = Vector2i(size / maxf(1,minf(size.x,size.y)) * base)
	if ui != null: ui.fit_screen.call_deferred()

func safe_rect() -> Rect2:
	var bounds = get_viewport().get_visible_rect()
	if OS.has_feature("mobile") or "--mobile-qa" in OS.get_cmdline_user_args():
		var safe = Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			var transform = get_viewport().get_final_transform().affine_inverse()
			return bounds.intersection(Rect2(transform*safe.position,transform.basis_xform(safe.size)))
	return bounds

func _build_marker():
	objective_marker = Node3D.new()
	add_child(objective_marker)
	var arrow = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = .14
	cone.bottom_radius = 0
	cone.height = .28
	arrow.mesh = cone
	var glow = StandardMaterial3D.new()
	glow.albedo_color = Color(.25,1,.75)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(.25,1,.75)
	glow.emission_energy_multiplier = 2
	arrow.material_override = glow
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	objective_marker.add_child(arrow)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = .35
	torus.outer_radius = .43
	torus.rings = 16
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = glow
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	objective_marker.add_child(ring)
	objective_marker.hide()

func _process(delta):
	if ui == null or objective_marker == null: return
	marker_phase += delta
	marker_target = ui.guide_info().get("target","")
	objective_marker.visible = targets.has(marker_target) and not state.ended
	if not objective_marker.visible: return
	var point = targets[marker_target].global_position
	objective_marker.global_position = point
	objective_marker.get_child(0).position.y = .85 + sin(marker_phase*3)*.08
	objective_marker.get_child(1).position.y = .035 - point.y

func _report_first_frame():
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("PROTOTYPE_FRAME_READY ",JSON.stringify({"platform":OS.get_name(),"touch":controls.touch_enabled,"first_game_frame_ms":Time.get_ticks_msec()-load_started,"texture_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}))

func _setup_input():
	if qa_mode: bindings.path = "user://investigation-qa/input_bindings.json"
	DirAccess.make_dir_recursive_absolute(bindings.path.get_base_dir())
	bindings.load_profile()
	if qa_mode: bindings.bindings = LabInputBindings.defaults(); bindings.apply()

func _use(id: String, kind: String, tool: bool):
	if kind == "npc": ui.open_dialogue(id); return
	if tool:
		context = id
		ui.open_terminal()
	else: ui.notice(content.case.devices[id].description)

func beta_preview() -> bool:
	var beta_build = updater.info.get("channel") == "beta" if updater != null else updates.installed.get("prerelease",true)
	return controls.beta_preview_enabled(beta_build)

func check_updates():
	if updater != null: updater.check()
	else: updates.check(beta_preview())

func frame_speaker(id: String):
	if not targets.has(id): return
	if not dialogue_camera_active:
		dialogue_camera_fov = 72.0
		dialogue_camera_active = true
	if dialogue_camera_tween != null: dialogue_camera_tween.kill()
	var head = investigation_environment.speaker_position(id) if detailed_world else targets[id].global_position + Vector3(0,.55,0)
	var pose = player.camera.global_transform.looking_at(head,Vector3.UP)
	dialogue_camera_tween = create_tween().set_parallel(true)
	dialogue_camera_tween.tween_property(player.camera,"global_transform",pose,.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	dialogue_camera_tween.tween_property(player.camera,"fov",68.0,.25)

func release_speaker():
	if not dialogue_camera_active: return
	if dialogue_camera_tween != null: dialogue_camera_tween.kill()
	# Keep the framed view and synchronize body yaw for subsequent movement.
	var pose = player.camera.global_transform
	var facing = -pose.basis.z
	player.rotation.y = atan2(-facing.x,-facing.z)
	player.camera.global_transform = pose
	dialogue_camera_tween = create_tween()
	dialogue_camera_tween.tween_property(player.camera,"fov",dialogue_camera_fov,.25)
	dialogue_camera_active = false

func dispatch(action: Dictionary) -> Dictionary:
	if blocked_save:
		ui.notice("보존된 저장을 확인하거나 새 조사를 선택하세요.")
		return {"code":"SAVE_BLOCKED","text":"저장 확인이 필요합니다."}
	var result = engine.step(state,action)
	var changed = result.state != state
	state = result.state
	if investigation_environment != null: investigation_environment.sync(state)
	if action.get("type") != "memo": ui.refresh()
	if changed: save_timer.start()
	return result

func command(text: String):
	var normalized = " ".join(text.strip_edges().split(" ",false)).to_lower()
	for row in content.commands:
		if row.text.to_lower() == normalized and context in row.devices and not engine.command_visible(state,row):
			ui.print_output(text,"현재 맡은 업무에서 사용할 수 없는 명령입니다.","error")
			return
	var action = engine.parse(text,context,state)
	if action.type == "pause":
		var preview = engine.step(state,action)
		if preview.code != "CONFIRM_PAUSE": ui.print_output(text,preview.text,"error" if preview.code in InvestigationUI.ERROR_CODES else "output"); return
		ui.confirm(engine._t("CONFIRM_PAUSE"),func():
			action.payload["confirmed"] = true
			var confirmed = dispatch(action)
			ui.print_output(text,confirmed.text,"error" if confirmed.code in InvestigationUI.ERROR_CODES else "output"))
	else:
		var result = dispatch(action)
		ui.print_output(text,result.text,"error" if result.code in InvestigationUI.ERROR_CODES else "output")

func save_now() -> bool:
	if blocked_save: return false
	var saved = store.save(state,content)
	if not saved: ui.notice(store.error)
	return saved

func new_game():
	if not store.preserve(): ui.notice(store.error); return
	state = engine.create_state()
	if investigation_environment != null: investigation_environment.sync(state)
	blocked_save = false
	context = ""
	ui.reset_session()
	ui.sync_memo()
	ui.refresh()
	save_now()

# Returns how many files were removed.
func reset_all_data() -> int:
	var removed = InvestigationDataReset.wipe(InvestigationDataReset.targets(self))
	state = engine.create_state()
	blocked_save = false
	context = ""
	controls.reset()
	bindings.bindings = LabInputBindings.defaults()
	bindings.apply()
	settings.values = LabSettings.DEFAULT_VALUES.duplicate()
	settings.values.quality = 2
	settings.apply()
	if investigation_environment != null: investigation_environment.sync(state)
	ui.reset_session()
	ui.sync_memo()
	ui.refresh()
	ui.refresh_input_hints()
	save_now()
	return removed

func transfer_file(path: String, exporting: bool):
	if exporting:
		ui.notice("진행 파일을 내보냈습니다." if store.export_file(path,state,content) else store.error)
		return
	var candidate = store.import_file(path,content)
	if candidate.has("error"): ui.notice(candidate.error); return
	if not store.preserve(): ui.notice(store.error); return
	state = candidate.state
	if investigation_environment != null: investigation_environment.sync(state)
	blocked_save = false
	ui.reset_session()
	ui.sync_memo()
	ui.refresh()
	save_now()
	ui.notice("사건 진행을 가져왔습니다.")

func _unhandled_input(event):
	if ui == null or (player != null and player.input_blocked()): return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == LabInputBindings.TABLET_KEY:
		if ui.mode == "field": ui.open_tablet()
		elif ui.mode == "tablet": ui.close()
		get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and ui != null: ui.toggle()
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT] and ui != null:
		save_now()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and ui != null:
		if updater!=null and updater.state=="preparing": return
		save_now()
		get_tree().quit()

func _box(position: Vector3, size: Vector3, color: Color, collision = true):
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = position
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	mesh.material_override = material
	add_child(mesh)
	if collision:
		var body = StaticBody3D.new()
		body.collision_layer = 5
		mesh.add_child(body)
		var shape = CollisionShape3D.new()
		var bounds = BoxShape3D.new()
		bounds.size = size
		shape.shape = bounds
		body.add_child(shape)
	return mesh

func _label(text: String, position: Vector3, size = 40):
	var label = Label3D.new()
	label.text = text
	label.font = load("res://assets/fonts/NotoSansKR.ttf")
	label.font_size = size
	label.pixel_size = .004
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _target(id: String, kind: String, position: Vector3, text: String):
	var target = InvestigationTarget.new()
	target.logical_id = id
	target.kind = kind
	target.label = text
	target.position = position
	target.collision_layer = 2
	target.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(.7,1.7,.6) if kind == "npc" else Vector3(1,.9,.4)
	shape.shape = box
	target.add_child(shape)
	add_child(target)
	targets[id] = target
	target.used.connect(_use)
	_label(text,position+Vector3(0,.9,0),28)

func _build_world():
	if "--prototype-dummy" not in OS.get_cmdline_user_args():
		_build_office_world()
		return
	_box(Vector3(0,-.1,0),Vector3(20,.2,24),Color(.18,.23,.27))
	_box(Vector3(0,1.5,-8),Vector3(20,3,.2),Color(.3,.34,.38))
	for x in [-10,10]: _box(Vector3(x,1.5,0),Vector3(.2,3,24),Color(.3,.34,.38))
	for x in [-3.3,3.3]: _box(Vector3(x,1.5,-4.5),Vector3(.15,3,7),Color(.3,.34,.38))
	for spec in [["관제실",-6.5],["서버실",0],["업무 구역",6.5]]: _label(spec[0],Vector3(spec[1],2.7,-7),44)
	var positions = {"control_console":Vector3(-6.5,1.2,-4),"server_console":Vector3(0,1.2,-4),"project_pc":Vector3(6.5,1.2,-4),"approval_archive":Vector3(-6.5,1.2,-.5),"maintenance_terminal":Vector3(6.5,1.2,-.5),"briefing_board":Vector3(-3,1.2,3)}
	for id in positions:
		var p = positions[id]
		_box(p-Vector3(0,.5,0),Vector3(1.2,.8,.7),Color(.12,.28,.35))
		_box(p,Vector3(.85,.55,.15),Color(.2,.7,.7),false)
		_target(id,"device",p+Vector3(0,0,.15),content.case.devices[id].label)
	var people = {"oh":Vector3(-6,1,3),"park":Vector3(0,1,1),"han":Vector3(6,1,3),"seo":Vector3(8,1,1)}
	for id in people:
		var p = people[id]
		_box(p,Vector3(.6,1.7,.6),Color(.6,.45,.25))
		_target(id,"npc",p+Vector3(0,0,.4),content.case.npcs[id].name+" · "+content.case.npcs[id].role)
	var env = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(.12,.18,.24)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = .65
	env.environment = settings
	add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	add_child(light)

func _build_office_world():
	world = LabWorld.new()
	world.name = "InvestigationOffice"
	add_child(world)
	world.setup(player,office_scene)
	if OS.has_feature("mobile") or "--mobile-qa" in OS.get_cmdline_user_args():
		get_viewport().scaling_3d_scale = .65
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		world.get_node("WindowSunset").shadow_enabled = false
	detailed_world = true
	investigation_environment = InvestigationEnvironment.new()
	investigation_environment.name = "InvestigationEnvironment"
	add_child(investigation_environment)
	investigation_environment.setup(world,content)
	targets = investigation_environment.targets
	for target in targets.values(): target.used.connect(_use)
	investigation_environment.sync(state)
	investigation_environment.spawn(player)

func review_target(id: String):
	if investigation_environment != null:
		investigation_environment.review_target(player,id)
		return
	var point = targets[id].global_position
	player.global_position = Vector3(point.x,.01,point.z+1.7)
	player.velocity = Vector3.ZERO
	player.camera.look_at(point)
