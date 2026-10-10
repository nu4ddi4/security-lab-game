class_name InvestigationDataReset
extends RefCounted

# "데이터 전체 초기화": removes everything the game keeps for the player on this
# device and starts over. Update data, installers, diagnostics and engine logs
# are not player data and stay.
const COUNTDOWN = 3
const UPDATE_PREFERENCE = "beta-update-settings-"

# Isolated test runs (qa_mode) only ever touch their own directory.
static func targets(game: InvestigationPrototype) -> Array:
	if game.qa_mode: return [game.store.directory]
	var paths = [game.store.directory,InvestigationControls.CONFIG_PATH,game.settings.path,game.bindings.path]
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with(UPDATE_PREFERENCE) and name.ends_with(".json"): paths.append("user://"+name)
	return paths

# Returns how many files were removed.
static func wipe(paths: Array) -> int:
	var removed = 0
	for path in paths:
		if DirAccess.dir_exists_absolute(path): removed += _remove_folder(path)
		elif FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK: removed += 1
	return removed

static func _remove_folder(path: String) -> int:
	var removed = 0
	for name in DirAccess.get_files_at(path):
		if DirAccess.remove_absolute(path.path_join(name)) == OK: removed += 1
	for name in DirAccess.get_directories_at(path): removed += _remove_folder(path.path_join(name))
	DirAccess.remove_absolute(path)
	return removed

static func summary() -> String:
	return "삭제되는 항목\n· 조사 진행과 자동 백업, 보존해 둔 이전 진행\n· 개인 메모\n· 소리·화면·시점 설정과 조작키, 터치 사용 여부\n· 업데이트 확인과 Beta 미리보기 선택\n\n유지되는 항목\n· 내보낸 진행 파일, 설치 파일·업데이트 데이터, 진단 정보\n\n되돌릴 수 없습니다. 삭제하려면 잠시 기다린 뒤 버튼을 누르세요."

# The confirm button unlocks after a short countdown so it cannot be hit by accident.
static func confirm(game: InvestigationPrototype):
	var dialog = ConfirmationDialog.new()
	dialog.title = "데이터 전체 초기화"
	dialog.dialog_text = summary()
	dialog.cancel_button_text = "취소"
	game.ui.root.add_child(dialog)
	var ok = dialog.get_ok_button()
	ok.theme_type_variation = "DangerButton"
	ok.disabled = true
	dialog.confirmed.connect(func():
		game.ui.notice("%d개 파일을 지우고 처음 상태로 돌아갔습니다." % game.reset_all_data())
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(mini(680,int(game.ui.get_viewport().get_visible_rect().size.x)-40),mini(420,int(game.ui.get_viewport().get_visible_rect().size.y)-40)))
	for remaining in range(COUNTDOWN,0,-1):
		if not is_instance_valid(dialog): return
		ok.text = "모두 삭제 (%d)" % remaining
		await game.get_tree().create_timer(1.0).timeout
	if not is_instance_valid(dialog): return
	ok.text = "모두 삭제"
	ok.disabled = false
	dialog.get_cancel_button().grab_focus()
