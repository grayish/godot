extends Control
## 데모 2: _process vs _physics_process.
## 엔진: main/main.cpp Main::iteration() — 한 프레임 = (0..N)번의 물리 틱(고정 스텝) + 정확히 1번의 process + 1번의 draw.
##   physics_steps 는 main/main_timer_sync.cpp advance_core() 가 time_accum 으로 계산한다 (최대 max_physics_steps_per_frame).
##   physics_ticks_per_second = 물리 틱 간격(시뮬레이션 해상도), max_fps = 프레임 끝 OS::add_frame_delay() 의 잠자기,
##   time_scale = 두 delta 모두에 곱해짐 (core/config/engine.cpp Engine::get_effective_time_scale).
## 노드 호출 순서: scene/main/scene_tree.cpp SceneTree::_process_group() 이 process_priority(낮은 값 먼저)로 정렬한다.
## pause: scene/main/node.cpp Node::can_process() 가 process_mode 와 SceneTree.paused 를 조합한다.

const TickProbeScript: GDScript = preload("res://demos/process_vs_physics/tick_probe.gd")

const TPS_OPTIONS: Array[int] = [30, 60, 120]
const FPS_OPTIONS: Array[int] = [0, 30, 60]
const SCALE_OPTIONS: Array[float] = [0.5, 1.0, 2.0]


## 물리 틱마다 움직이는 네모. 물리 보간이 꺼져 있으면 tps=30 에서 계단처럼, 켜면 부드럽게 보인다.
## 엔진: scene/main/canvas_item.cpp _physics_interpolated_changed() → RS::canvas_item_set_interpolated(),
##       main.cpp Main::iteration() 의 iteration_prepare()/iteration_end() 가 이전 트랜스폼을 저장한다.
class Mover extends Node2D:
	const LANE_WIDTH: float = 600.0
	var speed: float = 240.0
	var direction: float = 1.0

	func _physics_process(delta: float) -> void:
		position.x += speed * direction * delta
		if position.x > LANE_WIDTH - 20.0:
			position.x = LANE_WIDTH - 20.0
			direction = -1.0
		elif position.x < 20.0:
			position.x = 20.0
			direction = 1.0

	func _draw() -> void:
		# draw_* 는 RS::canvas_item_add_* 명령을 서버에 쌓아 둔다. 모양이 안 변하므로 다시 그릴 필요가 없다.
		draw_rect(Rect2(-16.0, -16.0, 32.0, 32.0), Color(0.95, 0.6, 0.2))


var _saved_tps: int = 60
var _saved_max_fps: int = 0
var _saved_time_scale: float = 1.0
var _saved_interpolation: bool = false

var _process_count: int = 0
var _physics_count: int = 0
var _last_second_ms: int = 0

var _stats_label: Label
var _counter_label: Label
var _mode_label: Label
var _mover: Mover
var _mode_probes: Array[Node] = []
var _order_process: Array[String] = []
var _order_physics: Array[String] = []
var _pending_process_order: bool = false
var _pending_physics_order: bool = false


func _ready() -> void:
	_saved_tps = Engine.physics_ticks_per_second
	_saved_max_fps = Engine.max_fps
	_saved_time_scale = Engine.time_scale
	_saved_interpolation = get_tree().physics_interpolation
	# 이 데모의 라벨은 paused 중에도 갱신되어야 하므로 ALWAYS. 자식은 INHERIT 면 이를 물려받으니 필요한 곳엔 명시한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 우선순위 탐침들보다 나중에 불리도록 큰 값 → 탐침이 남긴 순서를 같은 프레임 안에서 읽을 수 있다.
	process_priority = 1000
	process_physics_priority = 1000
	_last_second_ms = Time.get_ticks_msec()
	_build_ui()
	_build_probes()
	Log.section("데모 2: _process vs _physics_process")
	Log.info("프로젝트 설정 physics/common/physics_interpolation = %s → get_tree().physics_interpolation 으로 런타임에도 바꿀 수 있습니다." % str(ProjectSettings.get_setting("physics/common/physics_interpolation", false)))
	Log.info("1초마다 호출 횟수를 기록합니다. tps / max_fps / time_scale 을 바꾸고 숫자가 어떻게 달라지는지 보세요.")
	Log.info("max_fps 는 물리 틱 수를 바꾸지 않습니다 (프레임 끝에서 잠들 뿐). tps 는 시뮬레이션 자체의 시간 해상도입니다.")


