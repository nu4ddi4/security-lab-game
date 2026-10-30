class_name InvestigationUI
extends CanvasLayer

var game: InvestigationPrototype
var root: Control
var modal: PanelContainer
var tablet_backdrop: TextureRect
var tablet_nav = {}
var tablet_version: Label
var dialogue_scroll: ScrollContainer
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
var report_submit: Button
var end_day_button: Button
var toast: PanelContainer
var message: Label
var source: Label
var terminal: RichTextLabel
var terminal_objective: Label
var case_work_button: Button
var case_desk = InvestigationCaseDesk.new()
var clock_button: Button
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
var terminal_drafts = {}
var terminal_context = ""
var history_draft = ""
const ERROR_CODES = ["DEVICE_REQUIRED","UNKNOWN_COMMAND","WRONG_DEVICE","PERMISSION_REQUIRED","NO_RECORDS","INVALID_ACTION","QUESTION_UNAVAILABLE","REPORT_INCOMPLETE","DAY_NOT_READY","STALE_ACTION","SAVE_BLOCKED"]
const GOOD_WORDS = ["정상","완료","허용","승인","확인됨"]
const WARNING_WORDS = ["지연","필요","비활성","실패","오류","없음","미확인","불가","중단"]
var command_history = {}
var history_index = 0
var notes: VBoxContainer
var messenger: VBoxContainer
var latest_message: Control
var contact_title: Label
var contact = "oh"
var dialogue_title: Label
var dialogue_role: Label
var dialogue_portrait: Label
var conversation: RichTextLabel
var dialogue_questions: VBoxContainer
var speaker = ""
var report: VBoxContainer
var claim: OptionButton
var attachments = {}
var work: Label
var memo: TextEdit
var memo_status: Label
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
	# The tablet is a full page like the settings: same frosted backdrop, header and panel.
	tablet_backdrop = TextureRect.new()
	tablet_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tablet_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tablet_backdrop.material = InvestigationTheme.backdrop_material()
	tablet_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	tablet_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tablet_backdrop.hide()
	root.add_child(tablet_backdrop)
	modal = panel(0,0,1,1)
	modal.name = "Tablet"
	modal.theme_type_variation = "ShellRoot"
	modal.add_theme_constant_override("margin_left",14 if game.controls.mobile else 24)
	modal.visibility_changed.connect(func(): tablet_backdrop.visible = modal.visible and tablet_backdrop.texture != null)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",14)
	modal.add_child(body)
	var close_button = Button.new()
	close_button.text = "닫기" if game.controls.touch_enabled else "닫기 · Esc"
	close_button.set_meta("binding_text",close_button.text)
	close_button.custom_minimum_size.y = 48 if game.controls.mobile else 34
	close_button.add_theme_font_size_override("font_size",16 if game.controls.mobile else 14)
	close_button.pressed.connect(close)
	var header = InvestigationTheme.shell_header(body,[["노트",0],["메신저",1],["발생 보고",2],["업무",3],["설정",4]],3,func(id): tabs.current_tab = id,ContentVersion.running(),game.controls.mobile,[close_button])
	tablet_nav = header.buttons
	tablet_version = header.version
	var shell = PanelContainer.new()
	shell.theme_type_variation = "ShellPanel"
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(shell)
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(tabs)
	for name in ["노트","메신저","발생 보고","업무","설정"]:
		var scroll = ScrollContainer.new()
		scroll.name = name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box = VBoxContainer.new()
		box.name = "Body"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation",12)
		scroll.add_child(box)
		label(box,name,"TitleLabel")
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
		InvestigationTheme.mark_active(tablet_nav,index)
		if index == 4 and modal_open and game.settings != null and settings_screen == null: open_rebinding())
	label(tab(0),"북마크 · 조회한 업무 기록과 첨부","CaptionLabel")
	notes = VBoxContainer.new()
	notes.add_theme_constant_override("separation",8)
	tab(0).add_child(notes)
	label(tab(0),"개인 메모","SectionLabel")
	memo = TextEdit.new()
	memo.custom_minimum_size.y = 160
	memo.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	memo.placeholder_text = "오늘 확인한 업무 내용을 적으세요."
	tab(0).add_child(memo)
	memo_status = label(tab(0),"","CaptionLabel")
	memo.text_changed.connect(func():
		if ready_memo:
			game.dispatch({"type":"memo","payload":{"text":memo.text}})
			refresh_memo_status())
	label(tab(1),"사내 메신저 · 비동기 업무 연락과 이전 제출 자료","CaptionLabel")
	var layout = HBoxContainer.new()
	layout.add_theme_constant_override("separation",20)
	tab(1).add_child(layout)
	contact_picker = OptionButton.new()
	for id in game.content.case.npcs:
		contact_picker.add_item(game.content.case.npcs[id].name+" · "+game.content.case.npcs[id].role)
		contact_picker.set_item_metadata(contact_picker.item_count-1,id)
	tab(1).add_child(contact_picker)
	tab(1).move_child(contact_picker,2)
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
	label(report,"원문을 첨부하고 보고 내용을 작성하세요.","CaptionLabel")
	var claim_box = card_box(report)
	label(claim_box,"보고 내용","SectionLabel")
	claim = OptionButton.new()
	claim.add_item("보고 내용 선택")
	claim.item_selected.connect(func(_index): refresh_report_access())
	for item in game.content.rules.claims:
		claim.add_item(item.label)
		claim.set_item_metadata(claim.item_count-1,item.id)
	claim_box.add_child(claim)
	var evidence_box = card_box(report)
	label(evidence_box,"근거 원본","SectionLabel")
	report_hint = label(evidence_box,"아직 첨부할 원본이 없습니다. 장비에서 원본을 조회하면 이곳에서 선택할 수 있습니다.","CaptionLabel")
	for slot in ["scope","access","collection"]:
		label(evidence_box,{"scope":"기준 문서","access":"처리 기록","collection":"보관 기록"}[slot])
		var option = OptionButton.new()
		attachments[slot] = option
		evidence_box.add_child(option)
		option.item_selected.connect(func(_index): refresh_report_access())
	report.move_child(claim_box.get_parent(),report.get_child_count()-1)
	report_submit = button(report,"발생 보고 제출",submit_report,"PrimaryButton")
	button(report,"대조 기록",func(): case_desk.open(self,false))
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
	end_day_button = button(actions,"오늘 업무 종료",end_day,"PrimaryButton")
	clock_button = button(actions,"정시 업무 확인",func(): confirm("다음 정시 업무를 확인할까요?",func(): notice(game.dispatch({"type":"time.advance"}).text)))
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
	terminal_objective = label(body,"","CaptionLabel")
	case_work_button = button(body,"관제 업무",func(): case_desk.open(self,true))
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
	dialogue_panel = panel(.16,.505,.84,.96)
	dialogue_panel.theme_type_variation = "DialoguePanel"
	dialogue_panel.name = "Dialogue"
	if game.controls.mobile:
		dialogue_panel.anchor_left = .03
		dialogue_panel.anchor_right = .97
		dialogue_panel.anchor_top = .46
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	dialogue_panel.add_child(body)
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation",12)
	body.add_child(head)
	var portrait = PanelContainer.new()
	portrait.theme_type_variation = "PortraitPanel"
	portrait.custom_minimum_size = Vector2(46,46)
	head.add_child(portrait)
	dialogue_portrait = Label.new()
	dialogue_portrait.theme_type_variation = "TitleLabel"
	dialogue_portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(dialogue_portrait)
	var who = VBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation",0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	dialogue_title = label(who,"","HeadingLabel")
	dialogue_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	dialogue_role = label(who,"","CaptionLabel")
	dialogue_role.autowrap_mode = TextServer.AUTOWRAP_OFF
	var leave = button(head,"닫기" if game.controls.touch_enabled else "닫기 · Esc",close)
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rule = ColorRect.new()
	rule.color = Color(InvestigationTheme.ACCENT,.35)
	rule.custom_minimum_size.y = 1
	body.add_child(rule)
	conversation = RichTextLabel.new()
	conversation.custom_minimum_size.y = 64 if game.controls.mobile else 80
	conversation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conversation.bbcode_enabled = true
	conversation.selection_enabled = not game.controls.mobile
	for size in ["normal_font_size","bold_font_size"]: conversation.add_theme_font_size_override(size,17 if game.controls.mobile else 19)
	body.add_child(conversation)
	dialogue_scroll = ScrollContainer.new()
	dialogue_scroll.custom_minimum_size.y = 72 if game.controls.mobile else 64
	dialogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(dialogue_scroll)
	dialogue_questions = VBoxContainer.new()
	dialogue_questions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue_questions.add_theme_constant_override("separation",6)
	dialogue_scroll.add_child(dialogue_questions)

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
	refresh_memo_status()

