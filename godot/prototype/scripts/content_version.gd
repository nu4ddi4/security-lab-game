class_name ContentVersion
extends RefCounted

# project.godot is fixed inside the executable; a mounted data pack carries the running version.
static func running() -> String:
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://prototype/build_info.json"))
	if info is Dictionary and info.get("version") is String: return info.version
	return str(ProjectSettings.get_setting("application/config/version","개발"))
