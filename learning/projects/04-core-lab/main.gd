extends Control
## 데모 허브. 왼쪽: 데모 버튼 목록 / 오른쪽 위: 선택한 데모가 인스턴스화되는 자리 / 오른쪽 아래: Log 패널.
## 엔진: scene/main/node.cpp add_child()/remove_child(), scene/main/scene_tree.cpp queue_delete() → _flush_delete_queue()
## 헤드리스(--headless)에서도 _ready 가 오류 없이 끝나야 하므로 DisplayServer 기능을 전제하지 않는다.

const DEMOS: Array[Dictionary] = [
	{
		"title": "1. ClassDB 브라우저",
		"scene_path": "res://demos/classdb_browser/classdb_browser.tscn",
		"description": "ClassDB 리플렉션: 상속 사슬, 메서드/프로퍼티/시그널/상수 목록, ClassDB.instantiate",
	},
	{
		"title": "2. Object 모델",
		"scene_path": "res://demos/object_model/object_model.tscn",
		"description": "set/get/call, notification, 시그널 연결 플래그, ObjectDB 검증, WeakRef, free vs queue_free",
	},
	{
		"title": "3. 참조 카운트와 소유권",
		"scene_path": "res://demos/refcount_and_ownership/refcount_and_ownership.tscn",
		"description": "RefCounted 카운트, 순환 참조 누수, Node 소유권 트리, Resource duplicate / local_to_scene",
	},
	{
		"title": "4. Variant 내부",
		"scene_path": "res://demos/variant_internals/variant_internals.tscn",
		"description": "Packed 배열 COW vs Array 공유, String/StringName 비교, NodePath, RID, 직렬화 왕복",
	},
	{
		"title": "5. 리소스와 로더",
		"scene_path": "res://demos/resources_and_loaders/resources_and_loaders.tscn",
		"description": "ResourceSaver/Loader, 캐시 모드, 커스텀 .kv 포맷 로더/세이버, 스레드 로딩",
	},
	{
		"title": "6. 파일과 OS",
		"scene_path": "res://demos/file_and_os/file_and_os.tscn",
		"description": "FileAccess/DirAccess, 경로 변환, ConfigFile, JSON, StreamPeerBuffer, MD5",
	},
	{
		"title": "7. 스레드와 워커",
		"scene_path": "res://demos/threads_and_workers/threads_and_workers.tscn",
		"description": "Thread/Mutex/Semaphore, WorkerThreadPool 그룹 작업, 스레드에서 call_deferred",
	},
]

const LOG_COLORS: Array[Color] = [Color(0.85, 0.85, 0.85), Color(1.0, 0.75, 0.3), Color(0.5, 0.85, 1.0)]

var _demo_host: PanelContainer
var _log_panel: RichTextLabel
var _description: Label
var _current_demo: Node = null


func _ready() -> void:
	_build_ui()
	# Log 오토로드의 시그널을 받아 패널에 비춘다 (Object::connect → Callable 슬롯).
	Log.message.connect(_on_log_message)
	Log.section("04 코어 계층 실험실 허브")
	Log.info("왼쪽 버튼으로 데모를 고르세요. 로그는 stdout 과 이 패널에 동시에 찍힙니다.")
	Log.info("DisplayServer=%s (headless 이면 창 없이 실행 중), 렌더링 메서드=%s" % [
		DisplayServer.get_name(),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
	])


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	columns.add_child(left)
	var title := Label.new()
	title.text = "코어 계층 실험실 (core/)"
	left.add_child(title)
	for demo: Dictionary in DEMOS:
		var button := Button.new()
		button.text = String(demo["title"])
		# 버튼마다 Dictionary 를 bind → Callable 에 인자를 미리 묶는다 (core/variant/callable.h CallableCustomBind).
		button.pressed.connect(_open_demo.bind(demo))
		left.add_child(button)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.text = "데모를 선택하면 설명이 여기에 나옵니다."
	left.add_child(_description)
	var clear_button := Button.new()
	clear_button.text = "로그 지우기"
	clear_button.pressed.connect(func() -> void: _log_panel.clear())
	left.add_child(clear_button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_demo_host = PanelContainer.new()
	_demo_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_demo_host)
	_log_panel = RichTextLabel.new()
	_log_panel.custom_minimum_size = Vector2(0, 220)
	_log_panel.scroll_following = true
	_log_panel.selection_enabled = true
	right.add_child(_log_panel)


func _open_demo(demo: Dictionary) -> void:
	if _current_demo != null:
		# queue_free: 이번 프레임 끝(SceneTree::_flush_delete_queue)에 해제된다. 시그널 콜백 도중에도 안전.
		_current_demo.queue_free()
		_current_demo = null
	_description.text = String(demo["description"])
	var packed := load(String(demo["scene_path"])) as PackedScene
	if packed == null:
		Log.warn("씬을 찾지 못했습니다: %s" % String(demo["scene_path"]))
		return
	Log.section(String(demo["title"]))
	_current_demo = packed.instantiate()
	_demo_host.add_child(_current_demo)


func _on_log_message(text: String, level: int) -> void:
	# bbcode 파서를 거치지 않도록 add_text 를 쓴다 (로그에 [1, 2, 3] 같은 대괄호가 흔하다).
	_log_panel.push_color(LOG_COLORS[clampi(level, 0, LOG_COLORS.size() - 1)])
	_log_panel.add_text(text)
	_log_panel.pop()
	_log_panel.newline()
