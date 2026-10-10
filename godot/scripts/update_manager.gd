class_name LabUpdater
extends Node

const Policy = preload("res://scripts/update_policy.gd")
signal status_changed(message: String)
signal update_ready(version: String)
signal progress_changed(value: float)
var game: Node
var info: Dictionary = {}
var bundled: Dictionary = {}
var manifest: Dictionary = {}
var kind = "installer"
var candidate_sources: Array = []
var enabled = false
var local_test = false
var source = ""
var other_source = ""
var sources: Array = []
var source_index = 0
var candidates: Array = []
var verified_sources = 0
var check_error = ""
var progress = -1.0
var state = "disabled"
var stage = ""
var token = ""
var redirects = 0
var http: HTTPRequest
var consent_granted = false
var consent_dialog: ConfirmationDialog
var consent_player_enabled = false
var helper_pid = -1
var preparing_dialog: AcceptDialog
var settings_path = Policy.preference_path("dev")

func executable_path() -> String:
	return OS.get_executable_path()

func supported_platform() -> bool:
	return OS.get_name()=="Windows"

func build_info_path() -> String: return "res://prototype/build_info.json"
func stage_root() -> String: return "user://updates"
func automatic_check_enabled() -> bool: return true
func save_progress() -> bool: return false
func data_directory() -> String: return "user://"
func valid_saved_progress() -> bool: return false
func pause_for_install(): pass
func content_directory() -> String: return "user://content"
func beta_preview() -> bool: return info.get("channel") == "beta"

func setup(host: Node):
	game = host
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(build_info_path()))
	if not parsed is Dictionary or not Policy.build_valid(parsed): return
	info = parsed
	# A downloaded game-data pack replaces res://; the executable keeps its own identity.
	bundled = Engine.get_meta("bundled_build_info",info)
	settings_path = Policy.preference_path(info.channel,info.app_id)
	health_acknowledgement()
	var arguments = OS.get_cmdline_user_args()
	local_test = "--allow-local-update-url" in arguments
	source = info.manifest_url
	for argument in arguments:
		if argument.begins_with("--update-url="): source = argument.trim_prefix("--update-url=")
		elif argument.begins_with("--update-url-other="): other_source = argument.trim_prefix("--update-url-other=")
	var preference = JSON.parse_string(FileAccess.get_file_as_string(settings_path)) if FileAccess.file_exists(settings_path) else null
	enabled = Policy.enabled_for(info,arguments,preference,supported_platform())
	if not enabled: return
	if not Policy.trusted_manifest(source,info.channel,local_test,info.app_id): fail("업데이트 주소 또는 채널이 올바르지 않습니다."); return
	if not installed_identity_valid(): fail("자동 업데이트는 Security Lab 설치형 빌드에서 사용할 수 있습니다."); return
	http = HTTPRequest.new()
	http.use_threads = true
	http.accept_gzip = false
	http.max_redirects = 0
	http.timeout = 30
	http.request_completed.connect(response)
	add_child(http)
	state = "idle"
	if automatic_check_enabled(): check.call_deferred()

# The executable's own build; a downloaded data pack can make `info` newer than it.
func installed_identity() -> Dictionary:
	return bundled if not bundled.is_empty() else info

func installed_identity_valid() -> bool:
	var bundled = installed_identity()
	var executable = executable_path()
	if executable.get_file()!="SecurityLab.exe": return false
	var directory = executable.get_base_dir()
	if not FileAccess.file_exists(directory.path_join("build_info.json")) or not FileAccess.file_exists(directory.path_join("securitylab.install.json")): return false
	var sidecar = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("build_info.json")))
	var marker = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("securitylab.install.json")))
	return sidecar is Dictionary and sidecar==bundled and marker is Dictionary and marker.get("app_id")==bundled.app_id and marker.get("channel")==bundled.channel and marker.get("install_layout")==1

func set_enabled(value: bool):
	var file = FileAccess.open(settings_path,FileAccess.WRITE)
	if file==null: status_changed.emit("업데이트 설정을 저장하지 못했습니다."); return
	file.store_string(JSON.stringify({"enabled":value})); file.close()
	status_changed.emit("업데이트 설정은 다음 실행부터 적용됩니다.")
	if not value:
		enabled = false; consent_granted = false
		close_consent()
		if http!=null: http.cancel_request()
		state = "disabled"

func build_sources() -> Array:
	var rows = []
	for channel in Policy.channels_to_check(info.channel,beta_preview()):
		var url = Policy.manifest_url(channel,info.app_id)
		if channel==info.channel: url = source
		elif local_test:
			if other_source.is_empty(): continue
			url = other_source
		rows.append({"channel":channel,"url":url})
	return rows

