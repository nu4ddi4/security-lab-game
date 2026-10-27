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
	check(InvestigationUpdates.select_release(candidates,installed,"Android",true).version == "0.10.0","Beta preview uses numeric versions and the newest release of either kind")
	check(InvestigationUpdates.select_release(candidates,installed,"Android").version == "0.3.0","Without the preview a beta install only follows stable releases")
	installed.prerelease = false
	check(InvestigationUpdates.select_release(candidates,installed,"Windows",true).version == "0.10.0","A stable install receives beta builds only after opting in")
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
	story_checks(engine,content)
	review_checks(engine,content)
	print("INVESTIGATION_UNIT ",JSON.stringify({"scenarios":fixtures.scenarios.size(),"assertions":checks,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func release_fixture(version: String, prerelease: bool) -> Dictionary:
	var tag = "SecurityLab-proto-"+version
	var assets = []
	for ext in [".apk",".exe"]:
		assets.append({"name":tag+ext,"state":"uploaded","size":100.0,"browser_download_url":InvestigationUpdates.DOWNLOAD+tag+"/"+tag+ext})
	return {"tag_name":tag,"prerelease":prerelease,"draft":false,"assets":assets}

func transition(engine, s: Dictionary, kind: String, payload: Dictionary = {}, device = "control_console") -> Dictionary:
	var before = JSON.stringify(s)
	var result = engine.step(s,{"type":kind,"payload":payload,"deviceId":device})
	check(JSON.stringify(s) == before,"Story transitions preserve their input: "+kind)
	var roundtrip = InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(result.state,engine.content),engine.content)
	check(roundtrip.has("state"),"Story save roundtrip: "+kind+" / "+result.code)
	return result.state

func query(engine, s: Dictionary, command: String, device = "server_console") -> Dictionary:
	var result = engine.step(s,engine.parse(command,device,s))
	check(InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(result.state,engine.content),engine.content).has("state"),"Read save roundtrip: "+command)
	return result.state

func story_base(engine, approved = true, stop = true, empty = false) -> Dictionary:
	var s = engine.create_state()
	if empty: s.maintenanceAllowed = false
	for command in ["status","inspect account","logs tasks","logs backups"]: s = query(engine,s,command)
	s = query(engine,s,"inspect files","project_pc")
	s = query(engine,s,"inspect W-218","approval_archive")
	for id in ["oh_intro","park_intro","han_intro","seo_intro"]: s = transition(engine,s,"dialogue",{"id":id})
	s = transition(engine,s,"day.end",{"expectedDay":1,"confirmed":true})
	s = query(engine,s,"backup disable B-05")
	s = query(engine,s,"verify service")
	if approved:
		s = query(engine,s,"logs access --task T-17")
		s = query(engine,s,"inspect staging")
		s = transition(engine,s,"report",{"claim":"unauthorized_collection","attachments":{"scope":"approval","access":"access-night-1","collection":"staging-night-1"}})
		check(s.report.approved and s.day == 2,"Early report opens the actual audit permission on day two")
		for command in ["logs submissions","logs application","inspect PKG-218-R2","inspect metadata","inspect T-19"]: s = query(engine,s,command,"control_console")
		s = query(engine,s,"logs channel","maintenance_terminal")
	if stop and not empty: s = transition(engine,s,"pause",{"confirmed":true},"server_console")
	for day in range(2,7):
		if day == 3:
			s = query(engine,s,"inspect files","project_pc")
			if not s.ops.indexHealthy: s = query(engine,s,"repair index")
			s = query(engine,s,"verify search","project_pc")
		if day >= 4:
			s = query(engine,s,"verify service")
			s = query(engine,s,"verify search","project_pc")
		if approved and day == 5: s = query(engine,s,"logs requests","maintenance_terminal")
		if approved and day == 6: s = query(engine,s,"logs contracts","maintenance_terminal")
		s = transition(engine,s,"day.end",{"expectedDay":day,"confirmed":true})
	if approved:
		var links = {"C05":["message","submissions"],"C06":["submissions","application","package"],"C07":["metadata","message","submissions"],"C08":["request","message","approval"],"C09":["purpose","package","metadata"],"C10":["application","transfer"]}
		for claim in links: s = transition(engine,s,"inference",{"claim":claim,"records":links[claim]})
	return s

func report_fields(transfer: String, partial = false) -> Dictionary:
	return {"scope":"violation","collection":"collected","submission":"unknown" if partial else "seo","authorship":"unknown" if partial else "vendor","awareness":"unknown" if partial else "warning_seen","purpose":"unknown" if partial else "contract_support","transfer":transfer,"material":"unknown"}

func close_story(engine, s: Dictionary, fields: Dictionary, ending: String) -> Dictionary:
	s = transition(engine,s,"final.report",{"fields":fields})
	s = transition(engine,s,"day.end",{"expectedDay":7,"confirmed":true})
	check(s.ended and s.casework.ending.get("id") == ending,"Ending matrix "+ending)
	return s

func story_checks(engine, content):
	var base = story_base(engine)
	check(base.ops.indexHealthy and not base.records.values().any(func(r): return r.template == "index_damage"),"Early stop prevents a later index fault without removing past records")
	check(base.records.has("access-night-1") and base.records.has("staging-night-1"),"Early stop preserves previous access and staging history")
	check(base.casework.minute == 540 and base.casework.phase == "morning","Early report does not move the fixed day-seven dispatch time")
	var premature = engine.create_state()
	check(engine.step(premature,engine.parse("logs requests","maintenance_terminal",premature)).code == "NOT_YET_AVAILABLE","Request distribution is unavailable before day five")
	check(engine.step(premature,engine.parse("inspect metadata","control_console",premature)).code == "PERMISSION_REQUIRED","Audit permission cannot be bypassed by a direct command")
	check(not InvestigationResolution.supports(base,content,"C05",["message"]),"One channel message cannot prove the central submission chain")
	check(not InvestigationResolution.supports(base,content,"C07",["account"]),"Account ownership cannot prove package authorship")
	check(base.casework.links.has("C08") and base.casework.links.has("C09"),"Warning receipt and organization purpose require separate original documents")
	var a = transition(engine,base,"control.request",{"records":["application","transfer"]})
	a = transition(engine,a,"control.execute")
	a = transition(engine,a,"time.advance")
	check(a.casework.dispatch == "not_run" and a.casework.control.mode == "blocked_pre_run","Approved pre-run control prevents dispatch")
	a = query(engine,a,"logs controls","control_console")
	a = query(engine,a,"logs dispatch","control_console")
	a = query(engine,a,"logs receipts","control_console")
	a = transition(engine,a,"inference",{"claim":"C11","records":["control-execute","dispatch-7"]})
	a = close_story(engine,a,report_fields("not_run"),"A")
	check(a.records["final-report"].body.find("개인 판매") == -1,"Closing document does not disclose an unselected or hidden motive")
	close_story(engine,with_open_report(a),report_fields("not_run",true),"B")
	var sent = transition(engine,base,"time.advance")
	check(sent.casework.minute == 1050 and sent.casework.phase == "dispatching","17:30 starts the reserved job")
	var blocked = transition(engine,base,"control.request",{"records":["application","transfer"]})
	blocked = transition(engine,blocked,"time.advance")
	blocked = transition(engine,blocked,"control.execute")
	blocked = transition(engine,blocked,"time.advance")
	check(blocked.casework.dispatch == "blocked" and blocked.casework.control.mode == "blocked_during","In-flight control only claims a block before dispatch completes")
	sent = transition(engine,sent,"time.advance")
	check(sent.casework.dispatch == "sent" and sent.casework.receipt == "unconfirmed","Dispatch completion alone does not create a receipt")
	var late_control = transition(engine,sent,"control.request",{"records":["application","transfer"]})
	late_control = transition(engine,late_control,"control.execute")
	check(late_control.casework.dispatch == "sent","A control executed after completion never rewrites the dispatch result")
	sent = query(engine,sent,"logs dispatch","control_console")
	sent = query(engine,sent,"logs receipts","control_console")
	check(not InvestigationResolution.supports(sent,content,"C12",["dispatch-7","receipt-unconfirmed"]),"Pending channel response cannot support a receipt finding")
	close_story(engine,sent,report_fields("sent"),"E")
	var unsupported_receipt = report_fields("received")
	check(InvestigationResolution.evaluate(sent,content,unsupported_receipt).attribution_quality == "overclaimed","A receipt assertion without its original is marked unsupported")
	var confirmed = transition(engine,sent,"time.advance")
	var unobserved = close_story(engine,confirmed,report_fields("sent"),"D")
	check(InvestigationResolution.public_ending(unobserved) == "조사 종결" and not unobserved.records["final-report"].body.contains("receipt=confirmed"),"An unqueried receipt is not disclosed by the ending title or closing originals")
	confirmed = query(engine,confirmed,"logs receipts","control_console")
	confirmed = transition(engine,confirmed,"inference",{"claim":"C12","records":["dispatch-7","receipt-confirmed"]})
	close_story(engine,confirmed,report_fields("received"),"C")
	close_story(engine,confirmed,report_fields("received",true),"D")
	var intention = report_fields("received")
	intention.awareness = "full_intent"
	check(InvestigationResolution.evaluate(confirmed,content,intention).attribution_quality == "overclaimed","Organization documents do not prove the submitter directed the full external transfer")
	var wrong = report_fields("not_run")
	wrong.submission = "han"
	var f = close_story(engine,with_open_report(a),wrong,"F")
	check(f.casework.dispatch == "not_run","An unsupported report does not overwrite a successful physical block")
	var isolated = transition(engine,base,"staging.isolate")
	isolated = transition(engine,isolated,"time.advance")
	check(isolated.casework.dispatch == "not_run" and isolated.documents == base.documents,"Isolation blocks the reserved source while preserving historical documents")
	var empty = story_base(engine,false,false,true)
	check(engine.step(empty,{"type":"control.execute","deviceId":"control_console"}).code == "PERMISSION_REQUIRED","General work never grants high-privilege control")
	empty = transition(engine,empty,"time.advance")
	check(empty.casework.dispatch == "not_run" and empty.records["dispatch-7"].facts.reason == "NO_SOURCE","An empty staging location yields a no-source result")
	var unknown = {}
	for row in content.rules.finalFields: unknown[row.id] = "unknown"
	close_story(engine,empty,unknown,"F")
	var legacy_raw = FileAccess.get_file_as_string("res://prototype/tests/legacy-save.json")
	var migrated = InvestigationSaveCodec.decode(legacy_raw,content)
	check(migrated.has("state"),"A real completed beta save migrates without losing progress")
	if migrated.has("state"):
		check(migrated.state.day == 7 and not migrated.state.ended and migrated.state.casework.phase == "morning","Old prototype closure resumes at the day-seven work window")
		check(InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(migrated.state,content),content).has("state"),"Migrated save roundtrips in the unchanged envelope")
	check(InvestigationSaveCodec.decode(legacy_raw.replace('"schemaVersion": 1','"schemaVersion": 999'),content).has("error"),"Migration does not accept an unsupported envelope")
	var closing = engine.step(a,{"type":"dialogue","payload":{"id":"oh_closing"}})
	check(closing.code == "DIALOGUE" and not closing.text.contains("VENDOR-OPS"),"Post-case NPC handover stays within the NPC's own business role")
	var tampered = base.duplicate(true)
	tampered.casework.receipt = "confirmed"
	check(not InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(tampered,content),content).has("state"),"Forged future receipt state is rejected")
	tampered = base.duplicate(true)
	tampered.casework.links.C12 = ["access-night-1","staging-night-1"]
	check(not InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(tampered,content),content).has("state"),"Forged inference references are rejected")
	for id in content.records:
		check(not content.records[id].body.contains("단정하지") and not content.records[id].body.contains("별도 확인해야"),"Original records contain operational content without inference coaching: "+id)

