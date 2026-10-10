class_name InvestigationUI
extends CanvasLayer

var game: InvestigationPrototype
var root: Control
var modal: PanelContainer
var terminal_panel: PanelContainer
var dialogue_panel: PanelContainer
var briefing_panel: PanelContainer
var modal_open = false
var mode = "field"
var tabs: TabContainer
var hud: Label
var guide: Label
var prompt: Label
var prompt_panel: PanelContainer
var dot: Crosshair
var checklist: VBoxContainer
var report_hint: Label
var toast: PanelContainer
var message: Label
var source: Label
var terminal: RichTextLabel
var command_input: LineEdit
var command_list: VBoxContainer
var command_sidebar: VBoxContainer
var terminal_tools: HBoxContainer
var help_sessions = {}
var messenger_contacts: VBoxContainer
var contact_picker: OptionButton
var field_objective: PanelContainer
var new_session_button: Button
var scroll_finger = -1
var touch_scroll: Range
var terminal_buffers = {}
const ERROR_CODES = ["DEVICE_REQUIRED","UNKNOWN_COMMAND","WRONG_DEVICE","PERMISSION_REQUIRED","NO_RECORDS","INVALID_ACTION","QUESTION_UNAVAILABLE","REPORT_INCOMPLETE","DAY_NOT_READY","STALE_ACTION","SAVE_BLOCKED"]
const GOOD_WORDS = ["정상","완료","허용","승인","확인됨"]
const WARNING_WORDS = ["지연","필요","비활성","실패","오류","없음","미확인","불가","중단"]
var command_history = {}
var history_index = 0
var notes: VBoxContainer
var messenger: VBoxContainer
var contact_title: Label
var contact = "oh"
var dialogue_title: Label
var conversation: RichTextLabel
var dialogue_questions: VBoxContainer
var speaker = ""
var report: VBoxContainer
var claim: OptionButton
var attachments = {}
var work: Label
var memo: TextEdit
var ready_memo = false
var touch_setting: CheckButton
var update_setting: CheckButton
var preview_setting: CheckButton
var input_status: Label
var update_status: Label
var update_bar: ProgressBar
var update_hud: PanelContainer
var update_hud_label: Label
var update_hud_bar: ProgressBar
var update_value = -1.0
var update_check: Button
var update_download: Button
var binding_summary: Label
var settings_screen: InvestigationSettingsScreen
var settings_backdrop: Texture2D

# Aim point: a ring that closes and lights up when something can be used.
class Crosshair extends Control:
	var active = false
	func _draw():
		var color = InvestigationTheme.ACCENT if active else Color(.9,.95,1,.75)
		var center = size/2
		draw_arc(center,9.0 if active else 7.0,0,TAU,32,Color(0,0,0,.55),4.0,true)
		draw_arc(center,9.0 if active else 7.0,0,TAU,32,color,2.0,true)
		draw_circle(center,2.0,color)

func setup(controller: InvestigationPrototype):
	game = controller
	root = Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = InvestigationTheme.build(game.controls.mobile)
	get_viewport().gui_embed_subwindows = true
	var objective = PanelContainer.new()
	root.add_child(objective)
	field_objective = objective
	objective.theme_type_variation = "HudPanel"
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info = VBoxContainer.new()
	objective.add_child(info)
	hud = label(info,"","SectionLabel")
	guide = label(info,"")
	guide.add_theme_font_size_override("font_size",16)
	prompt_panel = PanelContainer.new()
	prompt_panel.theme_type_variation = "KeyCapPanel"
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.hide()
	root.add_child(prompt_panel)
	prompt = label(prompt_panel,"")
	prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color",InvestigationTheme.ACCENT)
	prompt.add_theme_font_override("font",InvestigationTheme.font(InvestigationTheme.BOLD_WEIGHT))
	dot = Crosshair.new()
	dot.size = Vector2(28,28)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)
	update_hud = PanelContainer.new()
	update_hud.theme_type_variation = "HudPanel"
	update_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_hud.hide()
	root.add_child(update_hud)
	var update_box = VBoxContainer.new()
	update_hud.add_child(update_box)
	update_hud_label = label(update_box,"","CaptionLabel")
	update_hud_bar = ProgressBar.new()
	update_hud_bar.show_percentage = false
	update_hud_bar.custom_minimum_size = Vector2(240,8)
	update_box.add_child(update_hud_bar)
	toast = PanelContainer.new()
	toast.theme_type_variation = "HudPanel"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.hide()
	root.add_child(toast)
	message = label(toast,"")
	message.custom_minimum_size.x = 380
	_build_tablet()
	_build_terminal()
	_build_dialogue()
	_build_briefing()
	fit_screen()
	refresh_settings()
	sync_memo()
	refresh()
	if game.blocked_save: open_tablet(3)
	elif game.state.day == 1 and "oh_intro" not in game.state.statements: open_briefing()
	else: close()

func panel(left: float, top: float, right: float, bottom: float) -> PanelContainer:
	var node = PanelContainer.new()
	root.add_child(node)
	node.theme_type_variation = "ModalPanel"
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.anchor_left = left
	node.anchor_top = top
	node.anchor_right = right
	node.anchor_bottom = bottom
	node.hide()
	return node

func heading(parent: Node, text: String) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	parent.add_child(row)
	row.add_child(InvestigationTheme.brand_mark())
	var title = label(row,text,"HeadingLabel")
	title.custom_minimum_size.x = 160
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button(row,"닫기" if game.controls.touch_enabled else "닫기 · Esc",close)
	return title

