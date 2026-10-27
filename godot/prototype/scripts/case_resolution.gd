class_name InvestigationResolution
extends RefCounted

const ACTIONS = ["inference", "control.request", "control.execute", "staging.isolate", "time.advance", "final.report"]
const AUDIT_KINDS = ["submissions", "application", "package", "metadata", "task19", "controls"]
const ENDINGS = {"A":"남겨진 기록","B":"차단된 경로","C":"늦은 확인","D":"도착한 자료","E":"수신 확인 대기","F":"서둘러 쓴 결론"}

static func initial() -> Dictionary:
	return {"version":2,"phase":"morning","minute":540,"links":{},"control":{"approved":false,"mode":"none"},"stagingIsolated":false,"dispatch":"pending","receipt":"none","final":{},"ending":{}}

static func supports(s: Dictionary, content: Dictionary, claim: String, ids: Array, legacy = false) -> bool:
	var rule = {}
	for row in content.rules.inferences:
		if row.id == claim: rule = row
	if rule.is_empty() or ids.size() > 6: return false
	for id in ids:
		if not id is String or id not in s.known or not s.records.has(id): return false
	if claim == "C11" and not legacy:
		for dispatch_id in ids:
			var dispatch = s.records[dispatch_id]
			if dispatch.template != "dispatch_audit": continue
			for action_id in ids:
				if effective_control(s.records[action_id],dispatch): return true
		return false
	var used = []
	for group in rule.requires:
		var found = ""
		for id in ids:
			if not id is String or id not in s.known or not s.records.has(id): return false
			if id not in used and s.records[id].template in group: found = id; break
		if found.is_empty(): return false
		used.append(found)
	if ids.any(func(id): return not id is String or id not in s.known): return false
	if claim in ["C05","C06","C07","C09"]:
		for id in used:
			if s.records[id].facts.get("package","PKG-218-R2") != "PKG-218-R2": return false
	if claim == "C08":
		if not s.records.request.facts.get("scopeWarning",false) or s.records.request.facts.get("acknowledgedBy") != "서유진": return false
	if claim == "C03" and not used.any(func(id): return s.records[id].template == "status_sample" and s.records[id].facts.get("delay",false)): return false
	if claim == "C04" and not used.any(func(id): return s.records[id].template == "files_sample" and not s.records[id].facts.get("indexHealthy",true)): return false
	if claim == "C11":
		return used.any(func(id): return s.records[id].template == "dispatch_audit" and s.records[id].facts.get("dispatch") in ["not_run","blocked"])
	if claim == "C12":
		return used.any(func(id): return s.records[id].template == "dispatch_audit" and s.records[id].facts.get("dispatch") == "sent") and used.any(func(id): return s.records[id].template == "receipt_audit" and s.records[id].facts.get("receipt") == "confirmed")
	return true

static func linked(s: Dictionary, content: Dictionary, claim: String) -> bool:
	return supports(s,content,claim,s.casework.links.get(claim,[]))

static func effective_control(action: Dictionary, dispatch: Dictionary) -> bool:
	if action.template not in ["control_audit","quarantine_audit"]: return false
	if action.time.dayOffset > dispatch.time.dayOffset or action.time.dayOffset == dispatch.time.dayOffset and action.time.minute > dispatch.time.minute: return false
	var operation = action.facts.get("operation")
	if dispatch.facts.get("dispatch") == "not_run":
		return operation == "HOLD" and dispatch.facts.get("reason") == "HELD" or operation == "ISOLATE" and dispatch.facts.get("reason") == "SOURCE_ISOLATED"
	if dispatch.facts.get("dispatch") == "blocked":
		return action.time.minute <= 1050 and operation in ["HOLD","ISOLATE"]
	return false

static func report_context(s: Dictionary) -> Dictionary:
	var w = s.casework
	return {"phase":w.phase,"minute":w.minute,"dispatch":w.dispatch,"receipt":w.receipt,"stagingIsolated":w.stagingIsolated,"controlMode":w.control.mode}

static func final_is_current(s: Dictionary) -> bool:
	return not s.casework.final.is_empty() and s.casework.final.get("context",{}) == report_context(s)

