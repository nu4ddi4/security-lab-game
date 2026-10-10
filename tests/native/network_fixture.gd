extends SceneTree
const Updater = preload("res://prototype/scripts/installer_updates.gd")
class FixtureUpdater extends Updater:
	var fixture_exe = ""
	var fixture_content = ""
	var restart_requested = false
	func executable_path() -> String: return fixture_exe
	func content_directory() -> String: return fixture_content
	func restart() -> bool:
		restart_requested = true
		return true
	func supported_platform() -> bool: return true
	func data_directory() -> String: return game.store.directory
	func pause_for_install(): pass
	var execute_install = false
	var install_requested = false
	func super_install_without_consent(): await super.install()
	func install():
		install_requested = true
		if execute_install: await super.install()
class FixtureUI extends Node:
	var root = Control.new()
	var modal_open = false
	func _ready(): add_child(root)
class FixturePlayer extends Node:
	var enabled = true
	func set_enabled(value: bool): enabled = value
class FixtureControls extends RefCounted:
	var automatic_updates = true
class Host extends Node:
	var store = InvestigationStore.new()
	var content = InvestigationContent.load_case()
	var state = InvestigationEngine.new(content).create_state()
	var controls = FixtureControls.new()
	func save_now() -> bool: return store.save(state,content)
	var ui: FixtureUI
	var player: FixturePlayer
	var settings = null
	var preview = true
	func beta_preview() -> bool: return preview
var manager: FixtureUpdater
var host: Host
var mode = ""
var original_directory = ""
var failure = ""

func _init(): run.call_deferred()

