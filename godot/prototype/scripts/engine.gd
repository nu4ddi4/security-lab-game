class_name InvestigationEngine
extends RefCounted

var content: Dictionary

func _init(data: Dictionary):
	content = data

func create_state() -> Dictionary:
	var s = {"schemaVersion":1, "day":1, "revision":0, "ended":false,
		"ops":{"duplicateBackup":true,"primaryBackup":true,"backupDelay":false,"indexHealthy":true,"serviceVerifiedDay":0,"searchVerifiedDay":0,"filesReadDay":0},
		"tasks":{"T-17":{"status":"scheduled","held":false},"T-19":{"status":"scheduled","held":false}},
		"maintenanceAllowed":true,"records":{},"known":[],"evidence":[],"baseline":[],"introduced":[],"statements":[],"eventIds":[],"documents":[],"messages":[],
		"report":{"approved":false,"claim":"","attachments":{},"feedback":""},"memo":""}
	for id in content.records:
		if content.records[id].initial: _append(s,id,id,int(content.records[id].time.dayOffset),int(content.records[id].time.minute))
	s.messages.append({"id":"handover","npc":"oh","day":1,"text":_t("HANDOVER")})
	return s

func _t(code: String, values: Dictionary = {}) -> String:
	var text = str(content.text.get(code,code))
	for key in values: text = text.replace("{"+str(key)+"}",str(values[key]))
	return text

func _result(s: Dictionary, code: String, text = "", events: Array = []) -> Dictionary:
	var output = _t(code) if text == "" else str(text)
	return {"state":s,"code":code,"text":output,"events":events,"messages":[{"code":code,"params":{"text":output}}]}

func _append(s: Dictionary, template: String, id: String, day: int, minute: int = 540):
	if s.records.has(id): return
	var record = content.records[template].duplicate(true)
	record["id"] = id
	record["template"] = template
	record["time"] = {"dayOffset":day,"minute":minute}
	s.records[id] = record

func _know(s: Dictionary, id: String) -> String:
	if not s.records.has(id): return ""
	var r = s.records[id]
	if id not in s.known:
		s.known.append(id)
		r["acquiredDay"] = s.day
		if r.evidence != "" and r.evidence not in s.evidence: s.evidence.append(r.evidence)
	return r.title + "\n" + r.source + " · " + _time(r.time) + "\n" + r.body

func _time(time: Dictionary) -> String:
	var day = int(time.dayOffset)
	return ("시작 전 %d일" % -day if day < 1 else "%d일차" % day) + " %02d:%02d" % [int(time.minute)/60,int(time.minute)%60]

func condition(s: Dictionary, rule: Dictionary) -> bool:
	match rule.get("op"):
		"always": return true
		"all": return rule.args.all(func(r): return condition(s,r))
		"any": return rule.args.any(func(r): return condition(s,r))
		"not": return not condition(s,rule.arg)
		"evidence_known": return rule.id in s.evidence
		"statement_known": return rule.id in s.statements
		"record_exists": return s.records.has(rule.id)
		"permission_granted", "report_approved": return s.report.approved
		"task_state": return s.tasks.has(rule.id) and s.tasks[rule.id].status == rule.value
	return false

func parse(command: String, device: String, s: Dictionary) -> Dictionary:
	if not content.case.devices.has(device): return {"type":"invalid","code":"DEVICE_REQUIRED"}
	if command.length() > 200: return {"type":"invalid","code":"UNKNOWN_COMMAND"}
	var normalized = " ".join(command.strip_edges().split(" ",false)).to_lower()
	for row in content.commands:
		if row.text.to_lower() == normalized:
			if device not in row.devices: return {"type":"invalid","code":"WRONG_DEVICE"}
			return {"type":row.action,"deviceId":device,"payload":row.args.duplicate(true)}
	return {"type":"invalid","code":"UNKNOWN_COMMAND"}

