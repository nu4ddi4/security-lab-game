class_name LabDiagnostics
extends Node

const Serializer = preload("res://scripts/diagnostics_serializer.gd")
const MAX_JSON = 16384
const LOG_TAIL = 65536
const README = """Security Lab local support package (schema 1)
diagnostics.json: system, display, settings and bounded runtime summary.
build_info.json: allowlisted build identity, never an arbitrary sidecar copy.
save_validation.json: validation results only; no save content or answers.
logs/recent.json: bounded engine log summaries; free-form log text is excluded.
updater.json: optional state/result enums; no URL, token, error text or paths.
session.json: previous exit marker; an unclean exit is not proof of a crash.
No network upload, machine ID, username, environment dump or arbitrary files.
Hardware model strings and paths are redacted. Review before sharing.
"""
var game: Node
var serializer = Serializer.new()
var data_directory = "user://diagnostics"
var save_directory = "user://"
var log_directory = "user://logs"
var update_directory = "user://updates"
var previous_session = {"available":false}
var session_start = ""
var session_ready = false
var session_writable = false
var last_package = ""
var events: Array = []

func setup(root: Node):
	game = root
	if not supported(): return
	save_directory = game.saves.directory
	if game.qa_mode:
		data_directory = "user://qa/diagnostics"
		log_directory = "user://qa/diagnostics-logs"
		update_directory = "user://qa/diagnostics-updates"
	begin_session()

func mark_ready():
	if not supported(): return
	session_ready = true
	write_session(false)

func supported() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("web")

func timestamp() -> String:
	return Time.get_datetime_string_from_system(true)

func safe_path(path: String) -> bool:
	if path.begins_with("res://"): return true
	var absolute = ProjectSettings.globalize_path(path).replace("\\","/")
	if not absolute.is_absolute_path() or absolute.begins_with("//"): return false
	var probe = absolute
	while not probe.is_empty():
		var parent = probe.get_base_dir()
		if parent == probe or parent.is_empty(): break
		var directory = DirAccess.open(parent)
		if directory != null and directory.is_link(probe.get_file()): return false
		probe = parent
	return true

func read_json(path: String, maximum = MAX_JSON) -> Dictionary:
	if not safe_path(path): return {"status":"unsafe_path"}
	if not FileAccess.file_exists(path): return {"status":"missing"}
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {"status":"unreadable"}
	if file.get_length() > maximum: file.close(); return {"status":"oversize"}
	var parser = JSON.new()
	var error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary: return {"status":"invalid"}
	return {"status":"ok","data":parser.data}

func build_info() -> Dictionary:
	var source = read_json("res://resources/build_info.json")
	var raw = source.get("data",{})
	if not raw.has("version"): raw.version = ProjectSettings.get_setting("application/config/version","unknown")
	return serializer.build(raw)

func begin_session():
	session_start = timestamp()
	var previous = read_json(data_directory.path_join("session.json"))
	if previous.status == "ok" and previous.data.get("schema") == 1 and previous.data.get("clean_exit") is bool:
		previous_session = {"available":true,"suspected_abnormal_exit":not previous.data.clean_exit,"ready":previous.data.get("ready") == true,"started_utc":safe_time(previous.data.get("started_utc")),"build":serializer.build(previous.data.get("build"))}
	if safe_path(data_directory) and DirAccess.make_dir_recursive_absolute(data_directory) == OK:
		session_writable = true
		write_session(false)
	add_event("session_started")

func safe_time(value) -> String:
	var regex = RegEx.new()
	regex.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$")
	return value if value is String and regex.search(value) != null else "unknown"

func write_session(clean_exit: bool):
	if not session_writable: return
	var target = data_directory.path_join("session.json")
	if not safe_path(target): return
	var file = FileAccess.open(target,FileAccess.WRITE)
	if file != null:
		file.store_string(serializer.json({"schema":1,"started_utc":session_start,"clean_exit":clean_exit,"ready":session_ready,"build":build_info()}))
		file.close()

func _exit_tree():
	write_session(true)

func add_event(code: String):
	if code not in ["session_started","copied","package_created","package_failed"]: return
	events.append({"event":code,"uptime_ms":Time.get_ticks_msec()})
	if events.size() > 32: events.pop_front()

func save_validation() -> Dictionary:
	var result = {}
	for name in ["progress.json","progress.backup.json"]:
		var path = save_directory.path_join(name)
		var loaded = read_json(path,131072)
		var status = loaded.status
		if status == "ok":
			# Decode into an isolated mission manager: never mutate game state,
			# backups, error_message or progress while collecting diagnostics.
			var store = preload("res://scripts/save_manager.gd").new()
			var probe = preload("res://scripts/missions.gd").new()
			status = "valid" if store.decode(JSON.stringify(loaded.data),probe) else "invalid"
			probe.free()
		result[name] = {"status":status}
	return result

