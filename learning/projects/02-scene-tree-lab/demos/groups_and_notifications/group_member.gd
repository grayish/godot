class_name GroupMember
extends Node
## 그룹/전파 실험용 멤버. ping() 은 call_group / propagate_call 의 대상, _notification 은 propagate_notification 의 대상.
## 엔진: scene/main/scene_tree.cpp SceneTree::call_group_flagsp() — group_map 에서 노드 목록을 복사해 트리 순서로 callp 하고,
##       GROUP_CALL_DEFERRED 면 MessageQueue::push_callp 로 미룬다. scene/main/node.cpp Node::propagate_call()/propagate_notification().
## 다른 파일에서는 class_name 대신 preload() 로 참조한다 (헤드리스에서는 전역 클래스 캐시가 없을 수 있다).

## 엔진 알림 번호와 겹치지 않는 사용자 정의 알림 (scene/main/node.h 의 마지막 엔진 알림은 9004 근처).
const NOTIFICATION_CUSTOM_PING: int = 10001

## selftest 용 조용한 기록.
static var verbose: bool = true
static var call_log: Array[String] = []

var label: String = ""
var ping_count: int = 0
var custom_ping_count: int = 0


func _init(p_label: String = "") -> void:
	label = p_label
	if not label.is_empty():
		name = label


func ping(source: String) -> void:
	ping_count += 1
	call_log.append(label)
	if verbose:
		Log.info("  [%s] ping(\"%s\")  pf=%d" % [label, source, Engine.get_process_frames()])


func _notification(what: int) -> void:
	# Object::notification() 은 엔진 알림이 아니어도 스크립트 _notification 까지 전달한다 → 사용자 정의 번호도 쓸 수 있다.
	if what == NOTIFICATION_CUSTOM_PING:
		custom_ping_count += 1
		if verbose:
			Log.info("  [%s] _notification(NOTIFICATION_CUSTOM_PING=%d)" % [label, what])


static func set_verbose(enabled: bool) -> void:
	verbose = enabled


static func clear_call_log() -> void:
	call_log.clear()


static func get_call_log() -> Array[String]:
	return call_log