func check():
	# A failed or postponed check must stay repeatable without restarting the game.
	if not enabled or state not in ["idle","failed","available"] or consent_dialog!=null: return
	sources = build_sources()
	if sources.is_empty(): return
	consent_granted = false
	manifest = {}; candidates = []; candidate_sources = []; verified_sources = 0; check_error = ""; source_index = 0; kind = "installer"
	state = "checking"; redirects = 0
	http.download_file = ""; http.body_size_limit = 16384
	status_changed.emit("업데이트 확인 중")
	request(sources[0].url)

func current_url() -> String:
	return sources[source_index].url if state=="checking" and source_index<sources.size() else source

# One unreachable or invalid channel never hides a valid update from another one.
func reject(message: String):
	if state!="checking": fail(message); return
	check_error = message
	next_source()

func next_source():
	source_index += 1; redirects = 0
	if source_index<sources.size(): request(sources[source_index].url); return
	if candidates.is_empty():
		if verified_sources==0: fail(check_error); return
		state = "idle"; status_changed.emit("현재 채널의 최신 버전입니다."); return
	var best = 0
	for i in candidates.size():
		if Policy.newer(candidates[i].version,candidates[best].version): best = i
	manifest = candidates[best]
	# A small game-data pack is enough when this executable can run it; otherwise the full installer.
	kind = "content" if content_applicable(manifest,candidate_sources[best]) else "installer"
	state = "available"
	status_changed.emit("업데이트가 있습니다 · %s · %s"%[manifest.version,"동의 후 게임 데이터만 내려받아 적용합니다." if kind=="content" else "동의 후 다운로드하고 설치합니다."])
	request_install()

func content_applicable(candidate: Dictionary, endpoint: String) -> bool:
	if not Policy.content_valid(candidate,candidate.channel,endpoint,local_test,info.app_id): return false
	var installed = installed_identity()
	if not Policy.hex(installed.get("compat"),64) or candidate.compat!=installed.compat: return false
	return candidate.commit not in ContentBootstrap.rejected(content_directory())

func request(url: String):
	if http.request(url,["Cache-Control: no-cache","Accept-Encoding: identity"])!=OK: fail("업데이트 연결을 시작하지 못했습니다.")

func response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
	if not enabled: return
	if code in [301,302,303,307,308] and result in [HTTPRequest.RESULT_SUCCESS,HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED]:
		var location = ""
		for header in headers:
			if header.to_lower().begins_with("location:"): location = header.substr(9).strip_edges()
		if redirects>=3 or not Policy.trusted_redirect(location,current_url(),local_test): reject("허용되지 않은 업데이트 리다이렉트입니다."); return
		redirects += 1; request.call_deferred(location); return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200: reject("업데이트 서버에 연결하지 못했습니다. 게임은 계속 사용할 수 있습니다."); return
	if state=="checking":
		var entry = sources[source_index]
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if not parsed is Dictionary or not Policy.manifest_valid(parsed,entry.channel,entry.url,local_test,info.app_id): reject("업데이트 정보의 형식 또는 채널 검증에 실패했습니다."); return
		verified_sources += 1
		if Policy.newer(parsed.version,info.version):
			candidates.append(parsed)
			candidate_sources.append(entry.url)
		next_source()
	elif state=="downloading":
		if not installer_verified(): fail("업데이트 파일의 크기 또는 SHA-256 검증에 실패했습니다."); return
		state = "ready"
		status_changed.emit("다운로드 완료 · 동의한 업데이트를 저장 후 설치합니다.")
		update_ready.emit(manifest.version)
		install.call_deferred()

func request_install():
	if not enabled or state not in ["available","ready"] or consent_dialog!=null: return
	var ui = game.get("ui") if game!=null else null
	if ui==null: return
	consent_dialog = ConfirmationDialog.new()
	consent_dialog.title = "업데이트가 있습니다"
	consent_dialog.dialog_text = ("현재 %s → 새 버전 %s (%s 채널)\n업데이트하시겠습니까? 게임 데이터만 내려받아(%.1fMB) 진행을 저장하고 게임을 다시 시작합니다." if kind=="content" else "현재 %s → 새 버전 %s (%s 채널)\n업데이트하시겠습니까? 다운로드가 끝나면 진행을 저장하고 게임을 종료한 뒤 설치·재실행합니다.")%([info.version,manifest.version,manifest.channel,float(manifest.content_size)/1048576.0] if kind=="content" else [info.version,manifest.version,manifest.channel])
	consent_dialog.ok_button_text = ("다운로드 후 적용" if kind=="content" else "다운로드 후 설치") if state=="available" else ("저장 후 적용" if kind=="content" else "저장 후 설치")
	consent_dialog.cancel_button_text = "나중에"
	consent_dialog.exclusive = true
	consent_dialog.theme = ui.root.theme
	consent_dialog.confirmed.connect(confirm_update)
	consent_dialog.canceled.connect(defer_update)
	consent_dialog.close_requested.connect(defer_update)
	var parent = ui.root
	var settings = game.get("settings")
	if settings!=null and settings.panel!=null and settings.panel.visible: parent = settings.panel
	parent.add_child(consent_dialog)
	var player = game.get("player")
	consent_player_enabled = player!=null and player.enabled
	if player!=null: player.set_enabled(false)
	consent_dialog.popup_centered(Vector2i(650,220))
	consent_dialog.get_cancel_button().grab_focus()

