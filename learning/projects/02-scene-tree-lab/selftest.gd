extends SceneTree
## 헤드리스 셀프테스트: godot --headless --path <프로젝트> -s res://selftest.gd
## UI 없이 프로젝트의 핵심 논리(생명주기 순서, 지연 실행, 그룹, 우선순위, PackedScene 상태, 입력 단계)를 검사한다.
## 구조: 테스트 Callable 큐를 _process 에서 프레임당 하나씩 실행한다. 프레임을 넘겨야 하는 테스트는 후속 Callable 을 큐 앞에 넣는다.
## 주의 1: -s 스크립트는 오토로드보다 먼저 컴파일된다 (main/main.cpp Main::start) → 여기서 Log 를 쓰거나,
##         Log 를 쓰는 스크립트를 preload 하면 컴파일 오류. 데모 스크립트는 _initialize() 에서 load() 로 읽는다.
## 주의 2: _initialize() 시점엔 root 가 아직 트리 밖이다 (scene_tree.cpp SceneTree::initialize 가 MainLoop::initialize 뒤에 root->_set_tree)
##         → 노드 추가/입력 주입은 _process 에서 한다.

const PROJECT_DIR: String = "02-scene-tree-lab"

var _queue: Array[Callable] = []
var _failures: Array[String] = []
var _passed: int = 0

var _probe_script: GDScript
var _member_script: GDScript
var _tick_script: GDScript
var _sample_scene: PackedScene
var _input_scene: PackedScene

var _deferred_flag: bool = false
var _group_holder: Node = null
var _priority_holder: Node = null
var _priority_order: Array[String] = []


func _initialize() -> void:
	_probe_script = load("res://demos/lifecycle_order/lifecycle_probe.gd")
	_member_script = load("res://demos/groups_and_notifications/group_member.gd")
	_tick_script = load("res://demos/process_vs_physics/tick_probe.gd")
	_sample_scene = load("res://demos/packed_scene_inspect/sample.tscn")
	_input_scene = load("res://demos/input_propagation/input_propagation.tscn")
	_queue = [
		_test_lifecycle_order,
		_test_deferred_request,
		_test_groups_request,
		_test_priority_setup,
		_test_packed_scene_state,
		_test_input_stage_order,
	]
	print("SELFTEST start: %d tests" % _queue.size())


func _process(_delta: float) -> bool:
	if _queue.is_empty():
		_finish()
		return true
	var test: Callable = _queue.pop_front()
	test.call()
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("SELFTEST PASS %s (%d checks)" % [PROJECT_DIR, _passed])
		quit(0)
	else:
		print("SELFTEST FAIL %s: %s" % [PROJECT_DIR, "; ".join(_failures)])
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failures.append(message)
		print("  FAIL: " + message)


## a 와 b 가 모두 있고 a 가 먼저인지.
func _before(events: Array[String], a: String, b: String) -> bool:
	var ia: int = events.find(a)
	var ib: int = events.find(b)
	return ia >= 0 and ib >= 0 and ia < ib


func _probe_events() -> Array[String]:
	var copy: Array[String] = []
	copy.assign(_probe_script.get_events())
	return copy


func _call_log() -> String:
	var copy: Array[String] = []
	copy.assign(_member_script.get_call_log())
	return ",".join(copy)


func _all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_all_descendants(child))
	return result


# ---------------------------------------------------------------- 1. 생명주기 순서

func _build_probe_tree() -> Node:
	var root: Node = _probe_script.new("Root")
	var a: Node = _probe_script.new("A")
	var b: Node = _probe_script.new("B")
	root.add_child(a)
	root.add_child(b)
	a.add_child(_probe_script.new("A1"))
	a.add_child(_probe_script.new("A2"))
	b.add_child(_probe_script.new("B1"))
	return root


