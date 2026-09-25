class_name KVFormatLoader
extends ResourceFormatLoader
## 커스텀 ".kv" 텍스트 포맷 로더 (GDScript 로 구현한 ResourceFormatLoader 플러그인).
## 엔진: core/io/resource_loader.cpp ResourceLoader::_load() 가 등록된 로더(최대 MAX_LOADERS=64)를 순회하며
##       처음으로 recognize_path() 가 true 인 로더에 load() 를 맡긴다. 각 가상 함수는 GDVIRTUAL_CALL 로 스크립트에 위임된다.
## 파일 형식:  # kv v1
##            key=<var_to_str 결과를 c_escape 한 한 줄>

const KeyValueStoreScript := preload("res://demos/resources_and_loaders/key_value_store.gd")
const EXTENSION: String = "kv"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray([EXTENSION])


func _handles_type(type: StringName) -> bool:
	# ResourceLoader.load(path, "Resource") 처럼 type_hint 가 오면 이 함수로 거른다.
	return type == &"Resource"


func _get_resource_type(path: String) -> String:
	# 엔진 클래스 이름을 돌려준다. 스크립트 클래스 이름은 _get_resource_script_class 가 담당.
	return "Resource" if path.get_extension().to_lower() == EXTENSION else ""


func _get_resource_script_class(path: String) -> String:
	return "KeyValueStore" if path.get_extension().to_lower() == EXTENSION else ""


func _recognize_path(path: String, _type: StringName) -> bool:
	return path.get_extension().to_lower() == EXTENSION


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	# 반환값이 int 면 Error 코드로 해석되고, Resource 면 성공이다 (resource_loader.cpp ResourceFormatLoader::load).
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var store: KeyValueStoreScript = KeyValueStoreScript.new()
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq < 0:
			return ERR_PARSE_ERROR
		var key := line.substr(0, eq)
		var value: Variant = str_to_var(line.substr(eq + 1).c_unescape())
		store.data[key] = value
	return store