func run():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture-mode="): mode = argument.trim_prefix("--fixture-mode=")
	host = Host.new(); root.add_child(host)
	host.preview = mode != "preview-off"
	var nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	original_directory = "user://qa/updater-network/"+nonce
	host.store.directory = original_directory
	DirAccess.make_dir_recursive_absolute(original_directory)
	var install = original_directory.path_join("Install A & B% $ 한")
	DirAccess.make_dir_recursive_absolute(install)
	write(install.path_join("SecurityLab.exe"),"fixture executable; never executed")
	write(install.path_join("build_info.json"),FileAccess.get_file_as_string("res://prototype/build_info.json"))
	write(install.path_join("securitylab.install.json"),JSON.stringify({"app_id":"security-lab-beta","channel":"beta","install_layout":1}))
	manager = FixtureUpdater.new(); manager.fixture_exe = ProjectSettings.globalize_path(install.path_join("SecurityLab.exe")); manager.fixture_content = original_directory.path_join("content"); root.add_child(manager)
	DirAccess.make_dir_recursive_absolute(manager.fixture_content)
	if mode=="content-rejected": ContentBootstrap.reject(manager.fixture_content,"a".repeat(40))
	manager.status_changed.connect(func(message): failure = message)
	if mode in ["dialog-dismiss","dialog-close","dialog-confirm"]:
		host.ui = FixtureUI.new(); host.add_child(host.ui)
		host.player = FixturePlayer.new(); host.add_child(host.player)
	manager.setup(host)
	for i in range(200):
		if manager.state in ["available","failed","disabled"]: break
		await create_timer(.1).timeout
	var success = false
	if mode in ["no-consent","declined","dialog-dismiss","dialog-close"]:
		success = manager.state=="available" and manager.stage=="" and not manager.consent_granted and not manager.install_requested
		if mode=="declined": manager.defer_update()
		if mode in ["dialog-dismiss","dialog-close"]:
			success = success and manager.consent_dialog!=null and not host.player.enabled
			if mode=="dialog-close": manager.consent_dialog.close_requested.emit()
			else: manager.consent_dialog.canceled.emit()
			success = success and manager.consent_dialog==null and host.player.enabled
		# Even a caller with a ready payload cannot install without consent.
		manager.state = "ready"
		await manager.super_install_without_consent()
		success = success and manager.state=="ready" and manager.helper_pid==-1
		manager.state = "available"
	elif manager.state=="available":
		if mode=="dialog-confirm":
			success = manager.consent_dialog!=null and not host.player.enabled
			if not success: quit(1); return
			manager.consent_dialog.confirmed.emit()
			success = manager.consent_dialog==null and host.player.enabled
		else: manager.confirm_update()
		for i in range(200):
			if manager.state in ["ready","failed","disabled"]: break
			await create_timer(.1).timeout
		await create_timer(.1).timeout
	if mode=="retry-after-failure":
		# The first answer is a server error; a later manual check must still work.
		success = manager.state=="failed"
		manager.check()
		for i in range(200):
			if manager.state in ["available","failed","disabled"]: break
			await create_timer(.1).timeout
		success = success and manager.state=="available"
	elif mode in ["ready","redirect-ready","helper-launch","save-failure","health-validation","bad-save-health","dialog-confirm","preview-newer-stable","preview-other-down","preview-off","content-update","content-mismatch","content-rejected"]:
		success = manager.state=="ready" and manager.installer_verified() and manager.consent_granted and manager.install_requested
		success = success and manager.kind==("content" if mode=="content-update" else "installer")
		if mode=="content-update":
			# The verified pack is handed to the launcher: pending metadata, saved progress, then a restart.
			manager.execute_install = true
			await manager.install()
			var pending = ContentBootstrap.read_json(manager.fixture_content.path_join("pending.json"))
			success = success and manager.restart_requested and pending.get("commit")==manager.manifest.commit and pending.get("sha256")==manager.manifest.content_sha256 and pending.get("compat")==manager.manifest.compat and FileAccess.file_exists(manager.fixture_content.path_join("pending.pck")) and host.store.load_state(host.content).has("state")
		if mode in ["preview-newer-stable","preview-off"]: success = success and manager.manifest.channel=="stable"
		if mode=="preview-other-down": success = success and manager.manifest.channel=="beta"
		if mode=="dialog-confirm": success = success and manager.consent_dialog==null and host.player.enabled
		if success and mode=="helper-launch":
			manager.execute_install = true
			await manager.install()
			success = manager.state=="failed" and manager.helper_pid>0 and host.store.load_state(host.content).has("state")
		elif success and mode=="save-failure":
			var invalid = original_directory.path_join("not-a-directory"); write(invalid,"file")
			host.store.directory = invalid
			manager.execute_install = true
			await manager.install()
			success = manager.state=="failed" and manager.helper_pid==-1
		elif success and mode in ["health-validation","bad-save-health"]:
			host.save_now()
			manager.info.version = manager.manifest.version; manager.info.commit = manager.manifest.commit
			write(install.path_join("build_info.json"),JSON.stringify(manager.info))
			write(manager.stage.path_join("transaction.json"),JSON.stringify({"schema":1,"token":manager.token,"target":manager.manifest,"data_directory":ProjectSettings.globalize_path(host.store.directory)}))
			if mode=="bad-save-health": write(original_directory.path_join("save.json"),"incompatible save")
			manager.acknowledge_health(manager.token)
			success = FileAccess.file_exists(manager.stage.path_join("health.json"))==(mode=="health-validation")
	elif mode not in ["no-consent","declined","dialog-dismiss","dialog-close","retry-after-failure"]: success = manager.state==("disabled" if mode=="disabled" else "failed") and not manager.consent_granted
	print("NATIVE_UPDATE_NETWORK ",JSON.stringify({"passed":success,"mode":mode,"state":manager.state,"message":failure,"installer_verified":manager.installer_verified() if manager.state=="ready" else false,"save_directory":ProjectSettings.globalize_path(original_directory)}))
	quit(0 if success else 1)

func write(path: String, value: String):
	var file = FileAccess.open(path,FileAccess.WRITE); file.store_string(value); file.close()