func refresh_memo_status():
	var limit = int(game.content.rules.maxMemoLength)
	var overflow = memo.text.length() > limit
	memo_status.text = "%d / %d자" % [memo.text.length(),limit]
	if overflow: memo_status.text += " · 초과한 내용은 저장되지 않습니다. 글자 수를 줄여 주세요."
	memo_status.add_theme_color_override("font_color",InvestigationTheme.WARNING if overflow else InvestigationTheme.TEXT_DIM)

func quote_note(record: Dictionary):
	var text = memo.text+"\n["+record.title+" · "+record.source+" · "+record.time+"]\n"
	var result = game.dispatch({"type":"memo","payload":{"text":text}})
	if result.code != "MEMO_SAVED": notice(result.text); return
	sync_memo()
	memo.set_caret_line(memo.get_line_count()-1)
	memo.set_caret_column(memo.get_line(memo.get_caret_line()).length())
	tabs.get_child(0).ensure_control_visible.call_deferred(memo)

func reset_session():
	case_desk.reset()
	help_sessions.clear()
	terminal_buffers.clear()
	terminal_drafts.clear()
	terminal_context = ""
	history_draft = ""
	command_history.clear()
	command_input.clear()
	claim.select(0)
	for option in attachments.values(): option.select(0)
	contact = "oh"
	close()
	if game.state.day == 1 and "oh_intro" not in game.state.statements: open_briefing()

