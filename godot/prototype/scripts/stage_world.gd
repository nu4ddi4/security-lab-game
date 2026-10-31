class_name OfficeStageWorld
extends Node3D

var game: InvestigationPrototype
var avatar: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var course: Node3D
var key = ""
var stride = 0.0
var originals: Array[Node3D] = []
var fragments: Array[Node3D] = []
var animations: Array[Tween] = []
const START = Vector3(0,8,0)
const FINISH = Vector3(8.4,9.5,0)

func setup(owner: InvestigationPrototype):
	game = owner
	avatar = Node3D.new()
	avatar.name = "EmployeeCharacter"
	game.player.add_child(avatar)
	mesh_part(avatar,Vector3(0,1.1,0),Vector3(.55,.6,.32),Color("29485c"))
	mesh_part(avatar,Vector3(0,1.64,0),Vector3(.38,.42,.35),Color("f1bf93"))
	mesh_part(avatar,Vector3(0,1.87,.01),Vector3(.42,.13,.38),Color("25313b"))
	mesh_part(avatar,Vector3(0,1.7,.15),Vector3(.39,.3,.08),Color("25313b"))
	for side in [-1,1]:
		mesh_part(avatar,Vector3(side*.09,1.68,-.18),Vector3(.045,.055,.02),Color("18212c"))
	mesh_part(avatar,Vector3(0,1.18,-.18),Vector3(.14,.19,.025),Color("ffbf48"))
	for side in [-1,1]:
		var leg = Node3D.new()
		avatar.add_child(leg)
		leg.position = Vector3(side*.16,.8,0)
		mesh_part(leg,Vector3(0,-.33,0),Vector3(.23,.65,.25),Color("26313f"))
		mesh_part(leg,Vector3(0,-.7,-.07),Vector3(.26,.14,.4),Color("121c28"))
		legs.append(leg)
		var arm = Node3D.new()
		avatar.add_child(arm)
		arm.position = Vector3(side*.37,1.35,0)
		mesh_part(arm,Vector3(0,-.25,0),Vector3(.19,.6,.23),Color("29485c"))
		mesh_part(arm,Vector3(0,-.59,0),Vector3(.18,.18,.21),Color("f1bf93"))
		arms.append(arm)
	game.player.enable_third_person()
	course = Node3D.new()
	course.name = "OvertimeRoofCourse"
	add_child(course)
	platform(START-Vector3(0,.2,0),Vector3(2.4,.4,3))
	for i in range(1,6): platform(START+Vector3(i*1.4,i*.3-.2,0),Vector3(.95,.4,1.6))
	platform(FINISH-Vector3(0,.2,0),Vector3(2.1,.4,3))
	mesh_part(course,FINISH+Vector3(0,.5,0),Vector3(.9,1,.6),Color("293442"))
	var monitor = mesh_part(course,FINISH+Vector3(0,1.2,0),Vector3(.9,.55,.15),Color("73dfc7"))
	monitor.name = "ShutdownMonitor"
	game._target("shutdown_pc","device",FINISH+Vector3(0,1,0),"마지막 컴퓨터 · 전원 스위치")
	course.hide()
	game.targets.shutdown_pc.monitoring = false

func mesh_part(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = position
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func platform(point: Vector3, size: Vector3):
	var body = StaticBody3D.new()
	course.add_child(body)
	body.position = point
	body.collision_layer = 1
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	mesh_part(body,Vector3.ZERO,size,Color("d69639"))

func prepare_stage():
	var current = "%d:%d" % [game.state.stage.index,game.state.stage.attempt]
	if key == current: return
	key = current
	restore_computers()
	course.visible = game.state.stage.index == 6
	game.targets.shutdown_pc.collision_layer = 2 if course.visible else 0
	if course.visible:
		game.player.global_position = START+Vector3(0,.05,0)
		game.player.rotation.y = -PI/2
	else: game.reset_player_pose()
	game.player.camera.rotation = Vector3.ZERO
	game.player.velocity = Vector3.ZERO

func at_finish() -> bool:
	return game.player.global_position.distance_to(FINISH) < 1.8 and game.player.is_on_floor()

func _physics_process(delta):
	if game == null or game.ui == null: return
	var walking = game.player.enabled and Vector2(game.player.velocity.x,game.player.velocity.z).length() > .1
	stride += delta*9 if walking else 0.0
	for i in range(2):
		legs[i].rotation.x = sin(stride+PI*i)*.55 if walking else 0.0
		arms[i].rotation.x = -legs[i].rotation.x*.7
	if game.player.enabled and game.state.stage.index == 6 and game.state.stage.phase == "playing" and game.player.global_position.y < 7.2:
		game.ui.command_result(game.dispatch({"type":"stage.fall"}))

func break_computer(id: String):
	restore_computers()
	var point = game.targets[id].global_position
	if game.detailed_world and game.investigation_environment.anchors.has("APPROACH_"+id):
		game.player.camera.reparent(game)
		game.player.camera.global_position = game.investigation_environment.anchors["APPROACH_"+id].global_position+Vector3(0,1.65,0)
		game.player.camera.look_at(point)
	var sources: Array[Node] = []
	if game.detailed_world:
		sources = game.world.model.find_children("*","MeshInstance3D",true,false)+game.investigation_environment.model.find_children("*","MeshInstance3D",true,false)
	else: sources = game.find_children("*","MeshInstance3D",true,false)
	if id == "shutdown_pc": sources = [course.get_node("ShutdownMonitor")]
	for node in sources:
		if not node.is_visible_in_tree(): continue
		var name_lower = str(node.name).to_lower()
		if not ("screen" in name_lower or "computer" in name_lower or "housing" in name_lower or "monitor" in name_lower): continue
		var center = node.global_transform*node.get_aabb().get_center()
		if center.distance_to(point) > 1.6: continue
		originals.append(node)
		node.hide()
		var pivot = Node3D.new()
		add_child(pivot)
		pivot.global_position = center
		var copy = MeshInstance3D.new()
		copy.mesh = node.mesh
		copy.material_override = node.material_override
		pivot.add_child(copy)
		copy.global_transform = node.global_transform
		fragments.append(pivot)
		var offset = Vector3(randf_range(-1,1),randf_range(.7,1.5),randf_range(-1,1))
		var animation = create_tween().set_parallel()
		animations.append(animation)
		animation.tween_property(pivot,"position",center+offset,.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		animation.tween_property(pivot,"rotation",offset*3,.6)
		animation.chain().tween_property(pivot,"position:y",point.y-.7,.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func restore_computers():
	for animation in animations:
		if animation.is_valid(): animation.kill()
	animations.clear()
	for node in originals:
		if is_instance_valid(node): node.show()
	originals.clear()
	for node in fragments:
		if is_instance_valid(node): node.queue_free()
	fragments.clear()
