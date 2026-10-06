extends SceneTree

var failures: Array = []
var assertions = 0

func check(value: bool, message: String):
	assertions += 1
	if not value: failures.append(message); push_error(message)

func equivalent(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not equivalent(a[i],b[i]): return false
		return true
	if (a is int or a is float) and (b is int or b is float): return a == b
	return typeof(a) == typeof(b) and a == b

func _initialize():
	var manager = LabMissions.new()
	root.add_child(manager)
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/parity.json"))
	for i in range(fixtures.steps.size()):
		var row = fixtures.steps[i]
		match row.action:
			"inspect": manager.inspect(row.args[0])
			"answer": manager.apply_answer(int(row.args[0]))
			"port": manager.apply_port(str(int(row.args[0])),row.args[1])
			"login": manager.apply_login(row.args[0])
			"restore": manager.restore_file(row.args[0])
			"command": manager.run_command(row.args[0])
			"next": manager.next_mission()
		var actual = {"mission":manager.mission().id,"score":manager.score(),"stage":manager.stage(),"verified":manager.progress().verified,"clues":manager.progress().clues,"ports":manager.state.ports,"login":manager.state.login,"hashes":manager.progress().hashes,"spatial":manager.progress().get("spatial"),"mode":manager.action().mode}
		for key in actual:
			check(equivalent(actual[key],row.expected[key]),"v0.7.0 parity checkpoint %d %s %s" % [i,row.action,key])
	var saves = LabSave.new()
	var clone = LabMissions.new()
	root.add_child(clone)
	for source in ["web-export.json","web-legacy.json"]:
		check(saves.decode(FileAccess.get_file_as_string("res://tests/"+source),clone),source + " import")
		check(clone.progress().verified and clone.score() == 100,source + " valid progress")
	var raw = JSON.stringify({"format":"security-lab-native","version":1,"game":saves.encode(manager)})
	check(saves.decode(raw,clone),"Native all-mission roundtrip")
	check(equivalent(saves.encode(clone),saves.encode(manager)),"Canonical persisted state equality")
	var baseline = JSON.stringify(clone.state)
	for malicious in ["not json",'{"version":999}',raw.replace('"443":true','"443":"yes"'),raw.replace('"id":"tutorial"','"id":"unknown"'),raw.replace('"rechecked":true','"rechecked":"true"')]:
		check(not saves.decode(malicious,clone),"Invalid import rejected")
		check(JSON.stringify(clone.state) == baseline,"Invalid import preserves current state")
	manager.reset_all()
	var fresh = JSON.stringify(manager.state)
	check(manager.device_task("INTERACT_AdminPC") == "조사 승인서 확인","Tutorial purpose prompt")
	manager.action()
	manager.device_status("INTERACT_AdminPC")
	check(JSON.stringify(manager.state) == fresh,"UX projections do not mutate progress")
	var prepared = manager.inspect("INTERACT_AdminPC")
	check(prepared.evidenceFound == 2 and prepared.evidenceTotal == 2,"Field card reports only earned evidence count")
	manager.apply_answer(0); manager.run_command("verify"); manager.next_mission()
	var unrelated = JSON.stringify(manager.state)
	var router = manager.inspect("INTERACT_Router")
	check(not router.recorded and router.next.contains("자료 서버"),"Unrelated E redirects without evidence")
	check(JSON.stringify(manager.state) == unrelated,"Unrelated equipment cannot change mission state")
	manager.inspect("INTERACT_ServerRack")
	check(manager.action().device == "INTERACT_Router" and manager.action().reason.contains("접근 정책 변경"),"Server observation explains why policy lives at firewall")
	manager.apply_answer(1); manager.apply_port("443",false); manager.apply_port("8080",false)
	check(manager.action().text.contains("자료 서버") and manager.action().reason.contains("현장에서 E"),"Recheck names destination and distinguishes F")
	check(manager.device_status("INTERACT_ServerRack").tone == "pending","Expired field observation uses pending tone")
	var wrong = manager.inspect("INTERACT_ServerRack")
	check(wrong.findings.size() == 2 and wrong.findings[0].contains("OPEN → FILTERED") and wrong.findings[0].contains("자료 열람 불가"),"Wrong defense reports factual normal-service failure")
	check(wrong.tone == "warning" and not wrong.next.contains("443"),"Recheck cannot reveal exact corrective setting")
	manager.run_command("verify"); check(not manager.progress().verified,"Observed wrong defense is not completion")
	manager.apply_port("443",true); manager.inspect("INTERACT_ServerRack"); manager.run_command("verify"); manager.next_mission()
	manager.inspect("INTERACT_AdminPC")
	manager.apply_login({"minLength":15,"blockCommon":true,"limitAttempts":true})
	var login = manager.inspect("INTERACT_AdminPC")
	check(login.findings.size() == 3 and login.findings[1].contains("무제한 → 제한됨"),"Login card summarizes change instead of raw attempts")
	manager.apply_answer(2); manager.run_command("verify"); manager.next_mission()
	check(manager.action().device == "INTERACT_FileCabinet" and manager.action().reason.contains("비교 기준"),"Integrity starts with trusted source")
	var source = manager.inspect("INTERACT_FileCabinet")
	check(source.evidenceFound < source.evidenceTotal and manager.action().device == "INTERACT_AdminPC","Source evidence is partial and analysis is separate")
	manager.inspect("INTERACT_AdminPC"); manager.restore_file("budget.csv")
	var restored = manager.inspect("INTERACT_AdminPC")
	check(restored.findings.size() == 3 and "\n".join(restored.findings).contains("불일치 → 승인 기준과 일치"),"Integrity summarizes restoration")
	check(not RegEx.create_from_string("[0-9a-f]{64}").search("\n".join(restored.findings)),"Full hashes stay in detailed tools")
	print("NATIVE_UNIT ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
