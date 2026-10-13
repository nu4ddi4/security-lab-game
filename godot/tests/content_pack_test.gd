extends SceneTree

var failures: Array = []
var assertions = 0

func expect(condition: bool, message: String):
	assertions += 1
	if not condition: failures.append(message)

func write(path: String, value: String):
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value)
	file.close()

func build_pack(directory: String, name: String, content: String) -> String:
	var marker = directory.path_join(name+".marker.json")
	write(marker,content)
	var path = directory.path_join(name+".pck")
	var packer = PCKPacker.new()
	expect(packer.pck_start(ProjectSettings.globalize_path(path))==OK,"pack writer starts")
	expect(packer.add_file("res://prototype/tests/content_marker.json",ProjectSettings.globalize_path(marker))==OK,"pack writer adds a file")
	expect(packer.flush()==OK,"pack writer finishes")
	return path

func meta_for(pack: String, version: String, commit: String, compat: String) -> Dictionary:
	return {"version":version,"commit":commit,"sha256":FileAccess.get_sha256(pack),"size":FileAccess.open(pack,FileAccess.READ).get_length(),"compat":compat,"channel":"beta"}

func _init():
	var compat = "a".repeat(64)
	var bundled = {"version":"0.9.0-beta.1","compat":compat,"commit":"1".repeat(40)}
	var root_directory = "user://qa/content-test/"+Crypto.new().generate_random_bytes(8).hex_encode()

	# Which packs may run on which executable.
	var pack_a = build_pack(root_directory,"a","from the first pack")
	var good = meta_for(pack_a,"0.9.0-beta.2","b".repeat(40),compat)
	expect(ContentBootstrap.usable(good,bundled),"a newer pack for the same compat key is usable")
	for case in [["compat",{"compat":"c".repeat(64)}],["older",{"version":"0.9.0-beta.1"}],["commit",{"commit":"zz"}],["hash",{"sha256":"short"}],["version type",{"version":2}]]:
		expect(not ContentBootstrap.usable(good.merged(case[1],true),bundled),"unusable pack: "+case[0])
	expect(not ContentBootstrap.usable(good,{"version":"0.9.0-beta.1"}),"an executable without a compat key never takes a pack")
	expect(ContentBootstrap.directory(PackedStringArray(["--content-dir=C:/elsewhere"]))==ContentBootstrap.DEFAULT_DIRECTORY,"players cannot redirect the content directory")
	expect(ContentBootstrap.directory(PackedStringArray(["--prototype-smoke","--content-dir=C:/elsewhere"]))=="C:/elsewhere","test runs can redirect the content directory")
	expect(ContentBootstrap.wanted(PackedStringArray(),"Windows") and not ContentBootstrap.wanted(PackedStringArray(["--disable-content-updates"]),"Windows") and not ContentBootstrap.wanted(PackedStringArray(),"Android"),"content packs apply on Windows unless disabled")

	# Activation keeps the previous pack and marks the new one as unconfirmed.
	var dir = root_directory.path_join("flow")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(pack_a),ProjectSettings.globalize_path(dir.path_join("pending.pck")))
	write(dir.path_join("pending.json"),JSON.stringify(good))
	expect(ContentBootstrap.activate_pending(dir,bundled),"an approved pack is activated")
	expect(FileAccess.file_exists(dir.path_join("active.pck")) and not FileAccess.file_exists(dir.path_join("pending.pck")) and not FileAccess.file_exists(dir.path_join("pending.json")),"activation moves the pending files")
	expect(ContentBootstrap.read_json(dir.path_join("active.json")).get("pending_boot")==true,"a fresh pack waits for its stability check")

	# A pack that never confirmed is dropped on the next start and remembered as bad.
	ContentBootstrap.recover_interrupted(dir)
	expect(not FileAccess.file_exists(dir.path_join("active.pck")) and ContentBootstrap.rejected(dir)==["b".repeat(40)],"an unconfirmed pack is rolled back and rejected")

	# A damaged download is never activated.
	var pack_b = build_pack(root_directory,"b","from the second pack")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(pack_b),ProjectSettings.globalize_path(dir.path_join("pending.pck")))
	var damaged = meta_for(pack_b,"0.9.0-beta.3","d".repeat(40),compat)
	damaged.sha256 = "0".repeat(64)
	write(dir.path_join("pending.json"),JSON.stringify(damaged))
	expect(not ContentBootstrap.activate_pending(dir,bundled) and not FileAccess.file_exists(dir.path_join("pending.pck")) and "d".repeat(40) in ContentBootstrap.rejected(dir),"a pack with the wrong hash is discarded")

	# Confirmed packs keep running; the next pack leaves the confirmed one as rollback target.
	DirAccess.copy_absolute(ProjectSettings.globalize_path(pack_a),ProjectSettings.globalize_path(dir.path_join("pending.pck")))
	var second = meta_for(pack_a,"0.9.0-beta.4","e".repeat(40),compat)
	write(dir.path_join("pending.json"),JSON.stringify(second))
	expect(ContentBootstrap.activate_pending(dir,bundled),"the next pack is activated")
	ContentBootstrap.confirm(dir)
	expect(ContentBootstrap.read_json(dir.path_join("active.json")).get("pending_boot")==false,"a stable pack is confirmed")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(pack_b),ProjectSettings.globalize_path(dir.path_join("pending.pck")))
	var third = meta_for(pack_b,"0.9.0-beta.5","f".repeat(40),compat)
	write(dir.path_join("pending.json"),JSON.stringify(third))
	expect(ContentBootstrap.activate_pending(dir,bundled) and FileAccess.file_exists(dir.path_join("previous.pck")),"the confirmed pack stays as rollback")
	ContentBootstrap.recover_interrupted(dir)
	expect(ContentBootstrap.read_json(dir.path_join("active.json")).get("commit")=="e".repeat(40),"rollback restores the confirmed pack")

	# A newly installed executable that already carries the data drops the older pack.
	expect(ContentBootstrap.load_active(dir,{"version":"0.9.0-beta.9","compat":compat,"commit":"2".repeat(40)}).is_empty() and not FileAccess.file_exists(dir.path_join("active.pck")),"a pack older than the executable is dropped")

	# Mounting replaces files for the rest of the process, so it runs last.
	var mounted = root_directory.path_join("mounted")
	DirAccess.make_dir_recursive_absolute(mounted)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(pack_a),ProjectSettings.globalize_path(mounted.path_join("pending.pck")))
	write(mounted.path_join("pending.json"),JSON.stringify(good))
	ContentBootstrap.activate_pending(mounted,bundled)
	var loaded = ContentBootstrap.load_active(mounted,bundled)
	expect(loaded.get("version")=="0.9.0-beta.2","the active pack is mounted")
	expect(FileAccess.get_file_as_string("res://prototype/tests/content_marker.json")=="from the first pack","mounted files replace the built-in ones")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_directory))
	print("CONTENT_PACK_TEST ",JSON.stringify({"passed":failures.is_empty(),"assertions":assertions,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
