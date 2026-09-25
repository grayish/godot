extends SceneTree
## 헤드리스 셀프테스트 (UI 없이 코어 로직만 검사).
## 실행: godot --headless --path learning/projects/04-core-lab -s res://selftest.gd
## MainLoop 를 직접 상속한다 (core/os/main_loop.h). -s 스크립트는 오토로드보다 먼저 컴파일되므로
## 여기서는 Log 오토로드를 참조하지 않고 print() 만 쓴다 (main/main.cpp Main::start 의 순서).
## 테스트는 프레임마다 하나씩 실행한다 (_process 가 true 를 돌려주면 루프 종료).

const PROJECT_DIR: String = "04-core-lab"
# class_name 전역 클래스는 에디터가 만든 .godot/global_script_class_cache.cfg 가 있어야 풀리므로
# 헤드리스에서도 항상 동작하도록 preload 로 스크립트를 직접 잡는다.
const KeyValueStoreScript := preload("res://demos/resources_and_loaders/key_value_store.gd")
const KVLoaderScript := preload("res://demos/resources_and_loaders/kv_format_loader.gd")
const KVSaverScript := preload("res://demos/resources_and_loaders/kv_format_saver.gd")

const KV_PATH: String = "user://selftest_store.kv"
const CFG_PATH: String = "user://selftest.cfg"
const GROUP_CHUNKS: int = 8

var _tests: Array[Callable] = []
var _index: int = 0
var _failures: Array[String] = []

# WorkerThreadPool 테스트용 공유 상태 (Mutex 로 보호).
var _group_data: PackedInt32Array = PackedInt32Array()
var _group_total: int = 0
var _group_mutex: Mutex = Mutex.new()


func _initialize() -> void:
	_tests = [
		_test_objectdb_validator,
		_test_packed_cow_vs_array_sharing,
		_test_kv_format_roundtrip,
		_test_worker_pool_group_sum,
		_test_config_file_roundtrip,
		_test_var_to_bytes_roundtrip,
	]
	print("SELFTEST start: %d tests" % _tests.size())


func _process(_delta: float) -> bool:
	if _index >= _tests.size():
		if _failures.is_empty():
			print("SELFTEST PASS " + PROJECT_DIR)
			quit(0)
		else:
			print("SELFTEST FAIL %s: %s" % [PROJECT_DIR, ", ".join(_failures)])
			quit(1)
		return true
	var test: Callable = _tests[_index]
	_index += 1
	print("-- %s" % test.get_method())
	test.call()
	return false


func _check(condition: bool, what: String) -> void:
	if condition:
		print("   ok   " + what)
	else:
		print("   실패 " + what)
		_failures.append(what)


## ObjectDB: 해제된 객체의 ID 로는 null 이 돌아온다 (core/object/object.h ObjectDB::get_instance validator).
func _test_objectdb_validator() -> void:
	var obj := Object.new()
	var id: int = obj.get_instance_id()
	_check(instance_from_id(id) == obj, "instance_from_id(id) 가 살아있는 객체를 돌려준다")
	_check(is_instance_id_valid(id), "is_instance_id_valid(id) == true (해제 전)")
	obj.free()
	_check(not is_instance_valid(obj), "free() 후 is_instance_valid(obj) == false")
	_check(instance_from_id(id) == null, "free() 후 instance_from_id(id) == null")
	_check(not is_instance_id_valid(id), "free() 후 is_instance_id_valid(id) == false")


## Packed 배열: duplicate() 후의 쓰기는 원본에 닿지 않는다 (COW, core/templates/cowdata.h).
## Array: 대입은 참조 공유, duplicate() 만 독립 사본.
func _test_packed_cow_vs_array_sharing() -> void:
	var packed := PackedInt32Array([1, 2, 3])
	var packed_alias := packed
	packed_alias.append(4)
	_check(packed.size() == 4, "PackedInt32Array 대입은 참조 공유 (alias.append 가 원본에 보임)")
	var packed_copy := packed.duplicate()
	packed_copy[0] = 99
	_check(packed[0] == 1 and packed_copy[0] == 99, "PackedInt32Array.duplicate() 후 쓰기는 원본과 분리 (COW)")
	var big := PackedInt32Array()
	big.resize(1_000_000)
	var cow := big.duplicate()
	cow[10] = 5
	_check(big[10] == 0 and cow[10] == 5, "큰 Packed 배열도 첫 쓰기 시점에 복사되어 원본 보존")

	var arr: Array = [1, 2, 3]
	var arr_alias := arr
	arr_alias.append(4)
	_check(arr.size() == 4, "Array 대입은 참조 공유 (alias.append 가 원본에 보임)")
	var arr_copy := arr.duplicate()
	arr_copy[0] = 99
	_check(arr[0] == 1 and arr_copy[0] == 99, "Array.duplicate() 는 독립 사본")


