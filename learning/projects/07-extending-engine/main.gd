extends Control

## 데모 허브. 왼쪽: 데모 버튼, 오른쪽: 선택한 데모 씬, 아래: Log autoload 를 비추는 로그 패널.
## UI 는 전부 코드로 만든다 (.tscn 을 작게 유지하고, 헤드리스에서도 같은 코드가 돈다).
## 엔진: scene/main/node.cpp _propagate_ready() — add_child 직후 자식들의 _ready 가 먼저 불린다.
##       scene/gui/box_container.cpp — VBox/HBox 의 크기 배분 (size_flags).

const DEMOS: Array[Dictionary] = [
	{
		"title": "1. 확장 클래스 확인 (ClassDB)",
		"scene_path": "res://demos/extension_check/extension_check.tscn",
		"description": "커스텀 C++ 모듈(Summator) / GDExtension(SummatorExt) 이 ClassDB 에 등록되었는지 확인하고, 있으면 인스턴스화해 호출한다. 없으면 빌드 명령을 보여준다.",
	},
	{
		"title": "2. @tool 스크립트와 에디터",
		"scene_path": "res://demos/tool_scripts/tool_scripts.tscn",
		"description": "에디터 자체가 Godot 앱이라는 점, Engine.is_editor_hint() 분기, _get_configuration_warnings(), @export_tool_button 을 보여준다.",
	},
	{
		"title": "3. 기여 워크플로우 체크리스트",
		"scene_path": "res://demos/contributing_guide/contributing_guide.tscn",
		"description": "CONTRIBUTING.md 요약: 이슈 → 제안 → 브랜치 → clang-format/pre-commit → doc XML → 테스트 → PR. 버튼으로 관련 문서를 연다.",
	},
]

var _demo_container: PanelContainer
var _description_label: Label
var _log_panel: RichTextLabel
var _current_demo: Node = null


func _ready() -> void:
	_build_ui()
	# Log autoload 의 시그널을 받아 하단 패널에 비춘다 (stdout 출력은 log.gd 가 이미 했다).
	Log.message.connect(_on_log_message)
	Log.section("07 엔진 확장과 기여 — 데모 허브")
	Log.info("왼쪽 버튼으로 데모를 고르세요. 데모 씬은 오른쪽 패널에 인스턴스화됩니다.")
	if not DEMOS.is_empty():
		_open_demo(0)


func _build_ui() -> void:
	var root_box := VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_box)

	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(top)

	# 왼쪽 열: DEMOS 배열에서 버튼 생성.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	top.add_child(left)
	var header := Label.new()
	header.text = "데모 목록"
	left.add_child(header)
	for i: int in DEMOS.size():
		var button := Button.new()
		button.text = String(DEMOS[i]["title"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# bind() 로 인덱스를 묶는다: Callable 은 core/variant/callable.cpp, 바인딩은 CallableCustomBind.
		button.pressed.connect(_open_demo.bind(i))
		left.add_child(button)

	# 오른쪽: 설명 + 데모 컨테이너.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	_description_label = Label.new()
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.text = "데모를 선택하세요."
	right.add_child(_description_label)
	_demo_container = PanelContainer.new()
	_demo_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_demo_container)

	# 하단: 로그 패널.
	_log_panel = RichTextLabel.new()
	_log_panel.custom_minimum_size = Vector2(0, 180)
	_log_panel.scroll_following = true
	_log_panel.selection_enabled = true
	root_box.add_child(_log_panel)


func _open_demo(index: int) -> void:
	if index < 0 or index >= DEMOS.size():
		return
	var demo: Dictionary = DEMOS[index]
	if _current_demo != null:
		# 이전 데모는 queue_free: 이번 프레임의 시그널 처리 중 free 하면 위험하다.
		# 엔진: scene/main/scene_tree.cpp SceneTree::_flush_delete_queue()
		_current_demo.queue_free()
		_current_demo = null
	_description_label.text = String(demo["description"])
	var packed: PackedScene = load(String(demo["scene_path"]))
	if packed == null:
		Log.warn("씬을 불러오지 못했습니다: " + String(demo["scene_path"]))
		return
	Log.section(String(demo["title"]))
	_current_demo = packed.instantiate()
	_demo_container.add_child(_current_demo)


func _on_log_message(text: String, level: int) -> void:
	if _log_panel == null:
		return
	match level:
		Log.Level.SECTION:
			_log_panel.append_text("\n" + text + "\n")
		Log.Level.WARN:
			_log_panel.append_text("! " + text + "\n")
		_:
			_log_panel.append_text(text + "\n")