func _build_tablet():
	modal = panel(.14,.09,.86,.91)
	modal.name = "Tablet"
	if game.controls.mobile:
		modal.anchor_left = .02
		modal.anchor_right = .98
		modal.anchor_top = .03
		modal.anchor_bottom = .97
	var body = VBoxContainer.new()
	modal.add_child(body)
	heading(body,"휴대 단말 · 보안 운영")
	label(body,"업무 기록 · 사내 연락 · 오늘 업무","CaptionLabel")
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	for name in ["노트","메신저","발생 보고","업무","설정"]:
		var scroll = ScrollContainer.new()
		scroll.name = name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box = VBoxContainer.new()
		box.name = "Body"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation",12)
		scroll.add_child(box)
		if name == "업무":
			# The day's actions stay below the scrolling summary instead of at its far end.
			var page = VBoxContainer.new()
			page.name = name
			page.add_theme_constant_override("separation",10)
			scroll.name = "Scroll"
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			page.add_child(scroll)
			tabs.add_child(page)
		else: tabs.add_child(scroll)
	tabs.tab_changed.connect(func(index):
		if index == 4 and modal_open and game.settings != null and settings_screen == null: open_rebinding())
	label(tab(0),"확보한 원본 · 장비에서 조회한 기록과 받은 첨부만 표시됩니다.","CaptionLabel")
	notes = VBoxContainer.new()
	notes.add_theme_constant_override("separation",8)
	tab(0).add_child(notes)
	label(tab(0),"개인 메모","SectionLabel")
	memo = TextEdit.new()
	memo.custom_minimum_size.y = 160
	memo.placeholder_text = "오늘 확인한 업무 내용을 적으세요."
	tab(0).add_child(memo)
	memo.text_changed.connect(func():
		if ready_memo: game.dispatch({"type":"memo","payload":{"text":memo.text}}))
	label(tab(1),"사내 메신저 · 비동기 업무 연락과 이전 제출 자료","CaptionLabel")
	var layout = HBoxContainer.new()
	layout.add_theme_constant_override("separation",20)
	tab(1).add_child(layout)
	contact_picker = OptionButton.new()
	for id in game.content.case.npcs:
		contact_picker.add_item(game.content.case.npcs[id].name+" · "+game.content.case.npcs[id].role)
		contact_picker.set_item_metadata(contact_picker.item_count-1,id)
	tab(1).add_child(contact_picker)
	tab(1).move_child(contact_picker,1)
	contact_picker.item_selected.connect(func(index): contact = contact_picker.get_item_metadata(index); refresh_messenger())
	messenger_contacts = VBoxContainer.new()
	messenger_contacts.custom_minimum_size.x = 210
	layout.add_child(messenger_contacts)
	for id in game.content.case.npcs:
		var npc = game.content.case.npcs[id]
		button(messenger_contacts,npc.name+"\n"+npc.role,func(): contact = id; refresh_messenger()).alignment = HORIZONTAL_ALIGNMENT_LEFT
	var thread = VBoxContainer.new()
	thread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(thread)
	contact_title = label(thread,"","HeadingLabel")
	messenger = VBoxContainer.new()
	messenger.add_theme_constant_override("separation",12)
	thread.add_child(messenger)
	report = tab(2)
	label(report,"승인 범위와 실제 행동을 대조하고, 확인한 원본을 직접 첨부하세요. 실행 계정과 실제 사람, 내부 수집과 외부 반출은 구분합니다.","CaptionLabel")
	var claim_box = card_box(report)
	label(claim_box,"주장","SectionLabel")
	claim = OptionButton.new()
	claim.add_item("주장 선택")
	for item in game.content.rules.claims:
		claim.add_item(item.label)
		claim.set_item_metadata(claim.item_count-1,item.id)
	claim_box.add_child(claim)
	var evidence_box = card_box(report)
	label(evidence_box,"근거 원본","SectionLabel")
	report_hint = label(evidence_box,"아직 첨부할 원본이 없습니다. 장비에서 원본을 조회하면 이곳에서 선택할 수 있습니다.","CaptionLabel")
	for slot in ["scope","access","collection"]:
		label(evidence_box,{"scope":"허용 범위 근거","access":"실제 접근 근거","collection":"실제 수집 근거"}[slot])
		var option = OptionButton.new()
		attachments[slot] = option
		evidence_box.add_child(option)
	button(report,"발생 보고 제출",submit_report,"PrimaryButton")
	var summary = PanelContainer.new()
	summary.theme_type_variation = "CardPanel"
	tab(3).add_child(summary)
	work = label(summary,"")
	var checks = PanelContainer.new()
	checks.theme_type_variation = "CardPanel"
	tab(3).add_child(checks)
	checklist = VBoxContainer.new()
	checklist.add_theme_constant_override("separation",6)
	checks.add_child(checklist)
	var actions = tabs.get_child(3)
	button(actions,"오늘 업무 종료",end_day,"PrimaryButton")
	var more = HFlowContainer.new()
	more.add_theme_constant_override("h_separation",8)
	more.add_theme_constant_override("v_separation",8)
	actions.add_child(more)
	button(more,"업무 배경과 점검 방법",open_briefing)
	button(more,"진행 내보내기",func(): file_dialog(true))
	button(more,"진행 가져오기",func(): file_dialog(false))
	new_session_button = button(more,"새 업무 시작",func(): confirm("현재 진행을 보관하고 새 업무를 시작할까요?",game.new_game),"DangerButton")
	button(tab(4),"설정 열기",open_rebinding,"PrimaryButton")

