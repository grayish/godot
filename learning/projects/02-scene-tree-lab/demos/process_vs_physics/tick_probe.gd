class_name TickProbe
extends Node
## _process / _physics_process 호출을 세고, sink Callable 이 있으면 (label, phase) 로 보고하는 탐침.
## process_priority / process_physics_priority / process_mode 실험에 쓴다.
## 엔진: scene/main/scene_tree.cpp SceneTree::_process_group() — 노드를 (physics) priority 로 정렬한 뒤
##   NOTIFICATION_PHYSICS_PROCESS / NOTIFICATION_PROCESS 를 보내고, scene/main/node.cpp Node::_notification() 이
##   GDVIRTUAL_CALL(_physics_process / _process) 로 바꾼다. set_process(false) 면 목록에서 빠져 비용이 0 이다.
## 다른 파일에서는 class_name 대신 preload() 로 참조한다 (헤드리스에서는 전역 클래스 캐시가 없을 수 있다).

var label: String = ""
var process_calls: int = 0
var physics_calls: int = 0
## (label: String, phase: String) — 비어 있으면 세기만 한다.
var sink: Callable = Callable()


func _init(p_label: String = "") -> void:
	label = p_label
	if not label.is_empty():
		name = label


func _process(_delta: float) -> void:
	process_calls += 1
	if sink.is_valid():
		sink.call(label, "process")


func _physics_process(_delta: float) -> void:
	physics_calls += 1
	if sink.is_valid():
		sink.call(label, "physics")


func _notification(what: int) -> void:
	# node.cpp _propagate_pause_notification(): pause 로 can_process() 가 바뀌는 노드에만 온다 (ALWAYS 는 못 받는다).
	if what == NOTIFICATION_PAUSED:
		Log.info("  [%s] NOTIFICATION_PAUSED (process_mode=%d)" % [label, process_mode])
	elif what == NOTIFICATION_UNPAUSED:
		Log.info("  [%s] NOTIFICATION_UNPAUSED (process_mode=%d)" % [label, process_mode])