func close_consent():
	if consent_dialog==null: return
	consent_dialog.hide(); consent_dialog.queue_free(); consent_dialog = null
	var player = game.get("player") if game!=null else null
	var ui = game.get("ui") if game!=null else null
	var settings = game.get("settings") if game!=null else null
	if player!=null:
		var blocked = (ui!=null and ui.modal_open) or (settings!=null and settings.panel!=null and settings.panel.visible)
		player.set_enabled(consent_player_enabled and not blocked)

func defer_update():
	consent_granted = false
	close_consent()
	status_changed.emit("업데이트를 미뤘습니다. 설정에서 다시 선택할 수 있습니다.")

func confirm_update():
	if not enabled or state not in ["available","ready"]: return
	consent_granted = true
	close_consent()
	if state=="ready": install.call_deferred(); return
	token = Crypto.new().generate_random_bytes(16).hex_encode()
	if kind=="content":
		stage = ProjectSettings.globalize_path(content_directory())
		if DirAccess.make_dir_recursive_absolute(stage)!=OK: fail("업데이트 준비 폴더를 만들지 못했습니다."); return
		ContentBootstrap.remove(content_directory().path_join("pending.json"))
		http.download_file = stage.path_join("pending.pck")
		http.body_size_limit = int(manifest.content_size); http.timeout = 180; redirects = 0
		state = "downloading"; status_changed.emit("동의한 게임 데이터 다운로드 중")
		request.call_deferred(manifest.content_url)
		return
	stage = ProjectSettings.globalize_path(stage_root().path_join(token))
	if DirAccess.make_dir_recursive_absolute(stage)!=OK: fail("업데이트 준비 폴더를 만들지 못했습니다."); return
	http.download_file = stage.path_join("SecurityLabSetup.exe")
	http.body_size_limit = int(manifest.size); http.timeout = 180; redirects = 0
	state = "downloading"; status_changed.emit("동의한 업데이트 설치 파일 다운로드 중")
	request.call_deferred(manifest.installer_url)

func download_path() -> String:
	return stage.path_join("pending.pck" if kind=="content" else "SecurityLabSetup.exe")

func installer_verified() -> bool:
	var path = download_path()
	var file = FileAccess.open(path,FileAccess.READ)
	if file==null: return false
	var size = file.get_length(); file.close()
	return size==int(manifest.content_size if kind=="content" else manifest.size) and FileAccess.get_sha256(path)==(manifest.content_sha256 if kind=="content" else manifest.sha256)

# Hand-over of the verified pack: the launcher mounts it on the next start.
func install_content():
	state = "preparing"
	if not installer_verified(): fail("설치 직전 검증에 실패했습니다. 현재 앱을 유지합니다."); return
	if not save_progress(): fail("진행 저장에 실패하여 업데이트를 중단했습니다."); return
	var pending = {"version":manifest.version,"commit":manifest.commit,"sha256":manifest.content_sha256,"size":int(manifest.content_size),"compat":manifest.compat,"channel":manifest.channel}
	if not ContentBootstrap.write_json(content_directory().path_join("pending.json"),pending): fail("업데이트 정보를 저장하지 못했습니다."); return
	status_changed.emit("진행 저장 완료 · 게임 데이터를 적용하기 위해 다시 시작합니다.")
	if not restart(): fail("게임을 다시 시작하지 못했습니다. 다음 실행 때 적용됩니다.")

func restart() -> bool:
	var arguments = []
	for argument in OS.get_cmdline_args():
		if argument=="--": break
		arguments.append(argument)
	var user_arguments = OS.get_cmdline_user_args()
	if not user_arguments.is_empty():
		arguments.append("--")
		arguments.append_array(user_arguments)
	if OS.create_process(executable_path(),PackedStringArray(arguments))<=0: return false
	get_tree().quit()
	return true

