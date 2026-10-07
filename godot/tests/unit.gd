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
	print("NATIVE_UNIT ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
