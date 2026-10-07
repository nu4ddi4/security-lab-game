class_name InvestigationDiagnostics
extends "res://scripts/diagnostics.gd"

func setup(root: Node):
	game = root
	save_directory = game.store.directory
	data_directory = save_directory.path_join("diagnostics")
	update_directory = "user://beta-updates"
	if game.qa_mode:
		log_directory = save_directory.path_join("diagnostics-logs")
	if supported(): begin_session()

func build_info() -> Dictionary:
	return serializer.build(read_json("res://prototype/build_info.json").get("data",{}))

func save_validation() -> Dictionary:
	var result = {}
	for name in ["save.json","save.backup.json"]:
		var loaded = read_json(save_directory.path_join(name),262144)
		var status = loaded.status
		if status=="ok": status = "valid" if InvestigationSaveCodec.decode(JSON.stringify(loaded.data),game.content).has("state") else "invalid"
		result[name] = {"status":status}
	return result

func runtime_summary() -> Dictionary:
	if game==null: return {"available":false}
	return {"available":true,"scene":"investigation_beta","uptime_ms":Time.get_ticks_msec(),"day":clampi(int(game.state.day),1,7),"save_blocked":game.blocked_save,"devices":game.targets.size(),"player_enabled":game.player.enabled,"on_floor":game.player.is_on_floor()}
