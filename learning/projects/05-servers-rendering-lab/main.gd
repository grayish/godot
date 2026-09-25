extends Control

## 데모 허브. 왼쪽: 데모 버튼 열 / 오른쪽: 데모가 인스턴스화되는 컨테이너 + 로그 패널.
## 헤드리스(--headless)에서도 _ready 가 오류 없이 끝나야 하므로 창/GPU 를 전제로 한 코드는 없다.
## 엔진: scene/main/scene_tree.cpp — 메인 씬은 root Window 아래에 add_child 되어
##       node.cpp _propagate_enter_tree() → _propagate_ready() 순서로 _ready 를 받는다 (3.3 절).

const DEMOS: Array[Dictionary] = [
	{
		"title": "1. 노드 vs MultiMesh vs RS 인스턴스",
		"scene_path": "res://demos/rs_no_nodes_3d/rs_no_nodes_3d.tscn",
		"description": "같은 박스 N개를 MeshInstance3D / MultiMeshInstance3D / RenderingServer.instance_create() 로 그려 노드 오버헤드를 비교합니다.",
	},
	{
		"title": "2. RS 캔버스 아이템 vs _draw()",
		"scene_path": "res://demos/rs_canvas_2d/rs_canvas_2d.tscn",
		"description": "RS.canvas_item_add_* 명령 리스트와 CanvasItem._draw()/queue_redraw() 가 같은 것임을 보여 줍니다.",
	},
	{
		"title": "3. PhysicsServer2D 직접 사용",
		"scene_path": "res://demos/physics_server_direct/physics_server_direct.tscn",
		"description": "body/shape RID 로 만든 물리 몸체와 RigidBody2D 노드를 나란히 굴리고 레이캐스트합니다.",
	},
	{
		"title": "4. RenderingDevice 컴퓨트",
		"scene_path": "res://demos/rendering_device_compute/rendering_device_compute.tscn",
		"description": "로컬 RD 와 메인 RD(렌더 스레드)에서 컴퓨트 셰이더로 float 배열을 2배로 만듭니다.",
	},
	{
		"title": "5. 품질 튜닝 패널",
		"scene_path": "res://demos/quality_tuning_panel/quality_tuning_panel.tscn",
		"description": "스케일링/AA/그림자/SSAO/디버그 드로우를 실시간으로 바꾸며 각 프로젝트 설정 키를 익힙니다.",
	},
	{
		"title": "6. 셰이더 파이프라인",
		"scene_path": "res://demos/shader_pipeline/shader_pipeline.tscn",
		"description": ".gdshader/#include, 일반·인스턴스·전역 유니폼, RS.get_shader_parameter_list 를 다룹니다.",
	},
	{
		"title": "7. AudioServer 버스와 제너레이터",
		"scene_path": "res://demos/audio_server/audio_server.tscn",
		"description": "버스/리버브 이펙트를 코드로 만들고 AudioStreamGenerator 로 사인파를 밀어 넣습니다.",
	},
]

const LOG_MAX_LINES: int = 300

var demo_holder: MarginContainer
var log_panel: RichTextLabel
var title_label: Label
var desc_label: Label
var current_demo: Node = null
var log_lines: int = 0


func _ready() -> void:
	_build_ui()
	Log.message.connect(_on_log_message)
	Log.section("Stage 5: 서버와 렌더링 파이프라인")
	Log.info("rendering_method=%s, driver=%s, DisplayServer=%s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(),
		DisplayServer.get_name(),
	])
	Log.info("왼쪽 버튼으로 데모를 엽니다. 이전 데모는 트리에서 떼어 낸 뒤 queue_free() 되고, _exit_tree 에서 서버 RID 를 반납합니다.")
	if DisplayServer.get_name() == "headless":
		Log.warn("헤드리스 모드: 더미 래스터라이저(servers/rendering/dummy/)가 RID 만 발급하고 아무것도 그리지 않습니다.")


func _build_ui() -> void:
	var root_box := HBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_box)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	root_box.add_child(left)
	var heading := Label.new()
	heading.text = "Stage 5: 서버 & 렌더링"
	left.add_child(heading)
	for i: int in DEMOS.size():
		var demo: Dictionary = DEMOS[i]
		var button := Button.new()
		button.text = String(demo["title"])
		button.tooltip_text = String(demo["description"])
		button.pressed.connect(_open_demo.bind(i))
		left.add_child(button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(right)
	title_label = Label.new()
	title_label.text = "데모를 선택하세요"
	right.add_child(title_label)
	desc_label = Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(desc_label)
	# 데모가 들어갈 자리. MarginContainer 라 Control 루트 데모는 자동으로 꽉 채워진다.
	demo_holder = MarginContainer.new()
	demo_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	demo_holder.clip_contents = true
	right.add_child(demo_holder)
	log_panel = RichTextLabel.new()
	log_panel.custom_minimum_size = Vector2(0, 170)
	log_panel.bbcode_enabled = true
	log_panel.scroll_following = true
	right.add_child(log_panel)


func _open_demo(index: int) -> void:
	if current_demo != null:
		# 먼저 트리에서 떼어 내면 _exit_tree 가 즉시 실행되어 RID/버스가 바로 반납된다.
		# 실제 삭제는 프레임 끝 SceneTree::_flush_delete_queue 에서 (scene/main/scene_tree.cpp).
		demo_holder.remove_child(current_demo)
		current_demo.queue_free()
		current_demo = null
	var demo: Dictionary = DEMOS[index]
	var packed: PackedScene = load(String(demo["scene_path"]))
	if packed == null:
		Log.warn("씬을 열 수 없음: " + String(demo["scene_path"]))
		return
	Log.section(String(demo["title"]))
	title_label.text = String(demo["title"])
	desc_label.text = String(demo["description"])
	current_demo = packed.instantiate()
	demo_holder.add_child(current_demo)


func _on_log_message(text: String, level: int) -> void:
	log_lines += 1
	if log_lines > LOG_MAX_LINES:
		log_panel.clear()
		log_lines = 0
	var color: String = "#d8d8d8"
	if level == Log.Level.WARN:
		color = "#ffb060"
	elif level == Log.Level.SECTION:
		color = "#80c8ff"
	# "[" 는 BBCode 태그 시작이므로 [lb] 로 이스케이프한다.
	log_panel.append_text("[color=%s]%s[/color]\n" % [color, text.replace("[", "[lb]")])
