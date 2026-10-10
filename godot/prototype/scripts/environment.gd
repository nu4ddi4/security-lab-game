class_name InvestigationEnvironment
extends Node3D

# The authored overlay owns placement, reach volumes, speaker focus and review
# poses. Logical IDs remain the case/save IDs, never mesh names or coordinates.
var model: Node3D
var anchors: Dictionary = {}
var targets: Dictionary = {}
var displays: Dictionary = {}
var last_visual_state = ""
var world: LabWorld

const GOOD = Color(.25,.72,.63)
const WARNING = Color(.9,.6,.25)

class EquipmentDisplay extends Control:
	var heading = ""
	var rows: Array = []
	var tone = GOOD
	var font = preload("res://assets/fonts/NotoSansKR.ttf")
	var paper_board = false

	func _draw():
		if paper_board:
			_draw_whiteboard()
			return
		draw_rect(Rect2(0,0,640,360),InvestigationTheme.BACKDROP)
		draw_rect(Rect2(0,0,640,7),tone)
		draw_string(font,Vector2(27,40),"SECURITY OPERATIONS   /   LOCAL SYSTEM",HORIZONTAL_ALIGNMENT_LEFT,600,15,InvestigationTheme.TEXT_FAINT)
		draw_string(font,Vector2(27,83),heading,HORIZONTAL_ALIGNMENT_LEFT,585,28,InvestigationTheme.TEXT)
		for i in rows.size():
			var y = 128+i*43
			draw_rect(Rect2(28,y-19,5,23),tone)
			draw_string(font,Vector2(47,y),str(rows[i]),HORIZONTAL_ALIGNMENT_LEFT,560,21,InvestigationTheme.TEXT_DIM)
		draw_line(Vector2(28,315),Vector2(610,315),InvestigationTheme.BORDER,1)
		draw_string(font,Vector2(28,342),"원본 기록과 조작은 현장 단말에서 확인",HORIZONTAL_ALIGNMENT_LEFT,600,16,InvestigationTheme.TEXT_FAINT)

	func _draw_whiteboard():
		var ink = Color(.055,.15,.23)
		draw_string(font,Vector2(26,53),heading,HORIZONTAL_ALIGNMENT_LEFT,590,42,ink)
		draw_polyline(PackedVector2Array([Vector2(28,64),Vector2(245,66),Vector2(380,63)]),ink,2,true)
		for i in rows.size():
			var y = 112+i*57
			var marker = Color(.42,.12,.08) if i in [1,2] and tone.r > .7 else ink
			draw_polyline(PackedVector2Array([Vector2(29,y-18),Vector2(42,y-17),Vector2(43,y-3),Vector2(28,y-4),Vector2(29,y-18)]),marker,1.6,true)
			draw_string(font,Vector2(54+(i%2)*3,y),str(rows[i]),HORIZONTAL_ALIGNMENT_LEFT,560,30,marker)
		draw_string(font,Vector2(365,343),"원본 기록으로 재확인!",HORIZONTAL_ALIGNMENT_LEFT,255,25,ink)

func setup(office: LabWorld, content: Dictionary):
	world = office
	model = load("res://assets/models/Investigation_Environment.glb").instantiate()
	add_child(model)
	_collect(model)
	for marker in anchors.values():
		if marker.has_meta("base_root"):
			var base = world.model.find_child(str(marker.get_meta("base_root")),true,false)
			if base is Node3D: base.global_position += marker.position
		if marker.has_meta("replace_base_collision"):
			var collider = world.protected_nodes.get(str(marker.get_meta("replace_base_collision")))
			if collider != null:
				var body = collider.get_node_or_null("NativeCollision")
				if body != null: body.collision_layer = 0
	var root = anchors.get("Investigation_Environment")
	if root != null:
		for source_name in str(root.get_meta("hide_base","")).split("|"):
			var node = world.model.find_child(source_name.replace(".","_"),true,false)
			if node is GeometryInstance3D: node.hide()
	for marker in anchors.values():
		if marker.has_meta("cull_node"): _cull(marker)
		if marker.has_meta("base_collider"):
			_refine_surface(marker)
		if marker.has_meta("collision_size"):
			var body = StaticBody3D.new()
			body.name = "InvestigationCollision"
			body.collision_layer = 1
			marker.add_child(body)
			world.box_collision(body,AABB(-_size(marker,"collision_size")*.5,_size(marker,"collision_size")))
		if not marker.has_meta("logical_id") or not str(marker.name).begins_with("INTERACT_"): continue
		var id = str(marker.get_meta("logical_id"))
		var kind = str(marker.get_meta("kind"))
		var definition = content.case.devices[id] if kind == "device" else content.case.npcs[id]
		var target = InvestigationTarget.new()
		target.name = "Target_"+id
		target.logical_id = id
		target.kind = kind
		target.label = definition.label if kind == "device" else definition.name+" · "+definition.role
		target.collision_layer = 2
		target.collision_mask = 0
		add_child(target)
		target.global_transform = marker.global_transform
		world.box_collision(target,AABB(-_size(marker,"target_size")*.5,_size(marker,"target_size")))
		targets[id] = target
		if kind == "device":
			var source_name = str(marker.get_meta("screen_node","SCREEN_"+id))
			var mesh = world.model.find_child(source_name,true,false) if marker.has_meta("screen_node") else anchors.get(source_name)
			if mesh is MeshInstance3D: _display(id,mesh)

func _collect(node: Node):
	if node is Node3D:
		anchors[str(node.name)] = node
		# Godot imports Blender custom properties under the glTF extras namespace.
		for key in node.get_meta("extras",{}): node.set_meta(key,node.get_meta("extras")[key])
	for child in node.get_children(): _collect(child)

