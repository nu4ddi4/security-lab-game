class_name LabMissions
extends Node

signal state_changed
signal observation(result: Dictionary)
var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/definitions.json"))
var state: Dictionary

func _init():
	reset_all(false)

func reset_all(notify = true):
	state = {"version": 2, "active": 0, "missions": [], "ports": {"443": true, "8080": true}, "login": {"minLength": 6, "blockCommon": false, "limitAttempts": false}, "files": definitions.original_files.duplicate(true)}
	state.files["budget.csv"] = definitions.tampered_budget
	for _m in definitions.missions:
		state.missions.append({"clues": [], "answer": null, "hint": 0, "verified": false, "checks": [], "hashes": [], "selectedFile": null, "observations": {"changed": false, "before": null, "after": null}})
	if notify: state_changed.emit()

func mission() -> Dictionary:
	return definitions.missions[state.active]

func progress() -> Dictionary:
	return state.missions[state.active]

func clue(key: String):
	if key not in progress().clues:
		progress().clues.append(key)
		if not progress().verified: progress().checks = []

func observed(snapshot: Dictionary):
	progress().observations["after" if progress().observations.changed else "before"] = snapshot.duplicate(true)

func invalidate(environment = false):
	progress().verified = false
	progress().checks = []
	if environment:
		progress().observations.changed = true
		progress().observations.after = null
		if progress().has("spatial"): progress().spatial.rechecked = false

func explained(index = -1) -> bool:
	if index < 0: index = state.active
	return state.missions[index].answer == definitions.missions[index].correct

func defended(index = -1) -> bool:
	if index < 0: index = state.active
	match definitions.missions[index].id:
		"tutorial": return explained(index)
		"services": return state.ports["443"] and not state.ports["8080"]
		"login": return state.login.minLength >= 15 and state.login.blockCommon and state.login.limitAttempts
		"integrity": return definitions.original_files.keys().all(func(key): return state.files[key] == definitions.original_files[key])
	return false

func score(index = -1) -> int:
	if index < 0: index = state.active
	var evidence = definitions.missions[index].evidence
	var found = 0
	for key in evidence:
		if key in state.missions[index].clues: found += 1
	var complete = found == evidence.size()
	return int(30.0 * found / evidence.size()) + (20 if complete and explained(index) else 0) + (30 if complete and explained(index) and defended(index) else 0) + (20 if state.missions[index].verified else 0)

func stage() -> String:
	var p = progress()
	if p.verified: return "검증 완료"
	if p.has("spatial") and p.observations.changed and not p.spatial.rechecked and mission().revisit_device != null: return "장비 재확인 필요"
	var complete = mission().evidence.all(func(key): return key in p.clues)
	if complete and explained() and defended(): return "방어 적용"
	if complete and explained(): return "취약 상태 확인"
	return "조사" if p.clues.size() else "준비"

func apply_answer(answer: int):
	if answer < 0 or answer >= mission().answers.size(): return
	progress().answer = answer
	invalidate()
	state_changed.emit()

func apply_port(port: String, allowed: bool):
	if mission().id != "services" or port not in ["443", "8080"]: return
	state.ports[port] = allowed
	invalidate(true)
	progress().clues.erase("rescan")
	state_changed.emit()

func apply_login(policy: Dictionary):
	if mission().id != "login" or int(policy.get("minLength",0)) not in [6,12,15] or not policy.get("blockCommon") is bool or not policy.get("limitAttempts") is bool: return
	state.login = {"minLength":int(policy.minLength),"blockCommon":policy.blockCommon,"limitAttempts":policy.limitAttempts}
	invalidate(true)
	state_changed.emit()

func accepted(value: String, policy: Dictionary) -> bool:
	return value.length() >= policy.minLength and (not policy.blockCommon or value.to_lower() not in definitions.common_passwords)

func login_result() -> Dictionary:
	return {"normal":accepted(definitions.normal_password,state.login),"commonBlocked":definitions.common_passwords.all(func(value): return not accepted(value,state.login)),"repeatedBlocked":state.login.limitAttempts}

