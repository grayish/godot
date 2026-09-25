extends Control
## 데모 6: PackedScene 과 SceneState 들여다보기.
## 엔진: scene/resources/packed_scene.cpp — SceneState 는 .tscn 을 파싱한 "노드/속성/연결 표" (nodes[], variants[], connections[]).
##   PackedScene::instantiate() → SceneState::instantiate() 가 표를 따라 노드를 만들고, 속성을 set 하고, owner 를 씬 루트로 잡은 뒤
##   [connection] 항목을 connect 한다. .tscn 텍스트 ↔ SceneState 변환은 scene/resources/resource_format_text.cpp.
##   PackedScene::pack(node) 는 반대로 owner 가 그 노드인 서브트리만 표로 만든다.

const SAMPLE: PackedScene = preload("res://demos/packed_scene_inspect/sample.tscn")

var _instance_host: Control
var _instance: Node = null


func _ready() -> void:
	_build_ui()
	Log.section("데모 6: PackedScene / SceneState")
	Log.info("sample.tscn 을 preload 했습니다. instantiate 전에는 리소스 안에 SceneState(노드 표)만 있습니다.")
	_dump_state()
	_instantiate()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	_add_button(row, "SceneState 덤프", _dump_state)
	_add_button(row, "instantiate → owner / 트리 출력", _instantiate)
	_add_button(row, "pack() 으로 다시 포장", _repack)
	_add_button(row, "인스턴스 제거", _remove_instance)

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "SceneState = .tscn 의 표 형태. 노드마다 (이름, 타입, 부모 경로, 속성 목록), 연결마다 (signal, from, to, method).\nowner: 씬 루트가 자기 씬의 모든 노드의 owner 다. pack() 은 owner 가 루트인 노드만 담는다."
	vbox.add_child(info)

	_instance_host = Control.new()
	_instance_host.name = "InstanceHost"
	_instance_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_instance_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_instance_host)


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _dump_state() -> void:
	var state: SceneState = SAMPLE.get_state()
	Log.section("SceneState 덤프 — get_node_count()=%d, get_connection_count()=%d" % [state.get_node_count(), state.get_connection_count()])
	for i: int in range(state.get_node_count()):
		Log.info("노드[%d] name=%s type=%s path=%s parent=%s owner=%s groups=%s" % [
			i, state.get_node_name(i), state.get_node_type(i), state.get_node_path(i), state.get_node_path(i, true),
			state.get_node_owner_path(i), state.get_node_groups(i),
		])
		for p: int in range(state.get_node_property_count(i)):
			Log.info("      %s = %s" % [state.get_node_property_name(i, p), var_to_str(state.get_node_property_value(i, p))])
	for c: int in range(state.get_connection_count()):
		Log.info("연결[%d] signal=%s from=%s to=%s method=%s flags=%d binds=%s unbinds=%d" % [
			c, state.get_connection_signal(c), state.get_connection_source(c), state.get_connection_target(c),
			state.get_connection_method(c), state.get_connection_flags(c), state.get_connection_binds(c), state.get_connection_unbinds(c),
		])


func _instantiate() -> void:
	if _instance != null:
		Log.warn("이미 인스턴스가 있습니다. 먼저 제거하세요.")
		return
	Log.section("SAMPLE.instantiate() → InstanceHost.add_child()")
	_instance = SAMPLE.instantiate()
	_instance_host.add_child(_instance)
	Log.info("scene_file_path = %s" % _instance.scene_file_path)
	Log.info("각 노드의 owner (SceneState::instantiate 가 루트로 설정; 루트 자신은 null):")
	_print_owner(_instance, _instance)
	Log.info("get_tree_string_pretty():")
	for line: String in _instance.get_tree_string_pretty().split("\n", false):
		Log.info("  " + line)


func _print_owner(node: Node, root: Node) -> void:
	var owner_name: String = str(node.owner.name) if node.owner != null else "null"
	Log.info("  %-16s owner=%s" % [root.get_path_to(node), owner_name])
	for child: Node in node.get_children():
		_print_owner(child, root)


func _repack() -> void:
	if _instance == null:
		Log.warn("먼저 instantiate 하세요.")
		return
	var packed := PackedScene.new()
	var err: Error = packed.pack(_instance)
	Log.section("PackedScene.new().pack(instance) → %s" % error_string(err))
	Log.info("새 SceneState: 노드 수 %d, 연결 수 %d (원본과 같아야 정상)" % [packed.get_state().get_node_count(), packed.get_state().get_connection_count()])
	Log.info("코드로 add_child 한 노드는 owner 가 없어 pack() 에 빠진다 — 포함하려면 node.owner = 루트 (연습 과제).")


func _remove_instance() -> void:
	if _instance == null:
		Log.warn("인스턴스가 없습니다.")
		return
	_instance.queue_free()
	_instance = null
	Log.info("인스턴스 queue_free(). 리소스(SAMPLE)는 그대로 남는다 — 씬 리소스와 노드 인스턴스는 별개다.")
