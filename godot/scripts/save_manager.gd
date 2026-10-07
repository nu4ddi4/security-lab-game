class_name LabSave
extends RefCounted

var directory = "user://"
var error_message = ""

func encode(manager: LabMissions) -> Dictionary:
	var rows = []
	for i in range(manager.definitions.missions.size()):
		var p = manager.state.missions[i]
		var row = {"id": manager.definitions.missions[i].id, "clues": p.clues.duplicate(), "answer": p.answer, "hint": p.hint, "verified": p.verified, "selectedFile": p.selectedFile, "observations": p.observations.duplicate(true)}
		if p.has("spatial"): row.spatial = p.spatial.duplicate(true)
		rows.append(row)
	return {"version": 2, "active": manager.mission().id, "missions": rows, "ports": manager.state.ports.duplicate(), "login": manager.state.login.duplicate(), "restored": manager.state.files["budget.csv"] == manager.definitions.original_files["budget.csv"], "hashComputed": manager.state.missions[3].hashes.size() == 3}

func save(manager: LabMissions) -> bool:
	var path = directory.path_join("progress.json")
	var temp = directory.path_join("progress.tmp")
	var file = FileAccess.open(temp,FileAccess.WRITE)
	if file == null:
		error_message = "진행을 저장하지 못했습니다: " + error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify({"format":"security-lab-native","version":1,"game":encode(manager)},"\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		# Preserve only a valid previous save; corrupt files never replace backups.
		var probe = LabMissions.new()
		if decode(FileAccess.get_file_as_string(path),probe): DirAccess.copy_absolute(path,directory.path_join("progress.backup.json"))
		probe.free()
	var result = DirAccess.rename_absolute(temp,path)
	if result != OK:
		error_message = "진행 파일 교체 실패: " + error_string(result)
		return false
	error_message = ""
	return true

func load_into(manager: LabMissions) -> String:
	var path = directory.path_join("progress.json")
	if not FileAccess.file_exists(path): return "새 조사"
	if decode(FileAccess.get_file_as_string(path),manager): return "저장된 조사 이어하기"
	DirAccess.copy_absolute(path,directory.path_join("progress.corrupt.%d.json" % Time.get_unix_time_from_system()))
	var backup = directory.path_join("progress.backup.json")
	if FileAccess.file_exists(backup) and decode(FileAccess.get_file_as_string(backup),manager): return "주 저장이 손상되어 유효한 백업을 복구했습니다."
	return "저장 파일을 읽지 못했습니다. 원본을 보존하고 새 조사로 시작합니다."

func decode(raw: String, manager: LabMissions) -> bool:
	if raw.to_utf8_buffer().size() > 131072: return fail("진행 JSON은 128KiB 이하여야 합니다.")
	var parser = JSON.new()
	if parser.parse(raw) != OK: return fail("JSON 형식이 아닙니다.")
	var parsed = parser.data
	if not parsed is Dictionary: return fail("JSON 형식이 아닙니다.")
	if parsed.has("game"):
		if parsed.get("format") in ["security-lab-native","security-lab-progress"]:
			if parsed.get("version") != 1: return fail("지원하지 않는 내보내기 버전입니다.")
		elif parsed.get("version") != 2 or not whole_number(parsed.get("revision")) or parsed.revision <= 0: return fail("지원하지 않는 진행 컨테이너입니다.")
	var data = parsed.get("game",parsed)
	if not data is Dictionary or not data.get("version") is float and not data.get("version") is int: return fail("지원하지 않는 저장 형식입니다.")
	if data.version != int(data.version) or int(data.version) not in [1,2] or not data.get("missions") is Array: return fail("지원하지 않는 저장 형식입니다.")
	var ids = ["tutorial","services","login","integrity"]
	if data.version == 1 and not whole_number(data.get("active")): return fail("기존 미션 번호가 올바르지 않습니다.")
	var active = ids.find(data.get("active")) if data.version == 2 else int(data.get("active",-1))
	if active < 0 or active >= 4: return fail("현재 미션이 올바르지 않습니다.")
	if not data.get("ports") is Dictionary or not data.get("login") is Dictionary: return fail("정책이 없습니다.")
	for port in ["443","8080"]:
		if not data.ports.get(port) is bool: return fail("포트 정책 오류")
	if not data.login.get("minLength") is float and not data.login.get("minLength") is int: return fail("정책 길이 오류")
	if data.login.minLength != int(data.login.minLength) or int(data.login.minLength) not in [6,12,15] or not data.login.get("blockCommon") is bool or not data.login.get("limitAttempts") is bool or not data.get("restored") is bool or not data.get("hashComputed") is bool: return fail("정책 형식 오류")
	var candidate = LabMissions.new()
	candidate.state.active = active
	candidate.state.ports = data.ports.duplicate()
	candidate.state.login = data.login.duplicate()
	candidate.state.login.minLength = int(data.login.minLength)
	if data.restored: candidate.state.files["budget.csv"] = candidate.definitions.original_files["budget.csv"]
	var seen = []
	for i in range(data.missions.size()):
		var row = data.missions[i]
		if not row is Dictionary: candidate.free(); return fail("미션 형식 오류")
		var index = ids.find(row.get("id")) if data.version == 2 else i
		if index < 0 or index >= 4 or index in seen: candidate.free(); return fail("중복 또는 알 수 없는 미션")
		seen.append(index)
		var m = candidate.definitions.missions[index]
		if not row.get("clues") is Array or row.clues.size() > m.clues.size() or not row.get("verified") is bool or not whole_number(row.get("hint")) or row.get("hint",-1) < 0 or row.get("hint",-1) > m.hints.size(): candidate.free(); return fail("미션 기록 오류")
		var clues = []
		for key in row.clues:
			if key not in m.clues or key in clues: candidate.free(); return fail("단서 오류")
			clues.append(key)
		if row.get("answer") != null and (not row.answer is float and not row.answer is int or int(row.answer) not in [0,1,2] or row.answer != int(row.answer)): candidate.free(); return fail("설명 오류")
		if row.get("selectedFile") != null and (index != 3 or row.selectedFile not in candidate.definitions.original_files): candidate.free(); return fail("선택 파일 오류")
		if index < active and not row.verified or index > active and (row.verified or clues.size() > 0 or row.get("answer") != null or row.get("hint",0) > 0 or row.get("selectedFile") != null): candidate.free(); return fail("미션 순서 오류")
		var p = candidate.state.missions[index]
		for key in ["clues","answer","hint","verified","selectedFile"]: p[key] = row.get(key,p[key])
		p.hint = int(p.hint)
		if p.answer != null: p.answer = int(p.answer)
		var changed = (not candidate.state.ports["443"] or not candidate.state.ports["8080"]) if index == 1 else (candidate.state.login.minLength != 6 or candidate.state.login.blockCommon or candidate.state.login.limitAttempts) if index == 2 else data.restored if index == 3 else false
		var observations = row.get("observations",{})
		if not observations is Dictionary: observations = {}
		p.observations = {"changed":changed or observations.get("changed") == true,"before":snapshot(observations.get("before"),index),"after":null}
		if p.observations.changed: p.observations.after = snapshot(observations.get("after"),index)
		if row.has("spatial"):
			var s = row.spatial
			if not s is Dictionary or not s.get("inspected") is Array or not s.get("rechecked") is bool or index > active: candidate.free(); return fail("현장 기록 오류")
			var inspected = []
			for id in s.inspected:
				if id not in m.required_devices or id in inspected: candidate.free(); return fail("현장 장비 오류")
				inspected.append(id)
			if s.rechecked and (not p.observations.changed or m.revisit_device not in inspected): candidate.free(); return fail("재확인 기록 오류")
			p.spatial = s.duplicate(true)
	for i in range(active+1):
		if i not in seen: candidate.free(); return fail("진행이 누락되었습니다.")
	if data.hashComputed:
		if active != 3 or "hash" not in candidate.state.missions[3].clues: candidate.free(); return fail("해시 기록 오류")
		candidate.state.active = 3
		candidate.run_command("hash files",false)
	# Recompute derived validation; a saved completion flag cannot grant progress.
	for i in range(active+1):
		candidate.state.active = i
		if candidate.progress().verified:
			candidate.verify()
			if not candidate.progress().verified: candidate.free(); return fail("완료 조건 불일치")
	candidate.state.active = active
	manager.state = candidate.state.duplicate(true)
	candidate.free()
	error_message = ""
	return true

func fail(message: String) -> bool:
	error_message = message
	return false

func whole_number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value == int(value)

func snapshot(value, index: int):
	if not value is Dictionary: return null
	if index == 1 and value.get("443") is bool and value.get("8080") is bool: return {"443":value["443"],"8080":value["8080"]}
	if index == 2 and whole_number(value.get("minLength")) and int(value.minLength) in [6,12,15] and value.get("blockCommon") is bool and value.get("limitAttempts") is bool: return {"minLength":int(value.minLength),"blockCommon":value.blockCommon,"limitAttempts":value.limitAttempts}
	if index == 3 and value.get("matches") is Dictionary:
		for filename in ["notice.txt","budget.csv","members.txt"]:
			if not value.matches.get(filename) is bool: return null
		return {"matches":value.matches.duplicate()}
	return null
