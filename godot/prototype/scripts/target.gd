class_name InvestigationTarget
extends Area3D

signal used(id: String, kind: String, tool: bool)
var logical_id = ""
var kind = "device"
var label = ""

func get_interaction_prompt() -> String:
	return label + "\nF — 조작" if kind == "device" else label + "\nF — 대화"

func inspect():
	used.emit(logical_id,kind,false)

func open_tool() -> String:
	return logical_id
