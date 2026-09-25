extends Control
## 데모 허브. 왼쪽 열: DEMOS 배열에서 코드로 만든 데모 버튼. 오른쪽: 선택한 데모가 인스턴스되는 자리(DemoHost)와
## Log 오토로드의 message 시그널을 그대로 비추는 로그 패널(LogView).
## 헤드리스(--headless --quit-after 5)에서도 _ready 가 오류 없이 끝나야 하므로 DisplayServer 기능을 전혀 가정하지 않는다.

## 데모 목록. 버튼은 이 배열에서 만든다. 각 데모는 res://demos/<이름>/<이름>.tscn + .gd 한 쌍으로 서로 독립이다.
const DEMOS: Array[Dictionary] = [
	{
		"title": "1. 생명주기 순서 (lifecycle_order)",
		"scene_path": "res://demos/lifecycle_order/lifecycle_order.tscn",
		"description": "_init → PARENTED → _enter_tree(부모→자식) → POST_ENTER_TREE/_ready(자식→부모) → _exit_tree → UNPARENTED → PREDELETE. reparent / request_ready 실험. 엔진: scene/main/node.cpp",
	},
	{
		"title": "2. process vs physics (process_vs_physics)",
		"scene_path": "res://demos/process_vs_physics/process_vs_physics.tscn",
		"description": "초당 _process/_physics_process 횟수, Engine.physics_ticks_per_second / max_fps / time_scale, 물리 보간, process_priority, process_mode 와 pause. 엔진: main/main.cpp Main::iteration()",
	},
	{
		"title": "3. 지연 실행 큐 (deferred_queue)",
		"scene_path": "res://demos/deferred_queue/deferred_queue.tscn",
		"description": "call_deferred / set_deferred / CONNECT_DEFERRED / await process_frame / await physics_frame / create_timer(0) 이 각각 언제 실행되는지. 엔진: core/object/message_queue.h, Main::iteration() 의 flush 지점",
	},
	{
		"title": "4. 그룹과 알림 전파 (groups_and_notifications)",
		"scene_path": "res://demos/groups_and_notifications/groups_and_notifications.tscn",
		"description": "add_to_group / get_nodes_in_group / call_group(_flags) / propagate_call / propagate_notification(사용자 알림) / SceneTree.node_added·node_removed. 엔진: scene/main/scene_tree.cpp group_map",
	},
	{
		"title": "5. 입력 전파 (input_propagation)",
		"scene_path": "res://demos/input_propagation/input_propagation.tscn",
		"description": "_input → _gui_input → _shortcut_input → _unhandled_key_input → _unhandled_input 순서와 set_input_as_handled(), mouse_filter STOP/PASS/IGNORE. 엔진: scene/main/viewport.cpp push_input()",
	},
	{
		"title": "6. PackedScene 들여다보기 (packed_scene_inspect)",
		"scene_path": "res://demos/packed_scene_inspect/packed_scene_inspect.tscn",
		"description": "PackedScene.get_state() 로 노드/속성/연결 표를 읽고, instantiate 후 owner 와 get_tree_string_pretty() 를 본다. 엔진: scene/resources/packed_scene.cpp",
	},
]

## Log.Level 순서(INFO, WARN, SECTION)에 대응하는 로그 색.
const LOG_COLORS: Array[Color] = [Color(0.86, 0.86, 0.86), Color(1.0, 0.72, 0.3), Color(0.55, 0.85, 1.0)]

var _host: PanelContainer
var _log_view: RichTextLabel
var _desc_label: Label
var _current_demo: Node = null


func _ready() -> void:
	# 데모 2 가 get_tree().paused 를 켜도 허브의 버튼과 로그는 계속 동작해야 한다.
	# 엔진: scene/main/node.cpp Node::can_process() — PROCESS_MODE_ALWAYS 는 SceneTree.paused 를 무시한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 레이아웃 전용 컨테이너들은 마우스를 무시한다(IGNORE). 기본값이 STOP 인 PanelContainer 나 이 루트가 STOP 이면
	# 데모 5 의 PASS 체인이 허브에서 끊겨 클릭이 _unhandled_input 까지 가는 것을 볼 수 없다 (viewport.cpp _gui_call_input).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	Log.message.connect(_on_log_message)
	Log.section("02 씬 트리 실험실")
	Log.info("왼쪽 버튼으로 데모를 고르세요. 이 패널은 Log 오토로드(res://log.gd)의 message 시그널을 그대로 비춥니다.")
	Log.info("헤드리스 셀프테스트: godot --headless --path <프로젝트> -s res://selftest.gd")


func _exit_tree() -> void:
	# 종료 중에는 자식(로그 패널)이 먼저 해제될 수 있다. 다른 노드의 PREDELETE 로그가 해제된 패널을 건드리지 않게 끊는다.
	if Log.message.is_connected(_on_log_message):
		Log.message.disconnect(_on_log_message)


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var left := VBoxContainer.new()
	left.name = "DemoList"
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 6)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)

	var title := Label.new()
	title.text = "씬 트리 실험실 (Stage 2)"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)

	for i: int in range(DEMOS.size()):
		var button := Button.new()
		button.text = str(DEMOS[i]["title"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_open_demo.bind(i))
		left.add_child(button)

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_label.text = "데모를 고르면 설명이 여기에 표시됩니다."
	left.add_child(_desc_label)

	var clear_button := Button.new()
	clear_button.text = "로그 지우기"
	clear_button.pressed.connect(func() -> void: _log_view.clear())
	left.add_child(clear_button)

	var right := VBoxContainer.new()
	right.name = "Right"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)

	_host = PanelContainer.new()
	_host.name = "DemoHost"
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.size_flags_stretch_ratio = 2.0
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_host)

	_log_view = RichTextLabel.new()
	_log_view.name = "LogView"
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.size_flags_stretch_ratio = 1.0
	_log_view.custom_minimum_size = Vector2(0, 200)
	_log_view.scroll_following = true
	_log_view.selection_enabled = true
	right.add_child(_log_view)


func _open_demo(index: int) -> void:
	var demo: Dictionary = DEMOS[index]
	if _current_demo != null:
		# 먼저 떼어내 이름 충돌을 피하고, 실제 삭제는 프레임 끝 SceneTree::_flush_delete_queue() 에 맡긴다.
		_host.remove_child(_current_demo)
		_current_demo.queue_free()
		_current_demo = null
	_desc_label.text = str(demo["description"])
	Log.section("데모 열기: " + str(demo["title"]))
	var packed: PackedScene = load(str(demo["scene_path"]))
	if packed == null:
		Log.warn("씬을 불러올 수 없습니다: " + str(demo["scene_path"]))
		return
	_current_demo = packed.instantiate()
	_host.add_child(_current_demo)


func _on_log_message(text: String, level: int) -> void:
	if not is_instance_valid(_log_view):
		return
	# BBCode 대신 push_color/add_text 를 써서 로그 본문의 "[" 가 태그로 해석되지 않게 한다.
	_log_view.push_color(LOG_COLORS[clampi(level, 0, LOG_COLORS.size() - 1)])
	_log_view.add_text(text)
	_log_view.pop()
	_log_view.newline()
