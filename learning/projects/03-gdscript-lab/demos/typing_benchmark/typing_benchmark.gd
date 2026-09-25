extends Control
## 데모 1: 타입이 성능을 만드는 이유.
## 같은 루프를 비타입/정적 타입으로 돌려 GridContainer 표로 보여준다.
## 측정은 버튼을 눌러야 시작한다 — 헤드리스 허브(--quit-after 5)가 빨리 끝나도록 _ready 에서는 돌리지 않는다.
## 커널 본체는 bench_kernels.gd 에 있다 (selftest 가 같은 함수를 호출해 두 버전의 결과가 같은지 검사).

# class_name BenchKernels 가 있지만 헤드리스 실행에는 에디터가 만든 전역 클래스 캐시
# (.godot/global_script_class_cache.cfg, core/config/project_settings.cpp get_global_class_list)가 없으므로 preload 로 참조한다.
const BenchKernels := preload("res://demos/typing_benchmark/bench_kernels.gd")
const DEFAULT_ITERATIONS: int = 1_000_000
const HEADER: Array[String] = ["측정 항목", "비타입 (µs)", "정적 타입 (µs)", "배속", "결과 동일"]

var _iterations_spin: SpinBox
var _run_button: Button
var _status: Label
var _grid: GridContainer


func _ready() -> void:
	_build_ui()
	Log.info("반복 횟수를 정하고 [벤치마크 실행] 을 누르면 7가지 루프를 비타입/정적 타입으로 재서 표에 채운다.")
	Log.info("핵심: `var x: int` 한 줄로 컴파일러가 OPCODE_OPERATOR 대신 OPCODE_OPERATOR_VALIDATED 를 내게 된다.")
	Log.info("  gdscript_byte_codegen.cpp write_binary_operator(): 두 피연산자 타입이 확정되면 Variant::get_validated_operator_evaluator() 로 함수 포인터를 미리 고른다.")
	Log.info("  gdscript_vm.cpp OPCODE_OPERATOR: 매번 Variant::evaluate() → variant_op.cpp 의 3차원 테이블 조회.")
	Log.info("바이트코드 확인: gdscript_disassembler.cpp 는 'validated operator' / 'operator' 로 구분해 찍는다 (README 의 '바이트코드 덤프' 참고).")
	Log.info("이 바이너리는 에디터(디버그) 빌드라 VM 에 검사 코드가 더 들어 있다. 릴리스 템플릿에서는 절대값이 더 작아진다.")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var controls := HBoxContainer.new()
	column.add_child(controls)
	var label := Label.new()
	label.text = "반복 횟수 (정수 산술 기준, 다른 항목은 비례 축소): "
	controls.add_child(label)
	_iterations_spin = SpinBox.new()
	_iterations_spin.min_value = 10_000
	_iterations_spin.max_value = 20_000_000
	_iterations_spin.step = 10_000
	_iterations_spin.value = DEFAULT_ITERATIONS
	controls.add_child(_iterations_spin)
	_run_button = Button.new()
	_run_button.text = "벤치마크 실행"
	_run_button.pressed.connect(_run_benchmarks)
	controls.add_child(_run_button)

	_status = Label.new()
	_status.text = "아직 실행하지 않았다."
	column.add_child(_status)

	_grid = GridContainer.new()
	_grid.columns = HEADER.size()
	column.add_child(_grid)
	_add_row(HEADER)

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "배속 = 비타입 시간 / 타입 시간. '스크립트 메서드 호출' 은 타입이 있어도 OPCODE_CALL 이라 차이가 작고, " \
			+ "'Dictionary 조회' 는 두 쪽 다 타입이 있고 키 종류(String vs StringName)만 다르다."
	column.add_child(note)


func _add_row(cells: Array[String]) -> void:
	for cell: String in cells:
		var label := Label.new()
		label.text = cell
		label.custom_minimum_size = Vector2(150, 0)
		_grid.add_child(label)


func _clear_rows() -> void:
	# 헤더(첫 줄)만 남기고 뒤에서부터 지운다.
	for i: int in range(_grid.get_child_count() - 1, HEADER.size() - 1, -1):
		var child: Node = _grid.get_child(i)
		_grid.remove_child(child)
		child.free()


@warning_ignore("integer_division")
func _run_benchmarks() -> void:
	var n: int = int(_iterations_spin.value)
	_clear_rows()
	_status.text = "측정 중..."
	Log.section("타입 벤치마크 n=%d" % n)

	_report("정수 산술 (%d회)" % n, BenchKernels.int_untyped(n), BenchKernels.int_typed(n))
	_report("Vector2 수학 (%d회)" % (n / 4), BenchKernels.vector2_untyped(n / 4), BenchKernels.vector2_typed(n / 4))

	var arrays: Dictionary = BenchKernels.make_arrays(n / 10)
	var plain: Array = arrays["plain"]
	var typed: Array[int] = arrays["typed"]
	_report("Array vs Array[int] 인덱스 합 (%d개)" % plain.size(), BenchKernels.array_untyped(plain), BenchKernels.array_typed(typed))

	var packed: PackedFloat32Array = BenchKernels.make_packed(n / 10)
	_report("PackedFloat32Array 합 (%d개)" % packed.size(), BenchKernels.packed_untyped(packed), BenchKernels.packed_typed(packed))

	_report("네이티브 메서드 호출 Variant vs RefCounted (%d회)" % (n / 4), BenchKernels.native_call_untyped(n / 4), BenchKernels.native_call_typed(n / 4))
	_report("스크립트 메서드 호출 Variant vs BenchKernels (%d회)" % (n / 4), BenchKernels.script_call_untyped(n / 4), BenchKernels.script_call_typed(n / 4))

	var dict: Dictionary = BenchKernels.make_dictionary()
	var string_keys: Array[String] = BenchKernels.make_string_keys()
	var name_keys: Array[StringName] = BenchKernels.make_stringname_keys()
	_report("Dictionary 조회 String 키 vs StringName 키 (%d회)" % (n / 4), BenchKernels.dict_string_keys(dict, string_keys, n / 4), BenchKernels.dict_stringname_keys(dict, name_keys, n / 4))

	_status.text = "완료. 숫자는 Time.get_ticks_usec() 차이 (µs). 다시 누르면 재측정한다."


func _report(title: String, untyped: Dictionary, typed: Dictionary) -> void:
	var untyped_usec: int = untyped["usec"]
	var typed_usec: int = typed["usec"]
	var ratio: float = float(untyped_usec) / float(maxi(typed_usec, 1))
	var same: bool = _same_result(untyped["result"], typed["result"])
	_add_row([title, str(untyped_usec), str(typed_usec), "%.2fx" % ratio, "예" if same else "아니오"])
	Log.info("%s: 비타입 %d µs, 타입 %d µs → %.2f배, 결과 동일=%s" % [title, untyped_usec, typed_usec, ratio, same])


## 두 버전이 같은 값을 냈는지 확인한다. float 는 오차 허용 비교.
func _same_result(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_VECTOR2 and typeof(b) == TYPE_VECTOR2:
		return (a as Vector2).is_equal_approx(b as Vector2)
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b
