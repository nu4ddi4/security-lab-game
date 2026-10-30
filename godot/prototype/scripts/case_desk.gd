class_name InvestigationCaseDesk
extends RefCounted

var ui
var dialog: AcceptDialog
var body: VBoxContainer
var view = 0
var at_console = false
var picks = []
var claim_picker: OptionButton
var final_picks = {}
var message: Label
var original_drafts = {}
var claim_draft = ""
var final_draft = {}
var final_submit: Button
var final_close: Button

func reset():
	if is_instance_valid(dialog): dialog.hide(); dialog.queue_free()
	view = 0
	original_drafts.clear()
	claim_draft = ""
	final_draft.clear()

func open(owner, console: bool):
	ui = owner
	at_console = console
	if is_instance_valid(dialog): dialog.hide(); dialog.queue_free()
	dialog = AcceptDialog.new()
	ui.localize_dialog(dialog,"관제 업무" if console else "대조 기록","닫기")
	ui.root.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	scroll.add_child(body)
	build()
	dialog.popup()
	fit()

func fit():
	if not is_instance_valid(dialog) or not dialog.visible: return
	var area = ui.game.safe_rect()
	dialog.size = Vector2i(mini(900,int(area.size.x)-32),mini(680,int(area.size.y)-88))
	# Embedded windows use the stretched game coordinates, not the host window's pixels.
	dialog.position = Vector2i(area.position+(area.size-Vector2(dialog.size))*.5)

func build(feedback = ""):
	ui.clear(body)
	picks.clear()
	final_picks.clear()
	var nav = OptionButton.new()
	for title in ["대조 기록","조치 요청","종결 보고","종결 문서"]: nav.add_item(title)
	nav.select(view)
	nav.item_selected.connect(func(index): view = index; build())
	body.add_child(nav)
	message = ui.label(body,feedback,"CaptionLabel")
	match view:
		0: build_links()
		1: build_control()
		2: build_final()
		3:
			if "final-report" in ui.game.state.known: ui.label(body,ui.game.state.records["final-report"].body)
			else: ui.label(body,"접수된 종결 문서가 없습니다.")
	for node in body.find_children("*","OptionButton",true,false):
		node.custom_minimum_size.y = 48 if ui.game.controls.mobile else 36
		node.fit_to_longest_item = false
		node.clip_text = true
		node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		node.get_popup().max_size = Vector2i(ui.popup_width(860),maxi(160,int(ui.game.get_viewport().get_visible_rect().size.y)-96))

func originals():
	ui.label(body,"보고서 첨부","SectionLabel")
	for i in range(4):
		var option = OptionButton.new()
		option.add_item("원문 선택")
		option.set_item_metadata(0,"")
		for record in ui.game.engine.project(ui.game.state).notes:
			option.add_item(record.title+" · "+record.source+" · "+record.time)
			option.set_item_metadata(option.item_count-1,record.id)
		var preview = Label.new()
		preview.theme_type_variation = "CaptionLabel"
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.hide()
		option.item_selected.connect(func(_index):
			var id = option.get_item_metadata(option.selected)
			var draft = original_drafts.get(view,["","","",""])
			draft[i] = id
			original_drafts[view] = draft
			preview.visible = id != ""
			if id != "":
				var record = ui.game.state.records[id]
				preview.text = record.title+"\n"+record.source+" · "+ui.game.engine._time(record.time)+"\n"+record.body
			if view == 0 and is_instance_valid(claim_picker): claim_picker.disabled = selected_records().size() < 2)
		body.add_child(option)
		body.add_child(preview)
		picks.append(option)
		var selected = original_drafts.get(view,["","","",""])[i]
		for index in range(option.item_count):
			if selected != "" and option.get_item_metadata(index) == selected:
				option.select(index)
				option.item_selected.emit(index)
				break

func selected_records() -> Array:
	var ids = []
	for option in picks:
		var id = option.get_item_metadata(option.selected)
		if id != "" and id not in ids: ids.append(id)
	return ids

func submit(kind: String, payload: Dictionary):
	var result = ui.game.dispatch({"type":kind,"deviceId":"control_console" if at_console else "","payload":payload})
	build(result.text)

func confirm(text: String, callback: Callable):
	var confirmation = ConfirmationDialog.new()
	ui.localize_dialog(confirmation,"확인")
	confirmation.dialog_text = text
	dialog.add_child(confirmation)
	confirmation.confirmed.connect(func(): confirmation.hide(); callback.call(); confirmation.queue_free())
	confirmation.canceled.connect(confirmation.queue_free)
	ui.open_dialog(confirmation,520)