func with_open_report(s: Dictionary) -> Dictionary:
	var next = s.duplicate(true)
	next.ended = false
	next.casework.ending.clear()
	next.casework.final.clear()
	next.known.erase("final-report")
	next.records.erase("final-report")
	return next

func review_checks(engine, content):
	var base = story_base(engine)
	var isolated = transition(engine,base,"control.request",{"records":["application","transfer"]})
	isolated = transition(engine,isolated,"staging.isolate")
	isolated = transition(engine,isolated,"time.advance")
	isolated = query(engine,isolated,"logs controls","control_console")
	isolated = query(engine,isolated,"logs dispatch","control_console")
	check(not InvestigationResolution.supports(isolated,content,"C11",["control-request","dispatch-7"]),"An authorization alone never proves execution or causes a source-isolation result")
	check(InvestigationResolution.supports(isolated,content,"C11",["control-request","staging-isolate","dispatch-7"]),"The actual isolation supports the result even when the authorization is selected first")
	isolated = transition(engine,isolated,"control.execute")
	isolated = query(engine,isolated,"logs controls","control_console")
	check(not InvestigationResolution.supports(isolated,content,"C11",["control-execute","dispatch-7"]),"A later hold cannot take credit for an earlier isolation")
	var sent = transition(engine,base,"time.advance")
	sent = transition(engine,sent,"time.advance")
	sent = query(engine,sent,"logs dispatch","control_console")
	sent = query(engine,sent,"logs receipts","control_console")
	sent = transition(engine,sent,"final.report",{"fields":report_fields("sent")})
	var submitted = sent.casework.final.duplicate(true)
	var later = transition(engine,sent,"time.advance")
	check(later.casework.final == submitted,"Later business time preserves the accepted findings, citations, and evaluation")
	check(not InvestigationResolution.final_is_current(later),"A changed business state requires explicit report review")
	check(engine.step(later,{"type":"day.end","payload":{"expectedDay":7,"confirmed":true}}).code == "FINAL_STALE","An outdated accepted report cannot silently close the new business state")
	check(InvestigationResolution.evaluate_report(later,content).id == "E","A frozen report retains the physical context it was submitted with")
	later = query(engine,later,"logs receipts","control_console")
	later = transition(engine,later,"inference",{"claim":"C12","records":["dispatch-7","receipt-confirmed"]})
	close_story(engine,later,report_fields("received"),"C")
	var toggled = engine.create_state()
	for i in range(200): toggled = engine.step(toggled,engine.parse("backup disable B-05" if i%2 == 0 else "backup enable B-05","server_console",toggled)).state
	check(toggled.records.size() == 14 and toggled.records["backup-change-history"].facts.entries.size() == 16,"Repeated backup changes use a bounded journal instead of exhausting save records")
	toggled = query(engine,toggled,"logs backups")
	check("backup-change-history" in toggled.known,"The backup command exposes its actual configuration change journal")
	check(InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(toggled,content),content).has("state"),"Two hundred backup changes still reload")
	var old_raw = FileAccess.get_file_as_string("res://prototype/tests/casework-v1-save.json")
	var migrated = InvestigationSaveCodec.decode(old_raw,content)
	check(migrated.has("state"),"A real v1 casework save with an accepted report migrates")
	if migrated.has("state"):
		var old = JSON.parse_string(old_raw).state
		var state = migrated.state
		check(state.casework.version == 2 and state.day == old.day and state.known == old.known and state.memo == old.memo,"Casework migration preserves progress and observed originals")
		check(not state.casework.links.has("C11") and not state.casework.final.links.has("C11"),"Migration removes only an approval incorrectly accepted as a successful control")
		check(state.casework.final.fields == old.casework.final.fields and state.casework.final.evaluation == old.casework.final.evaluation,"Migration preserves accepted findings and evaluation")
		check(InvestigationSaveCodec.decode(InvestigationSaveCodec.encode(state,content),content).has("state"),"Migrated accepted reports roundtrip in the existing save envelope")
	var overflow = JSON.parse_string(old_raw)
	var template = overflow.state.records["backup-change-15"] if overflow.state.records.has("backup-change-15") else {}
	for id in overflow.state.records:
		if overflow.state.records[id].template == "backup_change": template = overflow.state.records[id]; break
	check(not template.is_empty(),"The legacy fixture contains an actual per-change backup record")
	if not template.is_empty():
		for i in range(150):
			var record = template.duplicate(true)
			record.id = "backup-change-%d" % (i+1000)
			overflow.state.records[record.id] = record
		overflow.state.revision = 2000
		var recovered = InvestigationSaveCodec.decode(JSON.stringify(overflow),content)
		check(recovered.has("state") and recovered.state.records.size() < 100,"Old saves exhausted only by unread backup changes recover through bounded migration")
