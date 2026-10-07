class_name LabSettings
extends Node

var values = {"resolution":0,"fullscreen":false,"vsync":true,"quality":1,"master":0.65,"sfx":0.55,"sensitivity":0.0018,"fov":72.0}
var game: Node
var panel: Window
var path = "user://settings.json"

func setup(root: Node):
	game = root
	if game.qa_mode: path = "user://qa/settings.json"
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
	apply()
	game.ui.settings_requested.connect(show_menu)

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
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(values.master,.0001)))
	AudioServer.set_bus_mute(0,values.master <= 0)
	var sfx = AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(sfx,linear_to_db(maxf(values.sfx,.0001)))
	AudioServer.set_bus_mute(sfx,values.sfx <= 0)
	game.player.sensitivity = values.sensitivity
	game.player.camera.fov = values.fov

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
	game.ui.button(body,"적용하고 저장",func():
		values = {"resolution":resolution.selected,"fullscreen":fullscreen.button_pressed,"vsync":vsync.button_pressed,"quality":quality.selected,"master":master.value,"sfx":sfx.value,"sensitivity":sensitivity.value,"fov":fov.value}
		apply()
		var file = FileAccess.open(path,FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(values,"\t")); file.close()
		panel.queue_free(); panel = null)
	panel.popup_centered()

func slider(body: Node, title: String, value: float, low: float, high: float, step: float) -> HSlider:
	game.ui.label(body,title,17)
	var control = HSlider.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.value = value
	body.add_child(control)
	return control