func build_links():
	originals()
	claim_picker = OptionButton.new()
	claim_picker.add_item("대조 항목 선택")
	claim_picker.set_item_metadata(0,"")
	for row in ui.game.content.rules.inferences:
		claim_picker.add_item(row.label)
		claim_picker.set_item_metadata(claim_picker.item_count-1,row.id)
		if row.id == claim_draft: claim_picker.select(claim_picker.item_count-1)
	claim_picker.disabled = selected_records().size() < 2
	claim_picker.item_selected.connect(func(_index): claim_draft = claim_picker.get_item_metadata(claim_picker.selected))
	body.add_child(claim_picker)
	ui.button(body,"대조 기록 접수",func(): submit("inference",{"claim":claim_picker.get_item_metadata(claim_picker.selected),"records":selected_records()})).disabled = ui.game.state.ended
	if not ui.game.state.casework.links.is_empty():
		ui.label(body,"접수 이력","SectionLabel")
		for row in ui.game.content.rules.inferences:
			if not ui.game.state.casework.links.has(row.id): continue
			var texts = [row.label]
			for id in ui.game.state.casework.links[row.id]: texts.append(ui.game.state.records[id].title)
			ui.label(body,"\n".join(texts),"CaptionLabel")

func build_control():
	var state = ui.game.state
	if not at_console: ui.label(body,"조치 접수는 관제 단말에서 진행합니다."); return
	ui.label(body,"권한: "+("감사 업무" if state.report.approved else "일반 업무"),"CaptionLabel")
	if "transfer" in state.known:
		ui.label(body,state.records.transfer.title,"SectionLabel")
		originals()
		ui.button(body,"조치 승인 요청",func(): submit("control.request",{"records":selected_records()})).disabled = not state.report.approved or state.casework.control.approved or state.ended
		ui.button(body,"승인 조치 실행",func(): confirm("접수된 조치를 실행할까요?",func(): submit("control.execute",{}))).disabled = not state.casework.control.approved or state.casework.control.mode != "none" or state.ended
	if state.known.any(func(id): return state.records[id].template == "staging"):
		ui.label(body,"보관 위치 관리","SectionLabel")
		ui.button(body,"보관 위치 격리",func(): confirm("선택한 보관 위치를 격리할까요?",func(): submit("staging.isolate",{}))).disabled = not state.report.approved or not state.casework.links.has("C02") or state.casework.stagingIsolated or state.day != 7 or state.ended
	if state.day == 7 and not state.ended:
		ui.label(body,"업무 시각 %02d:%02d" % [int(state.casework.minute)/60,int(state.casework.minute)%60])
		ui.button(body,"업무 시각 갱신",func(): confirm("다음 정시 업무를 확인할까요?",func(): submit("time.advance",{}))).disabled = state.casework.phase == "replies"

func build_final():
	var state = ui.game.state
	if not at_console: ui.label(body,"종결 보고 접수는 관제 단말에서 진행합니다."); return
	if state.day != 7: ui.label(body,"종결 보고 접수일: 7일차"); return
	if state.casework.phase in ["morning","dispatching"]: ui.label(body,"정시 작업 확인 후 보고를 접수할 수 있습니다.","CaptionLabel")
	elif not state.casework.final.is_empty() and not InvestigationResolution.final_is_current(state): ui.label(body,"접수 후 업무 상태가 변경되었습니다. 보고 내용을 검토하고 다시 접수해 주세요.","CaptionLabel")
	var required = {"scope":["C01"],"collection":["C02"],"submission":["C05"],"authorship":["C07"],"awareness":["C08"],"purpose":["C09"],"transfer":["C10","C11","C12"],"material":["C02"]}
	var dispatch_observed = false
	var no_source_observed = false
	for id in state.known:
		var record = state.records[id]
		if record.template == "dispatch_audit":
			dispatch_observed = true
			if record.facts.get("reason") == "NO_SOURCE": no_source_observed = true
	for row in ui.game.content.rules.finalFields:
		ui.label(body,row.label,"SectionLabel")
		var picker = OptionButton.new()
		var unlocked = required[row.id].any(func(id): return state.casework.links.has(id))
		# The player first connects originals; the form never preselects a finding.
		for option in row.options:
			picker.add_item(option[1])
			picker.set_item_metadata(picker.item_count-1,option[0])
			var operational = row.id == "transfer" and dispatch_observed and option[0] != "received" or row.id == "material" and no_source_observed
			picker.set_item_disabled(picker.item_count-1,option[0] != "unknown" and not unlocked and not operational)
			if final_draft.get(row.id,state.casework.final.get("fields",{}).get(row.id,"unknown")) == option[0]: picker.select(picker.item_count-1)
		picker.disabled = state.ended
		picker.item_selected.connect(func(_index):
			final_draft[row.id] = picker.get_item_metadata(picker.selected)
			refresh_final_actions())
		body.add_child(picker)
		final_picks[row.id] = picker
	final_submit = ui.button(body,"종결 보고 접수",func(): submit("final.report",{"fields":selected_fields()}))
	final_close = ui.button(body,"조사 종결",func(): confirm("접수된 보고로 조사를 종결할까요?",func(): submit("day.end",{"expectedDay":7,"confirmed":true})))
	refresh_final_actions()

func selected_fields() -> Dictionary:
	var fields = {}
	for key in final_picks: fields[key] = final_picks[key].get_item_metadata(final_picks[key].selected)
	return fields

func refresh_final_actions():
	var state = ui.game.state
	if is_instance_valid(final_submit): final_submit.disabled = state.ended or state.casework.phase in ["morning","dispatching"]
	if is_instance_valid(final_close): final_close.disabled = state.ended or not InvestigationResolution.final_is_current(state) or selected_fields() != state.casework.final.get("fields",{})