func guide_info() -> Dictionary:
	var state = game.state
	if state.ended: return {"title":"업무 종결","text":"접수한 기록은 휴대 단말과 관제 단말에서 열람할 수 있습니다.","target":""}
	if state.day > 1:
		var daily = {
			2:["서비스 점검","자료 서비스의 응답과 운영 설정을 확인하고 금일 점검을 기록하세요."],
			3:["자료·검색 점검","업무 자료의 원본 목록과 검색 응답을 점검하고 운영 인계를 남겨 주세요."],
			4:["업무 기록 검토","운영 상태를 확인하고 승인 대장과 처리 기록을 검토하세요. 보고 접수는 휴대 단말에서 진행합니다."],
			5:["정비 이력 검토","운영 점검 후 금일 정비 요청과 접수·적용 이력을 검토하세요."],
			6:["요청 문서 검토","운영 점검과 업무 요청 문서 검토를 마치고 필요한 변경 요청을 접수하세요."],
			7:["정시 확인·종결","17:30 정시 업무를 확인하고 종결 보고를 접수하세요. 관제 단말에서 보고 업무를 진행합니다."]}
		var row = daily[int(state.day)]
		var target = ""
		if not game.engine.missing_work(state).is_empty():
			target = "project_pc" if state.day == 3 else "server_console" if state.ops.serviceVerifiedDay != state.day else "project_pc"
		return {"title":"%d일차 · %s" % [state.day,row[0]],"text":row[1],"target":target}
	if "oh_intro" not in state.statements: return {"title":"1 / 8 · 담당 업무 인계","text":"보안팀장 오세진에게 오늘 업무를 인계받으세요.","target":"oh"}
	if "park_intro" not in state.statements: return {"title":"2 / 8 · 서버 담당자","text":"서버 담당 박도윤에게 운영 업무를 인계받으세요.","target":"park"}
	for key in ["service","account","tasks"]:
		if key not in state.baseline: return {"title":"3 / 8 · 서버 기준 상태","text":"서버 단말에서 서비스·계정·등록 작업을 확인하세요. 조작 방법은 명령어 책에 있습니다.","target":"server_console"}
	if "han_intro" not in state.statements: return {"title":"4 / 8 · 업무 담당자","text":"한지우에게 담당 업무를 인계받으세요.","target":"han"}
	if "files" not in state.baseline: return {"title":"5 / 8 · 업무 자료","text":"업무 PC에서 원본 목록을 확인하세요.","target":"project_pc"}
	if "seo_intro" not in state.statements: return {"title":"6 / 8 · 정비 담당자","text":"서유진에게 정비 업무를 인계받으세요.","target":"seo"}
	if "approval" not in state.baseline: return {"title":"7 / 8 · 승인 대장","text":"승인서 보관함에서 배정 업무의 승인 대장을 확인하세요.","target":"approval_archive"}
	return {"title":"8 / 8 · 운영 인계 완료","text":"휴대 단말에서 오늘의 기록을 검토하고 업무를 종료하세요.","target":""}

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
	hud.text = objective.title if objective.title.begins_with("%d일차" % view.day) else "%d일차 · %s" % [view.day,objective.title]
	guide.text = LabInputBindings.hint(objective.text)
	field_objective.reset_size.call_deferred()
	case_work_button.visible = game.context == "control_console"
	clock_button.visible = view.day == 7 and not view.ended
	source.text = view.device.get("label","현장 단말")+" · 운영 점검 세션"
	terminal_objective.text = LabInputBindings.hint(objective.title+" · "+objective.text)
	clear(notes)
	if view.notes.is_empty(): label(notes,"아직 확보한 원본이 없습니다. 현장 장비에서 원본을 조회하거나 메신저의 첨부를 확인하세요.")
	for record in view.notes:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		notes.add_child(row)
		var open_note = button(row,record.title+" · "+record.source,func(): notice(record.title+"\n"+record.source+" · "+record.time+" · 확보 %d일차\n" % record.acquiredDay+record.body),"TileButton")
		open_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open_note.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open_note.clip_text = true
		open_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		open_note.tooltip_text = record.title+" · "+record.source
		button(row,"메모에 인용",quote_note.bind(record))
	report_hint.visible = true
	report_hint.text = "승인 완료 · 제출한 주장과 원본입니다. 감사 권한은 유지되며 다시 제출할 필요가 없습니다." if view.approved else "확인한 원본을 각 근거에 맞게 선택하세요." if not view.notes.is_empty() else "아직 첨부할 원본이 없습니다. 장비에서 원본을 조회하면 이곳에서 선택할 수 있습니다."
	if view.approved:
		for i in range(1,claim.item_count):
			if claim.get_item_metadata(i) == game.state.report.claim: claim.select(i)
	for slot in attachments:
		var option = attachments[slot]
		var selected = game.state.report.attachments.get(slot) if view.approved else option.get_item_metadata(option.selected) if option.selected >= 0 and option.item_count else null
		option.clear()
		option.add_item("원본 선택")
		for record in view.notes:
			option.add_item(record.title+" · "+record.time)
			option.set_item_metadata(option.item_count-1,record.id)
			if record.id == selected: option.select(option.item_count-1)
		option.disabled = view.approved or view.ended
	report_submit.disabled = view.approved or view.ended
	report_submit.text = "승인된 보고" if view.approved else "점검 종료" if view.ended else "발생 보고 제출"
	end_day_button.disabled = view.ended
	end_day_button.text = "업무 종결됨" if view.ended else "조사 종결" if view.day == 7 else "오늘 업무 종료"
	refresh_dialogue()
	refresh_messenger()
	refresh_commands()
	var assigned = game.state.day >= 2 or investigation_assigned()
	tabs.set_tab_hidden(2,not assigned)
	tablet_nav[2].visible = assigned
	new_session_button.text = "새 조사" if investigation_assigned() else "새 업무 시작"
	work.text = objective.title+"\n"+objective.text
	clear(checklist)
	label(checklist,"오늘의 필수 운영 확인","SectionLabel")
	if view.work.is_empty(): label(checklist,"✓  오늘의 필수 확인을 모두 마쳤습니다.")
	for line in view.work: label(checklist,"○  "+line)
	if investigation_assigned(): work.text += "\n\n발생 보고: "+("승인됨 · 감사 권한 유지" if view.approved else "미승인")
	if view.day == 7: work.text += "\n\n업무 시각 %02d:%02d" % [int(game.state.casework.minute)/60,int(game.state.casework.minute)%60]
	if view.ended: work.text += "\n\n"+InvestigationResolution.public_ending(game.state)
	refresh_report_access()

