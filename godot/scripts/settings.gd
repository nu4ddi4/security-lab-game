class_name LabSettings
extends Node

const DEFAULT_VALUES = {"resolution":0,"fullscreen":false,"vsync":true,"quality":1,"master":0.65,"sfx":0.55,"sensitivity":0.0018,"fov":72.0}
var values = DEFAULT_VALUES.duplicate()
var game: Node
var panel: Window
var path = "user://settings.json"
var binding_summary: Label

func setup(root: Node, connect_menu = true):
	game = root
	if game.qa_mode: path = "user://qa/settings.json"
	if game is InvestigationPrototype: path = "user://investigation-qa/settings.json" if game.qa_mode else "user://beta-settings.json"
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if raw is Dictionary:
		for key in values:
			if raw.has(key) and (typeof(raw[key]) == typeof(values[key]) or (raw[key] is float or raw[key] is int) and not values[key] is bool): values[key] = raw[key]
	values.resolution = clampi(int(values.resolution),0,2)
	values.quality = clampi(int(values.quality),0,3)
	values.master = clampf(values.master,0,1)
	values.sfx = clampf(values.sfx,0,1)
	values.sensitivity = clampf(values.sensitivity,.0005,.004)
	values.fov = clampf(values.fov,60,90)
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,"SFX")
		AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
	if not game is InvestigationPrototype or raw is Dictionary: apply()
	if connect_menu:
		game.ui.settings_requested.connect(show_menu)
		game.bindings.changed.connect(bindings_changed)

func bindings_changed():
	if is_instance_valid(binding_summary): binding_summary.text = LabInputBindings.summary()
	game.ui.refresh_input_hints()
	for device in game.world.devices.values(): device.update_placard()

func apply():
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		if not values.fullscreen: DisplayServer.window_set_size([Vector2i(1600,900),Vector2i(1280,720),Vector2i(1920,1080)][values.resolution])
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	var quality = int(values.quality)
	var viewport = get_viewport()
	viewport.msaa_3d = [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X,Viewport.MSAA_8X][quality]
	viewport.scaling_3d_scale = .8 if quality == 0 else 1.0
	var native_advanced = RenderingServer.get_current_rendering_method() == "forward_plus"
	if game.world != null: apply_graphics(quality,native_advanced)
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(values.master,.0001)))
	AudioServer.set_bus_mute(0,values.master <= 0)
	var sfx = AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sfx,linear_to_db(maxf(values.sfx,.0001)))
	AudioServer.set_bus_mute(sfx,values.sfx <= 0)
	game.player.sensitivity = values.sensitivity
	game.player.camera.fov = values.fov

func apply_graphics(quality: int, native_advanced: bool):
	var env = game.world.environment.environment
	env.ssao_enabled = native_advanced and quality >= 1
	env.ssao_radius = .6
	env.ssao_intensity = 1.35
	env.ssao_power = 1.4
	env.ssao_detail = .6
	env.ssr_enabled = false
	env.glow_enabled = native_advanced and quality >= 2
	env.glow_intensity = .15
	if game.world.has_node("OfficeReflection"): game.world.get_node("OfficeReflection").visible = native_advanced and quality >= 1

func save_values(candidate: Dictionary) -> Dictionary:
	var temporary = path+".tmp"
	var file = FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return {"ok":false,"message":"환경 설정 저장 실패 · "+error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(candidate,"\t"))
	file.flush()
	var error = file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary,path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok":false,"message":"환경 설정 저장 실패 · "+error_string(error)}
	values = candidate.duplicate(true)
	apply()
	return {"ok":true,"message":"설정을 저장했습니다."}

