class_name TerminalStageEntry
extends InvestigationEntryScreen

func build(owner: InvestigationUI):
	super.build(owner)
	introduction.get_child(introduction.get_child_count()-1).hide()

func show_menu(paused: bool):
	super.show_menu(paused)
	title.text = "일시정지" if paused else "퇴근.exe"
	description.text = "STAGE %02d · %s" % [ui.game.state.stage.index,ui.game.content.stages[int(ui.game.state.stage.index)-1].title] if paused else "명령어 하나 잘못 썼을 뿐인데."
	if not paused and ui.game.legacy_progress: description.text += "\n새 게임을 시작하면 이전 진행을 보관합니다."
	new_game.text = "처음부터" if ui.game.session_available else "시작하기"
	tablet.text = "스테이지 선택"
	tablet.visible = true
	tablet.disabled = not ui.game.session_available

func show_intro():
	super.show_intro()
	title.text = "퇴근.exe"
	description.text = "회사 컴퓨터는 생각보다 예민합니다."

func refresh_intro():
	intro_progress.text = "신입사원 PC 적응 과정"
	intro_title.text = "6대를 고치면 퇴근"
	intro_body.text = "명령어를 입력해 각 컴퓨터의 문제를 해결하세요.\n\n첫 두 대는 연습용입니다.\n세 번째부터 잘못 입력하면 컴퓨터가 터집니다."
	intro_previous.text = "메인 화면"
	intro_next.text = "첫 PC 켜기"

func previous_intro(): show_menu(false)
func next_intro(): finish_intro()
func finish_intro():
	intro_seen = true
	ui.call("begin_stage")
