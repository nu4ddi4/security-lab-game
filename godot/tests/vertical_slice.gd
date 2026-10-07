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
	check(game.equipment.screen_bindings > 0,"Actual monitor surfaces bound")
	check(game.equipment.leds.size() > 0,"Actual server LED materials bound")
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
	m.inspect("INTERACT_ServerRack")
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