func can_restore() -> bool:
	return mission().id == "integrity" and ["baseline","hash","mismatch"].all(func(key): return key in progress().clues)

func restore_file(filename: String) -> bool:
	if not can_restore() or filename not in definitions.original_files: return false
	progress().selectedFile = filename
	state.files[filename] = definitions.original_files[filename]
	invalidate(true)
	progress().hashes = []
	state_changed.emit()
	return true

func run_command(input: String, notify = true) -> String:
	var output = command_result(input)
	if notify: state_changed.emit()
	return output

func command_result(input: String) -> String:
	if input.length() > 200: return "입력은 200자 이하여야 합니다."
	var whitespace = RegEx.new()
	whitespace.compile("\\s+")
	input = whitespace.sub(input.strip_edges()," ",true)
	var words = input.strip_edges().split(" ", false)
	if words.is_empty(): return "help로 사용법을 확인하세요."
	if words[0] not in mission().commands: return "이 미션에서 허용된 게임 명령만 사용하세요."
	if input == "help":
		if mission().id == "tutorial": clue("help")
		return " / ".join(mission().quickCommands)
	if input == "verify": return verify()
	match mission().id:
		"tutorial":
			if input == "inspect approval":
				clue("approval")
				return "조사 승인서: club-server의 가상 서비스·더미 로그인·내장 파일만 조사합니다. 실제 IP·URL·외부 서버는 범위에 포함되지 않습니다."
		"services":
			if input == "scan club-server":
				observed(state.ports)
				clue("scan")
				if defended(): clue("rescan")
				return "443 %s · 필수 HTTPS 자료 서비스\n8080 %s · 사용하지 않는 관리 서비스" % ["OPEN" if state.ports["443"] else "FILTERED", "OPEN" if state.ports["8080"] else "FILTERED"]
			if input == "inspect club-server 443":
				clue("port-443")
				return "443: 자료 제공에 필요한 HTTPS 서비스. 자료 열람을 유지해야 합니다."
			if input == "inspect club-server 8080":
				clue("port-8080")
				return "8080: 사용하지 않는 이전 관리 서비스. 방화벽으로 접근을 차단해도 프로세스가 종료되는 것은 아닙니다."
		"login":
			if input == "inspect login":
				clue("login")
				observed(state.login)
				var rows = ["더미 후보 정책 검사:"]
				for value in definitions.common_passwords: rows.append(value + ": " + ("허용" if accepted(value,state.login) else "거부"))
				rows.append("연속 실패 기록:")
				for i in range(5): rows.append("%d회: %s" % [i+1,"제한됨" if state.login.limitAttempts and i >= 3 else "실패"])
				rows.append("정상 더미 사용자 첫 로그인: " + ("성공" if login_result().normal else "거부"))
				return "\n".join(rows)
		"integrity":
			if input == "inspect baseline":
				clue("baseline")
				return "기준 출처: 조사 승인 이전에 담당 교사가 보관한 승인된 오프라인 원본. 이 기준은 게임에서 변경할 수 없습니다. 분석 PC에서 내장 파일의 실제 SHA-256을 비교하세요."
			if input == "hash files":
				var rows = []
				var matches = {}
				progress().hashes = []
				for filename in definitions.original_files:
					var actual = state.files[filename].sha256_text()
					var expected = definitions.original_files[filename].sha256_text()
					var row = {"name":filename,"actual":actual,"expected":expected,"matches":actual == expected}
					progress().hashes.append(row)
					matches[filename] = row.matches
					rows.append(filename + " · " + ("일치" if row.matches else "변경 감지") + "\n현재 " + actual + "\n기준 " + expected)
				observed({"matches":matches})
				if not progress().verified: progress().checks = []
				clue("hash")
				if progress().hashes.any(func(row): return not row.matches): clue("mismatch")
				return "\n\n".join(rows)
	return "게임 전용 명령·대상만 허용됩니다. 실제 IP·URL·운영체제 명령은 실행하지 않습니다."