func show_menu():
	if panel != null: panel.popup_centered(); return
	panel = Window.new()
	panel.title = "환경 설정"
	panel.size = Vector2i(690,630)
	panel.transient = true
	panel.exclusive = true
	panel.theme = game.ui.root.theme
	panel.close_requested.connect(func(): panel.queue_free(); panel = null)
	game.ui.root.add_child(panel)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	panel.add_child(margin)
	var scroll = ScrollContainer.new()
	margin.add_child(scroll)
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	scroll.add_child(body)
	game.ui.label(body,"조작키",24)
	binding_summary = game.ui.wrapped_label(body,LabInputBindings.summary(),16,600)
	game.ui.button(body,"조작키 변경…",func():
		var editor = LabInputRebinding.new()
		editor.configure(game.bindings,game.player)
		panel.add_child(editor)
		editor.popup_centered())
	game.ui.label(body,"디스플레이 / 소리 / 조작",25)
	var resolution = OptionButton.new()
	for text in ["1600 × 900","1280 × 720","1920 × 1080"]: resolution.add_item(text)
	resolution.selected = values.resolution
	body.add_child(resolution)
	var fullscreen = CheckBox.new()
	fullscreen.text = "전체 화면"
	fullscreen.button_pressed = values.fullscreen
	body.add_child(fullscreen)
	var vsync = CheckBox.new()
	vsync.text = "VSync · 화면 찢어짐 방지"
	vsync.button_pressed = values.vsync
	body.add_child(vsync)
	var quality = OptionButton.new()
	for text in ["Low · 80% / 기본 그림자","Medium · 원래 해상도 / AO / 2× MSAA","High · 4× MSAA / 약한 화면 발광","Ultra · 8× MSAA"]: quality.add_item(text)
	quality.selected = values.quality
	body.add_child(quality)
	var master = slider(body,"전체 소리 · 0은 음소거",values.master,0,1,.05)
	var sfx = slider(body,"환경음 / 효과음",values.sfx,0,1,.05)
	var sensitivity = slider(body,"마우스 감도",values.sensitivity,.0005,.004,.0001)
	var fov = slider(body,"시야각",values.fov,60,90,1)
	if game.updater!=null and not game.updater.info.is_empty():
		game.ui.label(body,"업데이트 · %s · %s"%[game.updater.info.channel,game.updater.info.version],18)
		var automatic = CheckBox.new()
		automatic.text = "시작할 때 내 채널의 업데이트 확인 · 설치는 동의 후 진행"
		automatic.button_pressed = game.updater.enabled
		automatic.toggled.connect(game.updater.set_enabled)
		body.add_child(automatic)
		if game.updater.state in ["available","ready"]: game.ui.button(body,"업데이트 확인하고 설치…",game.updater.request_install)
	diagnostics_controls(body)
	game.ui.button(body,"적용하고 저장",func():
		values = {"resolution":resolution.selected,"fullscreen":fullscreen.button_pressed,"vsync":vsync.button_pressed,"quality":quality.selected,"master":master.value,"sfx":sfx.value,"sensitivity":sensitivity.value,"fov":fov.value}
		apply()
		var file = FileAccess.open(path,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(values,"\t")); file.close()
		panel.queue_free(); panel = null)
	panel.popup_centered()

func diagnostics_controls(body: VBoxContainer):
	game.ui.label(body,"진단 / 지원",22)
	game.ui.wrapped_label(body,"이 기기에서만 수집합니다. 저장 원문·계정·네트워크 주소·자유 형식 로그는 포함하지 않습니다. 공유 전에 ZIP 내용을 확인하세요.",16,600)
	var status = RichTextLabel.new()
	status.fit_content = true
	status.selection_enabled = true
	status.custom_minimum_size.y = 50
	body.add_child(status)
	var buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation",10)
	body.add_child(buttons)
	var copy = game.ui.button(buttons,"진단 정보 복사",func(): status.text = game.diagnostics.copy_information().message)
	var package = game.ui.button(buttons,"지원 패키지 만들기",func(): status.text = game.diagnostics.create_package().message)
	var choose = game.ui.button(body,"다른 폴더에 지원 패키지 저장…",func():
		var dialog = FileDialog.new()
		dialog.title = "지원 패키지를 저장할 폴더"
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.dir_selected.connect(func(path):
			if is_instance_valid(status): status.text = game.diagnostics.create_package(path).message
			dialog.queue_free())
		dialog.canceled.connect(func(): dialog.queue_free())
		panel.add_child(dialog)
		dialog.popup_centered(Vector2i(800,500)))
	game.ui.button(body,"생성 폴더 열기",func():
		if game.diagnostics.last_package.is_empty(): status.text = "먼저 지원 패키지를 만드세요."
		elif OS.shell_open(game.diagnostics.last_package.get_base_dir()) != OK: status.text = "폴더를 열지 못했습니다. 위의 경로를 사용하세요.")
	if OS.get_name() != "Windows":
		for control in [copy,package,choose]: control.disabled = true
		status.text = "Windows Native 전용 기능입니다."

func slider(body: Node, title: String, value: float, low: float, high: float, step: float) -> HSlider:
	game.ui.label(body,title,17)
	var control = HSlider.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.value = value
	body.add_child(control)
	return control
