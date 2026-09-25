extends Control
## 데모 허브. 왼쪽: 데모 버튼 목록, 오른쪽: 선택한 데모가 인스턴스되는 자리 + Log 미러 패널.
## --headless 에서도 _ready 가 오류 없이 끝나야 하므로 창/렌더링 기능을 전혀 가정하지 않는다.
## 엔진: main/main.cpp Main::start() (autoload → 메인 씬 순서), scene/main/scene_tree.cpp (씬 트리).

const DEMOS: Array[Dictionary] = [
	{
		"title": "1. 플랫폼 정보",
		"scene_path": "res://demos/platform_info/platform_info.tscn",
		"description": "OS / Engine / RenderingServer / DisplayServer 싱글턴이 지금 이 기기·이 바이너리에 대해 무엇을 답하는지, 기능 태그 표.",
	},
	{
		"title": "2. 기능 태그 오버라이드",
		"scene_path": "res://demos/feature_overrides/feature_overrides.tscn",
		"description": "project.godot 의 키.태그 오버라이드, get_setting vs get_setting_with_override, override.cfg, 익스포트 프리셋 custom features.",
	},
	{
		"title": "3. 입력 장치",
		"scene_path": "res://demos/input_devices/input_devices.tscn",
		"description": "조이패드 정보/실시간 축·버튼/진동, InputMap 액션 목록과 런타임 재매핑, 마우스 모드, 터치 에뮬레이션.",
	},
	{
		"title": "4. PCK 와 리소스",
		"scene_path": "res://demos/pck_and_resources/pck_and_resources.tscn",
		"description": "PCKPacker 로 DLC 팩 만들기, GDPC 헤더 읽기, load_resource_pack 전후 비교, 팩 안의 txt/tres 읽기.",
	},
	{
		"title": "5. 창과 디스플레이",
		"scene_path": "res://demos/window_and_display/window_and_display.tscn",
		"description": "DisplayServer.window_set_mode / vsync / 플래그, 콘텐츠 스케일, 임베디드 vs 네이티브 서브윈도우, 화면 정보.",
	},
	{
		"title": "6. 익스포트 프리셋 읽기",
		"scene_path": "res://demos/export_presets_reader/export_presets_reader.tscn",
		"description": "export_presets.cfg 를 ConfigFile 로 파싱해 6개 프리셋과 옵션 키를 표로. 익스포트 CLI 와 템플릿 위치.",
	},
]

var _host: MarginContainer
var _log_view: RichTextLabel
var _desc: Label
var _current: Node = null


func _ready() -> void:
	_build_ui()
	# 엔진: core/object/object.cpp emit_signalp() 가 연결된 Callable 을 순서대로 호출한다.
	Log.message.connect(_on_log_message)
	Log.section("06 Platform Lab 허브")
	Log.info("DisplayServer=%s, 렌더링 방식=%s, 드라이버=%s" % [
		DisplayServer.get_name(),
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(),
	])
	Log.info("왼쪽 버튼으로 데모를 고르세요. 아래 패널은 Log autoload 가 받은 메시지를 그대로 비춥니다.")
	_open_demo(0)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	split.add_child(left)
	var title := Label.new()
	title.text = "06 플랫폼 실험실"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)
	for i: int in DEMOS.size():
		var demo: Dictionary = DEMOS[i]
		var btn := Button.new()
		btn.text = String(demo["title"])
		btn.tooltip_text = String(demo["description"])
		btn.pressed.connect(_open_demo.bind(i))
		left.add_child(btn)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_desc)

	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_host = MarginContainer.new()
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.custom_minimum_size = Vector2(0, 400)
	right.add_child(_host)
	_log_view = RichTextLabel.new()
	_log_view.scroll_following = true
	_log_view.selection_enabled = true
	_log_view.custom_minimum_size = Vector2(0, 180)
	right.add_child(_log_view)


func _open_demo(index: int) -> void:
	if _current != null:
		# 엔진: scene/main/node.cpp queue_free() → SceneTree::queue_delete, 프레임 끝에 실제 해제.
		_host.remove_child(_current)
		_current.queue_free()
		_current = null
	var demo: Dictionary = DEMOS[index]
	var path: String = String(demo["scene_path"])
	Log.section(String(demo["title"]))
	var packed: PackedScene = load(path)
	if packed == null:
		Log.warn("씬을 불러올 수 없음: " + path)
		return
	_current = packed.instantiate()
	_host.add_child(_current)
	_desc.text = String(demo["description"])


func _on_log_message(text: String, level: int) -> void:
	if level == Log.Level.SECTION:
		_log_view.push_color(Color.SKY_BLUE)
		_log_view.add_text("== " + text)
		_log_view.pop()
	elif level == Log.Level.WARN:
		_log_view.push_color(Color.ORANGE)
		_log_view.add_text(text)
		_log_view.pop()
	else:
		_log_view.add_text(text)
	_log_view.newline()
