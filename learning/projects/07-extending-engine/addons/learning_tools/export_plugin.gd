@tool
extends EditorExportPlugin

## 익스포트 플러그인: Project > Export 진행 중 콜백을 받아 로그를 남기고, 생성한 텍스트 파일을 PCK 에 추가한다.
## 엔진: editor/export/editor_export_plugin.cpp — _export_begin/_export_file/_export_end 는
##       EditorExportPlatform::export_project_files() (editor/export/editor_export_platform.cpp) 가 호출.
##       add_file() 로 넣은 파일은 res:// 가상 경로로 익스포트 결과에서 load 할 수 있다.

const INFO_PATH: String = "res://learning_tools_export_info.txt"

var _file_count: int = 0
var _features: PackedStringArray = PackedStringArray()


func _get_name() -> String:
	# 필수 가상 메서드: 익스포터가 플러그인을 이름으로 정렬/식별한다.
	return "learning_tools"


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_file_count = 0
	_features = features
	print("[learning_tools] export begin: path=%s debug=%s flags=%d features=%s" % [path, is_debug, flags, ", ".join(features)])
	var info: String = "\n".join(PackedStringArray([
		"learning_tools export info",
		"time: " + Time.get_datetime_string_from_system(),
		"target: " + path,
		"debug: " + str(is_debug),
		"features: " + ", ".join(features),
	])) + "\n"
	# remap=false: 현재 파일을 대체하는 것이 아니라 새 파일을 추가한다.
	add_file(INFO_PATH, info.to_utf8_buffer(), false)


func _export_file(path: String, type: String, features: PackedStringArray) -> void:
	_file_count += 1
	# 파일마다 찍으면 너무 시끄러우므로 처음 몇 개만 보여준다.
	if _file_count <= 5:
		print("[learning_tools] export file #%d: %s (type=%s, features=%d)" % [_file_count, path, type, features.size()])


func _export_end() -> void:
	print("[learning_tools] export end: %d files, added %s (features=%d)" % [_file_count, INFO_PATH, _features.size()])
