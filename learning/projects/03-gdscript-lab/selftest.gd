extends SceneTree
## 헤드리스 셀프테스트: godot --headless --path <dir> -s res://selftest.gd
## 비UI 로직만 검사한다. 코루틴 테스트는 프레임이 필요하므로 _process 에서 한 테스트씩 진행한다.
## 엔진: core/os/main_loop.h — 스크립트로 MainLoop(_initialize/_process)를 구현하면 씬 없이도 프레임 루프를 얻는다.

const PROJECT_DIR: String = "03-gdscript-lab"
const MAX_FRAMES: int = 600

# 헤드리스에는 전역 클래스 캐시가 없어 class_name 대신 preload 로 참조한다.
# 주의: -s 스크립트의 preload 는 오토로드(Log) 등록보다 먼저 컴파일되므로, Log 를 쓰는 데모 씬 스크립트가 아니라
# Log 를 쓰지 않는 로직 전용 스크립트만 preload 한다.
const BenchKernels := preload("res://demos/typing_benchmark/bench_kernels.gd")
const CallableKit := preload("res://demos/variant_and_callable/callable_kit.gd")
const FrameWaiter := preload("res://demos/coroutines/frame_waiter.gd")
const ExpressionKit := preload("res://demos/expression_and_reflection/expression_kit.gd")
const VirtualPropBox := preload("res://demos/expression_and_reflection/virtual_props.gd")

var _tests: Array[Callable] = []
var _index: int = 0
var _busy: bool = false
var _frames: int = 0
var _failures: Array[String] = []
var _current_name: String = ""


func _initialize() -> void:
	_tests = [
		_test_typed_vs_untyped,
		_test_callable_bind_unbind,
		_test_expression,
		_test_coroutine_over_frames,
		_test_virtual_property,
	]
	print("SELFTEST start: %d tests" % _tests.size())


@warning_ignore("missing_await")
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > MAX_FRAMES:
		_failures.append("timeout after %d frames (test %s)" % [_frames, _current_name])
		_finish()
		return true
	if _busy:
		return false
	if _index >= _tests.size():
		_finish()
		return true
	_busy = true
	_run_one(_tests[_index]) # 코루틴을 발사 후 잊기 — 끝나면 _busy 를 내린다
	return false


func _run_one(test: Callable) -> void:
	_current_name = test.get_method()
	await test.call() # 코루틴이 아닌 테스트는 await 가 즉시 지나간다
	print("  %s: done" % _current_name)
	_index += 1
	_busy = false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [_current_name, message])


func _finish() -> void:
	if _failures.is_empty():
		print("SELFTEST PASS %s" % PROJECT_DIR)
		quit(0)
	else:
		print("SELFTEST FAIL %s: %s" % [PROJECT_DIR, str(_failures)])
		quit(1)


# ---------------------------------------------------------------- 1. 타입/비타입 커널이 같은 값을 낸다

func _test_typed_vs_untyped() -> void:
	var n: int = 3000
	_expect(BenchKernels.int_untyped(n)["result"] == BenchKernels.int_typed(n)["result"], "정수 합이 다르다")
	_expect(BenchKernels.int_typed(n)["result"] == 3 * (n * (n - 1) / 2) + n, "정수 합 공식 불일치")
	var vector_untyped: Vector2 = BenchKernels.vector2_untyped(n)["result"]
	var vector_typed: Vector2 = BenchKernels.vector2_typed(n)["result"]
	_expect(vector_untyped.is_equal_approx(vector_typed), "Vector2 결과가 다르다: %s vs %s" % [vector_untyped, vector_typed])

	var arrays: Dictionary = BenchKernels.make_arrays(500)
	var plain: Array = arrays["plain"]
	var typed: Array[int] = arrays["typed"]
	_expect(typed.is_typed() and not plain.is_typed(), "make_arrays 의 타입 여부가 틀렸다")
	_expect(BenchKernels.array_untyped(plain)["result"] == BenchKernels.array_typed(typed)["result"], "배열 합이 다르다")
	_expect(BenchKernels.array_typed(typed)["result"] == 124750, "배열 합 공식 불일치")

	var packed: PackedFloat32Array = BenchKernels.make_packed(500)
	_expect(is_equal_approx(float(BenchKernels.packed_untyped(packed)["result"]), float(BenchKernels.packed_typed(packed)["result"])), "PackedFloat32Array 합이 다르다")

	_expect(BenchKernels.native_call_untyped(100)["result"] == BenchKernels.native_call_typed(100)["result"], "네이티브 메서드 호출 결과가 다르다")
	_expect(BenchKernels.script_call_untyped(100)["result"] == 100 and BenchKernels.script_call_typed(100)["result"] == 100, "스크립트 메서드 호출 결과가 다르다")

	var dict: Dictionary = BenchKernels.make_dictionary()
	var by_string: Variant = BenchKernels.dict_string_keys(dict, BenchKernels.make_string_keys(), 2048)["result"]
	var by_name: Variant = BenchKernels.dict_stringname_keys(dict, BenchKernels.make_stringname_keys(), 2048)["result"]
	_expect(by_string == by_name and by_string == 2 * (BenchKernels.KEY_COUNT * (BenchKernels.KEY_COUNT - 1) / 2), "Dictionary 조회 합이 다르다: %s vs %s" % [by_string, by_name])


