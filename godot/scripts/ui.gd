class_name LabUI
extends CanvasLayer

signal resume_requested
signal reset_position_requested
signal save_requested
signal settings_requested
signal import_requested(path: String)
var missions: LabMissions
var player: LabPlayer
var root: Control
var hud: VBoxContainer
var title: Label
var detail: Label
var next_action: Label
var prompt: Label
var observation_text: Label
var modal: PanelContainer
var panel_content: VBoxContainer
var tabs: TabContainer
var terminal: RichTextLabel
var answers: VBoxContainer
var evidence: Label
var modal_open = true
var current_tab = "Notes"
var results_text: RichTextLabel
var status = "새 조사"
var toast: Label
var observations_timeout = 0.0

func setup(manager: LabMissions, actor: LabPlayer, load_status: String):
	missions = manager
	player = actor
	status = load_status
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	var font = FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansKR.ttf")
	font.variation_opentype = {2003265652:450.0}
	theme.default_font = font
	theme.default_font_size = 19
	for type in ["PanelContainer","TabContainer"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(.028,.047,.067,.97)
		style.border_color = Color(.20,.31,.38)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(18)
		theme.set_stylebox("panel" if type == "TabContainer" else "panel",type,style)
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color(.09,.16,.20)
	button_style.set_content_margin_all(10)
	button_style.set_corner_radius_all(4)
	theme.set_stylebox("normal","Button",button_style)
	var hover = button_style.duplicate()
	hover.bg_color = Color(.16,.28,.32)
	theme.set_stylebox("hover","Button",hover)
	root.theme = theme
	add_child(root)
	var hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(24,24)
	hud_panel.custom_minimum_size = Vector2(490,0)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_panel)
	hud = VBoxContainer.new()
	hud_panel.add_child(hud)
	title = label(hud,"SECURITY LAB",24)
	title.modulate = Color(.69,.86,.87)
	detail = label(hud,"",17)
	next_action = label(hud,"",18)
	next_action.custom_minimum_size.x = 450
	next_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt = label(root,"",20)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -88
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var crosshair = label(root,"·",26)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(5,20)
	observation_text = label(root,"",17)
	observation_text.position = Vector2(24,650)
	observation_text.custom_minimum_size = Vector2(570,180)
	observation_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast = label(root,"",16)
	toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	toast.offset_top = -30
	toast.offset_left = 24
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left = 100
	modal.offset_right = -100
	modal.offset_top = 65
	modal.offset_bottom = -65
	root.add_child(modal)
	panel_content = VBoxContainer.new()
	panel_content.add_theme_constant_override("separation",12)
	modal.add_child(panel_content)
	var heading = HBoxContainer.new()
	panel_content.add_child(heading)
	var logo = label(heading,"SECURITY LAB  /  NATIVE",25)
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading,"탐색 계속 · Esc",close_tool)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_content.add_child(tabs)
	for name in ["Terminal","Settings","Files","Comparison","Notes"]:
		var scroll = ScrollContainer.new()
		scroll.name = name
		tabs.add_child(scroll)
		var body = VBoxContainer.new()
		body.name = "Body"
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation",12)
		scroll.add_child(body)
	var term_body = tab_body("Terminal")
	label(term_body,"내장 가상 명령만 실행합니다. 실제 네트워크와 운영체제에 연결하지 않습니다.",17)
	terminal = RichTextLabel.new()
	terminal.custom_minimum_size.y = 240
	terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terminal.selection_enabled = true
	term_body.add_child(terminal)
	var input_row = HBoxContainer.new()
	term_body.add_child(input_row)
	var input = LineEdit.new()
	input.name = "Command"
	input.placeholder_text = "help / inspect / scan / hash / verify"
	input.max_length = 200
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(input)
	input.text_submitted.connect(func(value): execute(value); input.clear())
	button(input_row,"실행",func(): execute(input.text); input.clear())
	var quick = HBoxContainer.new()
	quick.name = "QuickCommands"
	term_body.add_child(quick)
	var notes = tab_body("Notes")
	label(notes,"조사 노트 · 근거를 확인한 뒤 원인을 판단하세요.",21)
	evidence = label(notes,"",18)
	evidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answers = VBoxContainer.new()
	notes.add_child(answers)
	results_text = RichTextLabel.new()
	results_text.fit_content = true
	results_text.custom_minimum_size.y = 120
	notes.add_child(results_text)
	var actions = HFlowContainer.new()
	panel_content.add_child(actions)
	button(actions,"현재 상태 재검증",func(): execute("verify"); refresh())
	button(actions,"다음 미션",func(): missions.next_mission(); refresh())
	button(actions,"저장",func(): save_requested.emit())
	button(actions,"환경 설정",func(): settings_requested.emit())
	button(actions,"출입구로 복귀",func(): reset_position_requested.emit(); close_tool())
	button(actions,"진행 가져오기",show_import)
	button(actions,"미션 초기화",func(): missions.reset_mission(); terminal.clear(); refresh())
	button(actions,"종료",func(): save_requested.emit(); get_tree().quit())
	missions.state_changed.connect(refresh)
	missions.observation.connect(show_observation)
	refresh()
	open_tool("Notes")
	toast.text = status + "  · WASD 이동 / 마우스 시점 / Shift 달리기 / Ctrl·C 앉기 / Space 점프 / E 조사 / F 도구"

