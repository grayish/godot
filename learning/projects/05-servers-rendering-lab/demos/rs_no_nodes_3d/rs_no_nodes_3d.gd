extends Control

## 데모 1: 같은 박스 N개를 세 가지 방식으로 그리고 비용을 비교한다.
##  (a) MeshInstance3D 노드 N개       — 노드마다 Object + Node 데이터 + 알림 + 트리 순회 비용
##  (b) MultiMeshInstance3D 1개        — 서버 쪽 트랜스폼 버퍼 하나, GPU 인스턴싱으로 드로우콜 1회
##  (c) RenderingServer.instance_create() N개 — 노드 없이 RID 만 들고 서버에 직접 명령 (3.7 절)
## 엔진: servers/rendering/renderer_scene_cull.cpp instance_allocate(:568) instance_set_base(:606)
##       instance_set_scenario(:849) instance_set_transform(:1012) — (a)(b)(c) 모두 결국 여기로 온다.
##       scene/3d/visual_instance_3d.cpp — MeshInstance3D 는 NOTIFICATION_TRANSFORM_CHANGED 를 받은 뒤에야
##       RS.instance_set_transform 을 부른다. 노드가 하는 일은 "RID 리모컨" 이다 (3.6 절).
##       servers/rendering/rendering_server_default.h — 모든 RS 호출은 FUNCn 매크로를 거쳐
##       CommandQueueMT(core/templates/command_queue_mt.h) 에 들어가거나(렌더 스레드 분리 시) 직접 실행된다.

enum Mode { NODES, MULTIMESH, SERVER }

const DEFAULT_COUNT: int = 1000
const BOX_SIZE: float = 0.6
const SPACING: float = 1.4

@onready var sub_viewport: SubViewport = $ViewportContainer/SubViewport
@onready var camera: Camera3D = $ViewportContainer/SubViewport/Camera3D

var mode: Mode = Mode.SERVER
var count: int = DEFAULT_COUNT
var box_mesh: BoxMesh
var elapsed: float = 0.0
var stats_timer: float = 0.0
var last_update_usec: int = 0

# (a) 노드 방식
var node_holder: Node3D = null
var mesh_nodes: Array[MeshInstance3D] = []
# (b) MultiMesh 방식
var multimesh_instance: MultiMeshInstance3D = null
# (c) 순수 서버 방식: RID 만 보관한다. 노드가 없으니 해제도 우리가 한다.
var server_instances: Array[RID] = []

var mode_option: OptionButton
var count_spin: SpinBox
var stats_label: Label


func _ready() -> void:
	box_mesh = BoxMesh.new()
	box_mesh.size = Vector3.ONE * BOX_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.55, 0.2)
	# PrimitiveMesh.material 은 서버의 mesh surface material 로 들어가므로 (c) 에서도 그대로 보인다.
	box_mesh.material = material
	$ViewportContainer/SubViewport/DirectionalLight3D.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	_build_ui()
	_rebuild()
	Log.info("(a) 는 노드마다 set_transform → NOTIFICATION_TRANSFORM_CHANGED 전파 → RS.instance_set_transform 순으로 갑니다.")
	Log.info("(b) 는 MultiMesh 버퍼(PackedFloat32Array) 하나를 서버에 올리고 드로우콜 1회로 그립니다.")
	Log.info("(c) 는 노드 없이 RID 배열만 두고 RS 에 직접 명령합니다. 그래도 instance_set_transform 은 CommandQueueMT 를 거칩니다.")
	Log.info("OBJECT_NODE_COUNT 가 (a) 에서만 N 만큼 늘어나는 것을 확인하세요. 모드와 개수를 바꾼 뒤 '적용'.")


func _exit_tree() -> void:
	# 노드/MultiMesh 는 씬과 함께 해제되지만 (c) 의 RID 는 직접 반납해야 한다.
	_free_server_instances()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(8, 8)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	mode_option = OptionButton.new()
	mode_option.add_item("(a) MeshInstance3D 노드")
	mode_option.add_item("(b) MultiMeshInstance3D")
	mode_option.add_item("(c) RenderingServer 인스턴스")
	mode_option.select(mode)
	row.add_child(mode_option)
	count_spin = SpinBox.new()
	count_spin.min_value = 100
	count_spin.max_value = 20000
	count_spin.step = 100
	count_spin.value = count
	row.add_child(count_spin)
	var apply := Button.new()
	apply.text = "적용"
	apply.pressed.connect(_on_apply)
	row.add_child(apply)
	stats_label = Label.new()
	stats_label.text = "..."
	box.add_child(stats_label)


