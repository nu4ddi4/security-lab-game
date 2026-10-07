class_name LabDoor
extends StaticBody3D

signal moved

var pivot: Node3D
var leaf_shape: CollisionShape3D
var player: LabPlayer
var desired_angle = 0.0
var open_angle = deg_to_rad(100.0)
var local_bounds: AABB
var blocked = false

func setup(node: Node3D, bounds: Array, actor: LabPlayer, angle: float):
	pivot = node
	player = actor
	open_angle = deg_to_rad(angle)
	local_bounds = AABB(Vector3(bounds[0], bounds[2], -bounds[4]), Vector3(bounds[3]-bounds[0], bounds[5]-bounds[2], bounds[4]-bounds[1]))
	leaf_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = local_bounds.size
	leaf_shape.shape = box
	leaf_shape.position = local_bounds.get_center()
	add_child(leaf_shape)
	collision_layer = 5
	collision_mask = 8

func get_interaction_prompt() -> String:
	return "E · 문 열기" if desired_angle == 0 else "E · 문 닫기"

func inspect():
	desired_angle = open_angle if desired_angle == 0 else 0.0
	moved.emit()

func _physics_process(delta):
	if pivot == null: return
	var old = pivot.rotation.y
	var candidate = move_toward(old, desired_angle, delta * open_angle / 0.45)
	if is_equal_approx(old, candidate): return
	# Conservative swept leaf sampling prevents opening OR closing through a body.
	for fraction in [0.33, 0.66, 1.0]:
		var t = pivot.global_transform * Transform3D(Basis(Vector3.UP, (candidate-old)*fraction), Vector3.ZERO)
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = leaf_shape.shape
		query.transform = t.translated_local(local_bounds.get_center())
		query.collision_mask = 8
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			blocked = true
			return
	blocked = false
	pivot.rotation.y = candidate
