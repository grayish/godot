extends Control
## 데모 5: 리소스와 로더 — ResourceSaver/ResourceLoader, ResourceCache, 커스텀 포맷 플러그인, 스레드 로딩.
## 엔진: core/io/resource_loader.cpp (_load 루프, load_threaded_request → _run_load_task),
##       core/io/resource_saver.cpp, core/io/resource.h ResourceCache.
## 2장 2.5 "I/O와 리소스" 를 코드로 옮긴 것.

const KeyValueStoreScript := preload("res://demos/resources_and_loaders/key_value_store.gd")
const KVLoaderScript := preload("res://demos/resources_and_loaders/kv_format_loader.gd")
const KVSaverScript := preload("res://demos/resources_and_loaders/kv_format_saver.gd")

const TRES_PATH: String = "user://core_lab_store.tres"
const KV_PATH: String = "user://core_lab_store.kv"
const BUNDLED_PATH: String = "res://demos/resources_and_loaders/sample_store.tres"

var _loader: ResourceFormatLoader = null
var _saver: ResourceFormatSaver = null
var _threaded_pending: bool = false
var _progress_bar: ProgressBar
var _file_view: Label


func _ready() -> void:
	_build_ui()
	Log.section("리소스와 로더")
	Log.info("user:// 실제 위치: %s" % OS.get_user_data_dir())
	_register_kv_format()
	_demo_save_and_cache()
	_demo_kv_format()
	_demo_threaded_load()


func _exit_tree() -> void:
	if _threaded_pending:
		# 진행 중인 스레드 로드는 반드시 회수한다 — 그래야 ResourceLoader 의 작업 테이블에 남지 않는다.
		ResourceLoader.load_threaded_get(BUNDLED_PATH)
		_threaded_pending = false
	if _loader != null:
		ResourceLoader.remove_resource_format_loader(_loader)
		_loader = null
	if _saver != null:
		ResourceSaver.remove_resource_format_saver(_saver)
		_saver = null
	print("커스텀 .kv 로더/세이버 등록 해제 (데모 종료)")


func _process(_delta: float) -> void:
	if not _threaded_pending:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(BUNDLED_PATH, progress)
	if not progress.is_empty():
		_progress_bar.value = float(progress[0]) * 100.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_threaded_pending = false
			var res: KeyValueStoreScript = ResourceLoader.load_threaded_get(BUNDLED_PATH) as KeyValueStoreScript
			Log.info("스레드 로드 완료 (프레임 %d): data=%s" % [Engine.get_process_frames(), str(res.data) if res != null else "null"])
			Log.info("load_threaded_request 는 WorkerThreadPool 태스크로 _run_load_task 를 돌린다 (resource_loader.cpp)")
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_threaded_pending = false
			Log.warn("스레드 로드 실패: status=%d" % status)
		_:
			pass


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "ResourceSaver / ResourceLoader / 커스텀 .kv 포맷 / 스레드 로딩 — 결과는 로그 패널에"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_add_button(buttons, ".tres 저장/캐시 비교", _demo_save_and_cache)
	_add_button(buttons, ".kv 저장/로드", _demo_kv_format)
	_add_button(buttons, "스레드 로드", _demo_threaded_load)
	_progress_bar = ProgressBar.new()
	_progress_bar.max_value = 100.0
	box.add_child(_progress_bar)
	_file_view = Label.new()
	_file_view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_file_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_file_view)


func _add_button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _register_kv_format() -> void:
	# 로더/세이버는 Ref 로 엔진 테이블에 보관된다. 데모가 끝나면 _exit_tree 에서 반드시 뺀다.
	_loader = KVLoaderScript.new()
	_saver = KVSaverScript.new()
	ResourceLoader.add_resource_format_loader(_loader)
	ResourceSaver.add_resource_format_saver(_saver)
	Log.info("커스텀 .kv 로더/세이버 등록 → 'Resource' 인식 확장자에 kv 포함? %s" % str(
		ResourceLoader.get_recognized_extensions_for_type("Resource").has("kv")))


