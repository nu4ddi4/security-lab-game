class_name LabSettings
extends Node

const OVERRIDE_HEADER = "; Written by Security Lab: renderer choice from Settings > Display."
const DEFAULT_VALUES = {"renderer":0,"display_version":1,"resolution":0,"fullscreen":true,"vsync":true,"quality":1,"master":0.65,"sfx":0.55,"sensitivity":0.0018,"fov":72.0}
var values = DEFAULT_VALUES.duplicate()
var game: Node
var path = "user://settings.json"

func setup(root: Node):
	game = root
	path = "user://investigation-qa/settings.json" if game.qa_mode else "user://beta-settings.json"
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if raw is Dictionary:
		# Settings saved before full screen became the default are moved over once.
		if not raw.has("display_version"): raw.fullscreen = true
		for key in values:
			if raw.has(key) and (typeof(raw[key]) == typeof(values[key]) or (raw[key] is float or raw[key] is int) and not values[key] is bool): values[key] = raw[key]
	values.resolution = clampi(int(values.resolution),0,2)
	values.quality = clampi(int(values.quality),0,3)
	values.renderer = clampi(int(values.renderer),0,1)
	values.master = clampf(values.master,0,1)
	values.sfx = clampf(values.sfx,0,1)
	values.sensitivity = clampf(values.sensitivity,.0005,.004)
	values.fov = clampf(values.fov,60,90)
	if AudioServer.get_bus_index("SFX") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count-1,"SFX")
		AudioServer.set_bus_send(AudioServer.bus_count-1,"Master")
	if raw is Dictionary: apply()
	elif not game.qa_mode:
		apply_window()
		# A first start has no saved choice yet; the advanced renderer still gets its effects.
		if game.world != null: apply_graphics(int(values.quality),RenderingServer.get_current_rendering_method() == "forward_plus")

# Window mode and sync only; a first start has no saved quality to apply.
func apply_window():
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"): return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if not values.fullscreen: DisplayServer.window_set_size([Vector2i(1600,900),Vector2i(1280,720),Vector2i(1920,1080)][values.resolution])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)

func apply():
	apply_window()
	var quality = int(values.quality)
	var viewport = get_viewport()
	var mobile = OS.has_feature("mobile") or "--mobile-qa" in OS.get_cmdline_user_args()
	viewport.msaa_3d = Viewport.MSAA_DISABLED if mobile else [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X,Viewport.MSAA_8X][quality]
	viewport.scaling_3d_scale = .65 if mobile else (.8 if quality == 0 else 1.0)
	# Sharper floors and desks at grazing angles; costs almost nothing on desktop GPUs.
	viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_DISABLED if mobile else [Viewport.ANISOTROPY_2X,Viewport.ANISOTROPY_4X,Viewport.ANISOTROPY_8X,Viewport.ANISOTROPY_16X][quality]
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
	# Screen-space bounce light: Forward+ only, from High upwards.
	env.ssil_enabled = native_advanced and quality >= 2
	env.ssil_radius = 3.0
	env.ssil_intensity = .6
	env.ssr_enabled = false
	env.glow_enabled = native_advanced and quality >= 2
	env.glow_intensity = .15
	if game.world.has_node("OfficeReflection"): game.world.get_node("OfficeReflection").visible = native_advanced and quality >= 1

# The renderer is chosen before the first frame, so the choice is stored next to the executable
# (override.cfg is read at start-up). "Compatibility" is the default and simply has no file.
static func renderer_choice_available() -> bool:
	return OS.has_feature("template") and OS.get_name() == "Windows" and not OS.has_feature("mobile")

static func override_path() -> String:
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")

# Returns "" on success, otherwise a message for the player.
static func write_renderer_choice(choice: int) -> String:
	return write_override(override_path(),choice) if renderer_choice_available() else ""

static func write_override(target: String, choice: int) -> String:
	var existing = FileAccess.get_file_as_string(target) if FileAccess.file_exists(target) else ""
	if not existing.is_empty() and not existing.begins_with(OVERRIDE_HEADER): return "다른 설정이 들어 있는 override.cfg가 있어 렌더러를 바꾸지 않았습니다."
	if choice == 0:
		if not existing.is_empty() and DirAccess.remove_absolute(target) != OK: return "렌더러 설정 파일을 지우지 못했습니다."
		return ""
	var file = FileAccess.open(target,FileAccess.WRITE)
	if file == null: return "설치 폴더에 렌더러 설정을 저장하지 못했습니다. 이 폴더에는 쓸 권한이 없습니다."
	file.store_string(OVERRIDE_HEADER+"\n[rendering]\n\nrenderer/rendering_method=\"forward_plus\"\n")
	file.close()
	return ""

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
	var renderer_changed = int(candidate.get("renderer",0)) != int(values.renderer)
	values = candidate.duplicate(true)
	apply()
	var warning = write_renderer_choice(int(values.renderer)) if renderer_changed else ""
	if not warning.is_empty(): return {"ok":false,"message":warning}
	return {"ok":true,"message":"설정을 저장했습니다."+(" 렌더러는 게임을 다시 시작하면 바뀝니다." if renderer_changed and renderer_choice_available() else "")}


