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
var dot: Label
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
var input_status: Label
var update_status: Label
var update_check: Button
var update_download: Button
var binding_summary: Label

func setup(controller: InvestigationPrototype):
	game = controller
	root = Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	var font = FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansKR.ttf")
	font.variation_opentype = {"wght":450}
	theme.default_font = font
	theme.default_font_size = 22 if game.controls.mobile else 18
	var normal = surface(Color(.08,.13,.17))
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover = normal.duplicate()
	hover.bg_color = Color(.12,.25,.3)
	theme.set_stylebox("normal","Button",normal)
	theme.set_stylebox("hover","Button",hover)
	theme.set_color("font_color","Button",Color(.9,.95,.98))
	root.theme = theme
	var objective = PanelContainer.new()
	root.add_child(objective)
	field_objective = objective
	objective.position = Vector2(24,20)
	objective.custom_minimum_size = Vector2(0,0)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective.add_theme_stylebox_override("panel",surface(Color(.025,.045,.065,.85)))
	var info = VBoxContainer.new()
	objective.add_child(info)
	hud = label(info,"")
	hud.add_theme_color_override("font_color",Color(.45,.85,.82))
	guide = label(info,"")
	guide.custom_minimum_size.x = 0
	guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_theme_font_size_override("font_size",16)
	prompt = label(root,"")
	prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -78
	prompt.offset_bottom = -16
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color",Color(.65,1,.9))
	dot = label(root,"·")
	dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	dot.autowrap_mode = TextServer.AUTOWRAP_OFF
	dot.add_theme_font_size_override("font_size",28)
	message = label(root,"")
	message.position = Vector2(24,190)
	message.custom_minimum_size.x = 380
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

