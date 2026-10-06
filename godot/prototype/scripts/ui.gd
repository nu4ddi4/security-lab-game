class_name InvestigationUI
extends CanvasLayer

var game: InvestigationPrototype
var root: Control
var modal: PanelContainer
var modal_open = true
var tabs: TabContainer
var hud: Label
var prompt: Label
var message: Label
var source: Label
var terminal: RichTextLabel
var command_input: LineEdit
var notes: VBoxContainer
var messenger: VBoxContainer
var conversation: RichTextLabel
var npc_select: OptionButton
var report: VBoxContainer
var claim: OptionButton
var attachments = {}
var work: Label
var memo: TextEdit
var ready_memo = false

func setup(controller: InvestigationPrototype):
	game = controller
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansKR.ttf")
	theme.default_font_size = 19
	root.theme = theme
	add_child(root)
	hud = label(root,"")
	hud.position = Vector2(22,18)
	prompt = label(root,"WASD 이동 · E 외관 · F 현장 도구 · Tab/Esc 휴대 단말")
	prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -55
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dot = label(root,"+")
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	message = label(root,"")
	message.position = Vector2(22,100)
	message.custom_minimum_size.x = 900
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left = 50
	modal.offset_right = -50
	modal.offset_top = 50
	modal.offset_bottom = -65
	root.add_child(modal)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	modal.add_child(body)
	var heading = HBoxContainer.new()
	body.add_child(heading)
	var title = label(heading,"잔여 권한 · 조사 프로토타입")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading,"현장으로 · Esc",close)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	for name in ["터미널","노트","메신저","발생 보고","업무"]:
		var scroll = ScrollContainer.new()
		scroll.name = name
		tabs.add_child(scroll)
		var box = VBoxContainer.new()
		box.name = "Body"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation",10)
		scroll.add_child(box)
	var term = tab(0)
	source = label(term,"현장 장비를 선택하세요.")
	var chooser = OptionButton.new()
	chooser.add_item("장비 선택 · 대체 조사")
	for id in game.content.case.devices:
		chooser.add_item(game.content.case.devices[id].label)
		chooser.set_item_metadata(chooser.item_count-1,id)
	chooser.item_selected.connect(func(index):
		if index > 0: game.context = chooser.get_item_metadata(index); refresh())
	term.add_child(chooser)
	terminal = RichTextLabel.new()
	terminal.custom_minimum_size.y = 280
	terminal.selection_enabled = true
	term.add_child(terminal)
	var row = HBoxContainer.new()
	term.add_child(row)
	command_input = LineEdit.new()
	command_input.placeholder_text = "help로 현재 장비의 명령 확인"
	command_input.max_length = 200
	command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(command_input)
	command_input.text_submitted.connect(func(text): game.command(text); command_input.clear())
	button(row,"실행",func(): game.command(command_input.text); command_input.clear())
	notes = VBoxContainer.new()
	tab(1).add_child(notes)
	label(tab(1),"개인 메모 · 내용은 채점하지 않습니다.")
	memo = TextEdit.new()
	memo.custom_minimum_size.y = 150
	tab(1).add_child(memo)
	memo.text_changed.connect(func():
		if ready_memo: game.dispatch({"type":"memo","payload":{"text":memo.text}}))
	sync_memo()
	npc_select = OptionButton.new()
	for id in game.content.case.npcs:
		npc_select.add_item(game.content.case.npcs[id].name+" · "+game.content.case.npcs[id].role)
		npc_select.set_item_metadata(npc_select.item_count-1,id)
	npc_select.item_selected.connect(func(_i): refresh_dialogue())
	tab(2).add_child(npc_select)
	messenger = VBoxContainer.new()
	tab(2).add_child(messenger)
	conversation = RichTextLabel.new()
	conversation.custom_minimum_size.y = 240
	conversation.selection_enabled = true
	tab(2).add_child(conversation)
	report = tab(3)
	label(report,"확인한 행동과 직접 고른 원본을 첨부하세요. 행위자·고의성·외부 반출은 추가 확인 대상입니다.")
	claim = OptionButton.new()
	claim.add_item("주장 선택")
	for c in game.content.rules.claims:
		claim.add_item(c.label)
		claim.set_item_metadata(claim.item_count-1,c.id)
	report.add_child(claim)
	for slot in ["scope","access","collection"]:
		label(report,{"scope":"허용 범위 근거","access":"실제 접근 근거","collection":"실제 수집 근거"}[slot])
		var option = OptionButton.new()
		attachments[slot] = option
		report.add_child(option)
	button(report,"발생 보고 제출",submit_report)
	work = label(tab(4),"")
	work.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(tab(4),"오늘 업무 종료",end_day)
	button(tab(4),"진행 내보내기",func(): file_dialog(true))
	button(tab(4),"진행 가져오기",func(): file_dialog(false))
	button(tab(4),"새 조사",func(): confirm("현재 진행을 보관하고 새 조사를 시작할까요?",game.new_game))
	refresh()
	open_tablet()