func refresh_report_access():
	if not is_instance_valid(report_submit): return
	var ids = []
	for option in attachments.values():
		if option.selected <= 0: continue
		var id = option.get_item_metadata(option.selected)
		if id not in ids: ids.append(id)
	claim.disabled = game.state.report.approved or game.state.ended or ids.size() < 2
	report_submit.disabled = claim.disabled or claim.selected <= 0

func refresh_dialogue():
	clear(dialogue_questions)
	if speaker == "": return
	var questions = game.engine.project(game.state).questions
	for question in questions:
		if question.npc == speaker and question.channel == "dialogue" and question_visible(question.id):
			var visited = "  · 확인함" if question.id in game.state.statements else ""
			var choice = button(dialogue_questions,"%d   %s%s" % [dialogue_questions.get_child_count()+1,question.label,visited],ask.bind(question.id),"ChoiceButton")
			choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if dialogue_questions.get_child_count() == 0: label(dialogue_questions,"지금 더 물어볼 내용이 없습니다.")
	fit_choices.call_deferred()

# All choices stay visible without scrolling unless they would crowd out the conversation.
func fit_choices():
	if not is_instance_valid(dialogue_scroll): return
	var wanted = dialogue_questions.get_combined_minimum_size().y
	# The scene must stay visible behind the conversation, so the choices never take more than a fifth of the screen.
	var cap = 76.0 if game.controls.mobile else get_viewport().get_visible_rect().size.y*.2
	dialogue_scroll.custom_minimum_size.y = clampf(wanted,48,cap)