func recent_logs() -> Array:
	var reports: Array = []
	if not safe_path(log_directory): return [{"source":"engine_log","status":"unsafe_path"}]
	var directory = DirAccess.open(log_directory)
	if directory == null: return [{"source":"engine_log","status":"missing"}]
	var candidates = []
	# Only engine-owned names; never recurse or read user-selected files.
	for name in directory.get_files():
		if name == "godot.log" or name.begins_with("godot") and name.ends_with(".log") and valid_log_name(name):
			candidates.append({"name":name,"modified":FileAccess.get_modified_time(log_directory.path_join(name))})
	candidates.sort_custom(func(a,b): return a.modified > b.modified)
	for candidate in candidates.slice(0,3):
		var path = log_directory.path_join(candidate.name)
		var row = {"source":"engine_log","status":"unreadable"}
		if not safe_path(path): row.status = "unsafe_path"; reports.append(row); continue
		var file = FileAccess.open(path,FileAccess.READ)
		if file != null:
			var size = file.get_length()
			file.seek(maxi(0,size-LOG_TAIL))
			var tail = file.get_buffer(LOG_TAIL).get_string_from_utf8()
			file.close()
			if size > LOG_TAIL: tail = tail.substr(tail.find("\n")+1)
			row = {"source":"engine_log","status":"ok","tail_truncated":size > LOG_TAIL,"summary":serializer.log_summary(tail)}
		reports.append(row)
	if reports.is_empty(): reports.append({"source":"engine_log","status":"missing"})
	return reports

func valid_log_name(name: String) -> bool:
	var regex = RegEx.new()
	regex.compile("^godot(?:[0-9_.-]+)?\\.log$")
	return regex.search(name) != null

func property(object: Object, name: String, fallback = null):
	if object == null: return fallback
	for entry in object.get_property_list():
		if entry.name == name: return object.get(name)
	return fallback

func updater_summary() -> Dictionary:
	var result = {"available":false,"state":"unavailable","recent_result":{"status":"missing"}}
	var updater = property(game,"updater")
	if updater is Object:
		result.available = true
		result.state = serializer.enum_value(property(updater,"state"),["disabled","idle","checking","downloading","ready","preparing","failed"])
		var enabled = property(updater,"enabled")
		if enabled is bool: result.enabled = enabled
		result.build = serializer.build(property(updater,"info",{}))
	if not safe_path(update_directory): return result
	var directory = DirAccess.open(update_directory)
	if directory == null: return result
	var candidates = []
	var regex = RegEx.new()
	regex.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
	for name in directory.get_directories():
		if regex.search(name) == null: continue
		var path = update_directory.path_join(name).path_join("result.json")
		if safe_path(path) and FileAccess.file_exists(path): candidates.append({"file":path,"modified":FileAccess.get_modified_time(path)})
		if candidates.size() >= 64: break
	candidates.sort_custom(func(a,b): return a.modified > b.modified)
	if not candidates.is_empty():
		var recent = read_json(candidates[0].file)
		result.recent_result = {"status":recent.status}
		if recent.status == "ok":
			result.available = true
			result.recent_result.state = serializer.enum_value(recent.data.get("state"),["verifying_startup","installed","rolled_back","recovery_required","cancelled"])
			result.recent_result.version = serializer.version(recent.data.get("version","unknown"))
	return result