static func handle(engine, s: Dictionary, kind: String, payload: Dictionary, device: String) -> Dictionary:
	var w = s.casework
	if kind == "inference":
		var ids = payload.get("records",[])
		if not ids is Array or not supports(s,engine.content,str(payload.get("claim","")),ids): return engine._result(s,"LINK_REJECTED")
		w.links[payload.claim] = ids.duplicate()
		return engine._result(s,"LINK_SAVED")
	if kind == "time.advance":
		return advance(engine,s)
	if device != "control_console": return engine._result(s,"WRONG_DEVICE")
	if kind == "final.report":
		if s.day != 7 or w.phase in ["morning","dispatching"]: return engine._result(s,"TIME_REQUIRED")
		var fields = payload.get("fields",{})
		if not fields is Dictionary or fields.size() != engine.content.rules.finalFields.size(): return engine._result(s,"INVALID_ACTION")
		for row in engine.content.rules.finalFields:
			if not fields.get(row.id) in row.options.map(func(o): return o[0]): return engine._result(s,"INVALID_ACTION")
		w.final = {"fields":fields.duplicate(true),"known":s.known.duplicate(),"links":w.links.duplicate(true),"context":report_context(s),"evaluation":evaluate(s,engine.content,fields)}
		return engine._result(s,"FINAL_SAVED")
	if not s.report.approved: return engine._result(s,"PERMISSION_REQUIRED")
	if kind == "control.request":
		if w.control.approved: return engine._result(s,"ALREADY_DONE")
		var ids = payload.get("records",[])
		if not ids is Array or not supports(s,engine.content,"C10",ids): return engine._result(s,"CONTROL_REJECTED")
		w.control.approved = true
		w.links.C10 = ids.duplicate()
		audit(engine,s,"control_audit","control-request",{"operation":"AUTHORIZE","job":"T-19","decision":"APPROVED"})
		return engine._result(s,"CONTROL_APPROVED")
	if kind == "control.execute":
		if not w.control.approved: return engine._result(s,"CONTROL_REJECTED")
		if w.control.mode != "none": return engine._result(s,"ALREADY_DONE")
		w.control.mode = "blocked_pre_run" if w.phase == "morning" else "blocked_during"
		s.tasks["T-19"] = {"status":"held","held":true}
		audit(engine,s,"control_audit","control-execute",{"operation":"HOLD","job":"T-19","mode":w.control.mode})
		return engine._result(s,"CONTROL_APPLIED")
	if kind == "staging.isolate":
		if s.day != 7 or not linked(s,engine.content,"C02"): return engine._result(s,"CONTROL_REJECTED")
		if w.stagingIsolated: return engine._result(s,"ALREADY_DONE")
		w.stagingIsolated = true
		audit(engine,s,"quarantine_audit","staging-isolate",{"operation":"ISOLATE","path":"/staging/maintenance/PKG-218-R2"})
		return engine._result(s,"CONTROL_APPLIED")
	return engine._result(s,"INVALID_ACTION")

static func audit(engine, s: Dictionary, template: String, id: String, facts: Dictionary):
	engine._append(s,template,id,int(s.day),int(s.casework.minute))
	var record = s.records[id]
	record.facts = facts.duplicate(true)
	record.body = audit_body(facts)

static func audit_body(facts: Dictionary) -> String:
	var lines = []
	var keys = facts.keys()
	keys.sort()
	for key in keys:
		var value = facts[key]
		var text = str(int(value)) if value is float and value == int(value) else str(value)
		lines.append(str(key)+"="+text)
	return "\n".join(lines)

static func advance(engine, s: Dictionary) -> Dictionary:
	if s.day != 7: return engine._result(s,"INVALID_ACTION")
	var w = s.casework
	match w.phase:
		"morning":
			w.minute = 1050
			if w.control.mode == "blocked_pre_run" or w.stagingIsolated or s.documents.is_empty():
				w.dispatch = "not_run"
				w.receipt = "none"
				w.phase = "after"
				var reason = "HELD" if w.control.mode == "blocked_pre_run" else "SOURCE_ISOLATED" if w.stagingIsolated else "NO_SOURCE"
				audit(engine,s,"dispatch_audit","dispatch-7",{"job":"T-19","dispatch":"not_run","reason":reason,"transaction":"TX-19"})
			else:
				w.phase = "dispatching"
				s.tasks["T-19"] = {"status":"running","held":false}
		"dispatching":
			w.minute = 1051
			w.phase = "after"
			w.dispatch = "blocked" if w.control.mode == "blocked_during" or w.stagingIsolated else "sent"
			w.receipt = "unconfirmed" if w.dispatch == "sent" else "none"
			audit(engine,s,"dispatch_audit","dispatch-7",{"job":"T-19","dispatch":w.dispatch,"transaction":"TX-19","items":s.documents.size()})
		"after":
			w.minute = 1055
			w.phase = "replies"
			if w.dispatch == "sent":
				w.receipt = "confirmed"
				audit(engine,s,"receipt_audit","receipt-confirmed",{"job":"T-19","transaction":"TX-19","receipt":"confirmed","response":"202 ACCEPTED"})
		"replies": return engine._result(s,"ALREADY_DONE")
	return engine._result(s,"TIME_ADVANCED")

