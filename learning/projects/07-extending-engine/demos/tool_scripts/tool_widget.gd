@tool
extends Node2D

## @tool 위젯. 에디터에서 이 씬을 열면 에디터 프로세스 안에서 _ready/_process/_draw 가 그대로 돈다.
## 에디터가 별도의 프로그램이 아니라 "EditorNode 를 루트에 얹은 Godot 앱"이기 때문이다
## (main/main.cpp Main::start() → editor/editor_node.cpp EditorNode).
## 엔진: modules/gdscript/gdscript.cpp GDScript::is_tool() — @tool 이 없으면 에디터는 스크립트 인스턴스를 만들지 않는다.
##       scene/main/node.cpp Node::update_configuration_warnings() → 씬 독의 경고 아이콘 갱신.

const BOX_SIZE: Vector2 = Vector2(360, 64)

## 비어 있으면 씬 독에 경고 아이콘이 뜬다 (_get_configuration_warnings).
@export var label_text: String = "":
	set(value):
		label_text = value
		update_configuration_warnings()
		queue_redraw()

@export var box_color: Color = Color(0.2, 0.5, 0.9):
	set(value):
		box_color = value
		queue_redraw()

## 인스펙터에 버튼으로 나타난다 (4.4+ @export_tool_button). 값은 Callable 이어야 한다.
@export_tool_button("자식 수 다시 세기", "Reload") var recount_action: Callable = recount

var child_count: int = 0
var editor_ticks: int = 0
var runtime_ticks: int = 0


func _ready() -> void:
	recount()


func _process(_delta: float) -> void:
	# 같은 코드가 에디터와 게임 양쪽에서 돈다. 에디터에서 하면 안 되는 일(저장, 랜덤 변경 등)은 이 분기로 막는다.
	if Engine.is_editor_hint():
		editor_ticks += 1
	else:
		runtime_ticks += 1


func recount() -> void:
	child_count = get_child_count()
	queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = PackedStringArray()
	if label_text.is_empty():
		warnings.append("label_text 가 비어 있습니다. 인스펙터에서 채우면 이 경고가 사라집니다.")
	return warnings


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BOX_SIZE), box_color)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var size: int = ThemeDB.fallback_font_size
	var shown: String = label_text if not label_text.is_empty() else "(label_text 비어 있음)"
	var mode: String = "에디터" if Engine.is_editor_hint() else "런타임"
	draw_string(font, Vector2(8, size + 8), "%s — %s, 자식 %d개" % [shown, mode, child_count], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