func _test_lifecycle_order() -> void:
	_probe_script.set_verbose(false)
	_probe_script.clear_events()
	var root: Node = _build_probe_tree()
	var built: Array[String] = _probe_events()
	_check(built.has("_init:Root") and built.has("NOTIFICATION_PARENTED:A1"), "트리 밖 구성: _init 과 PARENTED 가 기록되어야 함")
	_check(not built.has("_enter_tree:Root"), "트리 밖에서는 _enter_tree 가 오면 안 됨")

	_probe_script.clear_events()
	get_root().add_child(root)
	var ev: Array[String] = _probe_events()
	for pair: Array in [["Root", "A"], ["A", "A1"], ["A", "A2"], ["Root", "B"], ["B", "B1"]]:
		var parent: String = pair[0]
		var child: String = pair[1]
		_check(_before(ev, "_enter_tree:" + parent, "_enter_tree:" + child), "_enter_tree 는 부모(%s)가 자식(%s)보다 먼저" % [parent, child])
		_check(_before(ev, "_ready:" + child, "_ready:" + parent), "_ready 는 자식(%s)이 부모(%s)보다 먼저" % [child, parent])
		_check(_before(ev, "NOTIFICATION_POST_ENTER_TREE:" + child, "_ready:" + parent), "POST_ENTER_TREE(%s) 는 부모 _ready(%s) 전" % [child, parent])
	_check(ev.count("_ready:Root") == 1, "_ready 는 한 번만")
	_check(_before(ev, "_enter_tree:B1", "_ready:Root"), "모든 _enter_tree 가 루트 _ready 보다 먼저")
	_check(root.is_node_ready() and root.get_node("A/A1").is_node_ready(), "is_node_ready() 는 true")

	# 재추가: request_ready 없이는 _ready 가 다시 오지 않는다.
	get_root().remove_child(root)
	_probe_script.clear_events()
	get_root().add_child(root)
	ev = _probe_events()
	_check(ev.count("_ready:Root") == 0 and ev.count("_ready:A1") == 0, "재추가 시 _ready 는 다시 오지 않음")
	_check(ev.has("NOTIFICATION_POST_ENTER_TREE:Root") and ev.has("_enter_tree:A1"), "재추가 시 _enter_tree / POST_ENTER_TREE 는 다시 옴")

	# request_ready 는 그 노드에만 적용된다.
	get_root().remove_child(root)
	root.request_ready()
	_probe_script.clear_events()
	get_root().add_child(root)
	ev = _probe_events()
	_check(ev.count("_ready:Root") == 1, "request_ready() 후 재추가하면 Root 의 _ready 가 다시 옴")
	_check(ev.count("_ready:A") == 0, "request_ready() 는 자식(A)에는 영향 없음")

	# reparent: _ready 없이 exit/enter 만.
	_probe_script.clear_events()
	var a1: Node = root.get_node("A/A1")
	a1.reparent(root.get_node("B"))
	ev = _probe_events()
	_check(_before(ev, "_exit_tree:A1", "NOTIFICATION_UNPARENTED:A1") and _before(ev, "NOTIFICATION_PARENTED:A1", "_enter_tree:A1"), "reparent: _exit_tree → UNPARENTED → PARENTED → _enter_tree")
	_check(ev.count("_ready:A1") == 0 and a1.get_parent().name == &"B", "reparent 는 _ready 를 다시 부르지 않음")

	# 제거: _exit_tree 는 자식 먼저(역순), 그 다음 부모.
	_probe_script.clear_events()
	get_root().remove_child(root)
	ev = _probe_events()
	_check(_before(ev, "_exit_tree:A2", "_exit_tree:A") and _before(ev, "_exit_tree:A", "_exit_tree:Root"), "_exit_tree 는 자식 먼저")
	_check(_before(ev, "_exit_tree:B", "_exit_tree:A"), "_exit_tree 는 형제를 역순으로 (B 가 A 보다 먼저)")
	_check(_before(ev, "_exit_tree:Root", "NOTIFICATION_UNPARENTED:Root"), "UNPARENTED 는 _exit_tree 뒤")

	# 삭제: PREDELETE 는 부모가 먼저 받고(스크립트가 먼저), 자식은 그 뒤 memdelete 된다.
	_probe_script.clear_events()
	root.free()
	ev = _probe_events()
	_check(_before(ev, "NOTIFICATION_PREDELETE:Root", "NOTIFICATION_PREDELETE:A2"), "PREDELETE 는 부모(Root)가 자식(A2)보다 먼저")
	_check(ev.count("NOTIFICATION_PREDELETE:B1") == 1 and ev.count("NOTIFICATION_PREDELETE:A") == 1, "모든 노드가 PREDELETE 를 한 번 받음")
	_probe_script.set_verbose(true)


