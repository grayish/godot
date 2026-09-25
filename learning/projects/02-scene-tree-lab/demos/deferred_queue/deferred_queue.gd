extends Control
## 데모 3: "나중에 실행" 여섯 가지가 실제로 언제 실행되는지.
## 엔진: core/object/message_queue.h CallQueue::push_callp / push_set / push_callablep 에 쌓인 항목은
##   main/main.cpp Main::iteration() 의 message_queue->flush() (물리 틱마다 2번, process 뒤 1번) 와
##   scene/main/scene_tree.cpp SceneTree::physics_process()/process() 안의 flush() 에서 실행된다.
##   process_frame / physics_frame 시그널은 SceneTree::process()/physics_process() 첫머리에서 emit 된다 (노드들의 _process 보다 먼저).
##   create_timer 는 SceneTree::process_timers() 가 _process 뒤에 처리한다 — 0초 타이머도 같은 프레임 끝에 timeout 이 난다.
## 버튼 콜백은 DisplayServer 이벤트 처리 중(Main::iteration 밖)에 불리므로, 그때 요청한 것은 다음 iteration 의 첫 flush 에서 실행된다.

## CONNECT_DEFERRED 로 연결할 시그널.
signal deferred_ping(tag: String)

var _process_calls: int = 0
var _physics_calls: int = 0
var _phase: String = "콜백 밖"
var _request_in_process: bool = false
var _request_in_physics: bool = false
## set_deferred 대상. setter 가 실행 시점을 기록한다.
var _probe_value: int = 0:
	set(value):
		_probe_value = value
		_executed("set_deferred(\"_probe_value\")")


func _ready() -> void:
	_build_ui()
	# 엔진: Object::emit_signalp — CONNECT_DEFERRED 연결은 즉시 부르지 않고 MessageQueue::push_callablep 로 미룬다.
	deferred_ping.connect(_on_deferred_ping, CONNECT_DEFERRED)
	Log.section("데모 3: 지연 실행 큐(MessageQueue)와 프레임 시그널")
	Log.info("각 줄: pf=Engine.get_process_frames(), phf=Engine.get_physics_frames(), P#/PH#=이 노드의 _process/_physics_process 누적 호출 수, in_physics=Engine.is_in_physics_frame(), [단계]=요청/실행이 어느 콜백 안인지.")
	Log.info("요청 줄과 실행 줄의 숫자를 비교하세요. process_frames 는 Main::iteration() 끝에서 증가하므로 같은 iteration 안이면 pf 가 같습니다.")


func _process(_delta: float) -> void:
	_process_calls += 1
	_phase = "_process 안"
	if _request_in_process:
		_request_in_process = false
		_request_all("_process 안에서")
	_phase = "콜백 밖"


func _physics_process(_delta: float) -> void:
	_physics_calls += 1
	_phase = "_physics_process 안"
	if _request_in_physics:
		_request_in_physics = false
		_request_all("_physics_process 안에서")
	_phase = "콜백 밖"


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "위 줄: 개별 요청 (버튼 콜백 = Main::iteration 밖). 아래 줄: 여섯 가지를 한꺼번에, 요청 지점을 바꿔 가며.\n읽는 법 — pf 같음 = 같은 iteration 안에서 실행됨. in_physics=true = 물리 틱 안(또는 그 직후 flush)에서 실행됨."
	vbox.add_child(info)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	_add_button(grid, "call_deferred", _req_call_deferred)
	_add_button(grid, "set_deferred", _req_set_deferred)
	_add_button(grid, "CONNECT_DEFERRED 시그널 emit", _req_deferred_signal)
	_add_button(grid, "await get_tree().process_frame", _req_await_process_frame)
	_add_button(grid, "await get_tree().physics_frame", _req_await_physics_frame)
	_add_button(grid, "create_timer(0.0).timeout", _req_timer)

	var grid2 := GridContainer.new()
	grid2.columns = 3
	grid2.add_theme_constant_override("h_separation", 8)
	grid2.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid2)
	_add_button(grid2, "6가지 한꺼번에 (지금: 입력 콜백)", _request_all.bind("입력 콜백에서"))
	_add_button(grid2, "6가지 한꺼번에 (다음 _process 안)", func() -> void: _request_in_process = true)
	_add_button(grid2, "6가지 한꺼번에 (다음 _physics_process 안)", func() -> void: _request_in_physics = true)


func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _stamp() -> String:
	return "pf=%d phf=%d P#%d PH#%d in_physics=%s [%s]" % [Engine.get_process_frames(), Engine.get_physics_frames(), _process_calls, _physics_calls, Engine.is_in_physics_frame(), _phase]


func _request(kind: String) -> void:
	Log.info("요청 %-30s | %s" % [kind, _stamp()])


func _executed(kind: String) -> void:
	Log.info("   실행 %-27s | %s" % [kind, _stamp()])


func _req_call_deferred() -> void:
	_request("call_deferred")
	# 엔진: Object::call_deferred → MessageQueue::push_callp. 다음 flush() 에서 실행된다.
	call_deferred("_executed", "call_deferred")


func _req_set_deferred() -> void:
	_request("set_deferred")
	# 엔진: Object::set_deferred → MessageQueue::push_set → flush 때 setter 가 불린다.
	set_deferred("_probe_value", _probe_value + 1)


func _req_deferred_signal() -> void:
	_request("CONNECT_DEFERRED 시그널")
	deferred_ping.emit("CONNECT_DEFERRED 시그널")


func _req_await_process_frame() -> void:
	_request("await process_frame")
	_await_process_frame()


func _req_await_physics_frame() -> void:
	_request("await physics_frame")
	_await_physics_frame()


func _req_timer() -> void:
	_request("create_timer(0.0).timeout")
	# 엔진: SceneTree::create_timer → timers 리스트. process_timers() 가 _process 뒤에 돌며 time_left<=0 이면 timeout 을 emit 한다.
	get_tree().create_timer(0.0).timeout.connect(_executed.bind("create_timer(0.0).timeout"))


func _request_all(origin: String) -> void:
	Log.section("6가지 한꺼번에 요청 — " + origin)
	_req_call_deferred()
	_req_set_deferred()
	_req_deferred_signal()
	_req_await_process_frame()
	_req_await_physics_frame()
	_req_timer()


func _await_process_frame() -> void:
	# SceneTree::process() 첫머리의 emit_signal("process_frame") 에서 재개된다 — 노드들의 _process 보다 먼저.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_executed("await process_frame")


func _await_physics_frame() -> void:
	# SceneTree::physics_process() 첫머리의 emit_signal("physics_frame") 에서 재개된다 — 물리 틱 안(in_physics=true).
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_executed("await physics_frame")


func _on_deferred_ping(tag: String) -> void:
	_executed(tag)
