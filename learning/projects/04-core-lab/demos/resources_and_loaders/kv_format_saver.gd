class_name KVFormatSaver
extends ResourceFormatSaver
## 커스텀 ".kv" 텍스트 포맷 세이버 (ResourceFormatLoader 와 대칭 구조).
## 엔진: core/io/resource_saver.cpp ResourceSaver::save() — recognize(resource) 와 recognize_path(resource, path)
##       (기본 구현은 _get_recognized_extensions 의 확장자 비교) 를 모두 통과한 세이버의 save() 가 호출된다.

const KeyValueStoreScript := preload("res://demos/resources_and_loaders/key_value_store.gd")
const EXTENSION: String = "kv"


func _recognize(resource: Resource) -> bool:
	return resource is KeyValueStoreScript


func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	if resource is KeyValueStoreScript:
		return PackedStringArray([EXTENSION])
	return PackedStringArray()


func _save(resource: Resource, path: String, _flags: int) -> Error:
	var store: KeyValueStoreScript = resource as KeyValueStoreScript
	if store == null:
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_line("# kv v1")
	for key: Variant in store.data.keys():
		# var_to_str 는 .tres 와 같은 VariantWriter 문법 (core/variant/variant_parser.cpp). 여러 줄 값은 c_escape 로 한 줄에 담는다.
		file.store_line(str(key) + "=" + var_to_str(store.data[key]).c_escape())
	# FileAccess 는 RefCounted: 함수가 끝나 참조가 사라지면 자동으로 close() 된다.
	return OK
