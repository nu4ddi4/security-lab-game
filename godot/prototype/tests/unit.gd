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
	var installed = {"version":"0.2.0","prerelease":true,"tag_prefix":"SecurityLab-proto-"}
	var candidates = [release_fixture("0.3.0",false),release_fixture("0.2.1",true),release_fixture("0.10.0",true)]
	check(InvestigationUpdates.select_release(candidates,installed,"Android").version == "0.10.0","Prerelease updates use numeric versions and skip stable releases")
	installed.prerelease = false
	check(InvestigationUpdates.select_release(candidates,installed,"Windows").version == "0.3.0","Stable installs never offer prereleases")
	check(InvestigationUpdates.select_release(candidates,installed,"Android").url.ends_with(".apk"),"Android receives an APK")
	check(InvestigationUpdates.select_release(candidates,installed,"Windows").url.ends_with(".exe"),"Windows receives an EXE")
	installed.version = "0.3.0"
	check(InvestigationUpdates.select_release(candidates,installed,"Windows").is_empty(),"Installed and older releases are never offered")
	installed.version = "0.2.0"
	var draft = release_fixture("0.4.0",false)
	draft.draft = true
	check(InvestigationUpdates.select_release([draft],installed,"Android").is_empty(),"Draft releases are ignored")
	var other = release_fixture("0.4.0",false)
	other.tag_name = "v0.4.0"
	check(InvestigationUpdates.select_release([other],installed,"Android").is_empty(),"Prototype updates cannot switch to the legacy web game")
	var bad_release = release_fixture("0.4.0",false)
	bad_release.assets[0].browser_download_url = "https://example.com/update.apk"
	check(InvestigationUpdates.select_release([bad_release],installed,"Android").url == "","Update download URLs must belong to this repository and exact asset")
	var incomplete = release_fixture("0.4.0",false)
	incomplete.assets = []
	check(InvestigationUpdates.select_release([release_fixture("0.3.0",false),incomplete],installed,"Android").url == "","Do not offer an older APK when the newest release is incomplete")
	check(InvestigationUpdates.select_release([null,{},"bad"],installed,"Android").is_empty(),"Malformed release entries are ignored")
	check(InvestigationUpdates.newer("0.8.0-beta.2","0.8.0-beta.1"),"Beta sequence increases within the same target version")
	check(InvestigationUpdates.newer("0.8.0","0.8.0-beta.2"),"Stable version follows all beta sequences")
	check(not InvestigationUpdates.newer("0.2.0-beta.1","0.2.0"),"A beta never replaces the same stable version")
	check(InvestigationUpdates.select_release(candidates,installed,"Linux").url == "","Unavailable platform files are never replaced with Windows assets")
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
	check(not engine.investigation_assigned(original),"New work does not expose investigation UI")
	var initial_help = engine.step(original,engine.parse("help","server_console",original))
	check(initial_help.text.contains("inspect account") and not initial_help.text.contains("inspect staging"),"Help shows assigned operational commands only")
	check(not engine.step(original,engine.parse("ls","server_console",original)).text.contains("staging.log"),"Unassigned investigation files stay absent from listings")
	var assigned = original.duplicate(true)
	assigned.day = 4
	check(engine.investigation_assigned(assigned),"Team-lead day-four assignment reveals investigation")
	var assigned_help = engine.step(assigned,engine.parse("help","server_console",assigned))
	check(assigned_help.text.contains("inspect staging"),"Investigation commands appear after assignment")
	assigned.day = 2
	assigned.report.approved = true
	check(engine.investigation_assigned(assigned),"Previously approved saves retain their investigation assignment")
	var listing = engine.step(original,engine.parse("ls","server_console",original))
	check(listing.text.contains("account.txt"),"Terminal lists device files")
	check(listing.state == original,"Listing never acquires unread records")
	check(engine.step(original,engine.parse("pwd","server_console",original)).text == "/srv/operations","Terminal shows the selected device directory")
	var aliased = engine.step(original,engine.parse("cat scope.txt","approval_archive",original))
	var canonical = engine.step(original,engine.parse("inspect W-218","approval_archive",original))
	check(aliased.state == canonical.state and aliased.text == canonical.text,"File aliases retain canonical evidence and progression")
	check(not engine.step(original,engine.parse("ls","control_console",original)).text.contains("package.txt"),"Unapproved audit files stay out of directory listings")
	check(engine.step(original,engine.parse("cat package.txt","control_console",original)).code == "PERMISSION_REQUIRED","File alias cannot bypass audit permission")
	check(engine.step(original,engine.parse("cat package.txt","server_console",original)).code == "WRONG_DEVICE","File alias cannot bypass physical device context")
	check(engine.parse("cat /etc/passwd","server_console",original).type == "invalid","Terminal cannot read host files")
	check(engine.parse("cat scope.txt; curl example.com","control_console",original).type == "invalid","Terminal never interprets shell sequences")
	var projected = engine.project(original)
	check(projected.questions.any(func(q): return q.id == "seo_message" and q.channel == "messenger"),"Previous submissions belong to messenger")
	check(projected.questions.any(func(q): return q.id == "oh_intro" and q.channel == "dialogue"),"Work handover belongs to local dialogue")
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

func release_fixture(version: String, prerelease: bool) -> Dictionary:
	var tag = "SecurityLab-proto-"+version
	var assets = []
	for ext in [".apk",".exe"]:
		assets.append({"name":tag+ext,"state":"uploaded","size":100.0,"browser_download_url":InvestigationUpdates.DOWNLOAD+tag+"/"+tag+ext})
	return {"tag_name":tag,"prerelease":prerelease,"draft":false,"assets":assets}
