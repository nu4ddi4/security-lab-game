class_name LabUpdater
extends Node

const Policy = preload("res://scripts/update_policy.gd")
signal status_changed(message: String)
signal update_ready(version: String)
var game: Node
var info: Dictionary = {}
var manifest: Dictionary = {}
var enabled = false
var local_test = false
var source = ""
var state = "disabled"
var stage = ""
var token = ""
var redirects = 0
var http: HTTPRequest
var install_on_exit = false
var helper_pid = -1
var preparing_dialog: AcceptDialog
var settings_path = "user://update-settings.json"

func executable_path() -> String:
	return OS.get_executable_path()

func setup(host: Node):
	game = host
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://resources/build_info.json"))
	if not parsed is Dictionary or not Policy.build_valid(parsed): return
	info = parsed
	health_acknowledgement()
	var arguments = OS.get_cmdline_user_args()
	local_test = "--allow-local-update-url" in arguments
	source = info.manifest_url
	for argument in arguments:
		if argument.begins_with("--update-url="): source = argument.trim_prefix("--update-url=")
	var preference = JSON.parse_string(FileAccess.get_file_as_string(settings_path)) if FileAccess.file_exists(settings_path) else null
	enabled = Policy.enabled_for(info,arguments,preference,OS.get_name()=="Windows")
	if not enabled: return
	if not Policy.trusted_manifest(source,info.channel,local_test): fail("업데이트 주소 또는 채널이 올바르지 않습니다."); return
	if not installed_identity_valid(): fail("자동 업데이트는 Security Lab 설치형 빌드에서 사용할 수 있습니다."); return
	http = HTTPRequest.new()
	http.use_threads = true
	http.accept_gzip = false
	http.max_redirects = 0
	http.timeout = 30
	http.request_completed.connect(response)
	add_child(http)
	state = "idle"
	check.call_deferred()

func installed_identity_valid() -> bool:
	var executable = executable_path()
	if executable.get_file()!="SecurityLab.exe": return false
	var directory = executable.get_base_dir()
	if not FileAccess.file_exists(directory.path_join("build_info.json")) or not FileAccess.file_exists(directory.path_join("securitylab.install.json")): return false
	var sidecar = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("build_info.json")))
	var marker = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("securitylab.install.json")))
	return sidecar is Dictionary and sidecar==info and marker is Dictionary and marker.get("app_id")==Policy.APP_ID and marker.get("channel")==info.channel and marker.get("install_layout")==1

func set_enabled(value: bool):
	var file = FileAccess.open(settings_path,FileAccess.WRITE)
	if file==null: status_changed.emit("업데이트 설정을 저장하지 못했습니다."); return
	file.store_string(JSON.stringify({"enabled":value})); file.close()
	status_changed.emit("업데이트 설정은 다음 실행부터 적용됩니다.")
	if not value:
		enabled = false; install_on_exit = false
		if http!=null: http.cancel_request()
		state = "disabled"

func check():
	if not enabled or state!="idle": return
	state = "checking"; redirects = 0
	http.download_file = ""; http.body_size_limit = 16384
	status_changed.emit("%s 업데이트 확인 중"%info.channel)
	request(source)

func request(url: String):
	if http.request(url,["Cache-Control: no-cache","Accept-Encoding: identity"])!=OK: fail("업데이트 연결을 시작하지 못했습니다.")

func response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray):
	if not enabled: return
	if code in [301,302,303,307,308] and result in [HTTPRequest.RESULT_SUCCESS,HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED]:
		var location = ""
		for header in headers:
			if header.to_lower().begins_with("location:"): location = header.substr(9).strip_edges()
		if redirects>=3 or not Policy.trusted_redirect(location,source,local_test): fail("허용되지 않은 업데이트 리다이렉트입니다."); return
		redirects += 1; request.call_deferred(location); return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200: fail("업데이트 서버에 연결하지 못했습니다. 게임은 계속 사용할 수 있습니다."); return
	if state=="checking":
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if not parsed is Dictionary or not Policy.manifest_valid(parsed,info.channel,source,local_test): fail("업데이트 정보의 형식 또는 채널 검증에 실패했습니다."); return
		if not Policy.newer(parsed.version,info.version): state = "idle"; status_changed.emit("현재 채널의 최신 버전입니다."); return
		manifest = parsed
		token = Crypto.new().generate_random_bytes(16).hex_encode()
		stage = ProjectSettings.globalize_path("user://updates/"+token)
		if DirAccess.make_dir_recursive_absolute(stage)!=OK: fail("업데이트 준비 폴더를 만들지 못했습니다."); return
		http.download_file = stage.path_join("SecurityLabSetup.exe")
		http.body_size_limit = int(manifest.size); http.timeout = 180; redirects = 0
		state = "downloading"; status_changed.emit("업데이트 설치 파일 다운로드 중")
		request.call_deferred(manifest.installer_url)
	elif state=="downloading":
		if not installer_verified(): fail("업데이트 파일의 크기 또는 SHA-256 검증에 실패했습니다."); return
		state = "ready"; install_on_exit = true
		status_changed.emit("업데이트 준비 완료 · 종료할 때 저장 후 설치합니다.")
		update_ready.emit(manifest.version)