static func evaluate(s: Dictionary, content: Dictionary, fields: Dictionary) -> Dictionary:
	var required = {"scope":"C01","collection":"C02","submission":"C05","authorship":"C07","awareness":"C08","purpose":"C09"}
	var expected = {"scope":"violation","collection":"collected","submission":"seo","authorship":"vendor","awareness":"warning_seen","purpose":"contract_support"}
	var unsupported = []
	for key in required:
		if fields[key] != "unknown" and (fields[key] != expected[key] or not linked(s,content,required[key])): unsupported.append(key)
	var observed_dispatch = ""
	var observed_receipt = ""
	for id in s.known:
		var r = s.records[id]
		if r.template == "dispatch_audit": observed_dispatch = r.facts.dispatch
		if r.template == "receipt_audit": observed_receipt = r.facts.receipt
	var transfer = fields.transfer
	var correct_transfer = transfer == observed_dispatch and transfer in ["not_run","blocked"] or transfer == "sent" and observed_dispatch == "sent" and observed_receipt == "unconfirmed" or transfer == "received" and observed_dispatch == "sent" and observed_receipt == "confirmed" and linked(s,content,"C12")
	if transfer != "unknown" and not correct_transfer: unsupported.append("transfer")
	var material = fields.material
	if material != "unknown":
		var isolation_known = s.known.any(func(id): return s.records[id].template == "quarantine_audit")
		var staging_known = s.known.any(func(id): return s.records[id].template == "staging")
		if not (material == "isolated" and s.casework.stagingIsolated and isolation_known or material == "present" and not s.casework.stagingIsolated and staging_known or material == "empty" and s.documents.is_empty() and observed_dispatch == "not_run"): unsupported.append("material")
	var core = fields.scope == "violation" and linked(s,content,"C01") and fields.collection == "collected" and linked(s,content,"C02")
	var current_receipt_observed = s.casework.receipt == "none" or observed_receipt == s.casework.receipt
	var complete = core and fields.submission == "seo" and fields.authorship == "vendor" and linked(s,content,"C05") and linked(s,content,"C06") and linked(s,content,"C07") and linked(s,content,"C10") and correct_transfer and current_receipt_observed
	var truth = "complete" if complete else "partial" if core else "weak"
	var quality = "overclaimed" if not unsupported.is_empty() else "bounded" if fields.submission == "seo" and fields.authorship == "vendor" and fields.awareness == "warning_seen" else "undetermined"
	var receipt = s.casework.receipt
	# An unsupported report never overwrites the physical dispatch/receipt outcome.
	var ending = "F"
	if quality != "overclaimed" and truth != "weak":
		if receipt == "unconfirmed": ending = "E"
		elif receipt == "confirmed": ending = "C" if truth == "complete" and quality == "bounded" else "D"
		else: ending = "A" if truth == "complete" and quality == "bounded" else "B"
	return {"truth_level":truth,"attribution_quality":quality,"unsupported":unsupported,"id":ending,"name":ENDINGS[ending]}

static func close_case(engine, s: Dictionary) -> Dictionary:
	if s.casework.phase in ["morning","dispatching"]: return engine._result(s,"TIME_REQUIRED")
	if s.casework.final.is_empty(): return engine._result(s,"FINAL_REQUIRED")
	if not final_is_current(s): return engine._result(s,"FINAL_STALE")
	var evaluation = evaluate_report(s,engine.content)
	s.casework.final.evaluation = evaluation
	s.casework.ending = evaluation.duplicate(true)
	s.ended = true
	var lines = ["종결 문서 / "+public_ending(s),"보고 상태: 접수", "근거 검토: "+{"complete":"대조 기록 구비","partial":"일부 항목 판단 보류","weak":"인용 근거 미비"}[evaluation.truth_level]]
	if not evaluation.unsupported.is_empty():
		var labels = []
		for row in engine.content.rules.finalFields:
			if row.id in evaluation.unsupported: labels.append(row.label)
		lines.append("인용 근거 재검토 항목: "+", ".join(labels))
	lines.append("운영 처리 원문")
	for id in s.casework.final.known:
		var r = s.records[id]
		if r.template in ["dispatch_audit","receipt_audit","control_audit","quarantine_audit"]: lines.append(r.title+"\n"+r.body)
	lines.append("접수한 보고 내용")
	for row in engine.content.rules.finalFields:
		var value = s.casework.final.fields[row.id]
		for option in row.options:
			if option[0] == value: lines.append(row.label+": "+option[1])
	audit(engine,s,"final_report","final-report",{"ending":evaluation.id})
	s.records["final-report"].body = "\n".join(lines)
	engine._know(s,"final-report")
	return engine._result(s,"PROTOTYPE_ENDED",s.records["final-report"].body)