func surface(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	style.border_color = Color(.18,.3,.36)
	style.set_border_width_all(1)
	return style

func panel(left: float, top: float, right: float, bottom: float) -> PanelContainer:
	var node = PanelContainer.new()
	root.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.anchor_left = left
	node.anchor_top = top
	node.anchor_right = right
	node.anchor_bottom = bottom
	node.add_theme_stylebox_override("panel",surface(Color(.035,.055,.075,.98)))
	node.hide()
	return node

func heading(parent: Node, text: String) -> Label:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var title = label(row,text)
	title.custom_minimum_size.x = 160
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",22)
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
	label(body,"업무 기록 · 사내 연락 · 오늘 업무")
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	for name in ["노트","메신저","발생 보고","업무","설정"]:
		var scroll = ScrollContainer.new()
		scroll.name = name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var box = VBoxContainer.new()
		box.name = "Body"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation",12)
		scroll.add_child(box)
	label(tab(0),"확보한 원본 · 장비에서 조회한 기록과 받은 첨부만 표시됩니다.")
	notes = VBoxContainer.new()
	tab(0).add_child(notes)
	label(tab(0),"개인 메모")
	memo = TextEdit.new()
	memo.custom_minimum_size.y = 160
	memo.placeholder_text = "오늘 확인한 업무 내용을 적으세요."
	tab(0).add_child(memo)
	memo.text_changed.connect(func():
		if ready_memo: game.dispatch({"type":"memo","payload":{"text":memo.text}}))
	label(tab(1),"사내 메신저 · 비동기 업무 연락과 이전 제출 자료")
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
	var contacts = VBoxContainer.new()
	messenger_contacts = contacts
	contacts.custom_minimum_size.x = 210
	layout.add_child(contacts)
	for id in game.content.case.npcs:
		var npc = game.content.case.npcs[id]
		button(contacts,npc.name+"\n"+npc.role,func(): contact = id; refresh_messenger())
	var thread = VBoxContainer.new()
	thread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(thread)
	contact_title = label(thread,"")
	contact_title.add_theme_font_size_override("font_size",21)
	messenger = VBoxContainer.new()
	messenger.add_theme_constant_override("separation",12)
	thread.add_child(messenger)
	report = tab(2)
	var explanation = label(report,"승인 범위와 실제 행동을 대조하고, 확인한 원본을 직접 첨부하세요. 실행 계정과 실제 사람, 내부 수집과 외부 반출은 구분합니다.")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	claim = OptionButton.new()
	claim.add_item("주장 선택")
	for item in game.content.rules.claims:
		claim.add_item(item.label)
		claim.set_item_metadata(claim.item_count-1,item.id)
	report.add_child(claim)
	for slot in ["scope","access","collection"]:
		label(report,{"scope":"허용 범위 근거","access":"실제 접근 근거","collection":"실제 수집 근거"}[slot])
		var option = OptionButton.new()
		attachments[slot] = option
		report.add_child(option)
	button(report,"발생 보고 제출",submit_report)
	work = label(tab(3),"")
	work.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(tab(3),"오늘 업무 종료",end_day)
	button(tab(3),"업무 배경과 점검 방법",open_briefing)
	button(tab(3),"진행 내보내기",func(): file_dialog(true))
	button(tab(3),"진행 가져오기",func(): file_dialog(false))
	new_session_button = button(tab(3),"새 업무 시작",func(): confirm("현재 진행을 보관하고 새 업무를 시작할까요?",game.new_game))
	touch_setting = CheckButton.new()
	touch_setting.text = "터치 조작 사용\n키보드 입력도 함께 사용"
	touch_setting.button_pressed = game.controls.touch_enabled
	tab(4).add_child(touch_setting)
	touch_setting.toggled.connect(game.controls.set_touch)
	input_status = label(tab(4),"")
	label(tab(4),"터치: 왼쪽 엄지 이동 · 오른쪽 쓸어 시점 · 장비를 탭해 선택한 뒤 상호작용")
	if OS.get_name() == "Windows" or game.qa_mode:
		label(tab(4),"조작키 · 키보드")
		binding_summary = label(tab(4),LabInputBindings.summary(true))
		button(tab(4),"조작키 변경…",open_rebinding)
	update_setting = CheckButton.new()
	update_setting.text = "시작할 때 업데이트 확인"
	update_setting.button_pressed = game.controls.automatic_updates
	tab(4).add_child(update_setting)
	update_setting.toggled.connect(game.controls.set_automatic_updates)
	label(tab(4),"%s · %s 채널" % [game.updates.installed.get("version","개발"),"사전 릴리즈" if game.updates.installed.get("prerelease",true) else "안정"])
	update_status = label(tab(4),"")
	update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_check = button(tab(4),"업데이트 확인",func():
		if game.updater!=null: game.updater.check()
		else: game.updates.check())
	update_download = button(tab(4),"업데이트 확인하고 설치…",func():
		if game.updater!=null: game.updater.request_install()
		else: confirm("업데이트가 있습니다. 새 버전을 다운로드할까요? 설치 전 게임을 닫으세요. 저장은 유지됩니다.",game.updates.open_download))
	var diagnostic_status = label(tab(4),"")
	if OS.get_name()=="Windows":
		button(tab(4),"진단 정보 복사",func(): diagnostic_status.text = game.diagnostics.copy_information().message)
		button(tab(4),"지원 패키지 만들기",func(): diagnostic_status.text = game.diagnostics.create_package().message)
		button(tab(4),"지원 패키지 폴더 열기",func():
			if not game.diagnostics.last_package.is_empty(): OS.shell_open(game.diagnostics.last_package.get_base_dir()))

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
	terminal.add_theme_color_override("default_color",Color(.65,.92,.78))
	session.add_child(terminal)
	var row = HBoxContainer.new()
	session.add_child(row)
	var shell_prompt = label(row,"sec.ops >")
	shell_prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	shell_prompt.custom_minimum_size.x = 115 if game.controls.mobile else 100
	command_input = LineEdit.new()
	command_input.placeholder_text = "명령 입력 · help로 도움말"
	command_input.max_length = 200
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(command_input)
	command_input.text_submitted.connect(func(_text): execute_command())
	command_input.gui_input.connect(_terminal_input)
	button(row,"실행",execute_command)
	var tools = HBoxContainer.new()
	terminal_tools = tools
	session.add_child(tools)
	button(tools,"복사",func(): DisplayServer.clipboard_set(terminal.text))
	button(tools,"지우기",clear_terminal)
	if not game.controls.mobile:
		var hint = label(tools,"↑↓ 이력 · Tab 자동완성 · Ctrl+L 지우기")
		hint.autowrap_mode = TextServer.AUTOWRAP_OFF
		hint.add_theme_font_size_override("font_size",14)
	button(tools,"이전",func(): recall_command(-1))
	button(tools,"다음",func(): recall_command(1))
	var sidebar = VBoxContainer.new()
	command_sidebar = sidebar
	sidebar.custom_minimum_size.x = 340
	layout.add_child(sidebar)
	label(sidebar,"이 장비의 명령")
	label(sidebar,"선택하면 입력됩니다. Enter로 실행하세요.").add_theme_font_size_override("font_size",14)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	command_list = VBoxContainer.new()
	command_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(command_list)

func _build_dialogue():
	dialogue_panel = panel(.16,.62,.84,.96)
	dialogue_panel.name = "Dialogue"
	if game.controls.mobile:
		dialogue_panel.anchor_left = .03
		dialogue_panel.anchor_right = .97
		dialogue_panel.anchor_top = .46
	var body = VBoxContainer.new()
	dialogue_panel.add_child(body)
	dialogue_title = heading(body,"")
	conversation = RichTextLabel.new()
	conversation.custom_minimum_size.y = 64 if game.controls.mobile else 84
	conversation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conversation.selection_enabled = not game.controls.mobile
	body.add_child(conversation)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 72 if game.controls.mobile else 90
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	dialogue_questions = VBoxContainer.new()
	dialogue_questions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(dialogue_questions)

func _build_briefing():
	briefing_panel = panel(.24,.16,.76,.84)
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
	label(body,game.content.case.briefing.heading).add_theme_font_size_override("font_size",25)
	for key in ["background","assignment","method","first"]:
		var text = label(body,game.content.case.briefing[key])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button(body,"현장 점검 시작",close)
	button(body,"휴대 단말에서 업무 확인",func(): open_tablet(3))

func tab(index: int) -> VBoxContainer:
	return tabs.get_child(index).get_node("Body")

func label(parent: Node, text: String) -> Label:
	var node = Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable) -> Button:
	var node = Button.new()
	node.text = LabInputBindings.hint(text)
	if text.contains("Esc"): node.set_meta("binding_text",text)
	node.clip_text = text.length() > 18
	if node.clip_text: node.custom_minimum_size.x = 160
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
	input_status.text = "터치와 키보드를 함께 사용할 수 있습니다." if game.controls.touch_enabled else "키보드·마우스 조작"
	if game.controls.keyboard_seen: input_status.text += " · 키보드 입력 감지됨"
	if is_instance_valid(binding_summary): binding_summary.text = LabInputBindings.summary(true)
	update_status.text = game.updates.status
	update_check.disabled = game.updater.state in ["checking","downloading","preparing"] if game.updater!=null else game.updates.busy
	update_download.visible = game.updater.state in ["available","ready"] if game.updater!=null else not game.updates.download_url.is_empty()

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
		notes.add_child(row)
		button(row,record.title+" · "+record.source,func(): notice(record.title+"\n"+record.source+" · "+record.time+" · 확보 %d일차\n" % record.acquiredDay+record.body))
		button(row,"메모에 인용",func(): memo.text += "\n["+record.title+" · "+record.source+" · "+record.time+"]\n")
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
	work.text = objective.title+"\n"+objective.text+"\n\n오늘의 필수 운영 확인\n"+("확인 완료" if view.work.is_empty() else "\n".join(view.work))
	if assigned: work.text += "\n\n발생 보고: "+("승인됨 · 감사 권한 유지" if view.approved else "미승인")
	if assigned: work.text += "\n확인한 내부 수집 문서: "+("미확인" if view.documentCount < 0 else "%d개 · 반출과 별도" % view.documentCount)
	if view.ended: work.text += "\n\n"+game.engine._t("PROTOTYPE_ENDED")