func _build_terminal():
	terminal_panel = panel(.08,.09,.92,.91)
	terminal_panel.name = "Terminal"
	if game.controls.mobile:
		terminal_panel.anchor_left = .02
		terminal_panel.anchor_right = .98
		terminal_panel.anchor_top = .02
		terminal_panel.anchor_bottom = .98
	var body = VBoxContainer.new()
	terminal_panel.add_child(body)
	source = heading(body,"")
	if game.controls.mobile:
		button(source.get_parent(),"키보드 닫기",func(): command_input.release_focus(); hide_keyboard())
	var layout = HBoxContainer.new()
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation",20)
	body.add_child(layout)
	var session = VBoxContainer.new()
	session.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(session)
	terminal = RichTextLabel.new()
	terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terminal.custom_minimum_size = Vector2(0,80 if game.controls.mobile else 180)
	terminal.selection_enabled = not game.controls.mobile
	terminal.bbcode_enabled = true
	terminal.add_theme_color_override("default_color",Color(.8,.92,.88))
	terminal.add_theme_stylebox_override("normal",InvestigationTheme.box(InvestigationTheme.INSET,InvestigationTheme.BORDER,8,12))
	session.add_child(terminal)
	var row = HBoxContainer.new()
	session.add_child(row)
	var shell_prompt = label(row,"sec.ops >","SectionLabel")
	shell_prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	shell_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shell_prompt.custom_minimum_size.x = 115 if game.controls.mobile else 100
	command_input = LineEdit.new()
	command_input.placeholder_text = "명령 입력 · help로 도움말"
	command_input.max_length = 200
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(command_input)
	command_input.text_submitted.connect(func(_text): execute_command())
	command_input.gui_input.connect(_terminal_input)
	button(row,"실행",execute_command,"PrimaryButton")
	var tools = HBoxContainer.new()
	terminal_tools = tools
	session.add_child(tools)
	button(tools,"복사",func(): DisplayServer.clipboard_set(terminal.get_parsed_text()))
	button(tools,"지우기",clear_terminal)
	if not game.controls.mobile:
		var hint = label(tools,"↑↓ 이력 · Tab 자동완성 · Ctrl+L 지우기","CaptionLabel")
		hint.autowrap_mode = TextServer.AUTOWRAP_OFF
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button(tools,"이전",func(): recall_command(-1))
	button(tools,"다음",func(): recall_command(1))
	command_sidebar = VBoxContainer.new()
	command_sidebar.custom_minimum_size.x = 340
	layout.add_child(command_sidebar)
	label(command_sidebar,"이 장비의 명령","HeadingLabel")
	label(command_sidebar,"선택하면 입력됩니다. Enter로 실행하세요.","CaptionLabel")
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	command_sidebar.add_child(scroll)
	command_list = VBoxContainer.new()
	command_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_list.add_theme_constant_override("separation",4)
	scroll.add_child(command_list)

func _build_dialogue():
	dialogue_panel = panel(.16,.56,.84,.96)
	dialogue_panel.name = "Dialogue"
	if game.controls.mobile:
		dialogue_panel.anchor_left = .03
		dialogue_panel.anchor_right = .97
		dialogue_panel.anchor_top = .46
	var body = VBoxContainer.new()
	dialogue_panel.add_child(body)
	dialogue_title = heading(body,"")
	conversation = RichTextLabel.new()
	conversation.custom_minimum_size.y = 64 if game.controls.mobile else 150
	conversation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conversation.bbcode_enabled = true
	conversation.selection_enabled = not game.controls.mobile
	body.add_child(conversation)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 72 if game.controls.mobile else 64
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	dialogue_questions = VBoxContainer.new()
	dialogue_questions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(dialogue_questions)

func _build_briefing():
	briefing_panel = panel(.2,.1,.8,.9)
	briefing_panel.name = "Briefing"
	if game.controls.mobile:
		briefing_panel.anchor_left = .08
		briefing_panel.anchor_right = .92
		briefing_panel.anchor_top = .04
		briefing_panel.anchor_bottom = .96
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",18)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	briefing_panel.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var title = HBoxContainer.new()
	title.add_theme_constant_override("separation",14)
	title.add_child(InvestigationTheme.brand_mark())
	var headline = label(title,game.content.case.briefing.heading,"TitleLabel")
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(title)
	for key in ["background","assignment","method","first"]:
		var card = PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		body.add_child(card)
		label(card,game.content.case.briefing[key])
	button(body,"현장 점검 시작",close,"PrimaryButton")
	button(body,"휴대 단말에서 업무 확인",func(): open_tablet(3))

func card_box(parent: Node) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	parent.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	panel.add_child(box)
	return box

func tab(index: int) -> VBoxContainer:
	return tabs.get_child(index).find_child("Body",true,false)

func label(parent: Node, text: String, variation = "") -> Label:
	var node = Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not variation.is_empty(): node.theme_type_variation = variation
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable, variation = "") -> Button:
	var node = Button.new()
	node.text = LabInputBindings.hint(text)
	if text.contains("Esc"): node.set_meta("binding_text",text)
	if not variation.is_empty(): node.theme_type_variation = variation
	if game.controls.mobile: node.custom_minimum_size.y = 48
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func clear(node: Node):
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func sync_memo():
	ready_memo = false
	memo.text = game.state.memo
	ready_memo = true

func reset_session():
	help_sessions.clear()
	terminal_buffers.clear()
	command_history.clear()
	contact = "oh"
	close()
	if game.state.day == 1 and "oh_intro" not in game.state.statements: open_briefing()