func checks_for_current() -> Array:
	var p = progress()
	match mission().id:
		"tutorial": return [["help 확인", "help" in p.clues], ["승인서 확인", "approval" in p.clues], ["조사 범위 선택", explained()]]
		"services":
			observed(state.ports)
			return [["서비스 단서 조사", "scan" in p.clues and "port-8080" in p.clues], ["8080 접근 차단", not state.ports["8080"]], ["443 자료 서비스 정상", state.ports["443"]], ["방어 후 다시 scan", "rescan" in p.clues]]
		"login":
			observed(state.login)
			var result = login_result()
			return [["더미 기록 조사","login" in p.clues],["최소 길이 15 이상",state.login.minLength >= 15],["흔한 값 차단 정책",state.login.blockCommon and result.commonBlocked],["정상 사용자 첫 로그인 성공",result.normal],["연속 실패 3회 후 제한",state.login.limitAttempts and result.repeatedBlocked]]
		"integrity": return [["신뢰 기준 확인","baseline" in p.clues],["변경 감지 기록","mismatch" in p.clues],["변경 파일 선택",p.selectedFile == "budget.csv"],["원본 파일 복구",defended()],["복구 후 해시 재계산",p.hashes.size() == definitions.original_files.size() and p.hashes.all(func(row): return row.matches)]]
	return []

func verify() -> String:
	if not explained(): return "조사 근거에 맞는 설명을 먼저 선택하세요."
	var checks = checks_for_current()
	var p = progress()
	if p.has("spatial"):
		checks.append(["3D 조사 장비 확인", mission().required_devices.all(func(id): return id in p.spatial.inspected)])
		if mission().revisit_device != null: checks.append(["방어 후 현장 재확인", p.observations.changed and p.spatial.rechecked])
	p.checks = []
	var lines = PackedStringArray()
	p.verified = true
	for check in checks:
		p.checks.append({"label": check[0], "passed": check[1]})
		p.verified = p.verified and check[1]
		lines.append(("통과 · " if check[1] else "미충족 · ") + check[0])
	lines.append(mission().explanation if p.verified else "미충족 항목을 확인하고 다시 검증하세요.")
	return "\n".join(lines)

func next_mission() -> bool:
	if not progress().verified or state.active >= definitions.missions.size() - 1: return false
	state.active += 1
	state_changed.emit()
	return true

func reset_mission():
	var old = state.duplicate(true)
	reset_all(false)
	state.active = old.active
	for i in range(old.active): state.missions[i] = old.missions[i]
	if old.active > 1: state.ports = old.ports
	if old.active > 2: state.login = old.login
	state_changed.emit()

func action() -> Dictionary:
	var m = mission()
	var p = progress()
	if p.verified: return {"device": "", "mode": "complete", "text": "검증 완료 · 조사 노트에서 다음 미션 또는 완료 결과를 확인하세요.", "reason":""}
	for id in m.required_devices:
		if id not in p.get("spatial", {}).get("inspected", []):
			var reason = {"tutorial":"조사 전에 승인된 범위를 확인합니다.","services":"서버에서 노출 상태와 서비스 용도를 확인합니다.","login":"관제석에서 정상 로그인과 반복 실패를 함께 확인합니다."}.get(m.id,"보관함의 승인 원본이 비교 기준입니다." if id == "INTERACT_FileCabinet" else "분석 PC에서 현재 파일을 승인 원본과 비교합니다.")
			return {"device":id,"mode":"inspect","text":definitions.devices[id].label + "에서 E · " + device_task(id),"reason":reason}
	if p.observations.changed and not p.get("spatial", {}).get("rechecked", false) and m.revisit_device != null:
		return {"device":m.revisit_device,"mode":"recheck","text":"이전 관찰 만료 · " + definitions.devices[m.revisit_device].label + "에서 E로 변경 결과를 재확인하세요.","reason":"F는 설정 도구입니다. 변경 결과는 현장에서 E로 확인합니다."}
	var target = "INTERACT_Router" if m.id == "services" else "INTERACT_AdminPC"
	var instruction = "조사 노트에서 " + ("허용 범위" if m.id == "tutorial" else "원인 설명") + "를 선택하세요." if not explained() else "파일 비교·복구를 검토하세요." if not defended() and m.id == "integrity" else "방어 설정을 검토하세요." if not defended() else "현재 상태 재검증으로 방어와 정상 기능을 확인하세요."
	var reason = {"services":"서버는 상태 확인, 방화벽은 접근 정책 변경을 담당합니다.","login":"로그인 기록을 근거로 정책을 판단하고 변경합니다.","integrity":"보관함은 비교 기준, 분석 PC는 검사·복구를 담당합니다."}.get(m.id,"E로 확보한 승인서를 조사 노트에서 읽고 판단합니다.")
	return {"device":target,"mode":"verify" if explained() and defended() else "tool","text":definitions.devices[target].label + "에서 F · " + instruction,"reason":reason}