func tab_body(name: String) -> VBoxContainer:
	return tabs.get_node(name+"/Body")

func label(parent: Node, text: String, size = 19) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable) -> Button:
	var node = Button.new()
	node.text = text
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func clear_children(node: Node):
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func refresh():
	if missions == null or tabs == null: return
	var m = missions.mission()
	var p = missions.progress()
	title.text = "%02d / 04   %s" % [missions.state.active+1,m.title]
	detail.text = "%s  ·  근거 %d/%d  ·  %d점" % [missions.stage(), m.evidence.filter(func(key): return key in p.clues).size(),m.evidence.size(),missions.score()]
	next_action.text = missions.action().text
	clear_children(answers)
	for i in range(m.answers.size()):
		var option = button(answers,("✓  " if p.answer == i else "○  ") + m.answers[i],func(): missions.apply_answer(i))
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.tooltip_text = m.answerFeedback[i] if m.evidence.all(func(key): return key in p.clues) else m.investigation
	evidence.text = m.objective + "\n\n" + "\n".join(p.clues.map(func(key): return "• " + m.clues[key].label))
	results_text.text = (m.answerFeedback[p.answer] if p.answer != null and m.evidence.all(func(key): return key in p.clues) else m.investigation) + "\n\n" + "\n".join(p.checks.map(func(check): return ("통과 · " if check.passed else "미충족 · ") + check.label))
	var quick = tab_body("Terminal").get_node("QuickCommands")
	clear_children(quick)
	for command in m.quickCommands: button(quick,command,func(): execute(command))
	refresh_settings()
	refresh_files()
	var comparison = tab_body("Comparison")
	clear_children(comparison)
	label(comparison,"방어 전 / 후 관찰",23)
	for key in ["before","after"]:
		var snapshot = p.observations[key]
		label(comparison,("변경 전" if key == "before" else "변경 후") + "\n" + (JSON.stringify(snapshot,"  ") if snapshot != null else "아직 관찰하지 않았습니다."),18)
	label(comparison,"설정 변경 후 E 현장 재확인: " + ("완료" if p.get("spatial",{}).get("rechecked",false) else "필요" if p.observations.changed else "설정 변경 전"))
	observation_text.text = ""

