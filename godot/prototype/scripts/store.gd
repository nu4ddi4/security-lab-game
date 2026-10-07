class_name InvestigationStore
extends RefCounted

var directory = "user://investigation"
var error = ""

func load_state(content: Dictionary) -> Dictionary:
	var path = directory.path_join("save.json")
	if not FileAccess.file_exists(path): return {"new":true}
	return InvestigationSaveCodec.decode(FileAccess.get_file_as_string(path),content)

func save(state: Dictionary, content: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(directory)
	var path = directory.path_join("save.json")
	var temp = directory.path_join("save.tmp")
	var file = FileAccess.open(temp,FileAccess.WRITE)
	if file == null: error = "진행 파일을 열지 못했습니다."; return false
	file.store_string(InvestigationSaveCodec.encode(state,content))
	file.flush()
	var written = file.get_error()
	file.close()
	if written != OK: error = "진행을 저장하지 못했습니다."; return false
	if FileAccess.file_exists(path):
		var old = InvestigationSaveCodec.decode(FileAccess.get_file_as_string(path),content)
		if old.has("state"): DirAccess.copy_absolute(path,directory.path_join("save.backup.json"))
	var result = DirAccess.rename_absolute(temp,path)
	error = "" if result == OK else "진행 파일 교체 실패: " + error_string(result)
	return result == OK

func preserve() -> bool:
	var path = directory.path_join("save.json")
	if not FileAccess.file_exists(path): return true
	var result = DirAccess.copy_absolute(path,directory.path_join("save.preserved.%d.json" % Time.get_ticks_usec()))
	error = "" if result == OK else "현재 진행을 보존하지 못했습니다: " + error_string(result)
	return result == OK

func export_file(path: String, state: Dictionary, content: Dictionary) -> bool:
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null: error = "내보내기 파일을 열지 못했습니다."; return false
	file.store_string(InvestigationSaveCodec.encode(state,content))
	file.flush()
	var written = file.get_error()
	file.close()
	error = "" if written == OK else "진행 파일을 내보내지 못했습니다: " + error_string(written)
	return written == OK

func import_file(path: String, content: Dictionary) -> Dictionary:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {"error":"진행 파일을 열지 못했습니다."}
	if file.get_length() > 262144: file.close(); return {"error":"진행 파일은 256KiB 이하여야 합니다."}
	var raw = file.get_as_text()
	file.close()
	return InvestigationSaveCodec.decode(raw,content)
