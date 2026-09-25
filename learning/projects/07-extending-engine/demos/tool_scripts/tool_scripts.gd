@tool
extends Control

## 데모 2: @tool 스크립트와 "에디터는 Godot 앱" 이라는 사실.
## 이 루트 스크립트도 @tool 이라 에디터에서 씬을 열면 _ready 가 불린다 — 그래서 첫 줄에서
## Engine.is_editor_hint() 로 갈라 놓는다 (에디터에는 Log autoload 가 없다).
## 엔진: main/main.cpp Main::start() — `editor` 플래그면 EditorNode 를 만들어 SceneTree 루트에 add_child.
##       editor/editor_node.cpp — 에디터 UI 전체가 보통의 Control 노드 트리다.
##       core/config/engine.h Engine::editor_hint — is_editor_hint() 의 실체는 bool 하나.

@onready var _widget: Node2D = $ToolWidget

var _info: RichTextLabel


func _ready() -> void:
	if Engine.is_editor_hint():
		# 에디터 안: 위젯만 그리고 아무것도 로그하지 않는다.
		return
	_build_ui()
	Log.info("Engine.is_editor_hint() = %s — 지금은 런타임이므로 false" % Engine.is_editor_hint())
	Log.info("에디터는 Godot 앱이다: main/main.cpp Main::start() 가 EditorNode(editor/editor_node.cpp) 를 씬 트리에 얹는다.")
	Log.info("그래서 @tool 스크립트는 에디터 프로세스 안에서 같은 _ready/_process/_draw 를 돈다.")

	var script: Script = _widget.get_script()
	Log.info("ToolWidget 스크립트 is_tool() = %s (modules/gdscript/gdscript.cpp GDScript::is_tool)" % script.is_tool())

	# _get_configuration_warnings: 에디터가 씬 독 경고 아이콘에 쓰지만 직접 호출해 볼 수도 있다.
	var before: PackedStringArray = _widget.call("_get_configuration_warnings")
	Log.info("label_text 비었을 때 경고: %s" % [before])
	_widget.set("label_text", "안녕, @tool")
	var after: PackedStringArray = _widget.call("_get_configuration_warnings")
	Log.info("label_text 채운 뒤 경고: %s (빈 배열이면 아이콘이 사라진다)" % [after])

	# @export_tool_button 은 Callable 프로퍼티다 — 인스펙터의 버튼이 하는 일을 코드로 흉내낸다.
	var action: Callable = _widget.get("recount_action")
	Log.info("@export_tool_button 프로퍼티 recount_action = %s, 유효=%s" % [action, action.is_valid()])
	if action.is_valid():
		action.call()
		Log.info("recount_action.call() 실행 → child_count = %d" % int(_widget.get("child_count")))
	_refresh_info()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _info == null:
		return
	# 위젯의 카운터가 어느 분기에서 증가하는지 보여준다.
	if Engine.get_process_frames() % 30 == 0:
		_refresh_info()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "@tool 스크립트: Engine.is_editor_hint() / _get_configuration_warnings() / @export_tool_button"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	_info = RichTextLabel.new()
	_info.custom_minimum_size = Vector2(0, 150)
	_info.selection_enabled = true
	box.add_child(_info)
	var hint := Label.new()
	hint.text = "에디터에서 res://demos/tool_scripts/tool_scripts.tscn 을 열고 ToolWidget 을 선택해 보세요: 인스펙터에 버튼이 있고, label_text 를 비우면 씬 독에 경고 아이콘이 뜹니다."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)


func _refresh_info() -> void:
	_info.clear()
	_info.append_text("is_editor_hint: %s\n" % Engine.is_editor_hint())
	_info.append_text("ToolWidget.editor_ticks = %d (에디터에서만 증가)\n" % int(_widget.get("editor_ticks")))
	_info.append_text("ToolWidget.runtime_ticks = %d (게임에서만 증가)\n" % int(_widget.get("runtime_ticks")))
	_info.append_text("ToolWidget.label_text = \"%s\"\n" % String(_widget.get("label_text")))
	_info.append_text("경고: %s\n" % [_widget.call("_get_configuration_warnings")])
