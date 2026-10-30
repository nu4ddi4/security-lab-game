class_name InvestigationEntryScreen
extends RefCounted

var ui: InvestigationUI
var panel: PanelContainer
var layout: GridContainer
var menu: VBoxContainer
var introduction: VBoxContainer
var title: Label
var description: Label
var resume: Button
var new_game: Button
var tablet: Button
var main_menu: Button
var quit: Button
var intro_progress: Label
var intro_title: Label
var intro_body: Label
var intro_previous: Button
var intro_next: Button
var intro_index = 0
var intro_seen = false

func build(owner: InvestigationUI):
	ui = owner
	panel = ui.panel(0,0,1,1)
	panel.name = "Entry"
	panel.theme_type_variation = "ShellRoot"
	panel.add_theme_stylebox_override("panel",InvestigationTheme.box(InvestigationTheme.BACKDROP,InvestigationTheme.BACKDROP,0,24,0))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin = MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	center.add_child(margin)
	layout = GridContainer.new()
	layout.add_theme_constant_override("h_separation",80)
	layout.add_theme_constant_override("v_separation",32)
	margin.add_child(layout)
	var identity = VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation",20)
	layout.add_child(identity)
	ui.label(identity,"SECURITY LAB","CaptionLabel")
	title = ui.label(identity,"잔여 권한","TitleLabel")
	title.add_theme_font_size_override("font_size",52)
	description = ui.label(identity,"남겨진 기록을 읽고,\n당신의 판단으로 일주일의 업무를 마치세요.")
	description.add_theme_font_size_override("font_size",18)
	ui.label(identity,ContentVersion.running(),"CaptionLabel")
	menu = VBoxContainer.new()
	menu.custom_minimum_size.x = 260
	menu.add_theme_constant_override("separation",12)
	layout.add_child(menu)
	resume = action(menu,"계속하기",ui.resume_session,true)
	new_game = action(menu,"새 게임",request_new_game)
	tablet = action(menu,"휴대 단말",func(): ui.open_tablet())
	action(menu,"설정",ui.open_rebinding)
	main_menu = action(menu,"메인 화면",ui.return_to_main_menu)
	quit = action(menu,"게임 종료",func(): ui.confirm("진행을 저장하고 게임을 종료할까요?",ui.game.quit_game))
	introduction = VBoxContainer.new()
	introduction.add_theme_constant_override("separation",24)
	layout.add_child(introduction)
	intro_progress = ui.label(introduction,"","CaptionLabel")
	intro_title = ui.label(introduction,"","HeadingLabel")
	intro_title.add_theme_font_size_override("font_size",32)
	intro_body = ui.label(introduction,"")
	intro_body.add_theme_font_size_override("font_size",18)
	intro_body.add_theme_constant_override("line_spacing",8)
	var navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation",12)
	introduction.add_child(navigation)
	intro_previous = action(navigation,"이전",previous_intro)
	intro_next = action(navigation,"다음",next_intro,true)
	action(introduction,"소개 건너뛰기",finish_intro)
	panel.resized.connect(fit)
	fit()

func action(parent: Node, text: String, callback: Callable, primary = false) -> Button:
	var result = ui.button(parent,text,callback,"PrimaryButton" if primary else "Button")
	result.custom_minimum_size.y = 48
	return result

func fit():
	if layout == null: return
	# Use the available viewport, since a previous wide minimum can keep the
	# panel itself wider than the screen until the new layout is applied.
	var area = ui.game.safe_rect().size
	var width = area.x
	var narrow = width < 900 and not (area.y < 640 and width >= 700)
	layout.columns = 1 if narrow else 2
	layout.add_theme_constant_override("h_separation",40 if width < 1100 else 80)
	layout.custom_minimum_size.x = minf(940,maxf(0,width-96))
	description.custom_minimum_size.x = 0 if narrow else 220 if width < 850 else 320 if width < 1100 else 380
	introduction.custom_minimum_size.x = 0 if narrow else 360 if width < 1100 else 440
	panel.set_anchors_and_offsets_preset.call_deferred(Control.PRESET_FULL_RECT)

func show_menu(paused: bool):
	ui._show("pause" if paused else "main_menu",panel)
	title.text = "일시정지" if paused else "잔여 권한"
	description.text = ui.guide_info().title if paused else "남겨진 기록을 읽고,\n당신의 판단으로 일주일의 업무를 마치세요."
	resume.disabled = ui.game.blocked_save or not ui.game.session_available
	new_game.visible = not paused
	tablet.visible = paused
	main_menu.visible = paused
	menu.show()
	introduction.hide()
	fit()
	(resume if not resume.disabled else new_game).grab_focus()

func request_new_game():
	if ui.game.session_available or ui.game.blocked_save:
		ui.confirm("현재 진행을 보관하고 새 게임을 시작할까요?",ui.game.new_game)
	else: ui.game.new_game()

func show_intro():
	intro_index = 0
	ui._show("intro",panel)
	title.text = "잔여 권한"
	description.text = "첫 출근을 앞두고"
	menu.hide()
	introduction.show()
	refresh_intro()
	fit()

func refresh_intro():
	var pages = ui.game.content.case.introduction
	var page = pages[intro_index]
	intro_progress.text = "%02d / %02d" % [intro_index+1,pages.size()]
	intro_title.text = page.heading
	intro_body.text = page.body
	intro_previous.text = "메인 화면" if intro_index == 0 else "이전"
	intro_next.text = "첫 업무 시작" if intro_index == pages.size()-1 else "다음"
	intro_next.grab_focus()

func previous_intro():
	if intro_index == 0: show_menu(false); return
	intro_index -= 1
	refresh_intro()

func next_intro():
	if intro_index == ui.game.content.case.introduction.size()-1: finish_intro(); return
	intro_index += 1
	refresh_intro()

func finish_intro():
	intro_seen = true
	ui.open_briefing()