func device_task(id: String) -> String:
	if mission().device_commands.get(id,[]).is_empty(): return "조사 위치 안내"
	match mission().id:
		"tutorial": return "조사 승인서 확인"
		"services": return "서비스 상태 조사"
		"login": return "로그인 기록 조사"
	return "승인 원본 기준 조사" if id == "INTERACT_FileCabinet" else "파일 해시 비교"

func device_tool(id: String) -> Dictionary:
	if id == "INTERACT_Router": return {"tab":"Settings","label":"접근 정책"}
	if id == "INTERACT_FileCabinet": return {"tab":"Files","label":"파일 비교"}
	if id == "INTERACT_Whiteboard": return {"tab":"Notes","label":"조사 안내"}
	if id == "INTERACT_ServerRack": return {"tab":"Terminal","label":"터미널"}
	match mission().id:
		"tutorial": return {"tab":"Terminal","label":"조사 노트 · 터미널"}
		"integrity": return {"tab":"Files","label":"파일 비교·복구"}
	return {"tab":"Settings","label":"정책 설정"}

func field_transition(previous, current: String) -> String:
	return str(previous) + " → " + current if progress().observations.changed and previous != null and previous != current else current

func field_findings(id: String) -> Array:
	var before = progress().observations.before
	match mission().id:
		"tutorial": return ["조사 승인서 · club-server의 내장 가상 데이터만 조사","E로 근거를 확보하고 F로 판단·설정 도구를 엽니다."]
		"services":
			var rows = []
			for port in ["443","8080"]:
				var old = null if before == null else "OPEN" if before[port] else "FILTERED"
				var current = "OPEN" if state.ports[port] else "FILTERED"
				rows.append(port + " " + field_transition(old,current) + " · " + (("자료 열람 가능" if state.ports[port] else "자료 열람 불가") if port == "443" else ("관리 접근 허용" if state.ports[port] else "관리 접근 차단")))
			return rows
		"login":
			var old_normal = null if before == null else "성공" if accepted(definitions.normal_password,before) else "거부"
			var old_limit = null if before == null else "제한됨" if before.limitAttempts else "무제한"
			var allowed = definitions.common_passwords.filter(func(value): return accepted(value,state.login)).size()
			return ["정상 더미 로그인 · " + field_transition(old_normal,"성공" if login_result().normal else "거부"),"반복 실패 · " + field_transition(old_limit,"제한됨" if state.login.limitAttempts else "무제한"),"흔한 더미 후보 %d/%d개 허용 · 최소 길이 %d자" % [allowed,definitions.common_passwords.size(),state.login.minLength]]
	if id == "INTERACT_FileCabinet": return ["승인된 오프라인 원본이 비교 기준입니다.","분석 PC에서 현재 파일을 이 기준과 비교하세요."]
	var rows = []
	for row in progress().hashes:
		var old = null if before == null or not before.get("matches",{}).has(row.name) else "승인 기준과 일치" if before.matches[row.name] else "승인 기준과 불일치"
		rows.append(row.name + " · " + field_transition(old,"승인 기준과 일치" if row.matches else "승인 기준과 불일치"))
	return rows

