extends Node
const Policy = preload("res://scripts/update_policy.gd")
class TestDiagnostics extends InvestigationDiagnostics:
	func supported() -> bool: return true
class Player extends Node:
	var enabled = false
	func is_on_floor() -> bool: return false
class Host extends Node:
	var store = InvestigationStore.new()
	var content: Dictionary
	var state: Dictionary
	var blocked_save = false
	var qa_mode = true
	var settings = null
	var updater = null
	var player = Player.new()
	var targets = {}
	func save_now() -> bool: return not blocked_save and store.save(state,content)
class TestUpdater extends InvestigationInstallerUpdates:
	var executable = ""
	func executable_path() -> String: return executable
var failures = []
var assertions = 0
func check(condition: bool, message: String):
	assertions += 1
	if not condition: failures.append(message)
func write(path: String, value: String):
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value); file.close()
func _ready(): run.call_deferred()
func run():
	var host = Host.new(); get_tree().root.add_child(host); host.add_child(host.player)
	host.content = InvestigationContent.load_case()
	host.state = InvestigationEngine.new(host.content).create_state()
	host.state.memo = "private-evidence-memo-do-not-export"
	var nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	host.store.directory = "user://qa/beta-services/"+nonce
	check(host.save_now(),"Investigation saves before service checks")
	var before = FileAccess.get_file_as_string(host.store.directory.path_join("save.json"))
	var diagnostics = TestDiagnostics.new(); host.add_child(diagnostics); diagnostics.setup(host); diagnostics.mark_ready()
	check(diagnostics.save_validation()["save.json"].status=="valid","Investigation codec validates its own save")
	check(diagnostics.save_validation()["save.backup.json"].status=="missing","Missing investigation backup is explicit")
	var package = diagnostics.create_package()
	check(package.ok,"Beta support ZIP is created")
	var zip = ZIPReader.new()
	check(zip.open(diagnostics.last_package)==OK,"Support ZIP opens")
	var report = zip.read_file("diagnostics.json").get_string_from_utf8()
	var identity = JSON.parse_string(zip.read_file("build_info.json").get_string_from_utf8())
	check(identity.app_id=="security-lab-beta" and identity.channel in ["beta","stable"],"Support ZIP records beta product and channel")
	check(not report.contains(host.state.memo) and not report.contains("transaction.json"),"Support ZIP omits memo and updater transaction")
	check(FileAccess.get_file_as_string(host.store.directory.path_join("save.json"))==before,"Diagnostics never mutate investigation save")
	var log = diagnostics.serializer.log_summary('PROTOTYPE_READY {"devices":6,"npcs":4,"isolatedSave":"private-directory"}\nSCRIPT ERROR: Invalid access private-memo\n          at: refresh (res://prototype/scripts/ui.gd:42)')
	check(log.events[0].event=="investigation_ready" and log.errors[0].source=="res://prototype/scripts/ui.gd","Beta log summary keeps only allowlisted event and source")
	check(not JSON.stringify(log).contains("private-"),"Beta log summary never contains free text or save paths")
	zip.close()
	var cull_mesh = ArrayMesh.new()
	var cull_arrays = []
	cull_arrays.resize(Mesh.ARRAY_MAX)
	cull_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(0,1,0),Vector3(5,0,0),Vector3(6,0,0),Vector3(5,1,0)])
	cull_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,3,4,5])
	cull_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,cull_arrays)
	var culled = InvestigationEnvironment.without_region(cull_mesh,Transform3D(),AABB(Vector3(4,-1,-1),Vector3(3,3,2)))
	check(culled.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 3,"Culling removes only the triangles inside the box")
	check(InvestigationEnvironment.without_region(cull_mesh,Transform3D(),AABB(Vector3(-1,-1,-1),Vector3(20,3,2))).get_surface_count() == 0,"Culling can empty a surface")
	var reset_root = "user://qa/reset-test"
	write(reset_root.path_join("investigation/save.json"),"progress")
	write(reset_root.path_join("investigation/nested/save.backup.json"),"backup")
	write(reset_root.path_join("settings.json"),"settings")
	check(InvestigationDataReset.wipe([reset_root.path_join("investigation"),reset_root.path_join("settings.json"),reset_root.path_join("missing.json")])==3,"Reset removes folders and files and ignores missing ones")
	check(not DirAccess.dir_exists_absolute(reset_root.path_join("investigation")) and not FileAccess.file_exists(reset_root.path_join("settings.json")),"Reset leaves no player data behind")
	DirAccess.remove_absolute(reset_root)
	var updater = TestUpdater.new(); host.add_child(updater); updater.game = host
	updater.info = {"schema":1,"app_id":"security-lab-beta","platform":"windows-x86_64","version":"0.3.0-beta.1","channel":"beta","commit":"a".repeat(40),"install_layout":1,"updates_default":true,"manifest_url":Policy.manifest_url("beta","security-lab-beta")}
	updater.info = JSON.parse_string(JSON.stringify(updater.info))
	check(Policy.build_valid(updater.info),"Beta baked build identity is valid")
	check(Policy.preference_path("beta","security-lab-beta")!=Policy.preference_path("beta"),"Beta and Native preferences are isolated")
	var manifest = updater.info.duplicate(); manifest.version="0.4.0-beta.1"; manifest.commit="b".repeat(40); manifest.sha256="c".repeat(64); manifest.exe_sha256="d".repeat(64); manifest.size=2048; manifest.installer_url=Policy.REPOSITORY+"SecurityLab-beta-0.4.0/SecurityLabSetup.exe"
	check(Policy.manifest_valid(manifest,"beta",updater.info.manifest_url,false,"security-lab-beta"),"Beta accepts only its release installer")
	var sequential = manifest.duplicate(); sequential.version="0.8.0-beta.2"; sequential.installer_url=Policy.REPOSITORY+"SecurityLab-0.8.0-beta.2/SecurityLabSetup.exe"
	check(Policy.manifest_valid(sequential,"beta",updater.info.manifest_url,false,"security-lab-beta"),"Beta sequence uses its own immutable installer tag")
	var stable = sequential.duplicate(); stable.channel="stable"; stable.version="0.8.0"; stable.installer_url=Policy.REPOSITORY+"SecurityLab-0.8.0/SecurityLabSetup.exe"
	check(Policy.manifest_valid(stable,"stable",Policy.manifest_url("stable","security-lab-beta"),false,"security-lab-beta"),"Stable investigation uses a separate update channel")
	check(not Policy.manifest_valid(stable,"beta",updater.info.manifest_url,false,"security-lab-beta"),"Beta never switches into the stable channel")
	check(not Policy.manifest_valid(manifest,"beta",Policy.manifest_url("beta"),false),"Native rejects the beta product")
	var cross = manifest.duplicate(); cross.app_id="security-lab-native"
	check(not Policy.manifest_valid(cross,"beta",updater.info.manifest_url,false,"security-lab-beta"),"Beta rejects a Native manifest")
	host.blocked_save=true
	check(not updater.save_progress(),"Blocked investigation save cannot authorize installation")
	host.blocked_save=false
	check(updater.valid_saved_progress(),"Installation health uses investigation codec")
	updater.enabled=true; updater.state="ready"
	await updater.install()
	check(updater.state=="ready" and updater.helper_pid==-1,"Unapproved beta cannot install or start worker")
	var install = host.store.directory.path_join("install")
	write(install.path_join("SecurityLab.exe"),"fixture; never executed")
	write(install.path_join("build_info.json"),JSON.stringify(updater.info))
	write(install.path_join("securitylab.install.json"),JSON.stringify({"app_id":"security-lab-beta","channel":"beta","install_layout":1}))
	updater.executable=ProjectSettings.globalize_path(install.path_join("SecurityLab.exe"))
	check(updater.installed_identity_valid(),"Installed beta metadata matches its baked identity")
	var stage=updater.stage_root().path_join(nonce)
	write(stage.path_join("transaction.json"),JSON.stringify({"schema":1,"token":nonce,"target":updater.info,"data_directory":ProjectSettings.globalize_path("user://")}))
	updater.acknowledge_health(nonce)
	check(FileAccess.file_exists(stage.path_join("health.json")),"Healthy beta acknowledges its own save and installation")
	DirAccess.remove_absolute(stage.path_join("health.json"))
	write(host.store.directory.path_join("save.json"),"invalid investigation save")
	updater.acknowledge_health(nonce)
	check(not FileAccess.file_exists(stage.path_join("health.json")),"Invalid investigation save prevents health acknowledgement")
	check(diagnostics.save_validation()["save.json"].status=="invalid","Diagnostics report invalid investigation save")
	diagnostics.write_session(true)
	check(diagnostics.read_json(diagnostics.data_directory.path_join("session.json")).data.clean_exit,"Clean exit marker is written locally")
	print("INVESTIGATION_SERVICES ",JSON.stringify({"passed":failures.is_empty(),"assertions":assertions,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
