class_name InvestigationTarget
extends Area3D

signal used(id: String, kind: String, tool: bool)
var logical_id = ""
var kind = "device"
var label = ""

func get_interaction_prompt() -> String:
	return label + " · E 외관 / F 터미널" if kind == "device" else label + " · E/F 대화"

func inspect():
	used.emit(logical_id,kind,false)

func open_tool() -> String:
	return logical_id