func step(original: Dictionary, action: Dictionary) -> Dictionary:
	var kind = action.get("type","")
	var payload = action.get("payload",{})
	var device = action.get("deviceId","")
	if kind == "invalid": return _result(original,action.get("code","INVALID_ACTION"))
	if original.ended and kind != "memo": return _result(original,"PROTOTYPE_ENDED")
	if not payload is Dictionary: return _result(original,"INVALID_ACTION")
	if kind in ["help","status","directory","working_directory","checklist","read","backup_disable","backup_enable","index_repair","snapshot","pause","verify_service","verify_search"]:
		var allowed = false
		for row in content.commands:
			if row.action == kind and device in row.devices and (kind != "read" or row.args.kind == payload.get("kind")): allowed = true
		if not allowed: return _result(original,"WRONG_DEVICE")
	var s = original.duplicate(true)
	var result: Dictionary
	match kind:
		"working_directory": result = _result(s,"DIRECTORY",content.case.devices[device].directory)
		"directory":
			var rows = [content.case.devices[device].directory]
			for file in content.case.devices[device].files:
				var command = parse(file.command,device,s)
				if not s.report.approved and command.payload.get("kind","") in ["submissions","package"]: continue
				rows.append(file.name+"  —  "+file.description)
			result = _result(s,"DIRECTORY","\n".join(rows))
		"help":
			var rows = []
			for row in content.commands:
				if device in row.devices and (s.report.approved or row.args.get("kind","") not in ["submissions","package"]): rows.append(row.text + "  —  " + row.get("description",""))
			result = _result(s,"HELP", "\n".join(rows))
		"status":
			if device == "server_console" and "service" not in s.baseline: s.baseline.append("service")
			result = _result(s,"STATUS",_t("STATUS",{"day":s.day,"service":_t("DELAY" if s.ops.backupDelay else "NORMAL"),"index":_t("NORMAL" if s.ops.indexHealthy else "DAMAGED"),"task":_t("HELD" if s.tasks["T-17"].held else "RUNNING" if s.tasks["T-17"].status == "running" else "SCHEDULED")}))
		"checklist": result = _result(s,"CHECKLIST", "\n".join(missing_work(s)))
		"read": result = _read(s,str(payload.get("kind","")))
		"backup_disable", "backup_enable":
			var enable = kind == "backup_enable"
			if s.ops.duplicateBackup == enable: return _result(original,"NO_CHANGE")
			s.ops.duplicateBackup = enable
			s.ops.backupDelay = enable and s.day > 1
			s.ops.serviceVerifiedDay = 0
			_append(s,"backup_change","backup-change-%d" % (s.revision+1),int(s.day),600)
			s.records["backup-change-%d" % (s.revision+1)].facts["duplicateEnabled"] = enable
			s.records["backup-change-%d" % (s.revision+1)].body += "\n"+_t("BACKUP_ENABLED" if enable else "BACKUP_DISABLED")
			result = _result(s,"BACKUP_ENABLED" if enable else "BACKUP_DISABLED")
		"index_repair":
			if s.ops.indexHealthy: return _result(original,"INDEX_NORMAL")
			s.ops.indexHealthy = true
			s.ops.searchVerifiedDay = 0
			result = _result(s,"INDEX_REPAIRED")
		"snapshot":
			if s.tasks["T-17"].status != "running": return _result(original,"TASK_NOT_RUNNING")
			var id = "snapshot-%d" % s.day
			if not s.records.has(id):
				_append(s,"snapshot",id,int(s.day),600)
				s.records[id].facts = {"task":"T-17","status":s.tasks["T-17"].status,"account":content.case.tasks["T-17"].account,"documents":s.documents.duplicate()}
				s.records[id].body += "\nT-17 / "+content.case.tasks["T-17"].account+" / "+_t("RUNNING")+"\n"+"\n".join(s.documents)
			result = _result(s,"SNAPSHOT",_know(s,id))
		"pause":
			if s.tasks["T-17"].held: return _result(original,"ALREADY_HELD")
			if s.tasks["T-17"].status != "running": return _result(original,"TASK_NOT_RUNNING")
			if not payload.get("confirmed",false): return _result(original,"CONFIRM_PAUSE")
			s.tasks["T-17"].held = true
			s.tasks["T-17"].status = "held"
			result = _result(s,"TASK_HELD")
		"verify_service":
			if s.ops.backupDelay or s.ops.duplicateBackup or not s.ops.primaryBackup: return _result(original,"SERVICE_NOT_NORMAL")
			s.ops.serviceVerifiedDay = s.day
			result = _result(s,"SERVICE_VERIFIED")
		"verify_search":
			if not s.ops.indexHealthy: return _result(original,"SEARCH_NOT_NORMAL")
			s.ops.searchVerifiedDay = s.day
			result = _result(s,"SEARCH_VERIFIED")
		"dialogue": result = _dialogue(s,str(payload.get("id","")))
		"report": result = _report(s,payload)
		"day.end": result = _end_day(s,payload)
		"memo":
			if not payload.get("text") is String or payload.text.length() > content.rules.maxMemoLength: return _result(original,"MEMO_TOO_LONG")
			s.memo = payload.text
			result = _result(s,"MEMO_SAVED")
		_: return _result(original,"INVALID_ACTION")
	if result.code in ["PERMISSION_REQUIRED","NO_RECORDS","INVALID_ACTION","QUESTION_UNAVAILABLE","REPORT_INCOMPLETE","DAY_NOT_READY","CONFIRM_END","STALE_ACTION"]:
		return _result(original,result.code,result.text)
	if s != original: s.revision = int(original.revision)+1
	return result