func refresh_dialogue():
	clear(dialogue_questions)
	if speaker == "": return
	var questions = game.engine.project(game.state).questions
	for question in questions:
		if question.npc == speaker and question.channel == "dialogue" and question_visible(question.id):
			button(dialogue_questions,question.label,func():
				var result = game.dispatch({"type":"dialogue","payload":{"id":question.id}})
				conversation.text = result.text)
	if dialogue_questions.get_child_count() == 0: label(dialogue_questions,"지금 더 물어볼 내용이 없습니다.")

func bubble(text: String, outgoing = false):
	var row = HBoxContainer.new()
	messenger.add_child(row)
	if outgoing:
		var space = Control.new()
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(space)
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",surface(Color(.1,.25,.3) if outgoing else Color(.09,.12,.16)))
	row.add_child(card)
	var body = label(card,text)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 0

func refresh_messenger():
	clear(messenger)
	var npc = game.content.case.npcs[contact]
	contact_title.text = npc.name+" · "+npc.role
	var count = 0
	for msg in game.state.messages:
		if msg.npc == contact:
			bubble("%d일차 · %s\n%s" % [msg.day,npc.name,msg.text])
			count += 1
	for question in game.content.dialogue:
		if question.npc == contact and question.get("channel","dialogue") == "messenger" and question.id in game.state.statements:
			bubble("나\n"+question.label,true)
			bubble(npc.name+"\n"+question.response)
			if question.record != "" and question.record in game.state.known:
				var record = game.state.records[question.record]
				button(messenger,"첨부 · "+record.title,func(): notice(record.title+"\n"+record.source+"\n"+record.body))
			count += 1
	if count == 0: bubble("아직 받은 메시지가 없습니다. 담당자와 직접 대화하려면 현장에서 만나세요.")
	for question in game.engine.project(game.state).questions:
		if question.npc == contact and question.channel == "messenger" and question.id not in game.state.statements and question_visible(question.id):
			button(messenger,question.label,func(): game.dispatch({"type":"dialogue","payload":{"id":question.id}}))

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
			label(command_list,category).add_theme_color_override("font_color",Color(.4,.8,.8))
		button(command_list,row.text,func():
			command_input.text = row.text
			command_input.caret_column = row.text.length()
			if not game.controls.mobile: command_input.grab_focus())
		var detail = label(command_list,row.get("description",""))
		detail.custom_minimum_size.x = 300
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size",14)

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
	terminal_buffers[game.context] = ""
	terminal.text = ""

