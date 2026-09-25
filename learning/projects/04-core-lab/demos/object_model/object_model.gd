extends Control
## 데모 2: Object 모델 — 동적 프로퍼티/메서드 접근, notification, 시그널 플래그, ObjectDB, WeakRef, free/queue_free.
## 엔진: core/object/object.h (set/get/call/notification/connect), core/object/object.cpp emit_signalp(),
##       ObjectDB (object.h:880~) — ObjectID = 24비트 슬롯 + 39비트 validator + RefCounted 1비트.
## 2장 2.1 "Object와 GDCLASS" 를 코드로 옮긴 것.

## 실험 대상. Object 를 직접 상속 → RefCounted 가 아니므로 free() 로 직접 해제해야 한다.
class Probe extends Object:
	const NOTIFICATION_CUSTOM: int = 12345

	signal hit(amount: int)

	var hp: int = 10
	var last_notification: int = -1

	func take(amount: int) -> int:
		hp -= amount
		hit.emit(amount)
		return hp

	# notification(int) 은 가상 함수 대신 정수 코드를 계층 전체에 전파한다 (object.h _notificationv 체인).
	func _notification(what: int) -> void:
		last_notification = what
		if what == NOTIFICATION_CUSTOM:
			Log.info("  Probe._notification(NOTIFICATION_CUSTOM=%d) 도착" % what)
		elif what == NOTIFICATION_PREDELETE:
			# memdelete → predelete_handler → NOTIFICATION_PREDELETE → 소멸자 (core/os/memory.h)
			Log.info("  Probe._notification(NOTIFICATION_PREDELETE) — 곧 소멸자")


var _one_shot_calls: int = 0
var _deferred_calls: int = 0


func _ready() -> void:
	_build_ui()
	Log.section("Object 모델")
	_demo_dynamic_access()
	_demo_notification()
	_demo_signal_flags()
	_demo_objectdb()
	_demo_weakref()
	_demo_class_and_meta()
	_demo_free_vs_queue_free()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "Object 모델 실험 — 각 버튼이 한 가지 실험을 다시 실행하고 결과를 로그에 적는다"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	var items: Array = [
		["set/get/call", _demo_dynamic_access], ["notification", _demo_notification],
		["시그널 플래그", _demo_signal_flags], ["ObjectDB 검증", _demo_objectdb],
		["WeakRef", _demo_weakref], ["get_class/meta/tr", _demo_class_and_meta],
		["free vs queue_free", _demo_free_vs_queue_free],
	]
	for item: Array in items:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		grid.add_child(button)


func _demo_dynamic_access() -> void:
	Log.section("Object.set / get / call (StringName 기반 동적 접근)")
	var p := Probe.new()
	# set/get 은 인스펙터·.tscn 직렬화·애니메이션 트랙이 쓰는 바로 그 경로 (object.cpp Object::set → _setv 체인 → 스크립트 인스턴스).
	p.set(&"hp", 42)
	Log.info("p.set(&\"hp\", 42) → p.get(&\"hp\") = %s, 직접 접근 p.hp = %d" % [str(p.get(&"hp")), p.hp])
	Log.info("has_method(&\"take\")=%s  has_signal(&\"hit\")=%s  has_method(&\"nope\")=%s" % [
		str(p.has_method(&"take")), str(p.has_signal(&"hit")), str(p.has_method(&"nope"))])
	Log.info("p.call(&\"take\", 5) = %s, p.callv(&\"take\", [2]) = %s (Object::callp → 스크립트 인스턴스 → MethodBind)" % [
		str(p.call(&"take", 5)), str(p.callv(&"take", [2]))])
	Log.info("get_method_list() 에 스크립트 메서드 포함? %s" % str(p.get_method_list().any(
		func(m: Dictionary) -> bool: return m["name"] == "take")))
	p.free()


func _demo_notification() -> void:
	Log.section("notification() / _notification()")
	var p := Probe.new()
	p.notification(Probe.NOTIFICATION_CUSTOM)
	Log.info("p.notification(12345) 후 last_notification=%d. 엔진 상수와 겹치지 않는 값을 쓴다 (Node 는 10~, Control 은 40~, WM 은 1001~)" % p.last_notification)
	Log.info("이제 p.free() — PREDELETE(=%d) 가 먼저 오고 소멸자가 돈다:" % NOTIFICATION_PREDELETE)
	p.free()


func _demo_signal_flags() -> void:
	Log.section("시그널 연결 플래그 (Object::connect flags)")
	var p := Probe.new()
	_one_shot_calls = 0
	_deferred_calls = 0
	p.hit.connect(_on_hit_one_shot, CONNECT_ONE_SHOT)
	p.take(1)
	p.take(1)
	Log.info("CONNECT_ONE_SHOT: 두 번 emit 했지만 콜백 %d회, 아직 연결됨? %s (emit_signalp 가 호출 전에 먼저 끊는다)" % [
		_one_shot_calls, str(p.hit.is_connected(_on_hit_one_shot))])
	p.hit.connect(_on_hit_deferred, CONNECT_DEFERRED)
	p.take(1)
	Log.info("CONNECT_DEFERRED: emit 직후 콜백 %d회 — MessageQueue 에 들어가 다음 flush 때 실행 (core/object/message_queue.cpp)" % _deferred_calls)
	p.hit.connect(_on_hit_counted, CONNECT_REFERENCE_COUNTED)
	p.hit.connect(_on_hit_counted, CONNECT_REFERENCE_COUNTED)
	p.hit.disconnect(_on_hit_counted)
	Log.info("CONNECT_REFERENCE_COUNTED: 같은 Callable 두 번 connect 후 한 번 disconnect → 아직 연결됨? %s" % str(p.hit.is_connected(_on_hit_counted)))
	p.hit.disconnect(_on_hit_counted)
	Log.info("  두 번째 disconnect 후 연결됨? %s (플래그 없이 같은 Callable 을 두 번 connect 하면 오류)" % str(p.hit.is_connected(_on_hit_counted)))
	p.free()
	if not await _wait_for_frame_flush():
		return
	Log.info("CONNECT_DEFERRED: 프레임 flush 를 지나니 콜백 %d회 (MessageQueue::flush 는 SceneTree::process 안에서 실행)" % _deferred_calls)