static func evaluate_report(s: Dictionary, content: Dictionary) -> Dictionary:
	var snapshot = s.duplicate(true)
	snapshot.known = s.casework.final.known
	snapshot.casework.links = s.casework.final.links
	var context = s.casework.final.get("context",report_context(s))
	for key in ["phase","minute","dispatch","receipt","stagingIsolated"]: snapshot.casework[key] = context[key]
	snapshot.casework.control.mode = context.controlMode
	return evaluate(snapshot,content,s.casework.final.fields)

static func public_ending(s: Dictionary) -> String:
	if s.casework.ending.is_empty(): return "조사 종결"
	if s.casework.ending.id == "F": return ENDINGS.F
	var observed = s.casework.final.known
	var dispatch_seen = observed.any(func(id): return s.records[id].template == "dispatch_audit")
	var receipt_seen = observed.any(func(id): return s.records[id].template == "receipt_audit" and s.records[id].facts.get("receipt") == s.casework.receipt)
	return s.casework.ending.name if dispatch_seen and (s.casework.receipt == "none" or receipt_seen) else "조사 종결"

static func valid(s: Dictionary, content: Dictionary, legacy = false) -> bool:
	var w = s.get("casework")
	if not w is Dictionary or w.keys().size() != initial().size(): return false
	if w.get("version") != (1 if legacy else 2) or w.get("phase") not in ["morning","dispatching","after","replies"]: return false
	if not w.get("stagingIsolated") is bool or not w.get("links") is Dictionary or not w.get("final") is Dictionary or not w.get("ending") is Dictionary: return false
	if not w.get("control") is Dictionary or w.control.keys().size() != 2 or not w.control.get("approved") is bool or w.control.get("mode") not in ["none","blocked_pre_run","blocked_during"]: return false
	if w.get("dispatch") not in ["pending","not_run","blocked","sent"] or w.get("receipt") not in ["none","unconfirmed","confirmed"]: return false
	var minutes = {"morning":540,"dispatching":1050,"after":1050 if w.dispatch == "not_run" else 1051,"replies":1055}
	if w.get("minute") != minutes[w.phase] or s.day < 7 and w.phase != "morning": return false
	if w.phase in ["morning","dispatching"]:
		if w.dispatch != "pending" or w.receipt != "none": return false
		if s.records.has("dispatch-7"): return false
	else:
		if s.day != 7 or w.dispatch == "pending" or not s.records.has("dispatch-7"): return false
		var receipt = "confirmed" if w.phase == "replies" else "unconfirmed"
		if w.receipt != (receipt if w.dispatch == "sent" else "none"): return false
		if w.receipt == "confirmed" and not s.records.has("receipt-confirmed"): return false
	if w.control.approved != s.records.has("control-request") or w.control.approved and not s.report.approved: return false
	if w.control.approved and not linked(s,content,"C10"): return false
	if (w.control.mode != "none") != s.records.has("control-execute") or w.control.mode != "none" and not w.control.approved: return false
	if w.control.mode == "blocked_pre_run" and w.dispatch not in ["pending","not_run"]: return false
	if w.stagingIsolated != s.records.has("staging-isolate") or w.stagingIsolated and not s.report.approved: return false
	if w.stagingIsolated and (s.day != 7 or not linked(s,content,"C02")): return false
	if w.links.size() > content.rules.inferences.size(): return false
	for claim in w.links:
		if not w.links[claim] is Array or not supports(s,content,claim,w.links[claim],legacy): return false
	for id in s.records:
		var r = s.records[id]
		var f = r.facts
		match r.template:
			"status_sample":
				if not f.get("delay") is bool or f.get("latencyMs") != (3200 if f.delay else 120) or id != "status-%d-%d" % [r.time.dayOffset,1 if f.delay else 0]: return false
				if r.body != "response_ms=%d\nservice=documents" % f.latencyMs: return false
			"files_sample":
				if not f.get("indexHealthy") is bool or f.get("originalsExist") != true or id != "files-%d-%d" % [r.time.dayOffset,1 if f.indexHealthy else 0]: return false
			"checklist_log":
				if id != "checklist-%d" % r.time.dayOffset: return false
			"control_audit":
				if id not in ["control-request","control-execute"] or f.get("job") != "T-19": return false
				if id == "control-request" and (f.get("operation") != "AUTHORIZE" or f.get("decision") != "APPROVED"): return false
				if id == "control-execute" and (f.get("operation") != "HOLD" or f.get("mode") != w.control.mode): return false
				if id == "control-execute" and w.control.mode == "blocked_pre_run" and r.time.dayOffset == 7 and r.time.minute >= 1050: return false
				if id == "control-execute" and w.control.mode == "blocked_during" and (r.time.dayOffset != 7 or r.time.minute < 1050): return false
			"quarantine_audit":
				if id != "staging-isolate" or f.get("operation") != "ISOLATE" or f.get("path") != "/staging/maintenance/PKG-218-R2": return false
			"dispatch_audit":
				if id != "dispatch-7" or r.time.dayOffset != 7 or f.get("dispatch") != w.dispatch or f.get("transaction") != "TX-19" or f.get("job") != "T-19": return false
				if w.dispatch == "not_run":
					if f.get("reason") == "HELD" and w.control.mode != "blocked_pre_run": return false
					if f.get("reason") == "SOURCE_ISOLATED" and not w.stagingIsolated: return false
					if f.get("reason") == "NO_SOURCE" and not s.documents.is_empty(): return false
					if f.get("reason") not in ["HELD","SOURCE_ISOLATED","NO_SOURCE"]: return false
				if w.dispatch == "blocked" and not (w.control.mode == "blocked_during" and s.records["control-execute"].time.minute <= 1050 or w.stagingIsolated and s.records["staging-isolate"].time.minute <= 1050): return false
				if w.dispatch == "sent" and (s.documents.is_empty() or w.stagingIsolated and s.records["staging-isolate"].time.minute <= 1050): return false
			"receipt_audit":
				if w.phase in ["morning","dispatching"]: return false
				if r.time.dayOffset != 7 or f.get("receipt") not in ["none","unconfirmed","confirmed"] or id != "receipt-"+str(f.receipt) or f.get("transaction") != "TX-19" or f.get("job") != "T-19": return false
				if f.receipt == "confirmed" and w.receipt != "confirmed" or f.receipt == "none" and w.receipt != "none" or f.receipt == "unconfirmed" and w.dispatch != "sent": return false
			"final_report":
				if id != "final-report" or not s.ended or r.time.dayOffset != 7 or f.get("ending") != w.ending.get("id"): return false
		if r.template in ["control_audit","quarantine_audit","dispatch_audit","receipt_audit"]:
			if r.body != audit_body(f): return false
	if not w.final.is_empty():
		if w.final.keys().size() != (4 if legacy else 5) or not w.final.get("fields") is Dictionary or not w.final.get("links") is Dictionary or not w.final.get("evaluation") is Dictionary or not InvestigationSaveCodec.unique_ids(w.final.get("known"),s.known): return false
		if not legacy and not valid_context(s,w.final.get("context")): return false
		if w.final.fields.size() != content.rules.finalFields.size(): return false
		for row in content.rules.finalFields:
			if w.final.fields.get(row.id) not in row.options.map(func(o): return o[0]): return false
		var snapshot = s.duplicate(true)
		snapshot.known = w.final.known
		for claim in w.final.links:
			if not w.final.links[claim] is Array or not supports(snapshot,content,claim,w.final.links[claim],legacy): return false
		if evaluate_report(s,content) != w.final.evaluation: return false
	if s.ended:
		if w.final.is_empty() or w.ending != w.final.evaluation or not s.records.has("final-report"): return false
		if not legacy and not final_is_current(s): return false
	elif not w.ending.is_empty() or s.records.has("final-report"): return false
	return true

static func valid_context(s: Dictionary, context) -> bool:
	if not context is Dictionary or context.size() != 6: return false
	var w = s.casework
	if context.get("phase") not in ["after","replies"] or context.get("dispatch") != w.dispatch or not context.get("stagingIsolated") is bool: return false
	var minute = 1055 if context.phase == "replies" else 1050 if w.dispatch == "not_run" else 1051
	if context.get("minute") != minute or minute > w.minute: return false
	if context.get("receipt") != ("none" if w.dispatch != "sent" else "confirmed" if context.phase == "replies" else "unconfirmed"): return false
	if context.get("controlMode") not in ["none",w.control.mode]: return false
	if context.controlMode != w.control.mode and s.records["control-execute"].time.minute < minute: return false
	if context.stagingIsolated and not w.stagingIsolated: return false
	if context.stagingIsolated != w.stagingIsolated and s.records["staging-isolate"].time.minute < minute: return false
	for id in w.final.known:
		var record = s.records[id]
		if record.time.dayOffset == 7 and record.time.minute > minute: return false
	return true