func _demo_save_and_cache() -> void:
	Log.section("ResourceSaver.save + ResourceCache")
	var store: KeyValueStoreScript = KeyValueStoreScript.new()
	store.data = {"hp": 10, "name": "슬라임", "spawn": Vector2(1, 2)}
	var err := ResourceSaver.save(store, TRES_PATH)
	Log.info("ResourceSaver.save(store, %s) → %s (내장 텍스트 세이버가 .tres 를 인식)" % [TRES_PATH, error_string(err)])
	if err != OK:
		return
	Log.info("ResourceLoader.exists=%s, get_resource_type=%s" % [
		str(ResourceLoader.exists(TRES_PATH)), ResourceLoader.get_resource_type(TRES_PATH)])
	Log.info("저장 직후 캐시에 있나? has_cached=%s (save 는 resource_path 를 바꾸지 않아 캐시 등록도 안 됨)" % str(ResourceLoader.has_cached(TRES_PATH)))
	var first := ResourceLoader.load(TRES_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	var second := ResourceLoader.load(TRES_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	var ignored := ResourceLoader.load(TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	Log.info("CACHE_MODE_REUSE 두 번: id %d == %d ? %s (ResourceCache::resources 경로→포인터 맵 재사용)" % [
		first.get_instance_id(), second.get_instance_id(), str(first == second)])
	Log.info("CACHE_MODE_IGNORE: id %d — 새 객체 (캐시를 읽지도 쓰지도 않음)" % ignored.get_instance_id())
	Log.info("원본 store id %d 와 로드본은 다른 객체. 로드 후 has_cached=%s" % [store.get_instance_id(), str(ResourceLoader.has_cached(TRES_PATH))])
	_file_view.text = ".tres 내용:\n" + FileAccess.get_file_as_string(TRES_PATH)


func _demo_kv_format() -> void:
	Log.section("커스텀 .kv 포맷 (ResourceFormatLoader/Saver 플러그인)")
	var store: KeyValueStoreScript = KeyValueStoreScript.new()
	store.data = {"title": "코어 실험실", "retries": 3, "tags": ["core", "io"], "offset": Vector2(8, 16)}
	var err := ResourceSaver.save(store, KV_PATH)
	Log.info("ResourceSaver.save(..., %s) → %s (KVFormatSaver._recognize + 확장자 kv 일치)" % [KV_PATH, error_string(err)])
	if err != OK:
		return
	var text := FileAccess.get_file_as_string(KV_PATH)
	_file_view.text = ".kv 내용:\n" + text
	Log.info(".kv 파일 %d바이트, exists=%s, get_resource_type=%s (KVFormatLoader._get_resource_type)" % [
		text.length(), str(ResourceLoader.exists(KV_PATH)), ResourceLoader.get_resource_type(KV_PATH)])
	var loaded: KeyValueStoreScript = ResourceLoader.load(KV_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as KeyValueStoreScript
	if loaded == null:
		Log.warn(".kv 로드 실패")
		return
	Log.info("로드된 data=%s, 원본과 값 같음? %s, 같은 객체? %s" % [
		str(loaded.data), str(loaded.data == store.data), str(loaded == store)])
	var cached := ResourceLoader.load(KV_PATH)
	Log.info("기본 캐시 모드로 다시 로드 → resource_path=%s, has_cached=%s" % [cached.resource_path, str(ResourceLoader.has_cached(KV_PATH))])


func _demo_threaded_load() -> void:
	Log.section("ResourceLoader.load_threaded_request (백그라운드 로딩)")
	if _threaded_pending:
		Log.warn("이미 스레드 로드가 진행 중")
		return
	var err := ResourceLoader.load_threaded_request(BUNDLED_PATH)
	Log.info("요청 %s → %s. _process 에서 load_threaded_get_status 로 폴링한다" % [BUNDLED_PATH, error_string(err)])
	_threaded_pending = err == OK
	_progress_bar.value = 0.0