func guide_info() -> Dictionary:
	var state = game.state
	if state.ended: return {"title":"점검 종료","text":"휴대 단말에서 기록과 진행 파일을 확인하세요.","target":""}
	if state.day != 1:
		if investigation_assigned() and not state.report.approved:
			for item in [["E01","approval_archive","승인 범위 원본 확인"],["E06","server_console","작업의 실제 접근 기록 확인"],["E07","server_console","임시 보관 목록 확인"]]:
				if item[0] not in state.evidence: return {"title":"조사 업무 · 팀장 지시","text":item[2]+" 후 발생 보고에 원본을 첨부하세요.","target":item[1]}
			return {"title":"조사 업무 · 발생 보고","text":"휴대 단말의 발생 보고에서 승인 범위·실제 접근·수집 원본을 첨부하세요.","target":""}
		if state.report.approved and "E08" not in state.evidence: return {"title":"확대 조사 · 제출 감사","text":"관제 단말에서 제출·적용 감사 원본을 확인하세요.","target":"control_console"}
		if state.report.approved and "E10" not in state.evidence: return {"title":"확대 조사 · 보관 패키지","text":"관제 단말에서 보관 패키지를 확인하세요.","target":"control_console"}
		if state.report.approved and "E09" not in state.evidence: return {"title":"확대 조사 · 정상 작업 비교","text":"업무 PC의 정상 배포 기록과 감사 원본을 대조하세요.","target":"project_pc"}
		var remaining = game.engine.missing_work(state)
		var target = "project_pc" if state.day == 3 and (state.ops.filesReadDay != state.day or state.ops.searchVerifiedDay != state.day) else "server_console" if state.ops.serviceVerifiedDay != state.day else "project_pc" if state.ops.searchVerifiedDay != state.day else ""
		if remaining.is_empty(): target = ""
		return {"title":"%d일차 · 운영 점검" % state.day,"text":remaining[0] if not remaining.is_empty() else "오늘의 운영 확인을 마쳤습니다. 휴대 단말에서 기록·연락을 확인하고 업무를 종료하세요.","target":target}
	if "oh_intro" not in state.statements: return {"title":"1 / 8 · 담당 업무 인계","text":"눈앞의 보안팀장 오세진과 대화하세요. 가까이서 %s 대화를 시작합니다." % ("상호작용 버튼을 눌러" if game.controls.touch_enabled else "F를 눌러"),"target":"oh"}
	if "park_intro" not in state.statements: return {"title":"2 / 8 · 서버 담당자","text":"서버실 입구 옆의 박도윤에게 운영 업무를 인계받으세요.","target":"park"}
	for item in [["service","status","자료 서비스"],["account","inspect account","실행 계정"],["tasks","logs tasks","자동 작업"]]:
		if item[0] not in state.baseline: return {"title":"3 / 8 · 서버 기준 상태","text":"서버실 운영 랙의 서버 단말에서 %s 상호작용을 시작하세요. %s을 확인합니다. 명령은 help로 확인하세요." % ["상호작용 버튼으로" if game.controls.touch_enabled else "F로",item[2]],"target":"server_console"}
	if "han_intro" not in state.statements: return {"title":"4 / 8 · 프로젝트 담당자","text":"오른쪽 업무 구역의 한지우에게 LUMEN 자료를 인계받으세요.","target":"han"}
	if "files" not in state.baseline: return {"title":"5 / 8 · 원본 자료 확인","text":"오른쪽 업무 PC에서 실제 원본 파일을 확인하세요. 명령은 help로 확인하세요.","target":"project_pc"}
	if "seo_intro" not in state.statements: return {"title":"6 / 8 · 정비 담당자","text":"업무 구역의 서유진에게 유지보수 범위를 확인하세요. 이전 제출 자료는 휴대 단말의 메신저에서 볼 수 있습니다.","target":"seo"}
	if "approval" not in state.baseline: return {"title":"7 / 8 · 승인 범위 원본","text":"승인서 보관함에서 W-218 원본을 확인하세요. 명령은 help로 확인하세요. 확인한 원본은 휴대 단말의 노트에 자동으로 모입니다.","target":"approval_archive"}
	return {"title":"8 / 8 · 첫날 점검 완료","text":"%s 휴대 단말을 열어 노트와 메신저를 확인하세요. 업무 탭의 ‘오늘 업무 종료’로 다음 날을 시작합니다." % ("화면의 버튼으로" if game.controls.touch_enabled else "Tab으로"),"target":""}

func refresh_settings():
	if update_status == null: return
	touch_setting.set_pressed_no_signal(game.controls.touch_enabled)
	update_setting.set_pressed_no_signal(game.controls.automatic_updates)
	preview_setting.set_pressed_no_signal(game.beta_preview())
	input_status.text = "터치와 키보드를 함께 사용할 수 있습니다." if game.controls.touch_enabled else "키보드·마우스 조작"
	if game.controls.keyboard_seen: input_status.text += " · 키보드 입력 감지됨"
	if is_instance_valid(binding_summary): binding_summary.text = LabInputBindings.summary(true)
	update_status.text = game.updates.status
	update_bar.visible = update_value >= 0.0
	update_bar.value = maxf(update_value,0.0)*100.0
	update_check.disabled = game.updater.state in ["checking","downloading","preparing"] if game.updater!=null else game.updates.busy
	update_download.visible = game.updater.state in ["available","ready"] if game.updater!=null else not game.updates.download_url.is_empty()

# value in 0..1 while a download runs, negative otherwise
func update_progress(value: float):
	update_value = value
	update_hud_label.text = "업데이트 다운로드 · %d%%" % roundi(maxf(value,0.0)*100.0)
	update_hud_bar.value = maxf(value,0.0)*100.0
	update_hud.visible = value >= 0.0 and not modal_open
	refresh_settings()

# Bottom centre of the safe area; the chip is sized to its text first.
func place_prompt():
	prompt_panel.reset_size()
	var area = game.safe_rect()
	prompt_panel.position = Vector2(area.position.x+(area.size.x-prompt_panel.size.x)/2,area.end.y-prompt_panel.size.y-28)

func set_prompt_visible(value: bool):
	prompt.visible = value
	prompt_panel.visible = value