func install():
	if state!="ready" or not enabled or not consent_granted: return
	if kind=="content": install_content(); return
	state = "preparing"
	if not installed_identity_valid() or not installer_verified(): fail("설치 직전 검증에 실패했습니다. 현재 앱을 유지합니다."); return
	if not save_progress(): fail("진행 저장에 실패하여 업데이트를 중단했습니다."); return
	var ui = game.get("ui")
	if ui!=null:
		var settings = game.get("settings")
		if settings!=null and settings.panel!=null: settings.panel.hide(); settings.panel.queue_free(); settings.panel = null
		pause_for_install()
		preparing_dialog = AcceptDialog.new()
		preparing_dialog.title = "Security Lab 업데이트"
		preparing_dialog.dialog_text = "진행을 저장했습니다. 앱 종료와 업데이트 설치를 준비합니다."
		preparing_dialog.exclusive = true
		preparing_dialog.dialog_close_on_escape = false
		preparing_dialog.theme = ui.root.theme
		preparing_dialog.get_ok_button().hide()
		preparing_dialog.get_ok_button().disabled = true
		ui.root.add_child(preparing_dialog)
		preparing_dialog.popup_centered(Vector2i(580,160))
	var request_data = {"schema":1,"token":token,"parent_pid":OS.get_process_id(),"install_directory":executable_path().get_base_dir(),"data_directory":ProjectSettings.globalize_path(data_directory()),"current":info,"installed":installed_identity(),"target":manifest}
	for entry in [["transaction.json",JSON.stringify(request_data)], ["SecurityLabUpdater.ps1",FileAccess.get_file_as_string("res://resources/native_update_helper.ps1")]]:
		var file = FileAccess.open(stage.path_join(entry[0]),FileAccess.WRITE)
		if file==null: fail("업데이트 실행 준비를 저장하지 못했습니다."); return
		file.store_string(entry[1]); file.flush(); file.close()
	var powershell = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	helper_pid = OS.create_process(powershell,["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",stage.path_join("SecurityLabUpdater.ps1"),"-RequestPath",stage.path_join("transaction.json")])
	if helper_pid<=0: fail("업데이트 실행 도우미를 시작하지 못했습니다."); return
	status_changed.emit("진행 저장 완료 · 업데이트 설치를 준비합니다.")
	# The helper hashes the install tree and installer before it reports ready.
	for i in range(300):
		await get_tree().create_timer(.1).timeout
		var ready = JSON.parse_string(FileAccess.get_file_as_string(stage.path_join("ready.json"))) if FileAccess.file_exists(stage.path_join("ready.json")) else null
		if ready is Dictionary and ready.get("token")==token and ready.get("pid")==helper_pid:
			get_tree().quit(); return
		if not OS.is_process_running(helper_pid): break
	if OS.is_process_running(helper_pid): OS.kill(helper_pid)
	fail("설치 준비에 실패했습니다. 게임을 계속 사용할 수 있습니다.")

func set_progress(value: float):
	if is_equal_approx(value,progress): return
	progress = value
	progress_changed.emit(value)

# Download progress is shown while the installer or data pack is being fetched.
func _process(_delta):
	if state=="downloading" and is_instance_valid(http):
		var total = float(manifest.get("content_size" if kind=="content" else "size",0))
		set_progress(clampf(http.get_downloaded_bytes()/total,0.0,1.0) if total>0 else -1.0)
	elif progress>=0.0:
		set_progress(-1.0)

func fail(message: String):
	state = "failed"; consent_granted = false
	close_consent()
	if preparing_dialog!=null: preparing_dialog.queue_free(); preparing_dialog = null
	status_changed.emit(message)

func health_acknowledgement():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--update-relaunch="): acknowledge_health(argument.trim_prefix("--update-relaunch="))

func acknowledge_health(nonce: String):
	if not Policy.hex(nonce,32): return
	var directory = ProjectSettings.globalize_path(stage_root().path_join(nonce))
	if not FileAccess.file_exists(directory.path_join("transaction.json")): return
	var transaction = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("transaction.json")))
	if not transaction is Dictionary or transaction.get("schema")!=1 or transaction.get("token")!=nonce or transaction.get("target") is not Dictionary: return
	var target = transaction.target
	if target.get("app_id")!=info.app_id or target.get("channel")!=info.channel or target.get("version")!=info.version or target.get("commit")!=info.commit: return
	if not installed_identity_valid(): return
	var actual_directory = ProjectSettings.globalize_path(data_directory()).replace("\\","/").simplify_path().trim_suffix("/")
	var expected_directory = String(transaction.get("data_directory","")).replace("\\","/").simplify_path().trim_suffix("/")
	if actual_directory.to_lower()!=expected_directory.to_lower(): return
	if not valid_saved_progress(): return
	var file = FileAccess.open(directory.path_join("health.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"token":nonce,"version":info.version,"pid":OS.get_process_id()})); file.flush(); file.close()