func device_status(id: String) -> Dictionary:
	var p = progress()
	var next = action()
	var relevant = not mission().device_commands.get(id,[]).is_empty()
	var inspected = id in p.get("spatial",{}).get("inspected",[])
	var pending = inspected and p.observations.changed and not p.get("spatial",{}).get("rechecked",false) and id == mission().revisit_device
	var informational = mission().id == "tutorial" or mission().id == "integrity" and id == "INTERACT_FileCabinet"
	var tone = "pending" if pending else "neutral" if not inspected or informational else "normal" if defended() else "warning"
	var text = "E · " + device_task(id) if relevant else "현재 사건 조사 대상 아님"
	if id == "INTERACT_Router" and mission().id == "services": text = "서비스 접근 정책\nF · 접근 정책 편집"
	if inspected:
		text = "이전 관찰 만료\n설정 변경됨 · E 재확인" if pending else "현장 재확인 완료" if p.get("spatial",{}).get("rechecked",false) and id == mission().revisit_device else "현장 단서 확보"
		if not pending and mission().id == "services": text += "\n443 %s / 8080 %s" % ["OPEN" if state.ports["443"] else "FILTERED","OPEN" if state.ports["8080"] else "FILTERED"]
		if not pending and mission().id == "login": text += "\n정상 로그인 %s\n반복 실패 %s" % ["성공" if login_result().normal else "거부","제한됨" if state.login.limitAttempts else "무제한"]
		if not pending and mission().id == "integrity" and id == "INTERACT_AdminPC": text += "\n해시 %d개 불일치" % p.hashes.filter(func(row): return not row.matches).size()
	return {"text":text,"tone":tone,"objective":next.device == id,"action":"E · 변경 결과 재확인" if pending else "F · 최종 검증" if next.mode == "verify" else "F · " + device_tool(id).label if next.mode == "tool" else "E · " + device_task(id)}

func inspect(id: String) -> Dictionary:
	var p = progress()
	var relevant = mission().device_commands.get(id, [])
	var lines = []
	if relevant.is_empty():
		lines.append("현재 사건의 근거를 얻는 장비가 아닙니다. 다음 행동을 확인하세요.")
	else:
		if not p.verified and not p.has("spatial"): p.spatial = {"inspected": [], "rechecked": false}
		for command in relevant: lines.append(run_command(command, false))
		if p.has("spatial"):
			if id not in p.spatial.inspected: p.spatial.inspected.append(id)
			if p.observations.changed and id == mission().revisit_device: p.spatial.rechecked = true
	var recheck = p.observations.changed and id == mission().revisit_device
	var informational = mission().id == "tutorial" or mission().id == "integrity" and id == "INTERACT_FileCabinet"
	var result = {"device":id,"label":definitions.devices[id].label,"status":"변경 후 재확인 · " + ("정상 동작" if defended() else "문제 남음") if recheck else "현장 조사 완료" if not relevant.is_empty() else "현재 사건 조사 대상 아님","findings":field_findings(id) if not relevant.is_empty() else ["이 장비는 F로 접근 정책을 편집하는 곳입니다." if id == "INTERACT_Router" and mission().id == "services" else "현재 사건의 단서를 얻는 장비가 아닙니다."],"transcript":"\n".join(lines),"recorded":not relevant.is_empty(),"next":action().text,"evidenceFound":mission().evidence.filter(func(key): return key in p.clues).size(),"evidenceTotal":mission().evidence.size(),"tone":"neutral" if relevant.is_empty() or informational else "normal" if defended() else "warning"}
	state_changed.emit()
	observation.emit(result)
	return result

func equipment() -> Dictionary:
	var policy = state.login.duplicate()
	policy.normal = login_result().normal
	return {"mission": mission().id, "title": mission().title, "ports": state.ports.duplicate(), "login": policy, "hashes": progress().hashes.duplicate(true), "restored": state.files["budget.csv"] == definitions.original_files["budget.csv"], "changed": progress().observations.changed, "rechecked": progress().get("spatial", {}).get("rechecked", false), "verified": progress().verified}
