class_name ContentBootstrap
extends Node

# Launcher scene of exported builds. It applies a game-data pack the player already
# approved (downloaded by the updater) before the game scene loads, keeps the previous
# pack for rollback and drops a pack that did not survive its first start.
# It never touches the network: downloading stays behind the updater's consent dialog.
const MAIN_SCENE = "res://prototype/main.tscn"
const BUILD_INFO = "res://prototype/build_info.json"
const DEFAULT_DIRECTORY = "user://content"
const STABILITY_SECONDS = 5.0
const REJECTED_LIMIT = 8

# The directory can only be redirected by test runs.
static func directory(args: PackedStringArray) -> String:
	for argument in args:
		if argument.begins_with("--content-dir=") and ("--prototype-smoke" in args or "--allow-local-update-url" in args):
			return argument.trim_prefix("--content-dir=")
	return DEFAULT_DIRECTORY

static func wanted(args: PackedStringArray, os_name: String) -> bool:
	return os_name == "Windows" and "--disable-content-updates" not in args and "--server" not in args

# project.godot is fixed inside the executable; the mounted data pack carries the running version.
static func build_version() -> String:
	var info = read_json(BUILD_INFO)
	return String(info.get("version",ProjectSettings.get_setting("application/config/version","개발")))

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func write_json(path: String, value: Dictionary) -> bool:
	var temporary = path+".tmp"
	var file = FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path)) == OK

static func remove(path: String):
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func move(from: String, to: String) -> bool:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from),ProjectSettings.globalize_path(to)) == OK

# A pack applies only to the executable it was built for (same compat key) and only when it is newer.
static func usable(meta: Dictionary, bundled: Dictionary) -> bool:
	if not (NativeUpdatePolicy.hex(meta.get("sha256"),64) and NativeUpdatePolicy.hex(meta.get("commit"),40) and NativeUpdatePolicy.hex(meta.get("compat"),64)): return false
	if not meta.get("version") is String or not NativeUpdatePolicy.hex(bundled.get("compat"),64): return false
	return meta.compat == bundled.compat and NativeUpdatePolicy.newer(meta.version,String(bundled.get("version","")))

static func rejected(dir: String) -> Array:
	var commits = read_json(dir.path_join("rejected.json")).get("commits",[])
	return commits if commits is Array else []

static func reject(dir: String, commit: String):
	if commit.is_empty(): return
	var commits = rejected(dir)
	if commit not in commits: commits.append(commit)
	write_json(dir.path_join("rejected.json"),{"commits":commits.slice(maxi(0,commits.size()-REJECTED_LIMIT))})

static func pack_matches(path: String, meta: Dictionary) -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == String(meta.get("sha256","")) and (not meta.has("size") or FileAccess.open(path,FileAccess.READ).get_length() == int(meta.size))

# The pack just downloaded becomes the active one; the old active pack stays as the rollback.
static func activate_pending(dir: String, bundled: Dictionary) -> bool:
	var meta = read_json(dir.path_join("pending.json"))
	var pack = dir.path_join("pending.pck")
	if meta.is_empty() and not FileAccess.file_exists(pack): return false
	if not usable(meta,bundled) or not pack_matches(pack,meta):
		reject(dir,String(meta.get("commit","")))
		remove(pack)
		remove(dir.path_join("pending.json"))
		return false
	remove(dir.path_join("previous.pck"))
	remove(dir.path_join("previous.json"))
	if FileAccess.file_exists(dir.path_join("active.pck")):
		move(dir.path_join("active.pck"),dir.path_join("previous.pck"))
		move(dir.path_join("active.json"),dir.path_join("previous.json"))
	if not move(pack,dir.path_join("active.pck")):
		rollback(dir,false)
		return false
	meta.pending_boot = true
	write_json(dir.path_join("active.json"),meta)
	remove(dir.path_join("pending.json"))
	return true

