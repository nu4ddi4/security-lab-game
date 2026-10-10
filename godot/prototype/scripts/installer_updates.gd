class_name InvestigationInstallerUpdates
extends "res://scripts/update_manager.gd"

func build_info_path() -> String: return "res://prototype/build_info.json"
func stage_root() -> String: return "user://beta-updates"
func automatic_check_enabled() -> bool: return game.controls.automatic_updates
func save_progress() -> bool: return game.save_now()
func data_directory() -> String: return "user://"
func valid_saved_progress() -> bool: return game.store.load_state(game.content).has("state")
func pause_for_install(): game.ui.open_tablet(4)
func beta_preview() -> bool: return game.beta_preview()
