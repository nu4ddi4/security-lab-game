extends Node

var failures: Array = []
var assertions = 0
var directory = "user://qa/diagnostics-review"

func check(value: bool, message: String):
	assertions += 1
	if not value: failures.append(message); push_error(message)

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found != null: return found
	return null

func run(game: Node):
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-output="): directory = argument.trim_prefix("--qa-output=")
	DirAccess.make_dir_recursive_absolute(directory)
	await get_tree().process_frame
	check(game.qa_mode and game.saves.directory == "user://qa","Review uses isolated QA save directory")
	check(game.diagnostics.data_directory == "user://qa/diagnostics","Review uses isolated QA diagnostic marker and packages")
	game.ui.pause()
	game.settings.show_menu()
	await get_tree().process_frame
	var copy = find_button(game.settings.panel,"진단 정보 복사")
	var create = find_button(game.settings.panel,"지원 패키지 만들기")
	check(copy != null and create != null,"Settings exposes both native diagnostics actions")
	var before = JSON.stringify(game.missions.state)
	var save_error = game.saves.error_message
	var report = game.diagnostics.snapshot()
	check(JSON.stringify(game.missions.state) == before and game.saves.error_message == save_error,"Collection preserves mission and save state")
	check(report.runtime.interaction_anchors == 101 and report.runtime.colliders == 89 and report.runtime.doors == 3,"Protected gameplay structure intact")
	check(report.runtime.mission == "tutorial" and report.display.graphics_preset == "medium","Runtime and settings reflect real game")
	check(report.build.version == ProjectSettings.get_setting("application/config/version"),"Packaged build identity matches game")
	if not OS.has_feature("editor"):
		check(report.build.commit != "unknown" and report.build.commit.length() == 40,"Windows export contains stamped commit")
	create.pressed.emit()
	check(FileAccess.file_exists(game.diagnostics.last_package),"Settings button creates ZIP")
	var package = game.diagnostics.create_package(directory)
	check(package.ok,"Selected output folder creates ZIP")
	var reader = ZIPReader.new()
	check(reader.open(package.get("file","")) == OK,"Exported game ZIP readable")
	check(reader.get_files().size() == 8 and "logs/" in reader.get_files(),"Export includes serializer and complete support structure")
	var actual = JSON.parse_string(reader.read_file("diagnostics.json").get_string_from_utf8())
	check(actual != null and actual.build.commit == report.build.commit,"Exported JSON parses with same build identity")
	reader.close()
	if DisplayServer.get_name() != "headless":
		var scroll = game.settings.panel.find_children("*","ScrollContainer",true,false)[0]
		scroll.scroll_vertical = 10000
		await get_tree().create_timer(.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("settings-diagnostics.png"))
		game.settings.panel.get_texture().get_image().save_png(directory.path_join("diagnostics-controls.png"))
		copy.pressed.emit()
		var copied = JSON.parse_string(DisplayServer.clipboard_get())
		check(copied is Dictionary and copied.schema == 1,"UI copies diagnostics JSON to actual Windows clipboard")
	check(not game.diagnostics.create_package(directory.path_join("missing")).ok,"Unavailable output is isolated")
	check(game.saves.save(game.missions),"Save still works after diagnostics success and failure")
	check(JSON.stringify(game.missions.state) == before,"Diagnostics never changes active mission")
	var result = {"passed":failures.is_empty(),"assertions":assertions,"failures":failures,"package":package.get("file"),"build":report.build}
	var file = FileAccess.open(directory.path_join("review.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result,"\t")); file.close()
	print("DIAGNOSTICS_REVIEW ",JSON.stringify(result))
	get_tree().quit(0 if failures.is_empty() else 1)