func print_output(command: String, text: String):
	var output = terminal_buffers.get(game.context,"")+"\nsec.ops > "+command+"\n"+text+"\n"
	terminal_buffers[game.context] = output.right(24000)
	terminal.text = terminal_buffers[game.context]
	terminal.scroll_to_line(maxi(0,terminal.get_line_count()-1))

func _show(next_mode: String, window: Control):
	scroll_finger = -1
	touch_scroll = null
	hide_keyboard()
	game.release_speaker()
	for item in [modal,terminal_panel,dialogue_panel,briefing_panel]: item.hide()
	mode = next_mode
	modal_open = true
	window.show()
	hud.get_parent().get_parent().visible = next_mode == "dialogue"
	message.hide()
	game.player.set_enabled(false)
	game.controls.release_touches()
	for key in ["forward","back","left","right","sprint","crouch","jump"]: Input.action_release(key)
	prompt.hide()
	dot.hide()

func open_tablet(index = 3):
	_show("tablet",modal)
	tabs.current_tab = 3 if index == 2 and not investigation_assigned() else index
	refresh()

func open_briefing(): _show("briefing",briefing_panel)

func open_terminal():
	_show("terminal",terminal_panel)
	refresh()
	if not terminal_buffers.has(game.context):
		var device = game.content.case.devices[game.context]
		terminal_buffers[game.context] = "SECURITY OPERATIONS / "+device.label+"\n접속 사용자: sec.ops · "+device.zone+"\n\n"+device.description+"\n\n명령을 입력하세요. help를 입력하면 이 장비의 도움말이 표시됩니다."
	terminal.text = terminal_buffers[game.context]
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
	hud.get_parent().get_parent().show()
	message.show()
	dot.show()
	prompt.text = ""
	prompt.hide()

