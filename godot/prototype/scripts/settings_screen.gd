class_name InvestigationSettingsScreen
extends LabInputRebinding

# A full-screen, embedded settings window reuses the native binding editor's
# capture/validation/save rules. It owns no mission state or duplicate key map.
var game: InvestigationPrototype
var original_controls = {}
var pages = {}
var navigation = {}
var category = "controls"
var layout: HBoxContainer
var sidebar: VBoxContainer
var compact_navigation: OptionButton
var preview_column: VBoxContainer
var conflict_card: PanelContainer
var conflict_text: Label
var preview_key: Label
var preview_title: Label
var preview_image: TextureRect
var subtitle: Label
var mouse_options: VBoxContainer
var keys_options: VBoxContainer
var fields = {}
var background: TextureRect
var footer_tip: Label
var content: VBoxContainer
var current_action = "tool"
const CATEGORIES = [["general","일반","업데이트 · 진단 / 지원"],["display","화면","디스플레이 · 그래픽"],["sound","사운드","전체 소리 · 효과음"],["controls","조작","키 설정 · 마우스 · 터치"]]

func text(parent: Node, value: String, font_size = 16, color = InvestigationTheme.TEXT) -> Label:
	var label = add_label(parent,value,font_size)
	label.add_theme_color_override("font_color",color)
	if font_size >= 18: label.add_theme_font_override("font",InvestigationTheme.font(InvestigationTheme.BOLD_WEIGHT))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func running_version() -> String:
	return ContentVersion.running()

func action_button(parent: Node, value: String, callback: Callable, primary = false) -> Button:
	var node = add_button(parent,value,callback)
	node.custom_minimum_size.y = 32
	node.add_theme_font_size_override("font_size",14)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if primary: node.theme_type_variation = "PrimaryButton"
	return node

func card(parent: Node) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	parent.add_child(panel)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	panel.add_child(body)
	return body

