class_name LabDevice
extends Area3D

var device_id: String
var missions: LabMissions
var display_name: String
var zone: String
var placard: Label3D

func setup(id: String, manager: LabMissions, box: AABB):
	device_id = id
	missions = manager
	display_name = manager.definitions.devices[id].label
	zone = manager.definitions.devices[id].zone
	collision_layer = 2
	collision_mask = 0
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	collision.position = box.get_center()
	add_child(collision)
	placard = Label3D.new()
	placard.position = box.get_center() + Vector3(0,0,.061)
	placard.pixel_size = .00135
	placard.font_size = 30
	placard.font = load("res://assets/fonts/NotoSansKR.ttf")
	placard.modulate = Color(.72,.87,.88)
	placard.outline_modulate = Color(.025,.045,.06)
	placard.outline_size = 10
	add_child(placard)
	missions.state_changed.connect(update_placard)
	update_placard()

func update_placard():
	var action = missions.action()
	var inspected = device_id in missions.progress().get("spatial",{}).get("inspected",[])
	placard.text = display_name + "\n" + ("E · 재확인" if action.device == device_id and action.mode == "recheck" else "현장 단서 확보" if inspected else "E 조사 / F 도구")
	placard.modulate = Color(.86,.70,.47) if action.device == device_id and action.mode == "recheck" else Color(.72,.87,.88)

func get_interaction_prompt() -> String:
	return "E · 변경 후 상태 재확인 / F · 상세 도구" if missions.action().mode == "recheck" and missions.action().device == device_id else "E · 현장 조사 / F · " + ("접근 정책" if device_id == "INTERACT_Router" else "파일 비교" if device_id == "INTERACT_FileCabinet" else "조사 노트 · 도구")

func inspect():
	missions.inspect(device_id)

func open_tool() -> String:
	if device_id == "INTERACT_Router": return "Settings"
	if device_id == "INTERACT_FileCabinet": return "Files"
	if device_id == "INTERACT_Whiteboard": return "Notes"
	return "Terminal" if missions.mission().id in ["tutorial", "services"] else "Files" if missions.mission().id == "integrity" else "Settings"