func _size(node: Node3D, key: String) -> Vector3:
	var values = node.get_meta(key)
	return Vector3(values[0],values[1],values[2])

# Decoration that cannot be moved separately (a conduit drop in front of a display) is cut out of
# its base mesh, inside the box the overlay marker describes.
func _cull(marker: Node3D):
	var target = world.model.find_child(str(marker.get_meta("cull_node")),true,false)
	if not target is MeshInstance3D: return
	var size = _size(marker,"cull_size")
	target.mesh = InvestigationEnvironment.without_region(target.mesh,target.global_transform,AABB(marker.global_position-size*.5,size))

static func without_region(source: Mesh, transform: Transform3D, region: AABB) -> ArrayMesh:
	var result = ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty(): indices = PackedInt32Array(range(vertices.size()))
		var kept = PackedInt32Array()
		for i in range(0,indices.size()-2,3):
			var outside = false
			for corner in 3:
				if not region.has_point(transform*vertices[indices[i+corner]]): outside = true
			if outside:
				kept.push_back(indices[i])
				kept.push_back(indices[i+1])
				kept.push_back(indices[i+2])
		if kept.is_empty(): continue
		arrays[Mesh.ARRAY_INDEX] = kept
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
		result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(surface))
	return result

func _refine_surface(marker: Node3D):
	var collider = world.protected_nodes.get(str(marker.get_meta("base_collider")))
	if collider == null: return
	var body = collider.get_node_or_null("NativeCollision")
	if body == null or body.get_child_count()==0: return
	var collision = body.get_child(0)
	if not collision is CollisionShape3D: return
	var shape = collision.shape.duplicate()
	var height = float(marker.get_meta("surface_height"))
	shape.size.y = height
	collision.shape = shape
	collision.position.y = height*.5

func _display(id: String, mesh: MeshInstance3D):
	var viewport = SubViewport.new()
	viewport.name = "Display_"+id
	viewport.size = Vector2i(640,360)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var canvas = EquipmentDisplay.new()
	if id == "briefing_board":
		canvas.paper_board = true
		canvas.font = load("res://assets/fonts/Gaegu-Regular.ttf")
		viewport.transparent_bg = true
	canvas.size = viewport.size
	viewport.add_child(canvas)
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if canvas.paper_board:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = .65
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.albedo_texture = viewport.get_texture()
	# Viewport textures have no mip chain. These small, event-updated screens use
	# linear filtering, including on the exported Compatibility renderer.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mesh.material_override = material
	displays[id] = {"viewport":viewport,"canvas":canvas}
	var marker = anchors["INTERACT_Investigation_"+id]
	for name in str(marker.get_meta("additional_screens","")).split("|",false):
		var additional = world.model.find_child(name,true,false)
		if additional is MeshInstance3D: additional.material_override = material

func sync(state: Dictionary):
	# Only public operational state. Hidden access/collection evidence and the
	# responsible person are never exposed by a screen or by advancing the day.
	var visual = {"day":state.day,"ended":state.ended,"delay":state.ops.backupDelay,"index":state.ops.indexHealthy,"approved":state.report.approved,"serviceChecked":state.ops.serviceVerifiedDay==state.day,"searchChecked":state.ops.searchVerifiedDay==state.day}
	var signature = JSON.stringify(visual)
	if signature == last_visual_state: return
	last_visual_state = signature
	var service = "자료 서비스 지연" if visual.delay else "자료 서비스 정상"
	var search = "검색 색인 점검 필요" if not visual.index else "검색 색인 정상"
	var data = {
		"control_console":["관제 / 감사 단말",["%d일차 · 운영 점검" % visual.day,service,search,"감사 원본 열람 승인" if visual.approved else "감사 원본 · 승인 필요"]],
		"server_console":["문서 서비스 / 백업 운영",[service,"서비스 재검증 완료" if visual.serviceChecked else "서비스 확인 대기","백업 · 서버 단말에서 점검","실행 기록 · 원본 조회 필요"]],
		"project_pc":["LUMEN / 업무 자료",[search,"검색 재검증 완료" if visual.searchChecked else "검색 확인 대기","설계 · 계약 · 가격 자료","원본 파일 · 업무 PC에서 조회"]],
		"maintenance_terminal":["협력업체 / 정비 단말",["임시 유지보수 작업석","작업 범위 · 승인 원본 대조","제출 이력 · 정비 단말","담당자 연락 · 휴대 단말"]],
		"approval_archive":["승인 원본 / W-218",["보관 원본 · 현장 열람","승인 범위 · 원본 대조"]],
		"briefing_board":["%d일차 / 운영 인계" % visual.day,["점검 종료 · 기록 보관" if visual.ended else "서비스 → 검색 → 운영 재확인",service,search,"노트 · 근거 대조 / 보고 · 휴대 단말"]],
	}
	for id in displays:
		var display = displays[id]
		display.canvas.heading = data[id][0]
		display.canvas.rows = data[id][1]
		display.canvas.tone = WARNING if (id in ["server_console","control_console","briefing_board"] and visual.delay or id in ["project_pc","control_console","briefing_board"] and not visual.index) else GOOD
		display.canvas.queue_redraw()
		display.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func speaker_position(id: String) -> Vector3:
	return anchors["SPEAKER_"+id].global_position

func review_target(actor: LabPlayer, id: String):
	actor.global_position = anchors["APPROACH_"+id].global_position
	actor.velocity = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	actor.camera.look_at(speaker_position(id) if targets[id].kind=="npc" else targets[id].global_position)

func spawn(actor: LabPlayer):
	var marker = anchors.SPAWN_Investigation
	actor.global_transform = marker.global_transform
	actor.camera.look_at(anchors[str(marker.get_meta("look_at"))].global_position)