func objective_info() -> Dictionary:
	var objective = guide_info()
	if game.detailed_world and game.targets.has(objective.get("target","")):
		var target = game.targets[objective.target]
		var zone = game.content.case.devices.get(objective.target,{}).get("zone",game.content.case.npcs.get(objective.target,{}).get("role",""))
		objective.text += "\n%s · %.1fm"%[zone,game.player.global_position.distance_to(target.global_position)]
	return objective

func refresh():
	var view = game.engine.project(game.state,game.context)
	var objective = objective_info()
	hud.text = "%d일차 · %s" % [view.day,objective.title]
	guide.text = LabInputBindings.hint(objective.text)
	field_objective.reset_size.call_deferred()
	source.text = view.device.get("label","현장 단말")+" · 운영 점검 세션"
	clear(notes)
	if view.notes.is_empty(): label(notes,"아직 확보한 원본이 없습니다. 현장 장비에서 원본을 조회하거나 메신저의 첨부를 확인하세요.")
	for record in view.notes:
		if not investigation_assigned() and game.state.records[record.id].template in ["access","staging","submissions","package","snapshot","transfer"]: continue
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		notes.add_child(row)
		var open_note = button(row,record.title+" · "+record.source,func(): notice(record.title+"\n"+record.source+" · "+record.time+" · 확보 %d일차\n" % record.acquiredDay+record.body),"TileButton")
		open_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open_note.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button(row,"메모에 인용",func(): memo.text += "\n["+record.title+" · "+record.source+" · "+record.time+"]\n")
	report_hint.visible = view.notes.is_empty()
	for slot in attachments:
		var option = attachments[slot]
		var selected = option.get_item_metadata(option.selected) if option.selected >= 0 and option.item_count else null
		option.clear()
		option.add_item("원본 선택")
		for record in view.notes:
			option.add_item(record.title)
			option.set_item_metadata(option.item_count-1,record.id)
			if record.id == selected: option.select(option.item_count-1)
	refresh_dialogue()
	refresh_messenger()
	refresh_commands()
	var assigned = investigation_assigned()
	tabs.set_tab_hidden(2,not assigned)
	new_session_button.text = "새 조사" if assigned else "새 업무 시작"
	work.text = objective.title+"\n"+objective.text
	clear(checklist)
	label(checklist,"오늘의 필수 운영 확인","SectionLabel")
	if view.work.is_empty(): label(checklist,"✓  오늘의 필수 확인을 모두 마쳤습니다.")
	for line in view.work: label(checklist,"○  "+line)
	if assigned: work.text += "\n\n발생 보고: "+("승인됨 · 감사 권한 유지" if view.approved else "미승인")
	if assigned: work.text += "\n확인한 내부 수집 문서: "+("미확인" if view.documentCount < 0 else "%d개 · 반출과 별도" % view.documentCount)
	if view.ended: work.text += "\n\n"+game.engine._t("PROTOTYPE_ENDED")

func refresh_dialogue():
	clear(dialogue_questions)
	if speaker == "": return
	var questions = game.engine.project(game.state).questions
	for question in questions:
		if question.npc == speaker and question.channel == "dialogue" and question_visible(question.id):
			var choice = button(dialogue_questions,question.label,ask.bind(question.id),"ChoiceButton")
			choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if dialogue_questions.get_child_count() == 0: label(dialogue_questions,"지금 더 물어볼 내용이 없습니다.")

# The reply starts with the speaker's name; show it as a label, never as markup.
func speech(text: String) -> String:
	var safe = text.replace("[","[lb]")
	var lines = safe.split("\n",true,1)
	var name = game.content.case.npcs.get(speaker,{}).get("name","")
	if lines.size() == 2 and not name.is_empty() and lines[0].strip_edges() == name:
		return "[color=#%s][b]%s[/b][/color]\n%s" % [InvestigationTheme.ACCENT.to_html(false),lines[0],lines[1]]
	return safe

func ask(id: String):
	conversation.text = speech(game.dispatch({"type":"dialogue","payload":{"id":id}}).text)

func bubble(sender: String, text: String, outgoing = false):
	var row = HBoxContainer.new()
	messenger.add_child(row)
	if outgoing:
		var space = Control.new()
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(space)
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.theme_type_variation = "OutgoingBubblePanel" if outgoing else "BubblePanel"
	row.add_child(card)
	var content = VBoxContainer.new()
	card.add_child(content)
	if not sender.is_empty():
		var from = label(content,sender,"CaptionLabel")
		if outgoing: from.add_theme_color_override("font_color",InvestigationTheme.ACCENT)
	label(content,text)

func refresh_messenger():
	clear(messenger)
	var npc = game.content.case.npcs[contact]
	contact_title.text = npc.name+" · "+npc.role
	var ids = game.content.case.npcs.keys()
	for i in messenger_contacts.get_child_count():
		messenger_contacts.get_child(i).theme_type_variation = "PrimaryButton" if ids[i] == contact else ""
	var count = 0
	for msg in game.state.messages:
		if msg.npc == contact:
			bubble("%d일차 · %s" % [msg.day,npc.name],msg.text)
			count += 1
	for question in game.content.dialogue:
		if question.npc == contact and question.get("channel","dialogue") == "messenger" and question.id in game.state.statements:
			bubble("나",question.label,true)
			bubble(npc.name,question.response)
			if question.record != "" and question.record in game.state.known:
				var record = game.state.records[question.record]
				button(messenger,"첨부 · "+record.title,func(): notice(record.title+"\n"+record.source+"\n"+record.body),"TileButton")
			count += 1
	if count == 0: bubble("","아직 받은 메시지가 없습니다. 담당자와 직접 대화하려면 현장에서 만나세요.")
	for question in game.engine.project(game.state).questions:
		if question.npc == contact and question.channel == "messenger" and question.id not in game.state.statements and question_visible(question.id):
			button(messenger,question.label,func(): game.dispatch({"type":"dialogue","payload":{"id":question.id}}),"PrimaryButton")