# The reply starts with the speaker's name; show it as a label, never as markup.
func speech(text: String) -> String:
	var safe = text.replace("[","[lb]")
	var lines = safe.split("\n",true,1)
	var name = game.content.case.npcs.get(speaker,{}).get("name","")
	# The speaker already has a name plate above the conversation.
	if lines.size() == 2 and not name.is_empty() and lines[0].strip_edges() == name: return lines[1]
	return safe

func ask(id: String):
	conversation.text = speech(game.dispatch({"type":"dialogue","payload":{"id":id}}).text)
	conversation.scroll_to_line(0)

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
	return row

func refresh_messenger():
	clear(messenger)
	latest_message = null
	var npc = game.content.case.npcs[contact]
	contact_title.text = npc.name+" · "+npc.role
	var ids = game.content.case.npcs.keys()
	contact_picker.select(ids.find(contact))
	for i in messenger_contacts.get_child_count():
		messenger_contacts.get_child(i).theme_type_variation = "PrimaryButton" if ids[i] == contact else ""
	var count = 0
	for msg in game.state.messages:
		if msg.npc == contact:
			var row = bubble("%d일차 · %s" % [msg.day,npc.name],msg.text)
			if msg.day == game.state.day: latest_message = row
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
		var pick = button(command_list,row.get("description","장비 조작"),fill_command.bind(row.text),"TileButton")
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var detail = label(command_list,row.text,"CaptionLabel")
		detail.custom_minimum_size.x = 300