func runtime_summary() -> Dictionary:
	if game == null: return {"available":false}
	var summary = {"available":true,"uptime_ms":Time.get_ticks_msec(),"scene":"native_lab","paused":get_tree().paused,"load_ms":game.loaded_ms}
	if game.missions != null:
		summary.mission = serializer.enum_value(game.missions.mission().id,["tutorial","services","login","integrity"])
		summary.verified = game.missions.progress().verified
		summary.stage = serializer.enum_value(game.missions.stage(),["준비","조사","취약 상태 확인","방어 적용","장비 재확인 필요","검증 완료"])
	if game.world != null:
		summary.interaction_anchors = game.world.protected_nodes.size()
		summary.colliders = game.world.collider_count
		summary.doors = game.world.doors.size()
		summary.devices = game.world.devices.size()
	if game.player != null:
		summary.player_enabled = game.player.enabled
		summary.on_floor = game.player.is_on_floor()
	summary.last_frame = {"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"fps":Performance.get_monitor(Performance.TIME_FPS)}
	return summary

func rendering_value(method: String) -> String:
	if DisplayServer.get_name() == "headless": return "unavailable (headless)"
	return str(RenderingServer.call(method)) if RenderingServer.has_method(method) else "unavailable"

func snapshot() -> Dictionary:
	var headless = DisplayServer.get_name() == "headless"
	var window = Vector2i.ZERO if headless else DisplayServer.window_get_size()
	var display = {"display_server":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"window_pixels":{"width":window.x,"height":window.y},"window_mode":"headless" if headless else ["windowed","minimized","maximized","fullscreen","exclusive_fullscreen"][DisplayServer.window_get_mode()]}
	if is_inside_tree(): display.viewport = {"scaling_3d_scale":get_viewport().scaling_3d_scale,"msaa_3d":get_viewport().msaa_3d}
	if game != null and game.settings != null:
		display.settings = serializer.settings(game.settings.values)
		display.graphics_preset = ["low","medium","high","ultra"][clampi(int(game.settings.values.quality),0,3)]
	var system = {"os":OS.get_name(),"os_version":OS.get_version(),"cpu":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"gpu":rendering_value("get_video_adapter_name"),"gpu_vendor":rendering_value("get_video_adapter_vendor"),"graphics_api":rendering_value("get_video_adapter_api_version"),"architecture":Engine.get_architecture_name()}
	return serializer.clean({"schema":1,"generated_utc":timestamp(),"build":build_info(),"godot":Engine.get_version_info().string,"system":system,"display":display,"runtime":runtime_summary(),"save_validation":save_validation(),"updater":updater_summary(),"session":{"previous":previous_session,"current":{"started_utc":session_start,"ready":session_ready,"marker_writable":session_writable}},"recent_logs":recent_logs(),"events":events.duplicate(true),"privacy":{"local_only":true,"log_text_included":false,"save_content_included":false,"identifiers_included":false}})

func copy_information() -> Dictionary:
	if not supported(): return {"ok":false,"message":"진단 정보 복사는 Windows Native에서 지원합니다."}
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD): return {"ok":false,"message":"클립보드를 사용할 수 없습니다."}
	DisplayServer.clipboard_set(serializer.json(snapshot()))
	add_event("copied")
	return {"ok":true,"message":"진단 정보를 복사했습니다. 저장 원문과 개인 식별 정보는 포함하지 않습니다."}

func create_package(destination = "") -> Dictionary:
	if not supported(): return {"ok":false,"message":"지원 패키지는 Windows Native에서 지원합니다."}
	var target = destination if not destination.is_empty() else data_directory.path_join("packages")
	if not safe_path(target): return package_failure("안전한 로컬 폴더를 선택하세요.")
	if destination.is_empty() and DirAccess.make_dir_recursive_absolute(target) != OK: return package_failure("지원 패키지 폴더를 만들 수 없습니다.")
	if not DirAccess.dir_exists_absolute(target): return package_failure("저장 폴더가 없거나 사용할 수 없습니다.")
	var clock = Time.get_datetime_dict_from_system()
	var basename = "SecurityLab-Diagnostics-%04d%02d%02d-%02d%02d%02d" % [clock.year,clock.month,clock.day,clock.hour,clock.minute,clock.second]
	var path = target.path_join(basename+".zip")
	var counter = 1
	while FileAccess.file_exists(path):
		path = target.path_join(basename+"-%02d.zip" % counter)
		counter += 1
		if counter > 100: return package_failure("같은 시각의 패키지가 너무 많습니다. 잠시 후 다시 시도하세요.")
	var partial = path+".partial"
	if not safe_path(path) or FileAccess.file_exists(partial): return package_failure("출력 파일을 안전하게 만들 수 없습니다.")
	var report = snapshot()
	var entries = {"README.txt":README,"diagnostics.json":serializer.json(report),"build_info.json":serializer.json(report.build),"save_validation.json":serializer.json(report.save_validation),"logs/recent.json":serializer.json({"engine":report.recent_logs,"events":report.events}),"updater.json":serializer.json(report.updater),"session.json":serializer.json(report.session)}
	var writer = ZIPPacker.new()
	var error = writer.open(partial)
	if error != OK: return package_failure("ZIP 파일을 열지 못했습니다 · "+error_string(error))
	for name in entries:
		error = writer.start_file(name)
		if error == OK: error = writer.write_file(entries[name].to_utf8_buffer())
		if error == OK: error = writer.close_file()
		if error != OK: break
	var closing = writer.close()
	if error == OK: error = closing
	if error == OK: error = DirAccess.rename_absolute(partial,path)
	if error != OK:
		DirAccess.remove_absolute(partial)
		return package_failure("ZIP 저장에 실패했습니다 · "+error_string(error))
	last_package = ProjectSettings.globalize_path(path)
	add_event("package_created")
	return {"ok":true,"file":last_package,"message":"지원 패키지 생성 완료\n"+serializer.text(last_package)}

func package_failure(message: String) -> Dictionary:
	add_event("package_failed")
	return {"ok":false,"message":message+"\n다른 쓰기 가능한 폴더를 선택하세요. 게임과 저장은 계속 사용할 수 있습니다."}