# ---------------------------------------------------------------- 2. 지연 실행

func _test_deferred_request() -> void:
	_deferred_flag = false
	# Callable.call_deferred → MessageQueue::push_callablep. 이 _process 가 끝난 뒤 SceneTree::process() 의 flush 에서 실행된다.
	_set_deferred_flag.call_deferred()
	_check(not _deferred_flag, "call_deferred 직후에는 아직 실행되지 않아야 함")
	_queue.push_front(_test_deferred_check)


func _set_deferred_flag() -> void:
	_deferred_flag = true


func _test_deferred_check() -> void:
	_check(_deferred_flag, "다음 프레임에는 call_deferred 가 실행되어 있어야 함")


# ---------------------------------------------------------------- 3. 그룹

func _test_groups_request() -> void:
	_member_script.set_verbose(false)
	_member_script.clear_call_log()
	_group_holder = _member_script.new("Holder")
	get_root().add_child(_group_holder)
	for member_name: String in ["M1", "M2", "M3"]:
		var member: Node = _member_script.new(member_name)
		_group_holder.add_child(member)
		member.add_to_group("st_group")

	var nodes: Array[Node] = get_nodes_in_group("st_group")
	_check(nodes.size() == 3 and get_node_count_in_group("st_group") == 3, "get_nodes_in_group: 3개")
	_check(_group_holder.get_node("M2").is_in_group("st_group"), "is_in_group")
	_check(not _group_holder.is_in_group("st_group"), "Holder 는 그룹 밖")

	call_group("st_group", "ping", "call_group")
	_check(_call_log() == "M1,M2,M3", "call_group 은 트리 순서 (실제: %s)" % _call_log())
	_member_script.clear_call_log()
	call_group_flags(GROUP_CALL_REVERSE, "st_group", "ping", "reverse")
	_check(_call_log() == "M3,M2,M1", "GROUP_CALL_REVERSE 는 역순 (실제: %s)" % _call_log())

	_member_script.clear_call_log()
	_group_holder.propagate_call("ping", ["propagate"], true)
	_check(_call_log() == "Holder,M1,M2,M3", "propagate_call(parent_first=true) 는 Holder 포함, 부모 먼저 (실제: %s)" % _call_log())
	_member_script.clear_call_log()
	_group_holder.propagate_call("ping", ["propagate"], false)
	_check(_call_log() == "M1,M2,M3,Holder", "propagate_call(parent_first=false) 는 자식 먼저 (실제: %s)" % _call_log())

	_group_holder.propagate_notification(_member_script.NOTIFICATION_CUSTOM_PING)
	var pings_ok: bool = _group_holder.custom_ping_count == 1
	for child: Node in _group_holder.get_children():
		if child.custom_ping_count != 1:
			pings_ok = false
	_check(pings_ok, "propagate_notification(10001) 은 서브트리 모든 노드의 _notification 에 한 번씩")

	_member_script.clear_call_log()
	call_group_flags(GROUP_CALL_DEFERRED, "st_group", "ping", "deferred")
	_check(_call_log().is_empty(), "GROUP_CALL_DEFERRED 는 즉시 실행되지 않음")
	_queue.push_front(_test_groups_check)


func _test_groups_check() -> void:
	_check(_call_log() == "M1,M2,M3", "GROUP_CALL_DEFERRED 는 다음 flush 에서 트리 순서로 실행 (실제: %s)" % _call_log())
	_group_holder.get_node("M2").remove_from_group("st_group")
	_check(get_nodes_in_group("st_group").size() == 2, "remove_from_group 후 2개")
	get_root().remove_child(_group_holder)
	_group_holder.free()
	_group_holder = null
	_member_script.set_verbose(true)