func _exit_tree() -> void:
	# Engine 설정과 pause 는 씬이 아니라 프로세스 전체의 상태다. 데모를 떠날 때 반드시 되돌린다.
	Engine.physics_ticks_per_second = _saved_tps
	Engine.max_fps = _saved_max_fps
	Engine.time_scale = _saved_time_scale
	get_tree().physics_interpolation = _saved_interpolation
	get_tree().paused = false


func _process(_delta: float) -> void:
	_process_count += 1
	_update_labels()
	if _pending_process_order and _order_process.size() >= 3:
		Log.info("_process 호출 순서: %s  (트리에는 +10, +0, -10 순으로 넣었지만 process_priority 낮은 값이 먼저)" % ", ".join(_order_process))
		_order_process.clear()
		_pending_process_order = false
	var now: int = Time.get_ticks_msec()
	if now - _last_second_ms >= 1000:
		_last_second_ms = now
		_counter_label.text = "지난 1초: _process %d회 / _physics_process %d회" % [_process_count, _physics_count]
		Log.info("지난 1초: _process %d회, _physics_process %d회  (tps=%d, max_fps=%d, time_scale=%.2f, paused=%s)" % [_process_count, _physics_count, Engine.physics_ticks_per_second, Engine.max_fps, Engine.time_scale, get_tree().paused])
		_process_count = 0
		_physics_count = 0


func _physics_process(_delta: float) -> void:
	_physics_count += 1
	if _pending_physics_order and _order_physics.size() >= 3:
		Log.info("_physics_process 호출 순서: %s  (process_physics_priority 는 부호를 뒤집었으므로 순서도 반대)" % ", ".join(_order_physics))
		_order_physics.clear()
		_pending_physics_order = false


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	vbox.add_child(row1)
	_add_option(row1, "physics_ticks_per_second", ["30", "60", "120"], maxi(TPS_OPTIONS.find(Engine.physics_ticks_per_second), 0), _on_tps_selected)
	_add_option(row1, "max_fps", ["0 (무제한)", "30", "60"], maxi(FPS_OPTIONS.find(Engine.max_fps), 0), _on_fps_selected)
	_add_option(row1, "time_scale", ["0.5", "1.0", "2.0"], 1, _on_scale_selected)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	vbox.add_child(row2)
	var interp := CheckBox.new()
	interp.text = "물리 보간 (SceneTree.physics_interpolation + Mover.physics_interpolation_mode)"
	interp.button_pressed = get_tree().physics_interpolation
	interp.toggled.connect(_on_interpolation_toggled)
	row2.add_child(interp)
	var pause_button := Button.new()
	pause_button.text = "get_tree().paused 토글"
	pause_button.pressed.connect(_on_pause_pressed)
	row2.add_child(pause_button)
	var order_button := Button.new()
	order_button.text = "우선순위 호출 순서 기록"
	order_button.pressed.connect(_on_record_order_pressed)
	row2.add_child(order_button)

	_stats_label = Label.new()
	vbox.add_child(_stats_label)
	_counter_label = Label.new()
	_counter_label.text = "지난 1초: (측정 중)"
	vbox.add_child(_counter_label)
	_mode_label = Label.new()
	vbox.add_child(_mode_label)

	# 이동 레인: Node2D 는 Control 레이아웃에 참여하지 않으므로 고정 크기의 Control 위에 올린다.
	var lane := Control.new()
	lane.custom_minimum_size = Vector2(Mover.LANE_WIDTH, 48)
	lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lane)
	var lane_bg := ColorRect.new()
	lane_bg.color = Color(0.12, 0.12, 0.16)
	lane_bg.size = Vector2(Mover.LANE_WIDTH, 48)
	lane_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane.add_child(lane_bg)
	_mover = Mover.new()
	_mover.name = "Mover"
	_mover.position = Vector2(20, 24)
	# pause 하면 멈추는 것을 보이기 위해 PAUSABLE 을 명시 (부모가 ALWAYS 라 INHERIT 면 멈추지 않는다).
	_mover.process_mode = Node.PROCESS_MODE_PAUSABLE
	lane.add_child(_mover)