func installer_verified() -> bool:
	var path = stage.path_join("SecurityLabSetup.exe")
	var file = FileAccess.open(path,FileAccess.READ)
	if file==null: return false
	var size = file.get_length(); file.close()
	return size==int(manifest.size) and FileAccess.get_sha256(path)==manifest.sha256

func install():
	if state!="ready" or not enabled: return
	state = "preparing"
	if not installed_identity_valid() or not installer_verified(): fail("설치 직전 검증에 실패했습니다. 현재 앱을 유지합니다."); return
	if not game.saves.save(game.missions): fail("진행 저장에 실패하여 업데이트를 중단했습니다."); return
	var ui = game.get("ui")
	if ui!=null:
		var settings = game.get("settings")
		if settings!=null and settings.panel!=null: settings.panel.hide(); settings.panel.queue_free(); settings.panel = null
		ui.pause()
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
	var request_data = {"schema":1,"token":token,"parent_pid":OS.get_process_id(),"install_directory":executable_path().get_base_dir(),"data_directory":ProjectSettings.globalize_path(game.saves.directory),"current":info,"target":manifest}
	for entry in [["transaction.json",JSON.stringify(request_data)], ["SecurityLabUpdater.ps1",FileAccess.get_file_as_string("res://resources/native_update_helper.ps1")]]:
		var file = FileAccess.open(stage.path_join(entry[0]),FileAccess.WRITE)
		if file==null: fail("업데이트 실행 준비를 저장하지 못했습니다."); return
		file.store_string(entry[1]); file.flush(); file.close()
	var powershell = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	helper_pid = OS.create_process(powershell,["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",stage.path_join("SecurityLabUpdater.ps1"),"-RequestPath",stage.path_join("transaction.json")])
	if helper_pid<=0: fail("업데이트 실행 도우미를 시작하지 못했습니다."); return
	status_changed.emit("진행 저장 완료 · 업데이트 설치를 준비합니다.")
	for i in range(100):
		await get_tree().create_timer(.1).timeout
		var ready = JSON.parse_string(FileAccess.get_file_as_string(stage.path_join("ready.json"))) if FileAccess.file_exists(stage.path_join("ready.json")) else null
		if ready is Dictionary and ready.get("token")==token and ready.get("pid")==helper_pid:
			get_tree().quit(); return
		if not OS.is_process_running(helper_pid): break
	if OS.is_process_running(helper_pid): OS.kill(helper_pid)
	fail("설치 준비에 실패했습니다. 게임을 계속 사용할 수 있습니다.")

func fail(message: String):
	state = "failed"; install_on_exit = false
	if preparing_dialog!=null: preparing_dialog.queue_free(); preparing_dialog = null
	status_changed.emit(message)

func health_acknowledgement():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--update-relaunch="): acknowledge_health(argument.trim_prefix("--update-relaunch="))

func acknowledge_health(nonce: String):
	if not Policy.hex(nonce,32): return
	var directory = ProjectSettings.globalize_path("user://updates/"+nonce)
	if not FileAccess.file_exists(directory.path_join("transaction.json")): return
	var transaction = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("transaction.json")))
	if not transaction is Dictionary or transaction.get("schema")!=1 or transaction.get("token")!=nonce or transaction.get("target") is not Dictionary: return
	var target = transaction.target
	if target.get("app_id")!=info.app_id or target.get("channel")!=info.channel or target.get("version")!=info.version or target.get("commit")!=info.commit: return
	if not installed_identity_valid(): return
	var actual_directory = ProjectSettings.globalize_path(game.saves.directory).replace("\\","/").simplify_path().trim_suffix("/")
	var expected_directory = String(transaction.get("data_directory","")).replace("\\","/").simplify_path().trim_suffix("/")
	if actual_directory.to_lower()!=expected_directory.to_lower(): return
	var save_path = actual_directory.path_join("progress.json")
	if not FileAccess.file_exists(save_path) or not game.saves.decode(FileAccess.get_file_as_string(save_path),game.missions): return
	var file = FileAccess.open(directory.path_join("health.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"token":nonce,"version":info.version,"pid":OS.get_process_id()})); file.flush(); file.close()
