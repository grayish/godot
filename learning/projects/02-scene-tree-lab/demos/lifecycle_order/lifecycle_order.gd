extends Control
## 데모 1: 노드 생명주기 순서.
## Root > A > (A1, A2), Root > B > B1 탐침 트리를 코드로 만들어 붙이고/떼고/옮기며
## _init, PARENTED, _enter_tree, POST_ENTER_TREE, _ready, _exit_tree, UNPARENTED, PREDELETE 순서를 Log 로 본다.
## 엔진: scene/main/node.cpp _propagate_enter_tree()(위→아래) / _propagate_ready()(아래→위) / _propagate_exit_tree()(자식 먼저),
##       queue_free() → scene/main/scene_tree.cpp SceneTree::queue_delete() → 프레임 끝 _flush_delete_queue() → memdelete.

const ProbeScript: GDScript = preload("res://demos/lifecycle_order/lifecycle_probe.gd")

var _holder: Node
var _tree_view: Label
var _subtree_root: Node = null


func _ready() -> void:
	ProbeScript.set_verbose(true)
	_build_ui()
	Log.section("데모 1: 생명주기 순서")
	Log.info("각 줄의 f=N 은 Engine.get_process_frames(), 들여쓰기는 탐침 트리 안의 깊이입니다.")
	Log.info("규칙: _enter_tree 는 부모→자식(top-down), _ready 는 자식→부모(bottom-up), _ready 는 request_ready() 전까지 한 번만.")
	_add_subtree()


func _process(_delta: float) -> void:
	# 매 프레임 현재 트리 모양을 보여준다. queue_free 는 프레임 끝에야 지워지므로 그때 갱신되는 것이 보인다.
	if _holder.get_child_count() == 0:
		_tree_view.text = "(탐침 트리 없음)"
	else:
		_tree_view.text = _holder.get_tree_string_pretty()


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(320, 0)
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)
	_add_button(buttons, "서브트리 추가 (add_child)", _add_subtree)
	_add_button(buttons, "서브트리 제거 (queue_free)", _remove_subtree)
	_add_button(buttons, "reparent: A1 을 A ↔ B 로 옮기기", _reparent_a1)
	_add_button(buttons, "request_ready() 후 재추가", _readd_with_request_ready)
	_add_button(buttons, "재추가 (request_ready 없이)", _readd_plain)

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "로그 패널에서 순서를 읽으세요.\n- add_child: _enter_tree 는 위에서 아래로, _ready 는 아래에서 위로.\n- queue_free: 요청한 프레임 끝에 PREDELETE → _exit_tree → UNPARENTED.\n- reparent / 재추가: _ready 는 다시 오지 않고 POST_ENTER_TREE 만 온다.\n- request_ready(): 그 노드만 다음 진입 때 _ready 를 다시 받는다."
	buttons.add_child(info)

	_tree_view = Label.new()
	_tree_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_view.text = "(탐침 트리 없음)"
	row.add_child(_tree_view)

	# 탐침 트리가 붙을 자리. Control 이 아닌 Node 라 레이아웃에 영향을 주지 않는다.
	_holder = Node.new()
	_holder.name = "Holder"
	add_child(_holder)


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


## Root > A > (A1, A2), Root > B > B1. 트리 밖에서 만들므로 _init 과 PARENTED 만 기록된다.
func _build_probe_tree() -> Node:
	var root: Node = ProbeScript.new("Root")
	var a: Node = ProbeScript.new("A")
	var b: Node = ProbeScript.new("B")
	root.add_child(a)
	root.add_child(b)
	a.add_child(ProbeScript.new("A1"))
	a.add_child(ProbeScript.new("A2"))
	b.add_child(ProbeScript.new("B1"))
	return root


func _has_subtree() -> bool:
	return _subtree_root != null and is_instance_valid(_subtree_root) and not _subtree_root.is_queued_for_deletion()


func _add_subtree() -> void:
	if _holder.get_child_count() > 0:
		Log.warn("탐침 트리가 아직 있습니다 (queue_free 직후라면 프레임 끝에 지워집니다). 먼저 제거하세요.")
		return
	Log.section("서브트리 만들기 — 아직 트리 밖: _init 과 NOTIFICATION_PARENTED 만 온다")
	_subtree_root = _build_probe_tree()
	Log.section("Holder.add_child(Root) — _propagate_enter_tree(위→아래) 다음 _propagate_ready(아래→위)")
	_holder.add_child(_subtree_root)
	Log.info("is_node_ready(): Root=%s, A1=%s" % [_subtree_root.is_node_ready(), _subtree_root.get_node("A/A1").is_node_ready()])


func _remove_subtree() -> void:
	if not _has_subtree():
		Log.warn("제거할 탐침 트리가 없습니다.")
		return
	Log.section("Root.queue_free() (f=%d) — 지금은 SceneTree::queue_delete 에 넣기만 한다" % Engine.get_process_frames())
	Log.info("실제 삭제는 이 프레임 SceneTree::process() 끝의 _flush_delete_queue(): memdelete → PREDELETE(스크립트 먼저) → remove_child → _exit_tree(자식 먼저, 역순) → UNPARENTED → 자식들 memdelete.")
	_subtree_root.queue_free()
	_subtree_root = null


func _reparent_a1() -> void:
	if not _has_subtree():
		Log.warn("먼저 서브트리를 추가하세요.")
		return
	var a1: Node = _subtree_root.get_node("A/A1")
	var target: Node = _subtree_root.get_node("B") if a1.get_parent().name == &"A" else _subtree_root.get_node("A")
	Log.section("A1.reparent(%s) — node.cpp Node::reparent() 는 remove_child + add_child 다" % target.name)
	Log.info("→ _exit_tree/UNPARENTED 다음 PARENTED/_enter_tree/POST_ENTER_TREE. 그러나 ready_first 가 이미 false 라 _ready 는 다시 오지 않는다.")
	a1.reparent(target)


func _readd_with_request_ready() -> void:
	if not _has_subtree():
		Log.warn("먼저 서브트리를 추가하세요.")
		return
	Log.section("remove_child(Root) → Root.request_ready() → add_child(Root)")
	Log.info("request_ready() 는 그 노드의 ready_first 만 다시 true 로 만든다 (node.cpp Node::request_ready). 자식은 해당 없음 → Root 만 _ready 재호출.")
	_holder.remove_child(_subtree_root)
	_subtree_root.request_ready()
	_holder.add_child(_subtree_root)
	Log.info("자식까지 다시 _ready 하려면 Root.propagate_call(\"request_ready\") 후 재추가 (연습 과제).")


func _readd_plain() -> void:
	if not _has_subtree():
		Log.warn("먼저 서브트리를 추가하세요.")
		return
	Log.section("remove_child(Root) → add_child(Root) (request_ready 없이)")
	Log.info("_enter_tree 와 POST_ENTER_TREE 는 다시 오지만 _ready 는 아무 노드에도 오지 않는다.")
	_holder.remove_child(_subtree_root)
	_holder.add_child(_subtree_root)
