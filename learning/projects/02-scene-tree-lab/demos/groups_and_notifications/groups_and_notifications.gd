extends Control
## 데모 4: 그룹과 알림 전파.
## 엔진: scene/main/scene_tree.cpp — group_map(SceneTreeGroup) 이 add_to_group 의 저장소. get_nodes_in_group 은
##   _update_group_order() 로 트리 순서 정렬 후 반환, call_group_flagsp() 가 순서대로(REVERSE 면 역순) callp 한다.
##   node_added/node_removed 시그널은 node.cpp _propagate_enter_tree()/_propagate_exit_tree() 가 tree->node_added()/node_removed() 로 emit 한다.
## scene/main/node.cpp Node::propagate_call(parent_first) / propagate_notification(): 자기 서브트리를 재귀로 돈다 (그룹과 무관).

const MemberScript: GDScript = preload("res://demos/groups_and_notifications/group_member.gd")
const GROUP: StringName = &"lab_members"

var _holder: Node
var _tree_view: Label
var _added: int = 0


func _ready() -> void:
	MemberScript.set_verbose(true)
	_build_ui()
	_build_members()
	# 트리 전체의 노드 추가/제거 알림. 허브의 다른 노드도 오므로 이 데모 아래만 필터한다.
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	Log.section("데모 4: 그룹과 알림 전파")
	Log.info("Holder > M1(> M1a), M2, M3. M1, M1a, M2, M3 은 그룹 \"%s\" 에 있고 Holder 는 아니다." % GROUP)
	Log.info("call_group 은 그룹(트리 순서), propagate_* 는 서브트리(부모/자식 순서 선택) — 대상 집합이 다르다.")
	_show_group()


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)
	get_tree().node_removed.disconnect(_on_node_removed)


func _process(_delta: float) -> void:
	_tree_view.text = _holder.get_tree_string_pretty()


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	_add_button(grid, "그룹 조회 (get_nodes_in_group 등)", _show_group)
	_add_button(grid, "call_group(\"ping\")", _call_group)
	_add_button(grid, "call_group_flags(GROUP_CALL_REVERSE)", _call_group_reverse)
	_add_button(grid, "call_group_flags(GROUP_CALL_DEFERRED)", _call_group_deferred)
	_add_button(grid, "Holder.propagate_call(parent_first=true)", _propagate_parent_first)
	_add_button(grid, "Holder.propagate_call(parent_first=false)", _propagate_children_first)
	_add_button(grid, "Holder.propagate_notification(CUSTOM_PING)", _propagate_notification)
	_add_button(grid, "M2 그룹 제거/복귀 (remove_from_group)", _toggle_m2)
	_add_button(grid, "멤버 추가 (node_added)", _add_member)
	_add_button(grid, "마지막 멤버 제거 (node_removed)", _remove_last_member)

	_tree_view = Label.new()
	_tree_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tree_view)


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _build_members() -> void:
	_holder = MemberScript.new("Holder")
	add_child(_holder)
	for member_name: String in ["M1", "M2", "M3"]:
		var member: Node = MemberScript.new(member_name)
		_holder.add_child(member)
		member.add_to_group(GROUP)
	var m1a: Node = MemberScript.new("M1a")
	_holder.get_node("M1").add_child(m1a)
	m1a.add_to_group(GROUP)


func _show_group() -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(GROUP)
	Log.section("get_tree().get_nodes_in_group(\"%s\") → %d개, 트리 순서" % [GROUP, nodes.size()])
	for node: Node in nodes:
		Log.info("  %s  is_in_group=%s  get_groups()=%s" % [get_path_to(node), node.is_in_group(GROUP), node.get_groups()])
	Log.info("has_group=%s  get_node_count_in_group=%d  get_first_node_in_group=%s" % [get_tree().has_group(GROUP), get_tree().get_node_count_in_group(GROUP), get_tree().get_first_node_in_group(GROUP)])


func _call_group() -> void:
	Log.section("get_tree().call_group(\"%s\", \"ping\") — 즉시, 트리 순서" % GROUP)
	get_tree().call_group(GROUP, "ping", "call_group")


func _call_group_reverse() -> void:
	Log.section("call_group_flags(GROUP_CALL_REVERSE) — 즉시, 역순")
	get_tree().call_group_flags(SceneTree.GROUP_CALL_REVERSE, GROUP, "ping", "REVERSE")


func _call_group_deferred() -> void:
	Log.section("call_group_flags(GROUP_CALL_DEFERRED) — 요청 pf=%d, 실행은 다음 MessageQueue flush" % Engine.get_process_frames())
	get_tree().call_group_flags(SceneTree.GROUP_CALL_DEFERRED, GROUP, "ping", "DEFERRED")
	Log.info("  (이 줄이 ping 보다 먼저 찍히면 실제로 미뤄진 것)")


func _propagate_parent_first() -> void:
	Log.section("Holder.propagate_call(\"ping\", [...], parent_first=true) — 그룹과 무관하게 서브트리 전체, 부모 먼저")
	_holder.propagate_call("ping", ["propagate_call parent_first"], true)


func _propagate_children_first() -> void:
	Log.section("Holder.propagate_call(\"ping\", [...], parent_first=false) — 자식 먼저, 부모는 마지막")
	_holder.propagate_call("ping", ["propagate_call children_first"], false)


func _propagate_notification() -> void:
	Log.section("Holder.propagate_notification(NOTIFICATION_CUSTOM_PING=%d) — 자신 먼저, 그 다음 자식 재귀" % MemberScript.NOTIFICATION_CUSTOM_PING)
	_holder.propagate_notification(MemberScript.NOTIFICATION_CUSTOM_PING)


func _toggle_m2() -> void:
	var m2: Node = _holder.get_node("M2")
	if m2.is_in_group(GROUP):
		m2.remove_from_group(GROUP)
		Log.info("M2.remove_from_group → get_node_count_in_group=%d" % get_tree().get_node_count_in_group(GROUP))
	else:
		m2.add_to_group(GROUP)
		Log.info("M2.add_to_group → get_node_count_in_group=%d (다시 트리 순서로 정렬된다)" % get_tree().get_node_count_in_group(GROUP))


func _add_member() -> void:
	_added += 1
	var member: Node = MemberScript.new("New%d" % _added)
	# 트리 밖에서 add_to_group 하면 진입할 때 등록된다 (node.cpp _propagate_enter_tree 의 그룹 재등록).
	member.add_to_group(GROUP)
	Log.section("Holder.add_child(%s) → SceneTree.node_added 시그널" % member.name)
	_holder.add_child(member)


func _remove_last_member() -> void:
	var children: Array[Node] = _holder.get_children()
	if children.size() <= 3:
		Log.warn("기본 멤버(M1, M2, M3)는 남겨 둡니다. 먼저 멤버를 추가하세요.")
		return
	var last: Node = children.back()
	Log.section("%s.queue_free() → 프레임 끝에 제거되며 SceneTree.node_removed 시그널" % last.name)
	last.queue_free()


func _on_node_added(node: Node) -> void:
	if is_ancestor_of(node):
		Log.info("  node_added: %s (groups=%s)" % [get_path_to(node), node.get_groups()])


func _on_node_removed(node: Node) -> void:
	if is_ancestor_of(node):
		Log.info("  node_removed: %s" % node.name)