## process_frame 시그널은 SceneTree::process() 초입에 emit 되고, MessageQueue flush 와 _flush_delete_queue 는 그 뒤에 온다
## (scene/main/scene_tree.cpp). _ready 가 이번 프레임의 process_frame 보다 먼저 돌았다면(헤드리스 런너가 _process 안에서
## add_child 한 경우) await 한 번으로는 아직 flush 전이다. 그래서 두 번 기다려 "flush 를 확실히 지난" 시점을 잡는다.
## 데모가 그 사이 해제되면 false 를 돌려준다 (해제된 노드의 await 는 GDScriptInstance 소멸 시 조용히 끊긴다).
func _wait_for_frame_flush() -> bool:
	await get_tree().process_frame
	if not is_inside_tree():
		return false
	await get_tree().process_frame
	return is_inside_tree()


func _on_hit_one_shot(_amount: int) -> void:
	_one_shot_calls += 1


func _on_hit_deferred(_amount: int) -> void:
	_deferred_calls += 1


func _on_hit_counted(_amount: int) -> void:
	pass


func _demo_objectdb() -> void:
	Log.section("ObjectDB validator: 해제된 객체 ID 는 null")
	var p := Probe.new()
	var id: int = p.get_instance_id()
	Log.info("get_instance_id() = %d — 슬롯 인덱스 + validator, RefCounted 비트=%s" % [id, str(bool(id >> 63))])
	Log.info("instance_from_id(id) == p ? %s, is_instance_id_valid(id) = %s" % [str(instance_from_id(id) == p), str(is_instance_id_valid(id))])
	p.free()
	Log.info("free() 후: is_instance_valid(p)=%s, is_instance_id_valid(id)=%s, instance_from_id(id)=%s" % [
		str(is_instance_valid(p)), str(is_instance_id_valid(id)), str(instance_from_id(id))])
	Log.info("ObjectDB::get_instance() 는 슬롯의 validator 가 일치할 때만 포인터를 준다 → 댕글링 포인터 대신 null (object.h:914)")
	Log.info("Variant 가 Object 를 담을 때 ObjData{ObjectID id; Object *obj} 로 ID 를 함께 저장하는 이유가 이것 (variant.h)")


func _demo_weakref() -> void:
	Log.section("WeakRef: 소유하지 않고 살아 있는지만 본다")
	var node := Node.new()
	var weak: WeakRef = weakref(node)
	Log.info("weakref(node).get_ref() = %s" % str(weak.get_ref()))
	node.free()
	Log.info("node.free() 후 get_ref() = %s (WeakRef 는 ObjectID 만 들고 있다, core/object/ref_counted.h WeakRef)" % str(weak.get_ref()))


func _demo_class_and_meta() -> void:
	Log.section("get_class / is_class / 메타데이터 / tr")
	var node := Node2D.new()
	Log.info("Node2D.new(): get_class()=%s, is_class(\"Node\")=%s, is_class(\"Control\")=%s" % [
		node.get_class(), str(node.is_class("Node")), str(node.is_class("Control"))])
	Log.info("이 데모 스크립트의 get_class()=%s — 스크립트 class_name 은 엔진 클래스가 아니다 (get_script() 로 구분)" % get_class())
	node.set_meta(&"author", "student")
	node.set_meta(&"level", 3)
	Log.info("set_meta 후 get_meta_list()=%s, has_meta(&\"author\")=%s, get_meta(&\"missing\", \"기본값\")=%s" % [
		str(node.get_meta_list()), str(node.has_meta(&"author")), str(node.get_meta(&"missing", "기본값"))])
	Log.info("메타데이터는 .tscn 에 저장된다 (Object::metadata HashMap<StringName, Variant>, 프로퍼티 이름 metadata/*)")
	Log.info("tr(\"HELLO\") = %s — 번역이 없으면 원문 그대로 (core/string/translation_server.cpp)" % node.tr("HELLO"))
	node.free()


func _demo_free_vs_queue_free() -> void:
	Log.section("Object.free() vs Node.queue_free()")
	var immediate := Node.new()
	add_child(immediate)
	immediate.free()
	Log.info("free(): 즉시 memdelete → is_instance_valid=%s (시그널 콜백 도중이면 위험)" % str(is_instance_valid(immediate)))
	var queued := Node.new()
	add_child(queued)
	var id: int = queued.get_instance_id()
	queued.queue_free()
	Log.info("queue_free(): is_queued_for_deletion=%s, 아직 살아있음=%s (SceneTree::queue_delete → 프레임 끝 _flush_delete_queue)" % [
		str(queued.is_queued_for_deletion()), str(is_instance_valid(queued))])
	if not await _wait_for_frame_flush():
		return
	Log.info("프레임 flush 를 지나니 is_instance_id_valid=%s (scene/main/scene_tree.cpp _flush_delete_queue)" % str(is_instance_id_valid(id)))
