extends Node

var game: Node
var failures: Array = []

func check(value: bool, message: String):
	if not value: failures.append(message); push_error(message)

func run(root: Node):
	game = root
	await get_tree().physics_frame
	check(game.world.protected_nodes.size() == 101,"All 101 protected nodes imported")
	check(game.world.collider_count == 89,"All 89 authored colliders imported")
	check(game.world.doors.size() == 3,"Three preserved door pivots")
	check(game.player.global_position.y >= 0 and game.player.camera.global_position.y >= 1.6,"Initial view is above the floor at authored foot-level spawn")
	check(game.equipment.screen_bindings > 0,"Actual monitor surfaces bound")
	check(game.equipment.leds.size() > 0,"Actual server LED materials bound")
	for chair in game.world.layout.chairs:
		var visual = game.world.model.find_child(chair.name,true,false)
		var collider = game.world.protected_nodes[chair.collider].get_node("NativeCollision")
		var shape = collider.get_child(0)
		var center = collider.to_global(shape.position)
		var visible_center = game.world.node_bounds(visual).get_center()
		check(Vector2(center.x-visible_center.x,center.z-visible_center.z).length()<.10,chair.name+" visual and collision remain aligned")
	var m = game.missions
	m.inspect("INTERACT_AdminPC")
	m.apply_answer(0)
	m.run_command("verify")
	check(m.progress().verified and m.score() == 100,"Tutorial evidence, interpretation and field gate")
	m.next_mission()
	m.inspect("INTERACT_ServerRack")
	m.apply_answer(1)
	m.apply_port("443",false)
	m.apply_port("8080",false)
	check(game.ui.recheck_notice.visible and game.ui.recheck_notice.text.contains("자료 서버"),"Tool banner names E recheck destination")
	check(game.world.devices.INTERACT_ServerRack.placard.text.contains("이전 관찰 만료"),"Physical placard agrees with tool banner")
	m.inspect("INTERACT_ServerRack")
	check(game.ui.observation_status.text.contains("문제 남음") and game.ui.observation_text.text.contains("자료 열람 불가"),"Structured field card shows wrong-defense impact")
	m.run_command("verify")
	check(not m.progress().verified,"Wrong defense must fail when HTTPS is blocked")
	m.apply_port("443",true)
	m.run_command("scan club-server")
	m.run_command("verify")
	check(not m.progress().verified,"Terminal scan cannot replace physical recheck")
	m.inspect("INTERACT_ServerRack")
	m.run_command("verify")
	check(m.progress().verified and m.score() == 100,"Services correct defense and normal functionality")
	game.saves.save(m)
	var restored = LabMissions.new()
	check(game.saves.decode(JSON.stringify({"format":"security-lab-native","version":1,"game":game.saves.encode(m)}),restored),"Native save roundtrip")
	check(JSON.stringify(restored.state) == JSON.stringify(m.state),"State roundtrip including spatial evidence and derived checks")
	restored.free()
	print("VERTICAL_SLICE ",JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
