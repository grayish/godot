extends Control
## .tscn 해부. 에디터의 씬 독에 보이는 트리는 사실 이런 텍스트 파일이다.
## 왼쪽: mob.tscn 원문 (FileAccess 로 읽음). 오른쪽: 각 섹션 설명 + PackedScene.get_state() 가 본 같은 파일.
## 엔진: scene/resources/resource_format_text.cpp (파서: ResourceLoaderText::load 가 [gd_scene] 을 SceneState 로),
##       scene/resources/packed_scene.h/.cpp (SceneState: 노드/속성/연결의 평평한 배열, instantiate() 로 복원).

const TARGET_PATH := "res://demos/game/mob.tscn"

var source_edit: CodeEdit
var explain_label: RichTextLabel


func _ready() -> void:
	Log.section(".tscn 해부")
	_build_ui()
	var text: String = _read_text(TARGET_PATH)
	source_edit.text = text
	Log.info("%s 원문 %d줄을 FileAccess 로 읽었습니다." % [TARGET_PATH, text.split("\n").size()])
	explain_label.append_text(_explanation_bbcode())
	_show_scene_state()


func _build_ui() -> void:
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 8)
	add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var path_label := Label.new()
	path_label.text = TARGET_PATH + " (원문)"
	left.add_child(path_label)
	source_edit = CodeEdit.new()
	source_edit.editable = false
	source_edit.gutters_draw_line_numbers = true
	source_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(source_edit)

	explain_label = RichTextLabel.new()
	explain_label.bbcode_enabled = true
	explain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explain_label.selection_enabled = true
	columns.add_child(explain_label)


## res:// 도 그냥 파일이다 (익스포트 후에는 .pck 안의 파일). 실패하면 null 이 오고 get_open_error() 로 이유를 본다.
func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		Log.warn("파일을 열 수 없음: %s (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	return file.get_as_text()


## bbcode 에서 대괄호 자체를 쓰려면 [lb] [rb] 로 이스케이프한다.
func _explanation_bbcode() -> String:
	var lines: PackedStringArray = [
		"[b][lb]gd_scene load_steps=N format=3[rb][/b]",
		"헤더. format=3 이 Godot 4 텍스트 씬. load_steps 는 ext_resource + sub_resource + 1 — 로더가 진행률을 계산하는 데 쓴다.",
		"",
		"[b][lb]ext_resource type=\"Script\" path=\"res://...\" id=\"1_mob\"[rb][/b]",
		"바깥 파일 참조. 씬 안에서는 ExtResource(\"1_mob\") 로 가리킨다. 스크립트, 다른 씬(PackedScene), .tres 가 여기 온다.",
		"",
		"[b][lb]sub_resource type=\"CircleShape2D\" id=\"...\"[rb][/b]",
		"이 파일 안에만 존재하는 리소스(내장 리소스). 인스펙터에서 '새 CircleShape2D' 를 만들면 여기 저장된다. SubResource(\"id\") 로 참조.",
		"",
		"[b][lb]node name=\"Mob\" type=\"Area2D\" groups=[lb]\"mobs\"[rb][rb][/b]",
		"노드 한 개. parent 가 없으면 루트. 아래 줄들은 기본값과 다른 속성만 적힌다(기본값은 저장하지 않는다). "
		+ "parent=\".\" 은 루트의 자식, parent=\"HUD\" 는 HUD 의 자식. instance=ExtResource(...) 면 다른 씬을 인스턴스화한 노드.",
		"",
		"[b][lb]connection signal=\"body_entered\" from=\".\" to=\".\" method=\"_on_body_entered\"[rb][/b]",
		"에디터 Node 독 → Signals 탭에서 연결한 것. 인스턴스화 시 from.connect(signal, Callable(to, method)) 로 바뀐다.",
		"",
		"[b]엔진 소스[/b]",
		"파서: scene/resources/resource_format_text.cpp  ·  SceneState/PackedScene: scene/resources/packed_scene.cpp",
		"인스턴스화 순서: 노드 생성(ClassDB) → 속성 set → 그룹 add_to_group → 부모 add_child → 마지막에 [lb]connection[rb] connect",
		"",
		"[b]PackedScene.get_state() 가 본 같은 파일[/b]",
	]
	return "\n".join(lines) + "\n"


## 같은 파일을 리소스 로더가 파싱한 결과(SceneState)로 본다. 텍스트의 [node]/[connection] 과 1:1 로 맞아떨어진다.
func _show_scene_state() -> void:
	var packed: PackedScene = load(TARGET_PATH) as PackedScene
	if packed == null:
		Log.warn("PackedScene 로드 실패: " + TARGET_PATH)
		return
	var state: SceneState = packed.get_state()
	var summary: String = "SceneState: 노드 %d개, 연결 %d개" % [state.get_node_count(), state.get_connection_count()]
	Log.info(summary)
	explain_label.append_text(summary + "\n")
	for i: int in state.get_node_count():
		var line: String = "  node[%d] name=%s type=%s path=%s props=%d groups=%s" % [
			i, state.get_node_name(i), state.get_node_type(i), state.get_node_path(i),
			state.get_node_property_count(i), str(state.get_node_groups(i))]
		Log.info(line)
		explain_label.add_text(line + "\n")
		for p: int in state.get_node_property_count(i):
			var prop_line: String = "      %s = %s" % [state.get_node_property_name(i, p), str(state.get_node_property_value(i, p))]
			explain_label.add_text(prop_line + "\n")
	for i: int in state.get_connection_count():
		var line: String = "  connection[%d] %s.%s → %s.%s flags=%d" % [
			i, state.get_connection_source(i), state.get_connection_signal(i),
			state.get_connection_target(i), state.get_connection_method(i), state.get_connection_flags(i)]
		Log.info(line)
		explain_label.add_text(line + "\n")