func fill_command(text: String):
	command_input.text = text
	command_input.caret_column = text.length()
	if not game.controls.mobile: command_input.grab_focus()

func execute_command():
	if mode != "terminal": return
	var text = command_input.text.strip_edges()
	command_input.clear()
	history_draft = ""
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
	if direction > 0 and history_index >= history.size(): return
	if history_index == history.size() and direction < 0: history_draft = command_input.text
	history_index = clampi(history_index+direction,0,history.size())
	command_input.text = history[history_index] if history_index < history.size() else history_draft
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
	# Wrapping and scrollbar bounds are updated during the next layout pass.
	await get_tree().process_frame
	if mode == "terminal": terminal.scroll_to_line(maxi(0,terminal.get_line_count()-1))

static func color_tag(color: Color) -> String:
	return "[color=#%s]" % color.to_html(false)

static func terminal_markup(log: Array) -> String:
	var blocks = []
	for entry in log:
		var text = str(entry.text).replace("[","[lb]")
		blocks.append("sec.ops > "+text if entry.kind == "command" else text)
	return "\n".join(blocks)

static func style_line(line: String, _heading: bool) -> String:
	return line.replace("[","[lb]")

func _show(next_mode: String, window: Control):
	remember_terminal_draft()
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
	tabs.current_tab = 3 if index == 2 and game.state.day < 2 and not investigation_assigned() else index
	InvestigationTheme.mark_active(tablet_nav,tabs.current_tab)
	tablet_backdrop.texture = settings_backdrop
	tablet_backdrop.visible = modal.visible and settings_backdrop != null
	if index == 4 and settings_screen == null: open_rebinding()
	refresh()

func open_briefing(): _show("briefing",briefing_panel)

func open_terminal():
	_show("terminal",terminal_panel)
	terminal_context = game.context
	command_input.text = terminal_drafts.get(terminal_context,"")
	history_draft = command_input.text
	command_input.caret_column = command_input.text.length()
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
	dialogue_title.text = npc.name
	dialogue_role.text = npc.role
	dialogue_portrait.text = npc.name.substr(0,1)
	conversation.text = "무엇을 확인하시겠어요?"
	conversation.scroll_to_line(0)
	dialogue_scroll.scroll_vertical = 0
	refresh_dialogue()
	game.frame_speaker(id)

func close():
	if is_instance_valid(settings_screen) and settings_screen.visible:
		settings_screen.close_editor()
		return
	if game.blocked_save: return
	remember_terminal_draft()
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

func remember_terminal_draft():
	if mode == "terminal" and not terminal_context.is_empty():
		terminal_drafts[terminal_context] = command_input.text

func toggle():
	# Android Back does not send the cancel key to embedded windows.
	for option in root.find_children("*","OptionButton",true,false):
		if option.get_popup().visible:
			option.get_popup().hide()
			return
	var dialogs = root.find_children("*","AcceptDialog",true,false)
	dialogs.reverse()
	for dialog in dialogs:
		if dialog.visible:
			dialog.hide()
			dialog.canceled.emit()
			return
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
		popup.set_meta("scroll_notice",true)
		dialog_parent().add_child(popup)
		var scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		popup.add_child(scroll)
		var document = RichTextLabel.new()
		document.fit_content = true
		document.scroll_active = false
		document.selection_enabled = true
		document.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		document.text = text
		scroll.add_child(document)
		popup.confirmed.connect(popup.queue_free)
		popup.canceled.connect(popup.queue_free)
		popup.popup()
		fit_notice(popup)