func toggle():
	if modal_open: close()
	else: open_tablet()

func notice(text: String):
	message.text = text.left(180)
	var previous = message.text
	get_tree().create_timer(6).timeout.connect(func():
		if is_instance_valid(message) and message.text == previous: message.text = "")
	if modal_open or text.length() > 220:
		var popup = AcceptDialog.new()
		popup.title = "조사 기록" if investigation_assigned() else "업무 알림"
		popup.dialog_text = text
		popup.min_size = Vector2i(mini(650,int(get_viewport().get_visible_rect().size.x)-40),mini(400,int(get_viewport().get_visible_rect().size.y)-40))
		root.add_child(popup)
		popup.confirmed.connect(popup.queue_free)
		popup.canceled.connect(popup.queue_free)
		popup.popup_centered()

func confirm(text: String, callback: Callable):
	var dialog = ConfirmationDialog.new()
	dialog.dialog_text = text
	root.add_child(dialog)
	dialog.confirmed.connect(func(): callback.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(680,int(get_viewport().get_visible_rect().size.x)-40),mini(260,int(get_viewport().get_visible_rect().size.y)-40)))

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
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
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
		prompt.hide()
		return
	if game.detailed_world:
		var text = LabInputBindings.hint(objective_info().text)
		if guide.text != text:
			guide.text = text
			field_objective.reset_size.call_deferred()
	var target = game.player.target
	prompt.text = target.get_interaction_prompt().replace("E · ","F — ") if target != null else ""
	if game.controls.touch_enabled: prompt.text = prompt.text.replace("F — ","")
	prompt.text = LabInputBindings.hint(prompt.text)
	dot.position = game.player.aim_screen_point-Vector2(8,16) if game.player.aim_screen_point.x >= 0 else get_viewport().get_visible_rect().size*.5-Vector2(8,16)
	prompt.visible = target != null
	dot.add_theme_color_override("font_color",Color(.3,1,.75) if target != null else Color(.9,.95,1,.7))

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
	message.position = Vector2(safe.position.x+16,safe.position.y+175)
	message.custom_minimum_size.x = minf(380,safe.size.x-32)
	messenger_contacts.visible = not compact
	contact_picker.visible = compact
	command_sidebar.visible = not compact and help_sessions.get(game.context,false)
	command_input.custom_minimum_size.y = 48 if game.controls.mobile else 0
	for control in [touch_setting,update_setting,claim,contact_picker]:
		control.custom_minimum_size.y = 48 if game.controls.mobile else 0
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
	var editor = LabInputRebinding.new()
	editor.configure(game.bindings,game.player)
	root.add_child(editor)
	editor.popup_centered()

func refresh_input_hints():
	refresh_settings()
	guide.text = LabInputBindings.hint(objective_info().text)
	for control in root.find_children("*","Button",true,false):
		if control.has_meta("binding_text"): control.text = LabInputBindings.hint(control.get_meta("binding_text"))
