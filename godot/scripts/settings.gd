class_name LabSettings
extends Node

const DEFAULT_VALUES = {"resolution":0,"fullscreen":false,"vsync":true,"quality":1,"master":0.65,"sfx":0.55,"sensitivity":0.0018,"fov":72.0}
var values = DEFAULT_VALUES.duplicate()
var game: Node
var path = "user://settings.json"

func setup(root: Node):
	game = root
	path = "user://investigation-qa/settings.json" if game.qa_mode else "user://beta-settings.json"
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
	if raw is Dictionary: apply()

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