func refresh_settings():
	var body = tab_body("Settings")
	clear_children(body)
	label(body,"방어 정책 · 정상 기능도 함께 유지하세요.",23)
	if missions.mission().id == "services":
		for port in ["443","8080"]:
			var checkbox = CheckBox.new()
			checkbox.text = port + (" · 필수 HTTPS 자료 서비스 접근 허용" if port == "443" else " · 사용하지 않는 관리 서비스 접근 허용")
			checkbox.button_pressed = missions.state.ports[port]
			checkbox.toggled.connect(func(allowed): missions.apply_port(port,allowed))
			body.add_child(checkbox)
	elif missions.mission().id == "login":
		label(body,"실제 비밀번호는 입력하지 않습니다. 더미 사용자와 후보만 검사합니다.",18)
		var length = OptionButton.new()
		for value in [6,12,15]: length.add_item("최소 길이 %d자" % value)
		length.selected = [6,12,15].find(int(missions.state.login.minLength))
		body.add_child(length)
		var common = CheckBox.new()
		common.text = "흔한 값 차단"
		common.button_pressed = missions.state.login.blockCommon
		body.add_child(common)
		var attempts = CheckBox.new()
		attempts.text = "연속 실패 3회 후 제한"
		attempts.button_pressed = missions.state.login.limitAttempts
		body.add_child(attempts)
		button(body,"로그인 정책 적용",func(): missions.apply_login({"minLength":[6,12,15][length.selected],"blockCommon":common.button_pressed,"limitAttempts":attempts.button_pressed}))
	else: label(body,missions.mission().defenseGuidance,18)
	label(body,missions.action().text,18)

func refresh_files():
	var body = tab_body("Files")
	clear_children(body)
	label(body,"내장 파일 · 승인된 오프라인 기준",23)
	label(body,"개인 파일이나 실제 비밀번호를 수집하지 않습니다.",17)
	for filename in missions.definitions.original_files:
		label(body,filename,20)
		label(body,missions.state.files[filename],17)
		if missions.mission().id == "integrity":
			label(body,"승인된 원본:\n" + missions.definitions.original_files[filename],17)
			for row in missions.progress().hashes:
				if row.name == filename:
					var hash_label = label(body,("일치" if row.matches else "변경 감지") + "\n현재 " + row.actual + "\n기준 " + row.expected,15)
					hash_label.modulate = Color(.49,.75,.66) if row.matches else Color(.85,.65,.41)
			var restore = button(body,filename + " · 승인된 원본으로 복구",func(): missions.restore_file(filename))
			restore.disabled = not missions.can_restore()

func execute(command: String):
	var output = missions.run_command(command.strip_edges())
	terminal.append_text("\n> " + command + "\n" + output + "\n")
	terminal.scroll_to_line(terminal.get_line_count()-1)
	results_text.text += "\n" + output if command == "verify" else ""

func open_tool(tab: String):
	current_tab = tab
	tabs.current_tab = ["Terminal","Settings","Files","Comparison","Notes"].find(tab)
	modal.show()
	modal_open = true
	player.set_enabled(false)
	refresh()

func close_tool():
	var focused = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	modal.hide()
	modal_open = false
	player.set_enabled(true)
	resume_requested.emit()

func pause():
	if modal_open: close_tool()
	else: open_tool("Notes")

func show_observation(result: Dictionary):
	observation_text.text = result.label + "  /  " + result.status + "\n" + "\n".join(result.findings).substr(0,480) + "\n" + ("노트에 기록되었습니다.  " if result.recorded else "") + result.next
	observations_timeout = 14.0

func show_import():
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Security Lab 진행 JSON"])
	dialog.file_selected.connect(func(path): import_requested.emit(path); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	root.add_child(dialog)
	dialog.popup_centered(Vector2i(850,550))

func _process(delta):
	if player == null or missions == null: return
	if not modal_open:
		prompt.text = player.target.get_interaction_prompt() if player.target != null else "WASD 이동  ·  E 현장 조사  ·  F 상세 도구  ·  Esc 노트"
		var action = missions.action()
		var direction = ""
		if action.device != "":
			var target = player.get_parent().get_node("World").devices.get(action.device)
			if target != null:
				var point = target.global_transform * target.get_child(0).position
				var local = player.camera.global_basis.inverse() * (point-player.camera.global_position)
				var arrow = "앞" if abs(local.x) < abs(local.z)*.45 and local.z < 0 else "뒤" if abs(local.x) < abs(local.z)*.45 else "오른쪽" if local.x > 0 else "왼쪽"
				direction = "\n%s · %s · 직선 %.1fm" % [target.zone,arrow,player.global_position.distance_to(point)]
		next_action.text = action.text + direction
	observations_timeout -= delta
	if observations_timeout <= 0: observation_text.text = ""