func fit_notice(popup: Window):
	if not is_instance_valid(popup) or not popup.visible: return
	var area = game.safe_rect()
	popup.size = Vector2i(mini(600,int(area.size.x)-32),mini(520,int(area.size.y)-88))
	popup.position = Vector2i(area.position+(area.size-Vector2(popup.size))*.5)

func dialog_parent() -> Node:
	var parent: Node = root
	for candidate in root.find_children("*","Window",true,false):
		if candidate.visible and not candidate.is_queued_for_deletion() and (candidate is AcceptDialog or candidate == settings_screen): parent = candidate
	return parent

func confirm(text: String, callback: Callable):
	var dialog = ConfirmationDialog.new()
	localize_dialog(dialog,"확인")
	dialog.dialog_text = text
	dialog_parent().add_child(dialog)
	dialog.confirmed.connect(func(): dialog.hide(); callback.call(); dialog.queue_free())
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
	if game.state.ended: return
	var missing = game.engine.missing_work(game.state)
	if not missing.is_empty():
		notice("오늘 업무를 마치기 전에 확인해 주세요.\n\n"+"\n".join(missing))
		return
	var day = game.state.day
	var text = game.engine._t("CONFIRM_END")
	if day == 7: text = "접수한 보고로 조사를 종결할까요?"
	confirm(text,finish_day.bind(day))

func finish_day(day: int):
	var result = game.dispatch({"type":"day.end","payload":{"expectedDay":day,"confirmed":true}})
	if result.code != "DAY_STARTED":
		notice(result.text)
		return
	# Open the new assignment at its sender instead of leaving yesterday's page open.
	for i in range(game.state.messages.size()-1,-1,-1):
		var msg = game.state.messages[i]
		if msg.day == game.state.day:
			contact = msg.npc
			open_tablet(1)
			reveal_assignment()
			return
	open_tablet(3)

func reveal_assignment():
	await get_tree().process_frame
	if mode != "tablet" or tabs.current_tab != 1 or not is_instance_valid(latest_message): return
	var scroll = tabs.get_child(1)
	if scroll.is_ancestor_of(latest_message): scroll.ensure_control_visible(latest_message)

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

# Number keys pick the matching conversation choice.
func _unhandled_key_input(event: InputEvent):
	if mode != "dialogue" or not event.pressed or event.echo: return
	var index = event.keycode-KEY_1
	if index < 0 or index >= dialogue_questions.get_child_count(): return
	var choice = dialogue_questions.get_child(index)
	if choice is Button:
		get_viewport().set_input_as_handled()
		choice.pressed.emit()

func investigation_assigned() -> bool:
	return game.engine.investigation_assigned(game.state)

func question_visible(id: String) -> bool:
	return true

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
	for control in [touch_setting,update_setting,claim,contact_picker]+attachments.values():
		if is_instance_valid(control): control.custom_minimum_size.y = 48 if game.controls.mobile else 0
		if control is OptionButton:
			control.fit_to_longest_item = false
			control.clip_text = true
			control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if is_instance_valid(settings_screen):
		settings_screen.size = Vector2i(safe.size)
		settings_screen.position = Vector2i(safe.position)
	if is_instance_valid(case_desk.dialog): case_desk.fit.call_deferred()
	for popup in root.find_children("*","AcceptDialog",true,false):
		if popup.visible and popup.has_meta("scroll_notice"): fit_notice.call_deferred(popup)
	modal.add_theme_constant_override("margin_left",14 if game.controls.mobile else 24)
	for item in [modal,terminal_panel,briefing_panel,dialogue_panel]:
		if compact and item != modal:
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
