class_name LifecycleProbe
extends Node
## 생명주기 탐침. 탐침 트리의 모든 노드가 이 스크립트를 공유하며 각 단계를 기록한다.
## 기록은 static 배열 events 에 "<이벤트>:<태그>" 로 쌓인다 — selftest.gd 가 이 순서를 검사한다.
## 엔진 흐름 (scene/main/node.cpp):
##   add_child() → _propagate_enter_tree()  [부모→자식: NOTIFICATION_ENTER_TREE → _enter_tree → tree_entered]
##              → _propagate_ready()       [자식→부모: NOTIFICATION_POST_ENTER_TREE → (ready_first 면) NOTIFICATION_READY → _ready]
##   remove_child()/삭제 → _propagate_exit_tree() [자식 먼저(역순), 그 다음 자신: _exit_tree → NOTIFICATION_EXIT_TREE]
##   memdelete → Object::_predelete() → NOTIFICATION_PREDELETE (reversed=true 라 스크립트가 C++ 보다 먼저 받는다)
## 주의: 다른 파일에서는 class_name 대신 preload() 로 참조한다. 에디터로 한 번도 안 연 프로젝트에는
##       .godot/global_script_class_cache.cfg 가 없어 헤드리스에서 전역 클래스 이름이 풀리지 않는다.

## 모든 탐침이 공유하는 기록. 밖에서는 아래 static 함수로 접근한다.
static var events: Array[String] = []
## Log 로도 출력할지. selftest 는 끈다.
static var verbose: bool = true

var tag: String = ""


func _init(p_tag: String = "") -> void:
	# _init 시점: 부모도 트리도 없다. 이름을 여기서 정한다 (.tscn 인스턴스라면 나중에 SceneState 가 정한다).
	tag = p_tag
	if not tag.is_empty():
		name = tag
	_record("_init")


func _enter_tree() -> void:
	# node.cpp _propagate_enter_tree(): NOTIFICATION_ENTER_TREE 직후 GDVIRTUAL _enter_tree. 자식은 아직 트리 밖이다.
	_record("_enter_tree")


func _ready() -> void:
	# node.cpp _propagate_ready(): 자식들의 _propagate_ready 가 먼저 끝난 뒤 NOTIFICATION_READY. data.ready_first 일 때만.
	_record("_ready")


func _exit_tree() -> void:
	# node.cpp _propagate_exit_tree(): 자식(역순) 먼저, 그 다음 자신.
	_record("_exit_tree")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PARENTED:
			# add_child() 안(_add_child_nocheck)에서 트리 진입보다 먼저 온다.
			_record("NOTIFICATION_PARENTED")
		NOTIFICATION_UNPARENTED:
			# remove_child() 안에서 _propagate_exit_tree 뒤에 온다.
			_record("NOTIFICATION_UNPARENTED")
		NOTIFICATION_POST_ENTER_TREE:
			# _propagate_ready() 가 자식 처리 후 보낸다. _ready 와 달리 트리에 들어올 때마다 온다.
			_record("NOTIFICATION_POST_ENTER_TREE")
		NOTIFICATION_PREDELETE:
			# Object::_predelete(): 아직 parent/children 이 살아 있어 깊이 계산이 가능하다.
			_record("NOTIFICATION_PREDELETE")


## 조상 중 같은 탐침 스크립트를 가진 노드 수 = 들여쓰기 깊이 (Node 에는 공개 get_depth 가 없어 직접 센다).
func probe_depth() -> int:
	var depth: int = 0
	var parent: Node = get_parent()
	while parent != null and parent.get_script() == get_script():
		depth += 1
		parent = parent.get_parent()
	return depth


static func clear_events() -> void:
	events.clear()


static func get_events() -> Array[String]:
	return events


static func set_verbose(enabled: bool) -> void:
	verbose = enabled


func _record(event: String) -> void:
	events.append(event + ":" + tag)
	if verbose and is_instance_valid(Log):
		Log.info("f=%d %s[%s] %s" % [Engine.get_process_frames(), "    ".repeat(probe_depth()), tag, event])