## 커스텀 .kv 포맷: GDScript ResourceFormatLoader/Saver 를 등록해 user:// 로 저장/로드 왕복.
func _test_kv_format_roundtrip() -> void:
	var loader: ResourceFormatLoader = KVLoaderScript.new()
	var saver: ResourceFormatSaver = KVSaverScript.new()
	ResourceLoader.add_resource_format_loader(loader)
	ResourceSaver.add_resource_format_saver(saver)
	_check(ResourceLoader.get_recognized_extensions_for_type("Resource").has("kv"), "등록 후 'kv' 확장자가 인식된다")

	var store: KeyValueStoreScript = KeyValueStoreScript.new()
	store.data = {"hp": 7, "name": "슬라임", "pos": Vector2(1, 2), "tags": ["a", "b"]}
	var err: Error = ResourceSaver.save(store, KV_PATH)
	_check(err == OK, "ResourceSaver.save(.kv) == OK (%s)" % error_string(err))
	_check(FileAccess.file_exists(KV_PATH), ".kv 파일이 실제로 생성됨")
	_check(ResourceLoader.exists(KV_PATH), "ResourceLoader.exists(.kv)")
	_check(ResourceLoader.get_resource_type(KV_PATH) == "Resource", "get_resource_type(.kv) == 'Resource'")

	var loaded: Resource = ResourceLoader.load(KV_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(loaded != null and loaded is KeyValueStoreScript, ".kv 로드 결과가 KeyValueStore")
	if loaded is KeyValueStoreScript:
		var back: KeyValueStoreScript = loaded as KeyValueStoreScript
		_check(back.data == store.data, ".kv 왕복 후 data 가 같다: %s" % str(back.data))
		_check(back.get_instance_id() != store.get_instance_id(), "로드된 객체는 원본과 다른 인스턴스")

	ResourceLoader.remove_resource_format_loader(loader)
	ResourceSaver.remove_resource_format_saver(saver)
	_check(not ResourceLoader.get_recognized_extensions_for_type("Resource").has("kv"), "해제 후 'kv' 확장자 인식 안 됨")


## WorkerThreadPool 그룹 작업의 합 == 직렬 합 (core/object/worker_thread_pool.cpp add_group_task).
func _test_worker_pool_group_sum() -> void:
	_group_data.resize(200_000)
	for i: int in _group_data.size():
		_group_data[i] = i % 13
	var serial: int = 0
	for v: int in _group_data:
		serial += v
	_group_total = 0
	var group_id: int = WorkerThreadPool.add_group_task(_sum_chunk, GROUP_CHUNKS, -1, false, "selftest_sum")
	# 상태 조회는 wait 전에만 유효하다: wait_for_group_task_completion 이 그룹을 테이블에서 지운다.
	var processed_before_wait: int = WorkerThreadPool.get_group_processed_element_count(group_id)
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	_check(processed_before_wait >= 0 and processed_before_wait <= GROUP_CHUNKS, "wait 전 처리 요소 수 %d (0..%d)" % [processed_before_wait, GROUP_CHUNKS])
	_check(_group_total == serial, "그룹 합 %d == 직렬 합 %d" % [_group_total, serial])


func _sum_chunk(index: int) -> void:
	var chunk: int = ceili(float(_group_data.size()) / GROUP_CHUNKS)
	var begin: int = index * chunk
	var end: int = mini(begin + chunk, _group_data.size())
	var partial: int = 0
	for i: int in range(begin, end):
		partial += _group_data[i]
	_group_mutex.lock()
	_group_total += partial
	_group_mutex.unlock()


## ConfigFile 왕복 (core/io/config_file.cpp — VariantWriter/VariantParser 기반 INI).
func _test_config_file_roundtrip() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", false)
	cfg.set_value("video", "scale", 1.5)
	cfg.set_value("player", "spawn", Vector2(3, 4))
	cfg.set_value("player", "name", "용사")
	_check(cfg.save(CFG_PATH) == OK, "ConfigFile.save == OK")
	var cfg2 := ConfigFile.new()
	_check(cfg2.load(CFG_PATH) == OK, "ConfigFile.load == OK")
	_check(cfg2.get_sections() == PackedStringArray(["video", "player"]), "섹션 순서 유지: %s" % str(cfg2.get_sections()))
	_check(cfg2.get_value("video", "fullscreen") == false, "bool 값 왕복")
	_check(cfg2.get_value("video", "scale") == 1.5, "float 값 왕복")
	_check(cfg2.get_value("player", "spawn") == Vector2(3, 4), "Vector2 값 왕복 (타입 유지)")
	_check(cfg2.get_value("player", "name") == "용사", "String(UTF-8) 값 왕복")
	_check(cfg2.get_value("player", "missing", 42) == 42, "없는 키는 default")


## var_to_bytes / bytes_to_var 왕복 (core/io/marshalls.cpp encode_variant/decode_variant).
func _test_var_to_bytes_roundtrip() -> void:
	var payload: Dictionary = {
		"name": "슬라임",
		"hp": 12,
		"ratio": 0.25,
		"pos": Vector2(3, 4),
		"color": Color(1, 0.5, 0),
		"tags": PackedStringArray(["a", "b"]),
		"nested": {"ok": true, "list": [1, 2, 3]},
	}
	var bytes: PackedByteArray = var_to_bytes(payload)
	_check(bytes.size() > 0, "var_to_bytes 크기 %d 바이트" % bytes.size())
	var back: Variant = bytes_to_var(bytes)
	_check(typeof(back) == TYPE_DICTIONARY, "bytes_to_var 타입이 Dictionary")
	_check(back == payload, "bytes 왕복 후 값이 같다 (Dictionary == 는 재귀 값 비교)")
	var text: String = var_to_str(payload)
	_check(str_to_var(text) == payload, "var_to_str/str_to_var 왕복도 같다")
	# Object 는 내용이 아니라 ObjectID 만 실린다 (HEADER_DATA_FLAG_OBJECT_AS_ID → EncodedObjectAsID 대리 객체).
	var obj := Object.new()
	var obj_bytes: PackedByteArray = var_to_bytes({"o": obj})
	var obj_back: Variant = bytes_to_var(obj_bytes)
	var stand_in: Variant = obj_back["o"] if typeof(obj_back) == TYPE_DICTIONARY else null
	_check(stand_in is EncodedObjectAsID, "Object 는 EncodedObjectAsID 로만 복원된다 (내용 직렬화 안 됨)")
	if stand_in is EncodedObjectAsID:
		_check((stand_in as EncodedObjectAsID).object_id == obj.get_instance_id(), "EncodedObjectAsID.object_id == 원본 instance id")
	obj.free()
