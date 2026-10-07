class_name InvestigationContent
extends RefCounted

static func load_case() -> Dictionary:
	var result = {}
	for key in ["case", "records", "commands", "dialogue", "rules", "text"]:
		var filename = "text.ko" if key == "text" else key
		var parser = JSON.new()
		var path = "res://prototype/content/" + filename + ".json"
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			return {"error": "사건 자료를 읽지 못했습니다: " + filename}
		result[key] = parser.data
	if not result.case is Dictionary or not result.records is Dictionary or not result.commands is Array or not result.dialogue is Array or not result.rules is Dictionary or not result.text is Dictionary:
		return {"error": "사건 자료 형식이 올바르지 않습니다."}
	for command in result.commands:
		for id in command.devices:
			if not result.case.devices.has(id): return {"error": "알 수 없는 장비 ID"}
	for question in result.dialogue:
		if not result.case.npcs.has(question.npc) or question.record != "" and not result.records.has(question.record): return {"error": "대화 자료 참조 오류"}
	return result