# ---------------------------------------------------------------- 4. process_priority

func _test_priority_setup() -> void:
	_priority_holder = Node.new()
	_priority_holder.name = "PriorityHolder"
	get_root().add_child(_priority_holder)
	# 트리 순서는 +10, +0, -10. SceneTree::_process_group 이 priority 로 정렬하므로 호출 순서는 -10, +0, +10 이어야 한다.
	for prio: int in [10, 0, -10]:
		var probe: Node = _tick_script.new("prio%+d" % prio)
		probe.process_priority = prio
		probe.set("sink", _on_priority_tick)
		_priority_holder.add_child(probe)
	_priority_order.clear()
	_queue.push_front(_test_priority_check)


func _on_priority_tick(label: String, phase: String) -> void:
	if phase == "process":
		_priority_order.append(label)


func _test_priority_check() -> void:
	var first: String = ",".join(_priority_order.slice(0, 3))
	_check(_priority_order.size() >= 3 and first == "prio-10,prio+0,prio+10", "process_priority 낮은 값 먼저 (실제: %s)" % first)
	get_root().remove_child(_priority_holder)
	_priority_holder.free()
	_priority_holder = null


# ---------------------------------------------------------------- 5. PackedScene / SceneState

func _test_packed_scene_state() -> void:
	var state: SceneState = _sample_scene.get_state()
	_check(state.get_node_count() == 4, "sample.tscn 노드 수 4 (실제 %d)" % state.get_node_count())
	_check(String(state.get_node_name(0)) == "Sample" and String(state.get_node_type(0)) == "Node2D", "루트 노드 Sample:Node2D")
	_check(String(state.get_node_type(3)) == "Timer", "네 번째 노드는 Timer")
	_check(state.get_connection_count() == 1, "연결 1개")
	_check(String(state.get_connection_signal(0)) == "timeout" and String(state.get_connection_method(0)) == "_on_ping_timer_timeout", "연결: timeout → _on_ping_timer_timeout")

	var instance: Node = _sample_scene.instantiate()
	get_root().add_child(instance)
	var descendants: Array[Node] = _all_descendants(instance)
	var owners_ok: bool = descendants.size() == 3
	for child: Node in descendants:
		if child.owner != instance:
			owners_ok = false
	_check(owners_ok, "인스턴스의 하위 노드 3개 모두 owner == 씬 루트")
	_check(instance.owner == null, "씬 루트 자신의 owner 는 null")
	_check(instance.get("greeting") == "안녕, PackedScene!", "SceneState 의 속성값이 인스턴스에 적용됨")

	var repacked := PackedScene.new()
	_check(repacked.pack(instance) == OK and repacked.get_state().get_node_count() == 4, "pack() 결과 노드 수 4")
	get_root().remove_child(instance)
	instance.free()


# ---------------------------------------------------------------- 6. 입력 단계 순서

func _make_key(keycode: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	return key


func _test_input_stage_order() -> void:
	var demo: Node = _input_scene.instantiate()
	get_root().add_child(demo)
	# Viewport::push_input 을 직접 불러 DisplayServer 없이 전파 경로를 돈다 (마우스는 레이아웃이 필요해 키만 검사).
	get_root().push_input(_make_key(KEY_A))
	var got: String = ",".join(demo.stage_log)
	_check(got == "_input,_shortcut_input,_unhandled_key_input,_unhandled_input", "키 이벤트 단계 순서 (실제: %s)" % got)

	demo.handle_at["_shortcut_input"] = true
	get_root().push_input(_make_key(KEY_B))
	got = ",".join(demo.stage_log)
	_check(got == "_input,_shortcut_input", "_shortcut_input 에서 set_input_as_handled → 이후 단계 없음 (실제: %s)" % got)

	demo.handle_at["_shortcut_input"] = false
	demo.handle_at["_input"] = true
	get_root().push_input(_make_key(KEY_C))
	got = ",".join(demo.stage_log)
	_check(got == "_input", "_input 에서 set_input_as_handled → GUI 포함 이후 단계 없음 (실제: %s)" % got)

	get_root().remove_child(demo)
	demo.free()