func available_commands() -> Array:
	var rows = []
	for row in game.content.commands:
		if game.context in row.devices and game.engine.command_visible(game.state,row): rows.append(row)
	return rows

func refresh_commands():
	clear(command_list)
	command_sidebar.visible = help_sessions.get(game.context,false) and get_viewport().get_visible_rect().size.x >= 1100
	if not help_sessions.get(game.context,false): return
	var category = ""
	for row in available_commands():
		if row.get("category","조회") != category:
			category = row.get("category","조회")
			label(command_list,category,"SectionLabel")
		var pick = button(command_list,row.text,fill_command.bind(row.text),"TileButton")
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var detail = label(command_list,row.get("description",""),"CaptionLabel")
		detail.custom_minimum_size.x = 300

func fill_command(text: String):
	command_input.text = text
	command_input.caret_column = text.length()
	if not game.controls.mobile: command_input.grab_focus()

func execute_command():
	if mode != "terminal": return
	var text = command_input.text.strip_edges()
	command_input.clear()
	if text.is_empty(): return
	if not command_history.has(game.context): command_history[game.context] = []
	var history = command_history[game.context]
	if history.is_empty() or history[-1] != text: history.append(text)
	if history.size() > 80: history.pop_front()
	history_index = history.size()
	if text.to_lower() == "help":
		help_sessions[game.context] = true
		refresh_commands()
	match text.to_lower():
		"clear", "cls": clear_terminal()
		"history":
			var rows = []
			for i in range(history.size()): rows.append("%d  %s" % [i+1,history[i]])
			print_output(text,"\n".join(rows))
		_: game.command(text)
	if not game.controls.mobile: command_input.grab_focus()

func _terminal_input(event: InputEvent):
	if not event is InputEventKey or not event.pressed: return
	if event.keycode in [KEY_UP,KEY_DOWN]:
		recall_command(-1 if event.keycode == KEY_UP else 1)
		command_input.accept_event()
	elif event.keycode == KEY_TAB:
		if not help_sessions.get(game.context,false):
			print_output("도움말","help를 입력하면 장비 명령을 확인할 수 있습니다.")
			command_input.accept_event()
			return
		var prefix = command_input.text.to_lower()
		var options = available_commands().filter(func(row): return row.text.to_lower().begins_with(prefix))
		if options.size() == 1:
			command_input.text = options[0].text
			command_input.caret_column = command_input.text.length()
		elif not options.is_empty(): print_output("자동완성","\n".join(options.map(func(row): return row.text)))
		command_input.accept_event()
	elif event.ctrl_pressed and event.keycode == KEY_L:
		clear_terminal()
		command_input.accept_event()

func recall_command(direction: int):
	var history = command_history.get(game.context,[])
	history_index = clampi(history_index+direction,0,history.size())
	command_input.text = history[history_index] if history_index < history.size() else ""
	command_input.caret_column = command_input.text.length()

func clear_terminal():
	terminal_buffers[game.context] = []
	render_terminal()

# kind is "output" or "error"; errors are shown in the warning colour.
func print_output(command: String, text: String, kind = "output"):
	var log = terminal_buffers.get(game.context,[])
	log.append({"kind":"command","text":command})
	log.append({"kind":kind,"text":text})
	var size = 0
	for entry in log: size += entry.text.length()
	while size > 24000 and log.size() > 2: size -= log.pop_front().text.length()
	terminal_buffers[game.context] = log
	render_terminal()

func render_terminal():
	terminal.text = terminal_markup(terminal_buffers.get(game.context,[]))
	terminal.scroll_to_line(maxi(0,terminal.get_line_count()-1))

static func color_tag(color: Color) -> String:
	return "[color=#%s]" % color.to_html(false)

static func terminal_markup(log: Array) -> String:
	var blocks = []
	for entry in log:
		if entry.kind == "command" and blocks.size() > 1: blocks.append("")
		var lines = String(entry.text).split("\n")
		var markup = []
		match entry.kind:
			"command": markup = [color_tag(InvestigationTheme.ACCENT)+"[b]sec.ops >[/b][/color] [b]"+String(entry.text).replace("[","[lb]")+"[/b]"]
			"banner":
				for i in lines.size():
					var line = lines[i].replace("[","[lb]")
					markup.append(color_tag(InvestigationTheme.ACCENT)+"[b]"+line+"[/b][/color]" if i == 0 else color_tag(InvestigationTheme.TEXT_DIM)+line+"[/color]" if not line.is_empty() else "")
			"error":
				for line in lines: markup.append(color_tag(InvestigationTheme.WARNING)+line.replace("[","[lb]")+"[/color]")
			_:
				for i in lines.size(): markup.append(style_line(lines[i],i == 0 and lines.size() > 1))
		blocks.append("\n".join(markup))
	return "\n".join(blocks)

# "name — description" listings and "label: value" rows get their own colours.
static func style_line(line: String, heading: bool) -> String:
	var safe = line.replace("[","[lb]")
	if safe.strip_edges().is_empty(): return ""
	var dash = safe.find(" — ")
	if dash > 0 and dash < 40: return color_tag(Color(.72,1,.9))+safe.left(dash)+"[/color] "+color_tag(InvestigationTheme.TEXT_FAINT)+"—[/color] "+safe.substr(dash+3)
	var colon = safe.find(": ")
	if colon > 0 and colon < 24 and not safe.left(colon).contains(" / "):
		var value = safe.substr(colon+2)
		var tone = InvestigationTheme.TEXT
		if GOOD_WORDS.any(func(word): return value.contains(word)): tone = InvestigationTheme.TERMINAL_TEXT
		if WARNING_WORDS.any(func(word): return value.contains(word)): tone = InvestigationTheme.WARNING
		return color_tag(InvestigationTheme.TEXT_DIM)+safe.left(colon)+":[/color] "+color_tag(tone)+value+"[/color]"
	return "[b]"+safe+"[/b]" if heading and safe.length() < 40 else safe

