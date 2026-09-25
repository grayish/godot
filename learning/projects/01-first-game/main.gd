extends Control
## 데모 허브. 왼쪽: 데모 버튼 목록, 오른쪽: 선택한 데모가 인스턴스화되는 자리 + 아래 로그 패널.
## UI 대부분을 코드로 만드는 이유: .tscn 을 작게 유지하고, "노드 = 코드로도 만들 수 있는 객체" 임을 보여주기 위해.
## 엔진: scene/main/node.cpp add_child() → _propagate_enter_tree() → _propagate_ready() 순서로 _ready 가 불린다.

## 데모 목록. 버튼은 이 배열에서 만들어진다.
const DEMOS: Array[Dictionary] = [
	{
		"title": "게임 실행 (Dodge)",
		"scene_path": "res://demos/game/game.tscn",
		"description": "WASD/방향키로 삼각형을 움직여 몹을 피하세요. 노드 트리·씬 인스턴스·시그널·그룹·리소스·입력 액션이 모두 들어 있습니다.",
	},
	{
		"title": "시그널 101",
		"scene_path": "res://demos/signals_101/signals_101.tscn",
		"description": "시그널을 연결하는 세 가지 방법(.tscn / connect() / bind), 일회성 연결, 인자 있는 커스텀 시그널, await.",
	},
	{
		"title": "씬 인스턴스화",
		"scene_path": "res://demos/scene_instancing/scene_instancing.tscn",
		"description": "preload 한 card.tscn 을 여러 번 instantiate. owner / get_path / get_parent, add_child 전에 @export 설정, queue_free 와 free, reparent.",
	},
	{
		"title": ".tscn 해부",
		"scene_path": "res://demos/tscn_anatomy/tscn_anatomy.tscn",
		"description": "mob.tscn 을 텍스트로 읽어 [gd_scene] [ext_resource] [sub_resource] [node] [connection] 을 설명하고 PackedScene.get_state() 와 대조합니다.",
	},
]

const COLOR_INFO := Color(0.86, 0.88, 0.92)
const COLOR_WARN := Color(1.0, 0.78, 0.35)
const COLOR_SECTION := Color(0.45, 0.85, 1.0)

## 데모가 인스턴스화되는 컨테이너. 이전 데모는 여기서 free 된다.
var host: Control
var log_panel: RichTextLabel
var description_label: Label


func _ready() -> void:
	_build_ui()
	# 오토로드 Log 의 시그널을 받아 화면 로그 패널에 옮겨 적는다.
	Log.message.connect(_on_log_message)
	Log.section("01 First Game — 데모 허브")
	Log.info("왼쪽 버튼을 눌러 데모를 여세요. 렌더러: %s / DisplayServer: %s" % [
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), DisplayServer.get_name()])
	if DisplayServer.get_name() == "headless":
		# 검증 실행(--headless)에는 창이 없다. 버튼은 만들되 아무것도 열지 않는다.
		Log.warn("헤드리스 모드: 창이 없어 버튼을 누를 수 없습니다 (verify.sh 용 실행).")


func _build_ui() -> void:
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 8)
	add_child(columns)

	# ---- 왼쪽: 데모 버튼 ----
	var left := VBoxContainer.new()
	left.name = "Left"
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)

	var title := Label.new()
	title.text = "Stage 1 · 첫 게임"
	title.add_theme_font_size_override("font_size", 24)
	left.add_child(title)

	for i: int in DEMOS.size():
		var demo: Dictionary = DEMOS[i]
		var button := Button.new()
		button.text = str(demo["title"])
		button.tooltip_text = str(demo["description"])
		# Callable.bind: 시그널 인자(없음) 뒤에 인덱스가 붙어 _open_demo(i) 로 호출된다.
		button.pressed.connect(_open_demo.bind(i))
		left.add_child(button)

	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.text = "데모를 선택하면 설명이 여기에 나타납니다."
	left.add_child(description_label)

	# ---- 오른쪽: 데모 자리 + 로그 ----
	var right := VBoxContainer.new()
	right.name = "Right"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)

	host = Control.new()
	host.name = "DemoHost"
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.clip_contents = true  # 게임의 몹이 아레나 밖에서 태어나도 로그 패널을 덮지 않게
	right.add_child(host)

	log_panel = RichTextLabel.new()
	log_panel.name = "LogPanel"
	log_panel.custom_minimum_size = Vector2(0, 170)
	log_panel.scroll_following = true
	log_panel.selection_enabled = true
	right.add_child(log_panel)


## 데모를 연다. 이전 데모는 참조가 아니라 host 의 자식 목록으로 정리한다
## (게임은 재시작 때 스스로를 새 인스턴스로 바꾸므로 저장해 둔 참조가 낡을 수 있다).
func _open_demo(index: int) -> void:
	_close_current()
	var demo: Dictionary = DEMOS[index]
	var packed: PackedScene = load(str(demo["scene_path"]))
	if packed == null:
		Log.warn("씬을 불러올 수 없음: %s" % str(demo["scene_path"]))
		return
	description_label.text = str(demo["description"])
	Log.section(str(demo["title"]))
	# 엔진: scene/resources/packed_scene.cpp SceneState::instantiate() — 노드 트리 복원 + [connection] 연결.
	var instance: Node = packed.instantiate()
	host.add_child(instance)


func _close_current() -> void:
	for child: Node in host.get_children():
		# queue_free 는 프레임 끝(SceneTree::_flush_delete_queue)에 지운다. 지금 당장 트리에서 떼어
		# 새 데모와 이름이 겹치거나 시그널이 오가지 않게 한다.
		host.remove_child(child)
		child.queue_free()


func _on_log_message(text: String, level: int) -> void:
	var color := COLOR_INFO
	match level:
		Log.Level.WARN:
			color = COLOR_WARN
		Log.Level.SECTION:
			color = COLOR_SECTION
	# bbcode 대신 push/add/pop 을 쓰면 "[node ...]" 같은 대괄호 텍스트가 태그로 오해되지 않는다.
	log_panel.push_color(color)
	log_panel.add_text(text)
	log_panel.pop()
	log_panel.newline()