# Removes the active pack (remembering it as bad) and restores the previous one, if any.
static func rollback(dir: String, remember = true):
	if remember: reject(dir,String(read_json(dir.path_join("active.json")).get("commit","")))
	remove(dir.path_join("active.pck"))
	remove(dir.path_join("active.json"))
	if FileAccess.file_exists(dir.path_join("previous.pck")):
		move(dir.path_join("previous.pck"),dir.path_join("active.pck"))
		move(dir.path_join("previous.json"),dir.path_join("active.json"))

# A pack still marked pending_boot never reached its stability check last time.
static func recover_interrupted(dir: String):
	if read_json(dir.path_join("active.json")).get("pending_boot",false) == true: rollback(dir)

# Mounts the active pack; returns its metadata or {} when the executable's own data is used.
static func load_active(dir: String, bundled: Dictionary) -> Dictionary:
	for attempt in 2:
		var meta = read_json(dir.path_join("active.json"))
		if meta.is_empty(): return {}
		var pack = dir.path_join("active.pck")
		if not NativeUpdatePolicy.newer(String(meta.get("version","")),String(bundled.get("version",""))) or String(meta.get("compat","")) != String(bundled.get("compat","")):
			# A newly installed executable already carries this data (or other data).
			remove(pack); remove(dir.path_join("active.json")); remove(dir.path_join("previous.pck")); remove(dir.path_join("previous.json"))
			return {}
		if usable(meta,bundled) and pack_matches(pack,meta) and ProjectSettings.load_resource_pack(pack,true): return meta
		rollback(dir)
	return {}

static func confirm(dir: String):
	var meta = read_json(dir.path_join("active.json"))
	if meta.get("pending_boot",false) != true: return
	meta.pending_boot = false
	if write_json(dir.path_join("active.json"),meta):
		remove(dir.path_join("previous.pck"))
		remove(dir.path_join("previous.json"))

# Confirms the pack once the game has run for a few seconds, or exited normally.
class BootGuard extends Node:
	var directory = ""
	func _init(path: String):
		name = "ContentBootGuard"
		directory = path
	func _ready(): get_tree().create_timer(ContentBootstrap.STABILITY_SECONDS).timeout.connect(finish)
	func finish():
		ContentBootstrap.confirm(directory)
		queue_free()
	func _notification(what):
		if what == NOTIFICATION_WM_CLOSE_REQUEST: ContentBootstrap.confirm(directory)

func _ready():
	var bundled = read_json(BUILD_INFO)
	Engine.set_meta("bundled_build_info",bundled)
	var args = OS.get_cmdline_user_args()
	var dir = directory(args)
	var loaded = {}
	if wanted(args,OS.get_name()):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		recover_interrupted(dir)
		activate_pending(dir,bundled)
		loaded = load_active(dir,bundled)
	if not loaded.is_empty():
		Engine.set_meta("content_pack",loaded)
		print("CONTENT_PACK ",JSON.stringify({"loaded":true,"version":loaded.get("version"),"commit":loaded.get("commit")}))
	start.call_deferred(dir,loaded)

func start(dir: String, loaded: Dictionary):
	# Switching scenes removes this node, so the tree is kept for what follows.
	var tree = get_tree()
	if tree.change_scene_to_file(MAIN_SCENE) != OK:
		push_error("The game scene could not be loaded.")
		if not loaded.is_empty():
			# The mounted pack cannot be unmounted: restore the previous data and start again.
			rollback(dir)
			var arguments = []
			for argument in OS.get_cmdline_args():
				if argument == "--": break
				arguments.append(argument)
			var user_arguments = OS.get_cmdline_user_args()
			if not user_arguments.is_empty():
				arguments.append("--")
				arguments.append_array(user_arguments)
			OS.create_process(OS.get_executable_path(),PackedStringArray(arguments))
		tree.quit(1)
		return
	if loaded.get("pending_boot",false) == true: tree.root.add_child(BootGuard.new(dir))