func _show(next_mode: String, window: Control):
	if is_instance_valid(settings_screen): settings_screen.close_editor()
	if mode == "field" and DisplayServer.get_name() != "headless":
		settings_backdrop = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	scroll_finger = -1
	touch_scroll = null
	hide_keyboard()
	game.release_speaker()
	for item in [modal,terminal_panel,dialogue_panel,briefing_panel]: item.hide()
	mode = next_mode
	modal_open = true
	window.show()
	field_objective.visible = next_mode == "dialogue"
	toast.hide()
	update_hud.hide()
	game.player.set_enabled(false)
	game.controls.release_touches()
	for key in ["forward","back","left","right","sprint","crouch","jump"]: Input.action_release(key)
	set_prompt_visible(false)
	dot.hide()

func open_tablet(index = 3):
	_show("tablet",modal)
	tabs.current_tab = 3 if index == 2 and not investigation_assigned() else index
	if index == 4 and settings_screen == null: open_rebinding()
	refresh()

func open_briefing(): _show("briefing",briefing_panel)

func open_terminal():
	_show("terminal",terminal_panel)
	refresh()
	if not terminal_buffers.has(game.context):
		var device = game.content.case.devices[game.context]
		terminal_buffers[game.context] = [{"kind":"banner","text":"SECURITY OPERATIONS / "+device.label+"\n접속 사용자: sec.ops · "+device.zone+"\n\n"+device.description+"\n\n명령을 입력하세요. help를 입력하면 이 장비의 도움말이 표시됩니다."}]
	render_terminal()
	history_index = command_history.get(game.context,[]).size()
	if not game.controls.mobile: command_input.grab_focus()

func open_dialogue(id: String):
	speaker = id
	_show("dialogue",dialogue_panel)
	var npc = game.content.case.npcs[id]
	dialogue_title.text = npc.name+" · "+npc.role
	conversation.text = "무엇을 확인하시겠어요?"
	refresh_dialogue()
	game.frame_speaker(id)

func close():
	if is_instance_valid(settings_screen) and settings_screen.visible:
		settings_screen.close_editor()
		return
	if game.blocked_save: return
	var focused = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	hide_keyboard()
	scroll_finger = -1
	touch_scroll = null
	for item in [modal,terminal_panel,dialogue_panel,briefing_panel]: item.hide()
	game.release_speaker()
	mode = "field"
	modal_open = false
	game.player.set_enabled(true)
	field_objective.show()
	update_hud.visible = update_value >= 0.0
	toast.visible = not message.text.is_empty()
	dot.show()
	prompt.text = ""
	set_prompt_visible(false)

func toggle():
	if modal_open: close()
	else: open_tablet()

# Built-in dialogs would say "Please Confirm…" and "OK"; keep them in the game's language and size.
func localize_dialog(dialog: AcceptDialog, title: String, ok = "확인", cancel = "취소"):
	dialog.title = title
	dialog.ok_button_text = ok
	dialog.dialog_autowrap = true
	if dialog is ConfirmationDialog: dialog.cancel_button_text = cancel

func popup_width(wanted: int) -> int:
	return mini(wanted,int(get_viewport().get_visible_rect().size.x)-40)

# Wrapped text is measured at the final width first, so the dialog fits its content.
func open_dialog(dialog: Window, wanted: int):
	var width = popup_width(wanted)
	dialog.min_size = Vector2i(width,0)
	dialog.popup_centered(Vector2i(width,0))
	await get_tree().process_frame
	if is_instance_valid(dialog):
		dialog.reset_size()
		dialog.move_to_center()

func notice(text: String):
	message.text = text.left(180)
	toast.visible = not modal_open
	toast.reset_size.call_deferred()
	var previous = message.text
	get_tree().create_timer(6).timeout.connect(func():
		if is_instance_valid(message) and message.text == previous:
			message.text = ""
			toast.hide())
	if modal_open or text.length() > 220:
		var popup = AcceptDialog.new()
		localize_dialog(popup,"조사 기록" if investigation_assigned() else "업무 알림")
		popup.dialog_text = text
		root.add_child(popup)
		popup.confirmed.connect(popup.queue_free)
		popup.canceled.connect(popup.queue_free)
		open_dialog(popup,560)

