@tool
extends Node2D

## add_custom_type("SourceHintLabel2D", "Node2D", 이 스크립트, null) 로 등록되는 커스텀 노드.
## 커스텀 타입은 "진짜 클래스"가 아니라 Node2D + 스크립트다 (EditorPlugin.add_custom_type 문서).
## @tool 이므로 에디터 뷰포트에서도 _draw 가 돌아 자기 클래스 힌트를 그린다.
## 엔진: scene/main/canvas_item.cpp CanvasItem::_notification(NOTIFICATION_DRAW) → _draw 호출,
##       draw_string 은 RenderingServer canvas_item_add_* 명령으로 번역된다.

const SourceHint := preload("res://addons/learning_tools/source_hint.gd")
const LINE_GAP: int = 4

## 힌트를 그릴 대상 클래스. 비어 있거나 모르는 이름이면 자기 자신(Node2D)을 쓴다.
@export var target_class: String = "Node2D":
	set(value):
		target_class = value
		queue_redraw()

@export var color: Color = Color(1.0, 0.9, 0.3):
	set(value):
		color = value
		queue_redraw()


func hint_lines() -> PackedStringArray:
	var cls: String = target_class if ClassDB.class_exists(target_class) else get_class()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s (SourceHintLabel2D)" % cls)
	lines.append("src: " + SourceHint.engine_source_path(cls))
	lines.append("doc: " + SourceHint.doc_xml_path(cls))
	return lines


func _draw() -> void:
	# ThemeDB.fallback_font 는 폰트 에셋 없이도 쓸 수 있는 기본 폰트 (scene/theme/theme_db.cpp).
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var font_size: int = ThemeDB.fallback_font_size
	var y: float = float(font_size)
	for line: String in hint_lines():
		draw_string(font, Vector2(0.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
		y += float(font_size + LINE_GAP)