# ---------------------------------------------------------------- 2. Callable bind / unbind / callv / bindv, Signal 값

func _test_callable_bind_unbind() -> void:
	var kit := CallableKit.new()
	var add10: Callable = Callable(kit, "add").bind(10)
	_expect(add10.call(5) == 15, "bind(10).call(5) != 15")
	_expect(add10.get_bound_arguments_count() == 1, "bound arguments count != 1")
	var drop_one: Callable = add10.unbind(1)
	_expect(drop_one.call(5, 99) == 15, "bind(10).unbind(1).call(5, 99) != 15")
	_expect(drop_one.get_unbound_arguments_count() == 1, "unbound arguments count != 1")
	_expect(kit.add.callv([2, 3]) == 5, "callv([2, 3]) != 5")
	_expect(kit.add.bindv([7, 8]).call() == 15, "bindv([7, 8]).call() != 15")
	_expect(kit.greet.bind("?").call("셀프테스트") == "안녕, 셀프테스트?", "greet.bind 결과가 다르다")
	_expect(kit.call_count == 5, "call_count=%d (5 예상)" % kit.call_count)
	var base: int = 100
	var lambda: Callable = func(x: int) -> int: return x + base
	_expect(lambda.call(1) == 101 and lambda.is_custom(), "람다 캡처/is_custom 실패")

	var sig: Signal = Signal(kit, "pinged")
	var received: Array[int] = []
	sig.connect(func(value: int) -> void: received.append(value))
	kit.ping(3)
	sig.emit(4)
	_expect(received.size() == 2 and received[0] == 3 and received[1] == 4, "Signal 값 emit/connect 실패: %s" % [received])
	_expect(CallableKit.describe(42).contains("int"), "describe(42) 에 타입 이름이 없다")


# ---------------------------------------------------------------- 3. Expression

func _test_expression() -> void:
	var outcome: Dictionary = ExpressionKit.evaluate("a*2+b", PackedStringArray(["a", "b"]), [3, 4])
	_expect(outcome["ok"] == true and outcome["value"] == 10, "a*2+b (a=3, b=4) → %s" % [outcome])
	var bad: Dictionary = ExpressionKit.evaluate("a +* b", PackedStringArray(["a", "b"]), [1, 2])
	_expect(bad["ok"] == false and String(bad["error"]).length() > 0, "파싱 실패가 보고되지 않았다")
	var division: Dictionary = ExpressionKit.evaluate("a / 0", PackedStringArray(["a"]), [1])
	_expect(division["ok"] == false, "0 나눗셈이 실패로 보고되지 않았다")


# ---------------------------------------------------------------- 4. 코루틴: process_frame 을 기다린 뒤 값을 돌려준다

func _test_coroutine_over_frames() -> void:
	var start_frame: int = _frames
	var waited: int = await FrameWaiter.wait_frames(self, 3)
	_expect(waited == 3, "wait_frames(3) 가 %d 를 돌려줬다" % waited)
	_expect(_frames > start_frame, "프레임이 진행되지 않았다 (%d)" % _frames)
	# SceneTreeTimer 는 프레임 delta 를 빼며 줄어들므로 벽시계 기준으로는 최대 한 프레임 일찍 끝날 수 있다 — 여유를 둔다.
	var elapsed: int = await FrameWaiter.wait_seconds(self, 0.05)
	_expect(elapsed >= 30, "wait_seconds(0.05) 가 %d ms 만에 돌아왔다" % elapsed)


# ---------------------------------------------------------------- 5. _get_property_list 가상 프로퍼티

func _test_virtual_property() -> void:
	var box := VirtualPropBox.new()
	var props: Array[Dictionary] = box.get_property_list()
	var names: Array = props.map(func(p: Dictionary) -> String: return p["name"])
	_expect(names.has("virtual_prop"), "virtual_prop 이 get_property_list() 에 없다: %s" % [names])
	_expect(names.has("real_value"), "real_value 가 get_property_list() 에 없다")
	box.set("virtual_prop", 42)
	_expect(box.get("virtual_prop") == 42, "set/get 가상 프로퍼티 왕복 실패: %s" % [box.get("virtual_prop")])
	box.set("real_value", 9)
	_expect(box.real_value == 9, "real_value set 실패")
	var real_usage: int = 0
	var virtual_usage: int = 0
	for prop: Dictionary in props:
		if prop["name"] == "real_value":
			real_usage = prop["usage"]
		elif prop["name"] == "virtual_prop":
			virtual_usage = prop["usage"]
	_expect((real_usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0, "real_value 에 SCRIPT_VARIABLE 플래그가 없다")
	_expect((virtual_usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0, "가상 프로퍼티에 SCRIPT_VARIABLE 플래그가 붙었다")
