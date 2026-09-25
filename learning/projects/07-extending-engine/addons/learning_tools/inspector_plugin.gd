@tool
extends EditorInspectorPlugin

## 인스펙터 플러그인: Node 를 편집할 때 속성 목록 맨 위에 엔진 소스 경로 라벨을 끼운다.
## 엔진: editor/inspector/editor_inspector.cpp EditorInspector::update_tree() 가
##       등록된 플러그인마다 _can_handle → _parse_begin → _parse_property... 순으로 부른다.

const SourceHint := preload("res://addons/learning_tools/source_hint.gd")


func _can_handle(object: Object) -> bool:
	return object is Node


func _parse_begin(object: Object) -> void:
	var label := Label.new()
	label.text = "엔진 소스: " + SourceHint.engine_source_path(object.get_class())
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# add_custom_control: 속성 편집기가 아닌 임의의 컨트롤을 인스펙터에 넣는다.
	add_custom_control(label)
