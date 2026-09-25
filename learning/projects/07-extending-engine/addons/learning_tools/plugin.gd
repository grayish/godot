@tool
extends EditorPlugin

## 학습용 에디터 플러그인. 에디터도 Godot 앱(SceneTree 위에 올라간 EditorNode)이라서,
## 플러그인은 그 씬 트리에 컨트롤을 얹고 에디터 싱글턴에 콜백을 등록하는 것에 지나지 않는다.
## 엔진: editor/editor_node.cpp EditorNode::set_addon_plugin_enabled() — plugin.cfg 의 script 를 로드해
##       이 클래스를 인스턴스화하고 EditorNode 의 자식으로 add_child → _enter_tree 가 불린다.
##       editor/plugins/editor_plugin.cpp — add_control_to_dock / add_custom_type / add_tool_menu_item 구현.
## 주의: 이 파일은 --headless 검증에서 에디터 밖에서도 load() 되므로,
##       EditorInterface 같은 에디터 전용 호출은 클래스 본문이 아니라 함수 안에만 둔다.

const SourceHint := preload("res://addons/learning_tools/source_hint.gd")
const InspectorPluginScript := preload("res://addons/learning_tools/inspector_plugin.gd")
const ExportPluginScript := preload("res://addons/learning_tools/export_plugin.gd")
const SourceHintLabel2DScript := preload("res://addons/learning_tools/source_hint_label_2d.gd")

const DOCK_NAME: String = "Engine Source Hint"
const CUSTOM_TYPE_NAME: String = "SourceHintLabel2D"
const TOOL_MENU_NAME: String = "Learning: Print ClassDB stats"
const MAX_LISTED_NODES: int = 4

var _dock: VBoxContainer = null
var _dock_text: RichTextLabel = null
var _inspector_plugin: EditorInspectorPlugin = null
var _export_plugin: EditorExportPlugin = null


func _enter_tree() -> void:
	# (1) 독: 선택한 노드의 클래스/상속/엔진 소스 경로를 보여준다.
	#     add_control_to_dock 은 4.8 에서 add_dock(EditorDock) 으로 대체가 예고됨(deprecated).
	#     내부적으로는 EditorDock 을 만들어 컨트롤 이름을 제목으로 쓴다 (editor_plugin.cpp:95).
	_dock = VBoxContainer.new()
	_dock.name = DOCK_NAME
	var hint := Label.new()
	hint.text = "씬 독에서 노드를 선택하면 엔진 소스 경로를 추정합니다."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(hint)
	_dock_text = RichTextLabel.new()
	_dock_text.selection_enabled = true
	_dock_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(_dock_text)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)
	# EditorSelection 은 씬 독의 선택 상태 (editor/editor_interface.cpp get_selection).
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)

	# (2) 인스펙터 플러그인: 모든 Node 의 인스펙터 맨 위에 "엔진 소스: ..." 라벨을 끼운다.
	_inspector_plugin = InspectorPluginScript.new()
	add_inspector_plugin(_inspector_plugin)

	# (3) 커스텀 타입: "노드 추가" 대화상자에 SourceHintLabel2D 가 나타난다.
	#     실체는 Node2D + 스크립트일 뿐이다 (editor/editor_data.cpp EditorData::add_custom_type).
	add_custom_type(CUSTOM_TYPE_NAME, "Node2D", SourceHintLabel2DScript, null)

	# (4) 익스포트 플러그인: 익스포트 시작/파일/끝 로그 + 생성 파일 추가.
	_export_plugin = ExportPluginScript.new()
	add_export_plugin(_export_plugin)

	# (5) Project > Tools 메뉴 항목.
	add_tool_menu_item(TOOL_MENU_NAME, _print_classdb_stats)

	_on_selection_changed()
	print("[learning_tools] 플러그인 활성화: 독, 인스펙터 플러그인, 커스텀 타입, 익스포트 플러그인, 툴 메뉴 등록")


func _exit_tree() -> void:
	# 등록의 역순으로 해제한다. 해제를 빼먹으면 플러그인을 껐다 켤 때 중복 등록된다.
	remove_tool_menu_item(TOOL_MENU_NAME)
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	remove_custom_type(CUSTOM_TYPE_NAME)
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	var selection: EditorSelection = EditorInterface.get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
		_dock_text = null
	print("[learning_tools] 플러그인 비활성화")


func _on_selection_changed() -> void:
	if _dock_text == null:
		return
	var nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	_dock_text.clear()
	if nodes.is_empty():
		_dock_text.append_text("(선택된 노드 없음)")
		return
	var count: int = mini(nodes.size(), MAX_LISTED_NODES)
	for i: int in count:
		var node: Node = nodes[i]
		# get_class() 는 스크립트가 붙어 있어도 네이티브 클래스 이름을 돌려준다 (core/object/object.cpp).
		_dock_text.append_text("[%s]\n%s\n\n" % [node.name, SourceHint.describe_text(node.get_class())])
	if nodes.size() > count:
		_dock_text.append_text("... 외 %d개\n" % (nodes.size() - count))


## 툴 메뉴 콜백: ClassDB 통계를 출력 창(stdout)에 찍는다.
## 엔진: core/object/class_db.cpp — classes HashMap 이 곧 이 통계의 원천.
func _print_classdb_stats() -> void:
	var all_classes: PackedStringArray = ClassDB.get_class_list()
	var editor_only: int = 0
	var extension: int = 0
	for cls: String in all_classes:
		var api: int = ClassDB.class_get_api_type(cls)
		if api == ClassDB.API_EDITOR or api == ClassDB.API_EDITOR_EXTENSION:
			editor_only += 1
		if api == ClassDB.API_EXTENSION or api == ClassDB.API_EDITOR_EXTENSION:
			extension += 1
	print("[learning_tools] ClassDB 통계")
	print("  전체 클래스: %d" % all_classes.size())
	print("  Node 파생: %d" % ClassDB.get_inheriters_from_class("Node").size())
	print("  Control 파생: %d" % ClassDB.get_inheriters_from_class("Control").size())
	print("  Resource 파생: %d" % ClassDB.get_inheriters_from_class("Resource").size())
	print("  에디터 전용(API_EDITOR*): %d" % editor_only)
	print("  GDExtension 등록(API_*EXTENSION): %d" % extension)
	print("  Summator 존재: %s, SummatorExt 존재: %s" % [ClassDB.class_exists("Summator"), ClassDB.class_exists("SummatorExt")])
