class_name InvestigationSaveCodec
extends RefCounted

static func encode(state: Dictionary, content: Dictionary) -> String:
	return JSON.stringify({"format":"security-lab-investigation","schemaVersion":1,"contractVersion":1,"caseId":content.case.caseId,"contentVersion":content.case.contentVersion,"state":state},"\t")

static func decode(raw: String, content: Dictionary) -> Dictionary:
	if raw.to_utf8_buffer().size() > 262144: return {"error":"진행 파일은 256KiB 이하여야 합니다."}
	var parser = JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary: return {"error":"진행 JSON을 읽지 못했습니다."}
	var data = parser.data
	if data.get("format") != "security-lab-investigation" or data.get("schemaVersion") != 1 or data.get("contractVersion") != 1 or data.get("caseId") != content.case.caseId or data.get("contentVersion") != content.case.contentVersion:
		return {"error":"지원하지 않는 저장·사건 버전입니다. 원본은 보존됩니다."}
	var state = data.get("state")
	if state is Dictionary and not state.has("casework"):
		var legacy = content.duplicate(true)
		legacy.records = content.legacyRecords
		if not classic_valid(state,legacy,true): return {"error":"기존 진행 상태가 올바르지 않습니다. 원본은 보존됩니다."}
		state = upgrade(state,content)
	if state is Dictionary and state.get("casework") is Dictionary and state.casework.get("version") == 1:
		if not valid(state,content,true): return {"error":"기존 조사 상태가 올바르지 않습니다. 원본은 보존됩니다."}
		state = upgrade_casework(state,content)
	if not state is Dictionary or not valid(state,content): return {"error":"진행 상태·기록 참조가 올바르지 않습니다. 원본은 보존됩니다."}
	return {"state":state}