func _ready():
	prepare_window()
	borderless = true
	unresizable = true
	transparent_bg = false
	# All text is rendered by Godot. The reference image is never used as UI.
	var surface = Control.new()
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background = TextureRect.new()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	surface.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.material = InvestigationTheme.backdrop_material()
	var shade = ColorRect.new()
	shade.color = Color(InvestigationTheme.BACKDROP,.4)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin = MarginContainer.new()
	surface.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",14)
	margin.add_child(body)
	var assigned = game.ui.investigation_assigned()
	var close_button = Button.new()
	close_button.text = "닫기"
	close_button.custom_minimum_size.y = 48 if game.controls.mobile else 34
	close_button.add_theme_font_size_override("font_size",16 if game.controls.mobile else 14)
	close_button.pressed.connect(func(): close_editor())
	var header = InvestigationTheme.shell_header(body,[["노트",0],["메신저",1],["발생 보고",2,assigned],["업무",3],["설정",4]],4,func(id): if id != 4: leave_for(id),running_version(),game.controls.mobile,[close_button])
	header.buttons[4].mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel = PanelContainer.new()
	panel.theme_type_variation = "ShellPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	layout = HBoxContainer.new()
	layout.add_theme_constant_override("separation",24)
	panel.add_child(layout)
	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 218
	sidebar.add_theme_constant_override("separation",12)
	layout.add_child(sidebar)
	text(sidebar,"설정",26)
	text(sidebar,"게임 환경을 원하는 대로 구성하세요.",13,InvestigationTheme.TEXT_DIM)
	for entry in CATEGORIES:
		var b = action_button(sidebar,entry[1]+"\n"+entry[2],func(): select_category(entry[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 68
		navigation[entry[0]] = b
	var divider = VSeparator.new()
	sidebar.add_child(divider)
	text(sidebar,"LOCAL SIMULATION\n설정 변경은 조사 진행에 영향을 주지 않습니다.",12,InvestigationTheme.TEXT_FAINT)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",12)
	layout.add_child(content)
	compact_navigation = OptionButton.new()
	for entry in CATEGORIES: compact_navigation.add_item(entry[1])
	compact_navigation.item_selected.connect(func(i): select_category(CATEGORIES[i][0]))
	content.add_child(compact_navigation)
	subtitle = text(content,"조작",26)
	for entry in CATEGORIES:
		var scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(scroll)
		var page = VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation",12)
		scroll.add_child(page)
		pages[entry[0]] = page
	build_controls(pages.controls)
	build_general(pages.general)
	build_display(pages.display)
	build_sound(pages.sound)
	var footer = HBoxContainer.new()
	body.add_child(footer)
	footer_tip = text(footer,"키와 화면·소리는 저장 후 적용됩니다.\n터치와 업데이트 옵션은 즉시 저장됩니다.",12,InvestigationTheme.TEXT_DIM)
	footer_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button = action_button(footer,"기본값",restore_defaults)
	cancel_button = action_button(footer,"입력 대기 취소",cancel_capture)
	action_button(footer,"취소",close_editor)
	save_button = action_button(footer,"✓  저장하기",save_changes,true)
	select_category("controls")
	size_changed.connect(fit)
	refresh_buttons()

func build_controls(page: VBoxContainer):
	text(page,"키보드와 마우스 등 입력 장치를 설정합니다.",14,InvestigationTheme.TEXT_DIM)
	var modes = HBoxContainer.new()
	page.add_child(modes)
	action_button(modes,"키 설정",func(): keys_options.show(); mouse_options.hide(),true)
	action_button(modes,"마우스 / 터치",func(): cancel_capture(); keys_options.hide(); mouse_options.show())
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation",18)
	page.add_child(columns)
	keys_options = VBoxContainer.new()
	keys_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(keys_options)
	text(keys_options,"주요 조작 키",20)
	text(keys_options,"재설정을 누르고 새 키 하나를 입력하세요.",13,InvestigationTheme.TEXT_DIM)
	var rows = card(keys_options)
	rows.add_theme_constant_override("separation",2)
	for definition in LabInputBindings.ACTIONS:
		if definition.id == "inspect": continue
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		rows.add_child(row)
		var title = "상호작용" if definition.id == "tool" else "일시정지 / 휴대 단말" if definition.id == "pause" else definition.label+"로 이동" if definition.id in ["forward","back","left","right"] else definition.label
		var label = text(row,title,15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key = action_button(row,LabInputBindings.names(draft[definition.id]),func(): begin_capture(definition.id))
		key.custom_minimum_size.x = 132
		buttons[definition.id] = key
		var change = action_button(row,"재설정",func(): begin_capture(definition.id))
		change.custom_minimum_size.x = 76
		change.set_meta("action",definition.id)
	status = text(keys_options,"변경 사항은 저장하기를 눌러 확정합니다.",13,InvestigationTheme.TEXT_DIM)
	status.custom_minimum_size.y = 32
	preview_column = VBoxContainer.new()
	preview_column.custom_minimum_size.x = 270
	preview_column.add_theme_constant_override("separation",14)
	columns.add_child(preview_column)
	var conflict = card(preview_column)
	conflict_card = conflict.get_parent()
	text(conflict,"키 충돌 확인",18)
	conflict_text = text(conflict,"충돌 없음\n같은 키를 다른 동작에 중복 할당할 수 없습니다.",14,InvestigationTheme.TEXT_DIM)
	var preview = card(preview_column)
	text(preview,"미리보기",18,InvestigationTheme.ACCENT)
	text(preview,"게임 안에서 이렇게 표시됩니다.",13)
	preview_image = TextureRect.new()
	preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview_image.custom_minimum_size.y = 140
	preview.add_child(preview_image)
	var prompt_panel = PanelContainer.new()
	preview_image.add_child(prompt_panel)
	prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt_panel.anchor_left = .06
	prompt_panel.anchor_right = .94
	prompt_panel.anchor_top = .46
	prompt_panel.anchor_bottom = .95
	prompt_panel.theme_type_variation = "KeyCapPanel"
	var prompt_card = HBoxContainer.new()
	prompt_card.add_theme_constant_override("separation",10)
	prompt_panel.add_child(prompt_card)
	preview_key = text(prompt_card,"F",24,InvestigationTheme.ACCENT)
	preview_key.custom_minimum_size.x = 42
	preview_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_title = text(prompt_card,"상호작용\n장비 조사 · 대화 · 문 열기",12)
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_options = VBoxContainer.new()
	page.add_child(mouse_options)
	mouse_options.hide()
	fields.sensitivity = setting_slider(mouse_options,"마우스 감도",game.settings.values.sensitivity,.0005,.004,.0001)
	fields.fov = setting_slider(mouse_options,"시야각",game.settings.values.fov,60,90,1)
	game.ui.touch_setting = CheckButton.new()
	game.ui.touch_setting.text = "터치 조작 사용 · 키보드도 함께 사용"
	mouse_options.add_child(game.ui.touch_setting)
	game.ui.touch_setting.toggled.connect(game.controls.set_touch)
	game.ui.input_status = text(mouse_options,"")
	text(mouse_options,"터치: 왼쪽 엄지 이동 · 오른쪽 쓸어 시점\n장비를 탭해 선택한 뒤 상호작용합니다.",14)

func build_general(page: VBoxContainer):
	var updates = card(page)
	text(updates,"업데이트",20)
	text(updates,"현재 빌드 · "+running_version(),14)
	game.ui.update_setting = CheckButton.new()
	game.ui.update_setting.text = "시작할 때 내 채널의 업데이트 확인"
	updates.add_child(game.ui.update_setting)
	game.ui.update_setting.toggled.connect(game.controls.set_automatic_updates)
	game.ui.preview_setting = CheckButton.new()
	game.ui.preview_setting.text = "Beta 업데이트 미리보기"
	updates.add_child(game.ui.preview_setting)
	game.ui.preview_setting.toggled.connect(func(enabled):
		game.controls.set_beta_preview(enabled)
		game.check_updates())
	text(updates,"정식 릴리스가 아니어도 beta 커밋마다 나오는 빌드를 받습니다. 불안정할 수 있으며 저장은 유지됩니다.",13,InvestigationTheme.TEXT_DIM)
	game.ui.update_status = text(updates,"")
	game.ui.update_bar = ProgressBar.new()
	game.ui.update_bar.show_percentage = false
	game.ui.update_bar.custom_minimum_size.y = 8
	game.ui.update_bar.hide()
	updates.add_child(game.ui.update_bar)
	game.ui.update_check = action_button(updates,"업데이트 확인",game.check_updates)
	game.ui.update_download = action_button(updates,"업데이트 확인하고 설치…",func():
		if game.updater != null: game.updater.request_install()
		else: game.ui.confirm("업데이트를 다운로드할까요? 저장은 유지됩니다.",game.updates.open_download))
	var reset = card(page)
	text(reset,"데이터 전체 초기화",20)
	text(reset,"이 기기에 저장된 조사 진행·메모·설정을 모두 지우고 처음 상태로 시작합니다. 삭제 전에 지워지는 항목을 확인합니다.",14,InvestigationTheme.TEXT_DIM)
	action_button(reset,"데이터 전체 초기화…",func(): InvestigationDataReset.confirm(game)).theme_type_variation = "DangerButton"
	var diagnostics = card(page)
	text(diagnostics,"진단 / 지원",20)
	text(diagnostics,"이 기기에서만 수집합니다. 저장 원문·계정·네트워크 주소는 포함하지 않습니다.",14,InvestigationTheme.TEXT_DIM)
	var result = text(diagnostics,"")
	for entry in [["진단 정보 복사","copy"],["지원 패키지 만들기","package"],["생성 폴더 열기","folder"]]:
		var b = action_button(diagnostics,entry[0],func():
			if entry[1] == "copy": result.text = game.diagnostics.copy_information().message
			elif entry[1] == "package": result.text = game.diagnostics.create_package().message
			elif game.diagnostics.last_package.is_empty(): result.text = "먼저 지원 패키지를 만드세요."
			elif OS.shell_open(game.diagnostics.last_package.get_base_dir()) != OK: result.text = "폴더를 열지 못했습니다.")
		b.disabled = OS.get_name() != "Windows"

func build_display(page: VBoxContainer):
	var body = card(page)
	fields.resolution = setting_options(body,"창 해상도",["1600 × 900","1280 × 720","1920 × 1080"],game.settings.values.resolution)
	fields.quality = setting_options(body,"그래픽 품질",["Low · 80% 해상도","Medium · 2× MSAA","High · 4× MSAA","Ultra · 8× MSAA"],game.settings.values.quality)
	for entry in [["fullscreen","전체 화면"],["vsync","VSync · 화면 찢어짐 방지"]]:
		var check = CheckButton.new()
		check.text = entry[1]
		check.button_pressed = game.settings.values[entry[0]]
		body.add_child(check)
		fields[entry[0]] = check
	text(body,"현재 렌더러: "+RenderingServer.get_current_rendering_method()+"\n지원하는 효과만 적용합니다.",13,InvestigationTheme.TEXT_DIM)

func build_sound(page: VBoxContainer):
	var body = card(page)
	fields.master = setting_slider(body,"전체 소리 · 0은 음소거",game.settings.values.master,0,1,.05)
	fields.sfx = setting_slider(body,"환경음 / 효과음",game.settings.values.sfx,0,1,.05)
	text(body,"환경음과 효과음의 크기를 조절합니다.",14,InvestigationTheme.TEXT_DIM)

func setting_options(parent: Node, title: String, options: Array, value: int) -> OptionButton:
	text(parent,title,16)
	var control = OptionButton.new()
	for option in options: control.add_item(option)
	control.selected = value
	control.custom_minimum_size.y = 40
	parent.add_child(control)
	return control

func setting_slider(parent: Node, title: String, value: float, low: float, high: float, step: float) -> HSlider:
	var label = text(parent,title+"  ·  "+str(value),16)
	var slider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 36
	slider.value_changed.connect(func(next): label.text = title+"  ·  "+str(snappedf(next,step)))
	parent.add_child(slider)
	return slider

func select_category(id: String):
	cancel_capture()
	category = id
	for entry in CATEGORIES:
		var selected = entry[0] == id
		pages[entry[0]].get_parent().visible = selected
		navigation[entry[0]].theme_type_variation = "PrimaryButton" if selected else "Button"
		if selected:
			subtitle.text = entry[1]
			compact_navigation.selected = CATEGORIES.find(entry)
	fit()

func fit():
	if sidebar == null: return
	var narrow = size.x < 760
	sidebar.visible = not narrow
	compact_navigation.visible = narrow
	preview_column.visible = size.x >= 1200
	sidebar.custom_minimum_size.x = 180 if size.x < 1100 else 218
	for key in buttons:
		buttons[key].custom_minimum_size.x = 90 if narrow else 132
	footer_tip.visible = size.x >= 850

func begin_capture(action: String):
	current_action = action
	super.begin_capture(action)
	conflict_text.text = "새 키를 기다리고 있습니다.\nEsc도 할당할 키입니다. 취소 버튼으로 대기를 끝내세요."
	conflict_text.add_theme_color_override("font_color",InvestigationTheme.ACCENT)
	conflict_card.theme_type_variation = "CardPanel"

func cancel_capture():
	var waiting = not capture_action.is_empty()
	super.cancel_capture()
	if waiting and conflict_text != null:
		conflict_text.text = "입력 대기를 취소했습니다.\n현재 키 할당에는 충돌이 없습니다."
		conflict_text.add_theme_color_override("font_color",InvestigationTheme.ACCENT)
		conflict_card.theme_type_variation = "CardPanel"

func handle_input(event: InputEvent):
	var pending = capture_action
	super.handle_input(event)
	if not pending.is_empty():
		conflict_text.text = status.text
		conflict_text.add_theme_color_override("font_color",InvestigationTheme.DANGER if not capture_action.is_empty() else InvestigationTheme.ACCENT)
		conflict_card.theme_type_variation = "WarningPanel" if not capture_action.is_empty() else "CardPanel"
		refresh_preview()

func refresh_buttons():
	super.refresh_buttons()
	for node in keys_options.find_children("*","Button",true,false):
		if node.has_meta("action"): node.disabled = not capture_action.is_empty()
	refresh_preview()

func refresh_preview():
	if preview_key == null: return
	preview_key.text = LabInputBindings.names(draft[current_action])
	preview_title.text = "상호작용\n장비 조사 · 대화 · 문 열기" if current_action == "tool" else LabInputBindings.label_for(current_action)

func restore_defaults():
	super.restore_defaults()
	var defaults = LabSettings.DEFAULT_VALUES.duplicate()
	defaults.quality = 2
	for id in fields:
		var control = fields[id]
		if control is OptionButton: control.selected = defaults[id]
		elif control is CheckButton: control.button_pressed = defaults[id]
		else: control.value = defaults[id]
	conflict_text.text = "기본값으로 복원했습니다.\n저장하기를 눌러 적용하세요."

func save_changes():
	var result = bindings.save_profile(draft)
	status.text = result.message
	if not result.ok:
		select_category("controls")
		return
	var candidate = game.settings.values.duplicate(true)
	for id in fields:
		var control = fields[id]
		candidate[id] = control.selected if control is OptionButton else control.button_pressed if control is CheckButton else control.value
	result = game.settings.save_values(candidate)
	status.text = result.message if result.ok else "조작키는 저장되었습니다. "+result.message
	if result.ok: close_editor()
	else: select_category("controls")

# Going back to the game closes the tablet too; moving to another tablet page keeps it open so the
# pointer is never recaptured and re-centred in between.
func close_editor(keep_tablet := false):
	capture_action = ""
	hide()
	release_player()
	game.ui.settings_screen = null
	for key in original_controls: game.ui.set(key,original_controls[key])
	game.ui.refresh_settings()
	if not keep_tablet: game.ui.close()
	queue_free()

func leave_for(index: int):
	close_editor(true)
	game.ui.open_tablet(index)

