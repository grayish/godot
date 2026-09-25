extends Control
## 데모 2: Variant 와 Callable, Signal 을 값으로 다루기.
## 엔진: core/variant/variant.h (Variant::Type 39종, 24바이트), variant_op.cpp (연산자 테이블),
##       core/variant/callable.cpp, core/object/object.cpp Object::callp / emit_signalp.

const CallableKit := preload("res://demos/variant_and_callable/callable_kit.gd")

var _kit: CallableKit = CallableKit.new()
var _rerun_button: Button


func _ready() -> void:
	_build_ui()
	_run_all()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var title := Label.new()
	title.text = "출력은 아래 로그 패널(및 stdout)에 나온다."
	column.add_child(title)
	_rerun_button = Button.new()
	_rerun_button.text = "다시 실행"
	_rerun_button.pressed.connect(_run_all)
	column.add_child(_rerun_button)


func _run_all() -> void:
	_show_types()
	_show_conversions()
	_show_callables()
	_show_signals()
	_show_dynamic_calls()


func _show_types() -> void:
	Log.section("typeof / type_string — Variant::Type")
	var samples: Array = [
		null, true, 42, 3.5, "문자열", &"string_name", ^"Node/Path",
		Vector2(1, 2), Vector3i(1, 2, 3), Color.RED, Rect2(0, 0, 4, 4), Transform2D.IDENTITY,
		[1, 2], {"k": 1}, PackedInt32Array([1, 2]), Callable(), Signal(), RID(), self, _kit,
	]
	for value: Variant in samples:
		Log.info("  " + CallableKit.describe(value))
	Log.info("TYPE_MAX=%d: Variant 는 NIL 부터 PACKED_VECTOR4_ARRAY 까지 %d개 타입 (core/variant/variant.h Variant::Type)" % [TYPE_MAX, TYPE_MAX])
	Log.info("typeof(42) == TYPE_INT → %s ; 객체는 모두 TYPE_OBJECT 이고 클래스는 get_class() 로 본다: %s" % [typeof(42) == TYPE_INT, _kit.get_class()])


func _show_conversions() -> void:
	Log.section("암시 변환과 str()")
	var as_float: float = 3 # int → float 는 분석기가 허용하는 암시 변환
	Log.info("var f: float = 3 → %s (%s)" % [as_float, type_string(typeof(as_float))])
	var mixed: Variant = 1 + 2.0
	Log.info("1 + 2.0 → %s (%s): variant_op.cpp 의 (INT, FLOAT, OP_ADD) 항목이 FLOAT 를 낸다" % [mixed, type_string(typeof(mixed))])
	@warning_ignore("integer_division")
	var int_div: int = 7 / 2
	Log.info("7 / 2 = %d (정수 나눗셈), 7.0 / 2 = %s" % [int_div, 7.0 / 2])
	Log.info("str(42) + \"/\" + str(3.5) + \"/\" + str(Vector2(1, 2)) = %s" % (str(42) + "/" + str(3.5) + "/" + str(Vector2(1, 2))))
	Log.info("int(\"42\") + int(3.99) = %d (문자열 파싱, float 는 버림)" % (int("42") + int(3.99)))
	Log.info("type_convert(3.7, TYPE_INT) = %s ; Vector2(1, 2) * 2 = %s" % [type_convert(3.7, TYPE_INT), Vector2(1, 2) * 2])
	var text: String = var_to_str(Vector2(1, 2))
	Log.info("var_to_str(Vector2(1, 2)) = %s → str_to_var 로 복원: %s" % [text, str_to_var(text)])
	Log.info("\"%%s\" 포맷은 무엇이든 str() 로 바꾼다: %s / %s / %s" % [null, [1, "a"], {"k": Vector2.ONE}])
	Log.warn("\"5\" + 5 처럼 테이블에 없는 (STRING, INT, OP_ADD) 조합은 런타임 오류다 — 여기선 실행하지 않는다.")