static func whole(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == int(value) and value >= low and value <= high

static func unique_ids(value, allowed: Array) -> bool:
	if not value is Array or value.size() > allowed.size(): return false
	var seen = []
	for id in value:
		if not id is String or id not in allowed or id in seen: return false
		seen.append(id)
	return true

static func classic_valid(s: Dictionary, content: Dictionary, legacy = false) -> bool:
	if s.get("schemaVersion") != 1 or not whole(s.get("day"),1,7) or not whole(s.get("revision"),0,2147483647) or not s.get("ended") is bool or not s.get("maintenanceAllowed") is bool or not s.get("memo") is String or s.memo.length() > 4000: return false
	for key in ["ops","tasks","records","report"]:
		if not s.get(key) is Dictionary: return false
	for key in ["known","evidence","baseline","introduced","statements","eventIds","documents","messages"]:
		if not s.get(key) is Array: return false
	if s.ended and s.day != 7 or s.messages.size() > 32: return false
	# Older builds appended an unbounded, unread change record on each toggle.
	var record_count = s.records.size()
	if legacy:
		for id in s.records:
			if s.records[id] is Dictionary and s.records[id].get("template") == "backup_change" and id not in s.known: record_count -= 1
	if record_count > 100: return false
	for key in ["duplicateBackup","primaryBackup","backupDelay","indexHealthy"]:
		if not s.ops.get(key) is bool: return false
	for key in ["serviceVerifiedDay","searchVerifiedDay","filesReadDay"]:
		if not whole(s.ops.get(key),0,int(s.day)): return false
	if s.ops.serviceVerifiedDay == s.day and (s.ops.duplicateBackup or s.ops.backupDelay or not s.ops.primaryBackup) or s.ops.searchVerifiedDay == s.day and not s.ops.indexHealthy: return false
	if s.tasks.keys().size() != 2: return false
	for id in ["T-17","T-19"]:
		var task = s.tasks.get(id)
		if not task is Dictionary or not task.get("held") is bool or task.get("status") not in ["scheduled","running","held"] or task.held != (task.status == "held"): return false
	if s.day == 1 and s.tasks["T-17"].status != "scheduled": return false
	var allowed_events = ["audit-approved"]
	for day in range(1,int(s.day)):
		allowed_events.append("night-%d" % day)
		allowed_events.append("t17-run-%d" % day)
		if "night-%d" % day not in s.eventIds: return false
	if not unique_ids(s.eventIds,allowed_events): return false
	if not unique_ids(s.documents,content.case.documents) or not unique_ids(s.baseline,["service","account","tasks","files","approval"]) or not unique_ids(s.introduced,content.case.npcs.keys()): return false
	var question_ids = content.dialogue.map(func(q): return q.id)
	if not unique_ids(s.statements,question_ids): return false
	for id in content.records:
		if content.records[id].initial and not s.records.has(id): return false
	for id in s.records:
		var r = s.records[id]
		if not id is String or not r is Dictionary or r.get("id") != id or not content.records.has(r.get("template")): return false
		var base = content.records[r.template]
		for key in ["title","source","evidence"]:
			if r.get(key) != base[key]: return false
		if not r.get("body") is String or r.body.length() > 8000 or not r.get("facts") is Dictionary or not r.get("time") is Dictionary or not whole(r.time.get("dayOffset"),-14,int(s.day)) or not whole(r.time.get("minute"),0,1439): return false
		for key in base.facts:
			if r.facts.get(key) != base.facts[key]: return false
		if base.initial:
			if id != r.template or r.time != base.time or r.body != base.body: return false
		elif r.template in ["run","access","staging","index_damage"]:
			var day = int(r.time.dayOffset)
			var prefix = "index" if r.template == "index_damage" else r.template
			if day < 1 or day >= s.day or id != "%s-night-%d" % [prefix,day] or "t17-run-%d" % day not in s.eventIds: return false
			if r.template == "index_damage" and day < 2: return false
			if r.template == "staging" and not unique_ids(r.facts.get("documents"),s.documents): return false
		elif r.template == "snapshot":
			if id != "snapshot-%d" % int(r.time.dayOffset) or r.time.dayOffset < 2: return false
			if r.facts.get("task") != "T-17" or r.facts.get("status") != "running" or r.facts.get("account") != content.case.tasks["T-17"].account or not unique_ids(r.facts.get("documents"),s.documents): return false
		elif r.template == "backup_change":
			if not id.begins_with("backup-change-") or not r.facts.get("duplicateEnabled") is bool: return false
			if id == "backup-change-history":
				var entries = r.facts.get("entries")
				if not entries is Array or entries.is_empty() or entries.size() > 16: return false
				var previous = -1
				for entry in entries:
					if not entry is Dictionary or entry.size() != 3 or not whole(entry.get("revision"),0,int(s.revision)) or not whole(entry.get("day"),1,int(s.day)) or not entry.get("enabled") is bool: return false
					if entry.revision <= previous: return false
					previous = entry.revision
				if r.body != InvestigationEngine.backup_journal_body(entries) or r.facts.duplicateEnabled != entries[-1].enabled or r.time.dayOffset != entries[-1].day: return false
		elif r.template in ["status_sample","files_sample","checklist_log","control_audit","dispatch_audit","receipt_audit","quarantine_audit","final_report"]:
			if r.time.dayOffset < 1: return false
		else: return false
	if not unique_ids(s.known,s.records.keys()): return false
	var evidence = []
	for id in s.known:
		var r = s.records[id]
		if not whole(r.get("acquiredDay"),maxi(1,int(r.time.dayOffset)),int(s.day)): return false
		if r.evidence != "" and r.evidence not in evidence: evidence.append(r.evidence)
	if s.evidence != evidence: return false
	if not s.report.get("approved") is bool or not s.report.get("claim") is String or not s.report.get("attachments") is Dictionary or not s.report.get("feedback") is String: return false
	if s.report.approved:
		var engine = InvestigationEngine.new(content)
		if engine.report_failure(s,s.report) != "" or "audit-approved" not in s.eventIds: return false
	elif "audit-approved" in s.eventIds or s.evidence.any(func(id): return id in ["E08","E10","E12"]): return false
	for message in s.messages:
		if not message is Dictionary or not message.get("id") is String or not content.case.npcs.has(message.get("npc")) or not whole(message.get("day"),1,int(s.day)) or not message.get("text") is String: return false
	return true

static func valid(s: Dictionary, content: Dictionary, legacy = false) -> bool:
	if not classic_valid(s,content,legacy) or not InvestigationResolution.valid(s,content,legacy): return false
	for id in s.known:
		var r = s.records[id]
		var base = content.records[r.template]
		if base.get("audit",false) and not s.report.approved: return false
		if r.acquiredDay < base.get("availableDay",1): return false
	return true

static func upgrade_casework(old: Dictionary, content: Dictionary) -> Dictionary:
	var s = old.duplicate(true)
	s.casework.version = 2
	for links in [s.casework.links,s.casework.final.get("links",{})]:
		if links.has("C11") and not InvestigationResolution.supports(s,content,"C11",links.C11): links.erase("C11")
	if not s.casework.final.is_empty(): s.casework.final.context = InvestigationResolution.report_context(s)
	compact_backup_changes(s,content)
	return JSON.parse_string(JSON.stringify(s))

static func compact_backup_changes(s: Dictionary, content: Dictionary):
	var entries = []
	for id in s.records.keys():
		var record = s.records[id]
		if record.template != "backup_change" or id == "backup-change-history" or id in s.known: continue
		var suffix = id.trim_prefix("backup-change-")
		if not suffix.is_valid_int(): continue
		entries.append({"revision":int(suffix),"day":int(record.time.dayOffset),"enabled":record.facts.duplicateEnabled})
		s.records.erase(id)
	entries.sort_custom(func(a,b): return a.revision < b.revision)
	InvestigationEngine.new(content).backup_journal(s,entries)

static func upgrade(old: Dictionary, content: Dictionary) -> Dictionary:
	var engine = InvestigationEngine.new(content)
	var s = old.duplicate(true)
	s.casework = InvestigationResolution.initial()
	s.ended = false
	s.records = {}
	for id in content.records:
		if content.records[id].initial: engine._append(s,id,id,int(content.records[id].time.dayOffset),int(content.records[id].time.minute))
	for id in old.records:
		var before = old.records[id]
		engine._append(s,before.template,id,int(before.time.dayOffset),int(before.time.minute))
		var after = s.records[id]
		if not content.records[before.template].initial:
			after.facts = before.facts.duplicate(true)
			if before.template in ["access","staging","snapshot"]: after.body += "\n"+"\n".join(before.facts.get("documents",[]))
		if id in old.known: after.acquiredDay = before.acquiredDay
	s.evidence = []
	for id in s.known:
		var evidence = s.records[id].evidence
		if evidence != "" and evidence not in s.evidence: s.evidence.append(evidence)
	var message_codes = {"handover":"HANDOVER","day2-work":"DAY2_DELAY" if s.ops.backupDelay else "DAY2_NORMAL","day3-work":"DAY3_NORMAL" if s.ops.indexHealthy else "DAY3_DAMAGE","day4-work":"DAY4_APPROVED" if s.report.approved else "DAY4_COMPARE","audit-approved":"REPORT_APPROVED","late-followup":"LATE_APPROVED"}
	for message in s.messages:
		message.text = engine._t(message_codes.get(message.id,"HANDOVER"))
	if s.report.approved:
		s.casework.links.C01 = [s.report.attachments.scope,s.report.attachments.access]
		s.casework.links.C02 = [s.report.attachments.access,s.report.attachments.collection]
	compact_backup_changes(s,content)
	return JSON.parse_string(JSON.stringify(s))