func _read(s: Dictionary, kind: String) -> Dictionary:
	if kind in ["submissions","package"] and not s.report.approved: return _result(s,"PERMISSION_REQUIRED")
	var ids = []
	match kind:
		"approval":
			ids = ["approval"]
			if "approval" not in s.baseline: s.baseline.append("approval")
		"account":
			ids = ["account"]
			if "account" not in s.baseline: s.baseline.append("account")
		"backup": ids = ["backup"]
		"submissions": ids = ["submissions"]
		"package": ids = ["package"]
		"normal_jobs": ids = ["normal_jobs"]
		"tasks", "task17", "task19":
			if "tasks" not in s.baseline: s.baseline.append("tasks")
			if kind == "task19" and s.report.approved: ids = ["transfer"]
			else:
				var text = _t("TASKS",{"status":_t("HELD" if s.tasks["T-17"].held else "RUNNING" if s.tasks["T-17"].status == "running" else "SCHEDULED")})
				if kind != "task19":
					for id in s.records:
						if s.records[id].template == "run": text += "\n\n" + _know(s,id)
				return _result(s,"TASKS",text)
		"access", "staging":
			for id in s.records:
				if s.records[id].template == kind: ids.append(id)
		"files":
			s.ops.filesReadDay = s.day
			if "files" not in s.baseline: s.baseline.append("files")
			return _result(s,"FILES",_t("FILES"))
		"search": return _result(s,"SEARCH_RESULT",_t("SEARCH_OK" if s.ops.indexHealthy else "SEARCH_NOT_NORMAL"))
		"index":
			for id in s.records:
				if s.records[id].template == "index_damage": ids.append(id)
			if ids.is_empty(): return _result(s,"INDEX_NORMAL")
		_: return _result(s,"INVALID_ACTION")
	if ids.is_empty(): return _result(s,"NO_RECORDS")
	var rows = []
	for id in ids: rows.append(_know(s,id))
	if kind == "staging": rows.append(_t("COLLECTION_COUNT",{"count":s.documents.size()}))
	return _result(s,"RECORD_READ","\n\n".join(rows))

func _dialogue(s: Dictionary, id: String) -> Dictionary:
	for q in content.dialogue:
		if q.id != id: continue
		if not condition(s,q.condition): return _result(s,"QUESTION_UNAVAILABLE")
		if q.npc not in s.introduced: s.introduced.append(q.npc)
		if id not in s.statements: s.statements.append(id)
		var text = content.case.npcs[q.npc].name + "\n" + q.response
		if q.record != "": text += "\n\n" + _know(s,q.record)
		return _result(s,"DIALOGUE",text)
	return _result(s,"QUESTION_UNAVAILABLE")

func report_failure(s: Dictionary, payload: Dictionary) -> String:
	if payload.get("claim","") != content.rules.report.claim: return "REPORT_CLAIM"
	var attachments = payload.get("attachments",{})
	if not attachments is Dictionary: return "REPORT_INCOMPLETE"
	for slot in ["scope","access","collection"]:
		var id = attachments.get(slot,"")
		if id not in s.known or not s.records.has(id) or s.records[id].evidence != content.rules.report[slot]: return "REPORT_"+slot.to_upper()
	if s.records[attachments.access].facts.task != s.records[attachments.collection].facts.task: return "REPORT_LINK"
	return ""

func _report(s: Dictionary, payload: Dictionary) -> Dictionary:
	if s.report.approved: return _result(s,"REPORT_ALREADY_APPROVED")
	var failure = report_failure(s,payload)
	if failure != "": return _result(s,"REPORT_INCOMPLETE",_t(failure))
	s.report = {"approved":true,"claim":payload.claim,"attachments":payload.attachments.duplicate(true),"feedback":"approved"}
	s.eventIds.append("audit-approved")
	s.messages.append({"id":"audit-approved","npc":"oh","day":s.day,"text":_t("REPORT_APPROVED_HELD" if s.tasks["T-17"].held else "REPORT_APPROVED")})
	return _result(s,"REPORT_APPROVED_HELD" if s.tasks["T-17"].held else "REPORT_APPROVED","",[{"type":"audit.approved"}])

