extends Control
## 데모 허브. 왼쪽 열: DEMOS 배열에서 코드로 만든 버튼, 오른쪽: 선택한 데모 인스턴스 + Log 패널.
## 헤드리스(--headless)에서도 _ready 가 그대로 돌아야 하므로 DisplayServer 기능에 의존하지 않고,
## 아무것도 기다리지(await) 않는다.
## 엔진: scene/main/node.cpp _propagate_ready() — add_child 로 트리에 들어간 데모는 자식부터 _ready 를 받는다.

const DEMOS: Array[Dictionary] = [
	{
		"title": "1. 타입 벤치마크",
		"scene_path": "res://demos/typing_benchmark/typing_benchmark.tscn",
		"description": "같은 루프를 비타입/정적 타입으로 돌려 OPCODE_OPERATOR 와 OPCODE_OPERATOR_VALIDATED 의 차이를 잰다.",
	},
	{
		"title": "2. Variant 와 Callable",
		"scene_path": "res://demos/variant_and_callable/variant_and_callable.tscn",
		"description": "typeof/type_string, 암시 변환, Callable 만들기·bind/unbind·call/callv/call_deferred, Signal 을 값으로 다루기.",
	},
	{
		"title": "3. 코루틴 (await)",
		"scene_path": "res://demos/coroutines/coroutines.tscn",
		"description": "시그널·타이머·다른 코루틴을 await, 순차 vs 병렬 대기, GDScriptFunctionState 의 정체, 취소 패턴.",
	},
	{
		"title": "4. 클래스와 타입",
		"scene_path": "res://demos/classes_and_typing/classes_and_typing.tscn",
		"description": "class_name/내부 클래스, _init, static, super, is/as, 덕 타이핑, enum+match, @export, setter/getter, 타입 컨테이너.",
	},
	{
		"title": "5. Expression 과 리플렉션",
		"scene_path": "res://demos/expression_and_reflection/expression_and_reflection.tscn",
		"description": "Expression 파싱/실행, get_script_method_list, get_property_list 필터, set/get, _get_property_list 가상 프로퍼티.",
	},
	{
		"title": "6. 오류와 디버깅",
		"scene_path": "res://demos/errors_and_debugging/errors_and_debugging.tscn",
		"description": "assert, push_error/push_warning, Error 열거형 반환 패턴, @warning_ignore, print_stack, 디버거/에디터 감지.",
	},
]

## Log.Level 순서(INFO, WARN, SECTION)와 같은 색.
const LOG_COLORS: Array[Color] = [Color(0.85, 0.85, 0.85), Color(1.0, 0.8, 0.4), Color(0.5, 0.85, 1.0)]

var _button_column: VBoxContainer
var _description: Label
var _demo_host: MarginContainer
var _log_view: RichTextLabel
var _current_demo: Node = null


func _ready() -> void:
	_build_ui()
	# 오토로드는 메인 씬보다 먼저 트리에 들어가므로 여기서 안전하게 연결할 수 있다 (main/main.cpp Main::start).
	Log.message.connect(_on_log_message)
	Log.section("GDScript Lab 허브")
	Log.info("왼쪽 버튼으로 데모를 고르면 오른쪽에 씬이 인스턴스화되고, 이전 데모는 queue_free() 된다.")
	Log.info("이 패널은 Log 오토로드의 message 시그널을 그대로 비춘다. 같은 줄이 stdout 에도 찍힌다.")
	_open_demo(0)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(row)

	_button_column = VBoxContainer.new()
	_button_column.custom_minimum_size = Vector2(300, 0)
	row.add_child(_button_column)
	var title := Label.new()
	title.text = "03 GDScript Lab — 언어 내부"
	_button_column.add_child(title)
	for i: int in DEMOS.size():
		var button := Button.new()
		button.text = String(DEMOS[i]["title"])
		button.tooltip_text = String(DEMOS[i]["description"])
		# bind() 로 인덱스를 뒤에 붙인 Callable 을 연결한다 (core/variant/callable.cpp Callable::bind).
		button.pressed.connect(_open_demo.bind(i))
		_button_column.add_child(button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_description)
	_demo_host = MarginContainer.new()
	_demo_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_demo_host)
	_log_view = RichTextLabel.new()
	_log_view.scroll_following = true
	_log_view.custom_minimum_size = Vector2(0, 240)
	right.add_child(_log_view)


func _open_demo(index: int) -> void:
	if _current_demo != null:
		_demo_host.remove_child(_current_demo)
		# free() 대신 queue_free(): 아직 처리 중인 시그널/지연 호출이 끝난 프레임 끝에 지운다 (scene/main/scene_tree.cpp _flush_delete_queue).
		_current_demo.queue_free()
		_current_demo = null
	var info: Dictionary = DEMOS[index]
	var scene_path: String = String(info["scene_path"])
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		Log.warn("씬을 불러오지 못했다: " + scene_path)
		return
	_description.text = String(info["description"])
	Log.section(String(info["title"]))
	_current_demo = packed.instantiate()
	_demo_host.add_child(_current_demo)


func _on_log_message(text: String, level: int) -> void:
	var color: Color = LOG_COLORS[clampi(level, 0, LOG_COLORS.size() - 1)]
	# add_text() 는 BBCode 를 해석하지 않으므로 "[...]" 가 들어간 로그도 그대로 보인다.
	_log_view.push_color(color)
	_log_view.add_text(("== " + text) if level == Log.Level.SECTION else text)
	_log_view.pop()
	_log_view.newline()