func tab(index: int) -> VBoxContainer:
	return tabs.get_child(index).get_node("Body")

func label(parent: Node, text: String) -> Label:
	var node = Label.new()
	node.text = text
	parent.add_child(node)
	return node

func button(parent: Node, text: String, callback: Callable) -> Button:
	var node = Button.new()
	node.text = text
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

func clear(node: Node):
	for child in node.get_children(): node.remove_child(child); child.queue_free()

func sync_memo():
	ready_memo = false
	memo.text = game.state.memo
	ready_memo = true

func refresh():
	var view = game.engine.project(game.state,game.context)
	hud.text = "%d일차 · 수집 작업 %s · 자료 서비스 %s · 검색 %s" % [view.day,"중지" if view.held else "미통제","지연" if view.backupDelay else "정상","정상" if view.indexHealthy else "누락"]
	source.text = view.device.get("label","현장 장비를 선택하세요.")
	clear(notes)
	for record in view.notes:
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
	work.text = "오늘의 필수 운영 확인\n"+("확인 완료" if view.work.is_empty() else "\n".join(view.work))
	work.text += "\n\n발생 보고: "+("승인됨 · 감사 권한 유지" if view.approved else "미승인")
	work.text += "\n확인한 내부 수집 문서: "+("미확인" if view.documentCount < 0 else "%d개 · 반출과 별도" % view.documentCount)
	if view.ended: work.text += "\n\n"+game.engine._t("PROTOTYPE_ENDED")
	for msg in view.messages: work.text += "\n\n%d일차 · %s\n%s" % [msg.day,game.content.case.npcs[msg.npc].name,msg.text]

func refresh_dialogue():
	clear(messenger)
	var npc = npc_select.get_item_metadata(npc_select.selected)
	for q in game.engine.project(game.state).questions:
		if q.npc == npc:
			button(messenger,q.label,func():
				var output = game.dispatch({"type":"dialogue","payload":{"id":q.id}})
				conversation.text = output.text)

func submit_report():
	var selected = {}
	for slot in attachments:
		var option = attachments[slot]
		selected[slot] = option.get_item_metadata(option.selected) if option.selected > 0 else ""
	var value = claim.get_item_metadata(claim.selected) if claim.selected > 0 else ""
	var result = game.dispatch({"type":"report","payload":{"claim":value,"attachments":selected}})
	notice(result.text)

func print_output(command: String, text: String):
	terminal.text = (terminal.text+"\n> "+command+"\n"+text+"\n").right(24000)
	terminal.scroll_to_line(terminal.get_line_count()-1)

func show_tab(index: int):
	modal.show()
	modal_open = true
	game.player.set_enabled(false)
	for key in ["forward","back","left","right","sprint","crouch","jump"]: Input.action_release(key)
	tabs.current_tab = index

func open_tablet(): show_tab(4)
func open_terminal(): show_tab(0); refresh(); command_input.grab_focus()
func open_messenger(id: String):
	for i in range(npc_select.item_count):
		if npc_select.get_item_metadata(i) == id: npc_select.select(i)
	show_tab(2)
	refresh_dialogue()

func close():
	if game.blocked_save: return
	var focused = get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	modal.hide()
	modal_open = false
	game.player.set_enabled(true)

func toggle():
	if modal_open: close()
	else: open_tablet()

func notice(text: String):
	message.text = text.left(180)
	if text.length() > 220:
		var popup = AcceptDialog.new()
		popup.title = "조사 기록"
		popup.dialog_text = text
		popup.min_size = Vector2i(650,400)
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
	dialog.popup_centered(Vector2i(680,260))

func end_day():
	var day = game.state.day
	var text = game.engine._t("CONFIRM_END")
	if day == 7: text = game.engine._t("PROTOTYPE_ENDED_KNOWN" if "E12" in game.state.evidence else "PROTOTYPE_ENDED")+"\n조사로 돌아가려면 취소하세요."
	confirm(text,func():
		var result = game.dispatch({"type":"day.end","payload":{"expectedDay":day,"confirmed":true}})
		notice(result.text))

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
	if game == null or modal_open: return
	prompt.text = game.player.target.get_interaction_prompt() if game.player.target != null else "WASD 이동 · E 외관 · F 현장 도구 · Tab/Esc 휴대 단말"