func _on_apply() -> void:
	mode = mode_option.selected as Mode
	count = int(count_spin.value)
	_rebuild()


func _rebuild() -> void:
	_clear()
	var t0: int = Time.get_ticks_usec()
	match mode:
		Mode.NODES:
			_build_nodes()
		Mode.MULTIMESH:
			_build_multimesh()
		Mode.SERVER:
			_build_server()
	var build_usec: int = Time.get_ticks_usec() - t0
	_place_camera()
	Log.info("%s: %d개 생성에 %.2f ms" % [_mode_name(mode), count, build_usec / 1000.0])


func _build_nodes() -> void:
	node_holder = Node3D.new()
	sub_viewport.add_child(node_holder)
	for i: int in count:
		var mi := MeshInstance3D.new()
		mi.mesh = box_mesh
		mi.transform = compute_transform(i, count, elapsed)
		node_holder.add_child(mi)
		mesh_nodes.append(mi)


func _build_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box_mesh
	mm.instance_count = count
	for i: int in count:
		mm.set_instance_transform(i, compute_transform(i, count, elapsed))
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.multimesh = mm
	sub_viewport.add_child(multimesh_instance)


func _build_server() -> void:
	# 3.7 절의 예시 그대로: scenario 는 World3D 가 소유한 서버 쪽 "3D 월드" RID.
	var scenario: RID = camera.get_world_3d().scenario
	for i: int in count:
		var inst: RID = RenderingServer.instance_create()
		RenderingServer.instance_set_scenario(inst, scenario)
		RenderingServer.instance_set_base(inst, box_mesh.get_rid())
		RenderingServer.instance_set_transform(inst, compute_transform(i, count, elapsed))
		server_instances.append(inst)


func _clear() -> void:
	mesh_nodes.clear()
	if node_holder != null:
		node_holder.free()
		node_holder = null
	if multimesh_instance != null:
		multimesh_instance.free()
		multimesh_instance = null
	_free_server_instances()


func _free_server_instances() -> void:
	for inst: RID in server_instances:
		RenderingServer.free_rid(inst)
	server_instances.clear()


func _process(delta: float) -> void:
	elapsed += delta
	var t0: int = Time.get_ticks_usec()
	match mode:
		Mode.NODES:
			for i: int in mesh_nodes.size():
				mesh_nodes[i].transform = compute_transform(i, count, elapsed)
		Mode.MULTIMESH:
			if multimesh_instance != null:
				var mm: MultiMesh = multimesh_instance.multimesh
				for i: int in count:
					mm.set_instance_transform(i, compute_transform(i, count, elapsed))
		Mode.SERVER:
			for i: int in server_instances.size():
				RenderingServer.instance_set_transform(server_instances[i], compute_transform(i, count, elapsed))
	last_update_usec = Time.get_ticks_usec() - t0
	stats_timer += delta
	if stats_timer >= 0.5:
		stats_timer = 0.0
		_update_stats()


func _update_stats() -> void:
	var text: String = "%s | FPS %d | 트랜스폼 갱신 루프 %.2f ms\n" % [_mode_name(mode), Engine.get_frames_per_second(), last_update_usec / 1000.0]
	text += "RENDER_TOTAL_OBJECTS_IN_FRAME %d | RENDER_TOTAL_DRAW_CALLS_IN_FRAME %d\n" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	]
	text += "TIME_PROCESS %.2f ms | OBJECT_NODE_COUNT %d" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	]
	stats_label.text = text


func _place_camera() -> void:
	var side: float = ceil(sqrt(float(count)))
	var dist: float = side * SPACING
	camera.far = maxf(200.0, dist * 4.0)
	camera.look_at_from_position(Vector3(0.0, dist * 0.8, dist * 0.9), Vector3.ZERO)


func _mode_name(m: Mode) -> String:
	match m:
		Mode.NODES:
			return "(a) MeshInstance3D 노드"
		Mode.MULTIMESH:
			return "(b) MultiMeshInstance3D"
	return "(c) RenderingServer 인스턴스"


## 격자 위에 놓고 시간에 따라 위아래로 흔들며 회전시키는 트랜스폼. 순수 함수라 셀프테스트에서도 검사한다.
static func compute_transform(index: int, total: int, time: float) -> Transform3D:
	var side: int = maxi(1, ceili(sqrt(float(total))))
	var col: int = index % side
	var row: int = int(index / float(side))
	var x: float = (col - side * 0.5) * SPACING
	var z: float = (row - side * 0.5) * SPACING
	var y: float = sin(time * 2.0 + index * 0.05) * 0.5
	var basis := Basis(Vector3.UP, time + index * 0.01)
	return Transform3D(basis, Vector3(x, y, z))