func _show_callables() -> void:
	Log.section("Callable 만들기와 호출")
	var by_name: Callable = Callable(_kit, "add")
	var by_ref: Callable = _kit.add
	var base: int = 100
	var lambda: Callable = func(x: int) -> int: return x + base # 로컬 base 를 값으로 캡처
	Log.info("Callable(obj, \"add\").call(1, 2) = %d ; obj.add.callv([3, 4]) = %d" % [by_name.call(1, 2), by_ref.callv([3, 4])])
	Log.info("람다.call(5) = %d — is_custom=%s (GDScriptLambdaCallable, modules/gdscript/gdscript_lambda_callable.cpp)" % [lambda.call(5), lambda.is_custom()])
	Log.info("두 Callable 이 같은 대상인가? by_name == by_ref → %s, is_standard=%s" % [by_name == by_ref, by_name.is_standard()])

	var add10: Callable = by_ref.bind(10)
	Log.info("add.bind(10).call(5) = %d — bind 는 호출 인자 '뒤에' 붙는다" % add10.call(5))
	var drop_one: Callable = add10.unbind(1)
	Log.info("add.bind(10).unbind(1).call(5, 99) = %d — unbind 는 호출 시 넘어온 뒤쪽 인자를 버린 뒤 bind 인자를 붙인다" % drop_one.call(5, 99))
	Log.info("get_bound_arguments=%s, get_bound_arguments_count=%d, get_unbound_arguments_count=%d" % [drop_one.get_bound_arguments(), drop_one.get_bound_arguments_count(), drop_one.get_unbound_arguments_count()])
	Log.info("get_object=%s, get_method=%s, get_argument_count=%d, is_valid=%s" % [by_name.get_object(), by_name.get_method(), by_name.get_argument_count(), by_name.is_valid()])

	var temp_node := Node.new()
	var dangling: Callable = Callable(temp_node, "get_name")
	temp_node.free()
	Log.info("free() 된 객체의 Callable: is_valid=%s, is_null=%s (ObjectID 로 매번 ObjectDB 를 조회하므로 안전하게 false)" % [dangling.is_valid(), dangling.is_null()])
	Log.info("Callable() 빈 값: is_null=%s" % Callable().is_null())

	var before: int = _kit.call_count
	_kit.add.call_deferred(1, 2)
	Log.info("add.call_deferred(1, 2): 지금 call_count=%d — MessageQueue(core/object/message_queue.cpp)가 이 프레임 끝에 비워질 때 실행된다" % _kit.call_count)
	_report_deferred.call_deferred(before)


func _report_deferred(before: int) -> void:
	Log.info("  (지연 호출 처리됨 — _ready 가 끝나고 MessageQueue::flush 시점) call_count %d → %d: 그 사이 동기 호출들 뒤에 지연된 add(1, 2) 가 실행됐다" % [before, _kit.call_count])


func _show_signals() -> void:
	Log.section("Signal 을 값으로")
	var sig: Signal = Signal(_kit, "pinged")
	var received: Array[int] = []
	var listener: Callable = func(value: int) -> void: received.append(value)
	sig.connect(listener)
	Log.info("Signal(obj, \"pinged\"): get_name=%s, get_object=%s, is_connected=%s, 연결 수=%d" % [sig.get_name(), sig.get_object(), sig.is_connected(listener), sig.get_connections().size()])
	sig.emit(7)
	_kit.pinged.emit(8)
	_kit.ping(9)
	Log.info("sig.emit(7), obj.pinged.emit(8), obj.ping(9) → 수신 %s (emit 은 동기: 돌아오기 전에 콜백이 끝나 있다)" % [received])
	sig.disconnect(listener)
	Log.info("disconnect 후 연결 수=%d, Signal().is_null()=%s" % [sig.get_connections().size(), Signal().is_null()])

	if not _kit.has_user_signal("custom_event"):
		_kit.add_user_signal("custom_event", [{"name": "payload", "type": TYPE_STRING}])
	var got: Array[String] = []
	_kit.connect("custom_event", func(payload: String) -> void: got.append(payload), CONNECT_ONE_SHOT)
	_kit.emit_signal("custom_event", "런타임에 추가한 시그널")
	_kit.emit_signal("custom_event", "ONE_SHOT 이라 이건 안 온다")
	Log.info("add_user_signal + CONNECT_ONE_SHOT: 수신 %s" % [got])


func _show_dynamic_calls() -> void:
	Log.section("직접 호출 vs Object.call(\"이름\")")
	Log.info("obj.add(1, 2) = %d — 컴파일러가 이름을 알고 있지만 스크립트 메서드라 OPCODE_CALL_RETURN (GDScriptInstance::callp 조회)" % _kit.add(1, 2))
	Log.info("obj.call(\"add\", 1, 2) = %s — Object::callp: 스크립트 인스턴스 → 네이티브 MethodBind 순으로 찾는다" % _kit.call("add", 1, 2))
	Log.info("obj.callv(\"add\", [3, 4]) = %s — 인자를 배열로" % _kit.callv("add", [3, 4]))
	Log.info("has_method(\"add\")=%s, has_method(\"nope\")=%s — 없는 이름을 call() 하면 런타임 오류이므로 먼저 확인한다" % [_kit.has_method("add"), _kit.has_method("nope")])
	Log.info("스크립트 메서드 목록: %s" % [_kit.get_script().get_script_method_list().map(func(m: Dictionary) -> String: return m["name"])])