func missing_work(s: Dictionary) -> Array:
	var missing = []
	if s.day == 1:
		for key in ["service","account","tasks","files","approval"]:
			if key not in s.baseline: missing.append(_t("CHECK_"+key.to_upper()))
		for id in ["park","han","seo"]:
			if id not in s.introduced: missing.append(content.case.npcs[id].name + " · " + _t("INTRO"))
	elif s.day == 2:
		if s.ops.serviceVerifiedDay != s.day: missing.append(_t("CHECK_SERVICE_VERIFY"))
	elif s.day == 3:
		if s.ops.filesReadDay != s.day: missing.append(_t("CHECK_FILES"))
		if s.ops.searchVerifiedDay != s.day: missing.append(_t("CHECK_SEARCH_VERIFY"))
	elif s.day < 7:
		if s.ops.serviceVerifiedDay != s.day: missing.append(_t("CHECK_SERVICE_VERIFY"))
		if s.ops.searchVerifiedDay != s.day: missing.append(_t("CHECK_SEARCH_VERIFY"))
	return missing

func _end_day(s: Dictionary, payload: Dictionary) -> Dictionary:
	if payload.get("expectedDay",-1) != s.day: return _result(s,"STALE_ACTION")
	if not payload.get("confirmed",false): return _result(s,"CONFIRM_END")
	var missing = missing_work(s)
	if not missing.is_empty(): return _result(s,"DAY_NOT_READY","\n".join(missing))
	if s.day == 7:
		s.ended = true
		return _result(s,"PROTOTYPE_ENDED")
	var previous = int(s.day)
	var event = "night-%d" % previous
	if event in s.eventIds: return _result(s,"STALE_ACTION")
	s.eventIds.append(event)
	s.ops.backupDelay = s.ops.duplicateBackup and s.ops.primaryBackup
	var task = s.tasks["T-17"]
	if not task.held and s.maintenanceAllowed and s.ops.primaryBackup:
		s.eventIds.append("t17-run-%d" % previous)
		task.status = "running"
		for template in ["run","access","staging"]: _append(s,template,"%s-night-%d" % [template,previous],previous,1390)
		for i in range(mini(previous*2,content.case.documents.size())):
			var document = content.case.documents[i]
			if document not in s.documents: s.documents.append(document)
		s.records["staging-night-%d" % previous].facts["documents"] = s.documents.duplicate()
		s.records["staging-night-%d" % previous].body += "\n" + "\n".join(s.documents)
		if s.eventIds.filter(func(id): return id.begins_with("t17-run-")).size() == 2 and s.ops.indexHealthy:
			s.ops.indexHealthy = false
			_append(s,"index_damage","index-night-%d" % previous,previous,1390)
	s.day = previous+1
	if s.day == 2: s.messages.append({"id":"day2-work","npc":"han","day":2,"text":_t("DAY2_DELAY" if s.ops.backupDelay else "DAY2_NORMAL")})
	if s.day == 3: s.messages.append({"id":"day3-work","npc":"han","day":3,"text":_t("DAY3_NORMAL" if s.ops.indexHealthy else "DAY3_DAMAGE")})
	if s.day == 4: s.messages.append({"id":"day4-work","npc":"oh","day":4,"text":_t("DAY4_APPROVED" if s.report.approved else "DAY4_COMPARE")})
	if s.day == content.rules.lateFollowupDay:
		var text = _t("LATE_APPROVED" if s.report.approved else "LATE_HELD" if task.held else "LATE_COLLECTION")
		s.messages.append({"id":"late-followup","npc":"oh","day":s.day,"text":text})
	return _result(s,"DAY_STARTED",_t("DAY_STARTED",{"day":s.day}),[{"type":"day.started","day":s.day}])

func project(s: Dictionary, context: String = "") -> Dictionary:
	var questions = []
	for q in content.dialogue:
		if condition(s,q.condition): questions.append({"id":q.id,"npc":q.npc,"label":q.label,"channel":q.get("channel","dialogue")})
	var notes = []
	var observed_documents = []
	var collection_observed = false
	for id in s.known:
		var r = s.records[id]
		notes.append({"id":id,"title":r.title,"source":r.source,"time":_time(r.time),"body":r.body,"acquiredDay":r.acquiredDay})
		if r.template in ["staging","snapshot"]:
			collection_observed = true
			for document in r.facts.get("documents",[]):
				if document not in observed_documents: observed_documents.append(document)
	return {"day":s.day,"ended":s.ended,"device":content.case.devices.get(context,{}),"notes":notes,"questions":questions,"messages":s.messages.duplicate(true),"work":missing_work(s),"approved":s.report.approved,"held":s.tasks["T-17"].held,"indexHealthy":s.ops.indexHealthy,"backupDelay":s.ops.backupDelay,"documentCount":observed_documents.size() if collection_observed else -1,"memo":s.memo,"knowsTransfer":"E12" in s.evidence}
