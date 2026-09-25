extends Control
## 데모 5: Expression 과 리플렉션.
## 엔진: core/math/expression.cpp (자체 토크나이저/파서/실행기 — GDScript 와 별개의 작은 언어),
##       core/object/object.cpp get_property_list / get_method_list / set / get,
##       modules/gdscript/gdscript.cpp GDScript::get_script_method_list / get_script_property_list.

const VirtualPropBox := preload("res://demos/expression_and_reflection/virtual_props.gd")
const ExpressionKit := preload("res://demos/expression_and_reflection/expression_kit.gd")
const SAMPLES: Array[String] = [
	"a * 2 + b",
	"Vector2(a, b).length()",
	"max(a, b) + sqrt(16)",
	"double_it(a) + counter",
	"[a, b].size() + {\"k\": a}.size()",
	"a / 0",
	"a +* b",
]

@export var counter: int = 0
var label_text: String = "리플렉션"

var _expr_edit: LineEdit
var _a_spin: SpinBox
var _b_spin: SpinBox
var _result: Label


## Expression 의 base_instance 로 self 를 넘기면 식 안에서 부를 수 있는 메서드.
func double_it(x: float) -> float:
	return x * 2.0


func _ready() -> void:
	_build_ui()
	_run_samples()
	_show_reflection()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_expr_edit = LineEdit.new()
	_expr_edit.text = "a * 2 + b"
	_expr_edit.placeholder_text = "a, b, counter, double_it(x) 를 쓸 수 있다"
	_expr_edit.custom_minimum_size = Vector2(320, 0)
	_expr_edit.text_submitted.connect(_on_text_submitted)
	row.add_child(_expr_edit)
	_a_spin = _make_spin(row, 3)
	_b_spin = _make_spin(row, 4)
	var button := Button.new()
	button.text = "평가"
	button.pressed.connect(_evaluate_from_ui)
	row.add_child(button)
	_result = Label.new()
	_result.text = "식을 입력하고 [평가]"
	column.add_child(_result)


func _make_spin(parent: Node, initial: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -1000
	spin.max_value = 1000
	spin.step = 1
	spin.value = initial
	parent.add_child(spin)
	return spin


func _on_text_submitted(_text: String) -> void:
	_evaluate_from_ui()


func _evaluate_from_ui() -> void:
	var outcome: Dictionary = ExpressionKit.evaluate(_expr_edit.text, PackedStringArray(["a", "b"]), [_a_spin.value, _b_spin.value], self)
	_result.text = str(outcome["value"]) if outcome["ok"] else String(outcome["error"])
	Log.info("Expression \"%s\" (a=%s, b=%s) → %s" % [_expr_edit.text, _a_spin.value, _b_spin.value, _result.text])


func _run_samples() -> void:
	Log.section("Expression: parse(식, 입력 이름들) → execute(값들, base_instance)")
	for text: String in SAMPLES:
		var outcome: Dictionary = ExpressionKit.evaluate(text, PackedStringArray(["a", "b"]), [3, 4], self)
		if outcome["ok"]:
			Log.info("  %-34s = %s" % [text, outcome["value"]])
		else:
			Log.warn("  %-34s → %s" % [text, outcome["error"]])
	Log.info("Expression 은 GDScript 가 아니다: 자체 파서(core/math/expression.cpp)로 산술, 내장 타입 생성자, 전역 함수, base_instance 의 메서드만 다룬다.")
	Log.info("파싱/실행 도우미는 expression_kit.gd (ExpressionKit.evaluate) — selftest 가 같은 함수로 \"a*2+b\" 를 검사한다.")


func _show_reflection() -> void:
	Log.section("스크립트 리플렉션: 무엇이 어디에 있는가")
	var script: Script = get_script()
	Log.info("get_script(): %s, get_global_name()=\"%s\" (class_name 이 없으면 빈 문자열)" % [script.resource_path, script.get_global_name()])
	var method_names: Array = script.get_script_method_list().map(func(m: Dictionary) -> String: return m["name"])
	Log.info("get_script_method_list(): %d개 — %s" % [method_names.size(), ", ".join(PackedStringArray(method_names))])
	var script_props: Array = script.get_script_property_list().map(func(p: Dictionary) -> String: return p["name"])
	Log.info("get_script_property_list(): %s" % [script_props])
	var all_props: Array[Dictionary] = get_property_list()
	var script_vars: Array = all_props.filter(func(p: Dictionary) -> bool: return (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0)
	Log.info("get_property_list() %d개 중 PROPERTY_USAGE_SCRIPT_VARIABLE(%d) 인 것: %s" % [all_props.size(), PROPERTY_USAGE_SCRIPT_VARIABLE, script_vars.map(func(p: Dictionary) -> String: return p["name"])])
	Log.info("get_method_list().size()=%d — ClassDB.class_get_method_list(\"Control\").size()=%d 에 스크립트 메서드가 더해진 수" % [get_method_list().size(), ClassDB.class_get_method_list("Control").size()])

	Log.section("이름으로 set / get")
	set("counter", 41)
	counter += 1
	Log.info("set(\"counter\", 41) 뒤 counter += 1 → counter=%d, get(\"counter\")=%s" % [counter, get("counter")])
	set("label_text", "set() 으로 바뀜")
	Log.info("label_text=%s ; get_indexed(\"size:x\")=%s (콜론 경로로 하위 필드까지)" % [label_text, get_indexed("size:x")])
	Log.info("has_method(\"double_it\")=%s, get_method_argument_count(\"double_it\")=%d, call(\"double_it\", 4.5)=%s" % [has_method("double_it"), get_method_argument_count("double_it"), call("double_it", 4.5)])
	Log.info("Object::set 은 없는 이름이면 조용히 실패한다: set(\"nope\", 1) 뒤 get(\"nope\")=%s" % [get("nope")])

	Log.section("_get_property_list / _get / _set 로 만든 가상 프로퍼티")
	var box := VirtualPropBox.new()
	var box_props: Array[Dictionary] = box.get_property_list()
	var names: Array = box_props.map(func(p: Dictionary) -> String: return p["name"])
	Log.info("VirtualPropBox.get_property_list() 에 virtual_prop=%s, real_value=%s" % [names.has("virtual_prop"), names.has("real_value")])
	box.set("virtual_prop", 42)
	Log.info("set(\"virtual_prop\", 42) → get()=%s (_set/_get 이 받았다) ; real_value 는 보통 변수: %s" % [box.get("virtual_prop"), box.real_value])
	for prop: Dictionary in box_props:
		if prop["name"] == "virtual_prop" or prop["name"] == "real_value":
			Log.info("  %s: usage=%d, SCRIPT_VARIABLE 플래그=%s" % [prop["name"], prop["usage"], (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0])
	Log.info("인스펙터/씬 저장/애니메이션 트랙이 모두 이 get_property_list 를 통해 객체를 본다 — 가상 프로퍼티도 똑같이 보인다.")