func _add_option(parent: Node, label_text: String, items: Array[String], selected: int, callback: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	for item: String in items:
		option.add_item(item)
	option.select(selected)
	option.item_selected.connect(callback)
	parent.add_child(option)


func _build_probes() -> void:
	# (a) 우선순위 탐침: 트리 순서는 +10, +0, -10 이지만 호출 순서는 -10 → +0 → +10 (낮은 값 먼저).
	#     process_physics_priority 는 부호를 뒤집어 두 우선순위가 서로 독립임을 보인다.
	var prio_holder := Node.new()
	prio_holder.name = "PriorityProbes"
	add_child(prio_holder)
	for prio: int in [10, 0, -10]:
		var probe: TickProbeScript = TickProbeScript.new("prio%+d" % prio)
		probe.process_priority = prio
		probe.process_physics_priority = -prio
		probe.sink = _on_probe_tick
		prio_holder.add_child(probe)

	# (b) process_mode 탐침: 같은 부모 아래 세 가지 모드. pause 토글 뒤 호출 수를 비교한다.
	var mode_holder := Node.new()
	mode_holder.name = "ModeProbes"
	add_child(mode_holder)
	var modes: Dictionary = {
		"ALWAYS": Node.PROCESS_MODE_ALWAYS,
		"PAUSABLE": Node.PROCESS_MODE_PAUSABLE,
		"WHEN_PAUSED": Node.PROCESS_MODE_WHEN_PAUSED,
	}
	for mode_name: String in modes:
		var probe: TickProbeScript = TickProbeScript.new(mode_name)
		probe.process_mode = modes[mode_name]
		mode_holder.add_child(probe)
		_mode_probes.append(probe)


func _on_probe_tick(label: String, phase: String) -> void:
	if phase == "process" and _pending_process_order:
		_order_process.append(label)
	elif phase == "physics" and _pending_physics_order:
		_order_physics.append(label)


func _update_labels() -> void:
	_stats_label.text = "Engine.get_physics_frames() = %d    get_process_frames() = %d    get_frames_drawn() = %d\nget_physics_interpolation_fraction() = %.3f    get_frames_per_second() = %.0f    is_in_physics_frame() = %s\ntps = %d    max_fps = %d    time_scale = %.2f    paused = %s    physics_interpolation = %s" % [
		Engine.get_physics_frames(), Engine.get_process_frames(), Engine.get_frames_drawn(),
		Engine.get_physics_interpolation_fraction(), Engine.get_frames_per_second(), Engine.is_in_physics_frame(),
		Engine.physics_ticks_per_second, Engine.max_fps, Engine.time_scale, get_tree().paused, get_tree().physics_interpolation,
	]
	var parts: Array[String] = []
	for node: Node in _mode_probes:
		var probe: TickProbeScript = node
		parts.append("%s: process %d / physics %d" % [probe.label, probe.process_calls, probe.physics_calls])
	_mode_label.text = "process_mode 별 호출 수 —  " + "   |   ".join(parts)


func _on_tps_selected(index: int) -> void:
	Engine.physics_ticks_per_second = TPS_OPTIONS[index]
	Log.info("Engine.physics_ticks_per_second = %d (물리 스텝 %.4f초). Main::iteration 이 밀린 시간만큼 물리 틱을 돌린다 (최대 max_physics_steps_per_frame=%d)." % [TPS_OPTIONS[index], 1.0 / TPS_OPTIONS[index], Engine.max_physics_steps_per_frame])


func _on_fps_selected(index: int) -> void:
	Engine.max_fps = FPS_OPTIONS[index]
	Log.info("Engine.max_fps = %d (0 = 제한 없음). core/os/os.cpp OS::add_frame_delay 가 프레임 끝에서 잠든다. 물리 틱 수는 그대로!" % FPS_OPTIONS[index])


func _on_scale_selected(index: int) -> void:
	Engine.time_scale = SCALE_OPTIONS[index]
	Log.info("Engine.time_scale = %.1f. physics/process 양쪽 delta 에 곱해진다 — 호출 횟수는 안 변하고 delta 만 변한다." % SCALE_OPTIONS[index])


func _on_interpolation_toggled(enabled: bool) -> void:
	get_tree().physics_interpolation = enabled
	_mover.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if enabled else Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mover.reset_physics_interpolation()
	Log.info("physics_interpolation = %s. tps 를 30 으로 낮추면 차이가 보입니다. 엔진: scene_tree.cpp set_physics_interpolation_enabled → RS::set_physics_interpolation_enabled." % enabled)


func _on_pause_pressed() -> void:
	get_tree().paused = not get_tree().paused
	Log.info("get_tree().paused = %s → ALWAYS 는 계속, PAUSABLE 은 멈춤, WHEN_PAUSED 는 이제부터 돎. NOTIFICATION_PAUSED/UNPAUSED 는 can_process 가 바뀐 노드에만 온다." % get_tree().paused)


func _on_record_order_pressed() -> void:
	_order_process.clear()
	_order_physics.clear()
	_pending_process_order = true
	_pending_physics_order = true
	Log.info("다음 프레임의 호출 순서를 기록합니다 (paused 면 PAUSABLE 탐침이 안 돌아 기록이 안 될 수 있음)...")
