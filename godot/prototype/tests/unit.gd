extends SceneTree

var checks = 0
var failures = []

func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message); push_error(message)

func at(state: Dictionary, path: String):
	var value = state
	for part in path.split("."): value = value.get(part) if value is Dictionary else null
	return value

func _initialize():
	var content = InvestigationContent.load_case()
	check(not content.has("error"),"Content loads")
	if content.has("error"): quit(1); return
	var engine = InvestigationEngine.new(content)
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://prototype/tests/scenarios.json"))
	var last: Dictionary
	for scenario in fixtures.scenarios:
		var state = engine.create_state()
		for i in range(scenario.steps.size()):
			var row = scenario.steps[i]
			var action = row.get("action",{})
			if row.has("command"): action = engine.parse(row.command,row.device,state)
			var before = JSON.stringify(state)
			var result = engine.step(state,action)
			check(JSON.stringify(state) == before,"Pure transition: %s/%d" % [scenario.id,i])
			state = result.state
			if row.has("code"): check(result.code == row.code,"Result: %s/%d %s vs %s" % [scenario.id,i,result.code,row.code])
			for path in row.get("expect",{}): check(at(state,path) == row.expect[path],"State: %s/%d %s" % [scenario.id,i,path])
			var saved = InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(state,content),content)
			check(saved.has("state"),"Save roundtrip: %s/%d %s" % [scenario.id,i,saved.get("error","")])
			check(not state.eventIds.size() > 20,"Bounded unique events")
		last = state
		if scenario.id == "repair-does-not-pause":
			check(engine.project(state).documentCount == -1,"Unqueried collection stays unknown in the UI")
			var observed = engine.step(state,engine.parse("inspect staging","server_console",state)).state
			check(engine.project(observed).documentCount == observed.documents.size(),"Queried collection shows unique observed documents")
	var original = engine.create_state()
	var bad = original.duplicate(true)
	bad.day = 4
	check(not InvestigationSaveCodec.valid(bad,content),"Date jump without nights rejected")
	bad = original.duplicate(true)
	bad.known = ["package"]
	bad.evidence = ["E10"]
	bad.records.package.acquiredDay = 1
	check(not InvestigationSaveCodec.valid(bad,content),"Unapproved audit evidence rejected")
	var valid = InvestigationSaveCodec.encode(last,content)
	check(InvestigationSaveCodec.decode(valid.replace('"schemaVersion": 1','"schemaVersion": 999'),content).has("error"),"Unknown save version rejected")
	check(InvestigationSaveCodec.decode("not json",content).has("error"),"Malformed save rejected")
	var repeated = engine.step(last,{"type":"day.end","payload":{"expectedDay":7,"confirmed":true}})
	check(repeated.state == last,"Ending repeated without new event")
	check(not engine.condition(original,{"op":"evidence_known","id":"E07"}),"Unknown evidence cannot unlock question")
	check(engine.step(original,{"type":"read","deviceId":"project_pc","payload":{"kind":"submissions"}}).code == "WRONG_DEVICE","Direct action still checks device")
	print("INVESTIGATION_UNIT ",JSON.stringify({"scenarios":fixtures.scenarios.size(),"assertions":checks,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