func confirm(text: String, callback: Callable):
	var dialog = ConfirmationDialog.new()
	localize_dialog(dialog,"확인")
	dialog.dialog_text = text
	root.add_child(dialog)
	dialog.confirmed.connect(func(): callback.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	open_dialog(dialog,520)

func submit_report():
	var selected = {}
	for slot in attachments:
		var option = attachments[slot]
		selected[slot] = option.get_item_metadata(option.selected) if option.selected > 0 else ""
	var value = claim.get_item_metadata(claim.selected) if claim.selected > 0 else ""
	notice(game.dispatch({"type":"report","payload":{"claim":value,"attachments":selected}}).text)

func end_day():
	var day = game.state.day
	var text = game.engine._t("CONFIRM_END")
	if day == 7: text = game.engine._t("PROTOTYPE_ENDED_KNOWN" if "E12" in game.state.evidence else "PROTOTYPE_ENDED")+"\n조사로 돌아가려면 취소하세요."
	confirm(text,func(): notice(game.dispatch({"type":"day.end","payload":{"expectedDay":day,"confirmed":true}}).text))

func file_dialog(exporting: bool):
	var dialog = FileDialog.new()
	localize_dialog(dialog,"진행 내보내기" if exporting else "진행 가져오기","저장" if exporting else "열기")
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	# The system picker speaks the player's language; other platforms keep the in-game one.
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.json ; 잔여 권한 진행"])
	if exporting: dialog.current_file = "residual-permissions-save.json"
	root.add_child(dialog)
	dialog.file_selected.connect(func(path): game.transfer_file(path,exporting); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(800,550))

func _process(_delta):
	if game == null: return
	if game.controls.mobile and mode == "terminal" and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		var keyboard = DisplayServer.virtual_keyboard_get_height()
		var height = maxf(1,DisplayServer.window_get_size().y)
		terminal.custom_minimum_size.y = 24 if keyboard > 0 else 80
		terminal_tools.visible = keyboard == 0
		terminal_panel.anchor_bottom = clampf(.98-keyboard/height,.2,.98)
	if modal_open:
		set_prompt_visible(false)
		return
	if game.detailed_world:
		var text = LabInputBindings.hint(objective_info().text)
		if guide.text != text:
			guide.text = text
			field_objective.reset_size.call_deferred()
	var target = game.player.target
	var hint = target.get_interaction_prompt().replace("E · ","F — ") if target != null else ""
	if game.controls.touch_enabled: hint = hint.replace("F — ","")
	hint = LabInputBindings.hint(hint)
	if prompt.text != hint:
		prompt.text = hint
		place_prompt.call_deferred()
	dot.position = (game.player.aim_screen_point if game.player.aim_screen_point.x >= 0 else get_viewport().get_visible_rect().size*.5)-dot.size/2
	set_prompt_visible(target != null)
	if dot.active != (target != null):
		dot.active = target != null
		dot.queue_redraw()

func _input(event: InputEvent):
	if game == null or not game.controls.touch_enabled or not modal_open: return
	# RichTextLabel handles desktop selection; mobile transcripts use finger
	# scrolling directly and never feed the player's look gesture.
	if event is InputEventScreenTouch:
		if event.pressed and scroll_finger < 0:
			var transcript = terminal if mode == "terminal" else conversation if mode == "dialogue" else null
			if transcript != null and transcript.get_global_rect().has_point(event.position):
				scroll_finger = event.index
				touch_scroll = transcript.get_v_scroll_bar()
		elif not event.pressed and event.index == scroll_finger:
			scroll_finger = -1
			touch_scroll = null
	elif event is InputEventScreenDrag and event.index == scroll_finger and touch_scroll != null:
		touch_scroll.value -= event.relative.y
		get_viewport().set_input_as_handled()

func investigation_assigned() -> bool:
	return game.engine.investigation_assigned(game.state)

func question_visible(id: String) -> bool:
	return investigation_assigned() or id not in ["han_account","seo_collection","seo_submission","oh_audit"]

func fit_screen():
	if root == null or command_sidebar == null: return
	var size = get_viewport().get_visible_rect().size
	var safe = game.safe_rect()
	var compact = size.x < 1100
	field_objective.position = safe.position+Vector2(16,16)
	var objective_width = minf(420,safe.size.x-200 if game.controls.touch_enabled else safe.size.x-32)
	guide.custom_minimum_size.x = maxf(160,objective_width-36)
	field_objective.set_deferred("size",Vector2(objective_width,0))
	toast.position = Vector2(safe.position.x+16,safe.position.y+175)
	message.custom_minimum_size.x = minf(380,safe.size.x-64)
	update_hud.position = Vector2(safe.position.x+16,safe.end.y-72-(130 if game.controls.touch_enabled else 0))
	toast.reset_size.call_deferred()
	messenger_contacts.visible = not compact
	contact_picker.visible = compact
	command_sidebar.visible = not compact and help_sessions.get(game.context,false)
	command_input.custom_minimum_size.y = 48 if game.controls.mobile else 0
	for control in [touch_setting,update_setting,claim,contact_picker]:
		if is_instance_valid(control): control.custom_minimum_size.y = 48 if game.controls.mobile else 0
	if is_instance_valid(settings_screen):
		settings_screen.size = Vector2i(safe.size)
		settings_screen.position = Vector2i(safe.position)
	for item in [modal,terminal_panel,briefing_panel,dialogue_panel]:
		if compact:
			item.anchor_left = .02
			item.anchor_right = .98
			item.anchor_top = .52 if item == dialogue_panel else .02
			item.anchor_bottom = .98
		item.offset_left = safe.position.x
		item.offset_right = safe.end.x-size.x
		item.offset_top = safe.position.y
		item.offset_bottom = safe.end.y-size.y

func hide_keyboard():
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
func open_rebinding():
	if is_instance_valid(settings_screen): return
	var editor = InvestigationSettingsScreen.new()
	editor.game = game
	editor.original_controls = {}
	for key in ["touch_setting","update_setting","preview_setting","input_status","update_status","update_bar","update_check","update_download"]: editor.original_controls[key] = get(key)
	editor.configure(game.bindings,game.player)
	editor.theme = root.theme
	settings_screen = editor
	root.add_child(editor)
	editor.background.texture = settings_backdrop
	editor.preview_image.texture = settings_backdrop
	modal.hide()
	editor.popup()
	editor.size = Vector2i(game.safe_rect().size)
	editor.position = Vector2i(game.safe_rect().position)
	refresh_settings()

func refresh_input_hints():
	refresh_settings()
	guide.text = LabInputBindings.hint(objective_info().text)
	for control in root.find_children("*","Button",true,false):
		if control.has_meta("binding_text"): control.text = LabInputBindings.hint(control.get_meta("binding_text"))
