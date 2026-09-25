extends Control
## 데모 3: 코루틴 (await).
## 엔진: modules/gdscript/gdscript_vm.cpp OPCODE_AWAIT — 현재 스택을 GDScriptFunctionState(힙, gdscript_function.h:506)에 복사하고,
##       기다릴 시그널에 Callable(state, "_signal_callback") 을 CONNECT_ONE_SHOT 으로 연결한 뒤 함수에서 빠져나온다.
##       시그널이 오면 GDScriptFunctionState::resume() → OPCODE_AWAIT_RESUME 부터 이어서 실행한다.
##       인스턴스가 먼저 사라지면 GDScriptInstance 소멸자가 pending_func_states 의 연결을 끊는다 (gdscript.cpp).
## 이 빌드(4.8)에서는 코루틴의 반환값을 await 없이 변수에 담으면 파싱 오류, Callable.call() 로 받으면 런타임 오류다.
## 그래서 "정지된 호출"은 시그널에 걸린 연결(Signal.get_connections)로 관찰한다.

## 정적 코루틴(wait_frames / wait_seconds)은 frame_waiter.gd 에 있다 — selftest 가 같은 함수를 프레임에 걸쳐 검사한다.
const FrameWaiter := preload("res://demos/coroutines/frame_waiter.gd")

signal go

var _cancel_requested: bool = false
var _loop_running: bool = false
var _loop_ticks: int = 0
var _status: Label


@warning_ignore("missing_await")
func _ready() -> void:
	_build_ui()
	_demo_await_signal()
	# 아래 둘은 코루틴이다. await 없이 호출하면 첫 await 에서 여기로 돌아오고 (MISSING_AWAIT 경고 대상),
	# 나머지는 시그널이 올 때마다 이어진다. 반환값을 받으려 하면 오류이므로 "발사 후 잊기"로만 쓴다.
	_demo_values_and_branches()
	_demo_sequential_vs_parallel()
	_start_cancellable_loop()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	_status = Label.new()
	_status.text = "코루틴 데모 — 결과는 로그 패널에"
	column.add_child(_status)
	var row := HBoxContainer.new()
	column.add_child(row)
	var rerun := Button.new()
	rerun.text = "순차 vs 병렬 다시 재기"
	rerun.pressed.connect(_demo_sequential_vs_parallel)
	row.add_child(rerun)
	var start := Button.new()
	start.text = "취소 가능한 루프 시작"
	start.pressed.connect(_start_cancellable_loop)
	row.add_child(start)
	var cancel := Button.new()
	cancel.text = "취소 요청"
	cancel.pressed.connect(_request_cancel)
	row.add_child(cancel)


# ---------------------------------------------------------------- 시그널 await 와 정지된 호출의 정체

@warning_ignore("missing_await")
func _demo_await_signal() -> void:
	Log.section("await 시그널 — 정지된 호출은 무엇인가")
	_wait_for_go() # 첫 await 에서 곧바로 돌아온다
	for conn: Dictionary in go.get_connections():
		var callback: Callable = conn["callable"]
		var target: Object = callback.get_object()
		Log.info("go 에 걸린 연결: 대상=%s, 메서드=%s, flags=%d (CONNECT_ONE_SHOT=%d), 바인딩 인자 %d개" % [target.get_class(), callback.get_method(), conn["flags"], CONNECT_ONE_SHOT, callback.get_bound_arguments_count()])
		Log.info("  → 이것이 GDScriptFunctionState (부모 %s). 바인딩 인자는 자기 자신을 담아 참조 카운트를 유지한다 (gdscript_vm.cpp OPCODE_AWAIT)" % ClassDB.get_parent_class(target.get_class()))
	go.emit()
	Log.info("go.emit() 에서 돌아옴 — 재개는 emit 안에서 동기적으로 끝났고 ONE_SHOT 연결은 사라졌다 (남은 연결 %d)" % go.get_connections().size())


func _wait_for_go() -> void:
	Log.info("  _wait_for_go: await go 직전")
	await go
	Log.info("  _wait_for_go: 시그널을 받아 재개됨")


# ---------------------------------------------------------------- 값 반환, 타이머, 가끔만 기다리는 함수

func _demo_values_and_branches() -> void:
	Log.section("값을 돌려주는 코루틴 / 가끔만 기다리는 함수 / 타이머")
	var t0: int = Time.get_ticks_msec()
	var doubled: int = await _double_next_frame(21)
	if not is_inside_tree():
		return # 기다리는 동안 데모가 트리에서 빠졌을 수 있다 — get_tree() 가 null 이 되므로 여기서 멈춘다
	Log.info("await _double_next_frame(21) = %d (%d ms, 한 프레임 뒤)" % [doubled, Time.get_ticks_msec() - t0])

	t0 = Time.get_ticks_msec()
	var quick: int = await _maybe_wait(false)
	if not is_inside_tree():
		return
	Log.info("await _maybe_wait(false) = %d, %d ms — 분기가 await 를 안 타도 즉시 값이 온다" % [quick, Time.get_ticks_msec() - t0])
	Log.info("  분석기(gdscript_analyzer.cpp)는 본문 어딘가에 await 가 있으면 함수 전체를 코루틴으로 표시하므로 호출자는 항상 await 해야 한다")

	t0 = Time.get_ticks_msec()
	var slow: int = await _maybe_wait(true)
	if not is_inside_tree():
		return
	Log.info("await _maybe_wait(true) = %d, %d ms — 이번엔 0.05s 타이머를 기다렸다" % [slow, Time.get_ticks_msec() - t0])

	t0 = Time.get_ticks_msec()
	await get_tree().create_timer(0.1).timeout
	if not is_inside_tree():
		return
	Log.info("await get_tree().create_timer(0.1).timeout → %d ms (SceneTreeTimer 는 SceneTree 가 매 프레임 줄여 가며 timeout 을 emit)" % (Time.get_ticks_msec() - t0))

	var waited: int = await FrameWaiter.wait_frames(get_tree(), 2)
	if not is_inside_tree():
		return
	Log.info("await FrameWaiter.wait_frames(tree, 2) = %d — 인스턴스가 없는 static 코루틴도 똑같이 동작한다 (state.instance_id 만 비어 있다)" % waited)


func _double_next_frame(x: int) -> int:
	await get_tree().process_frame
	return x * 2


func _maybe_wait(really: bool) -> int:
	if really:
		await get_tree().create_timer(0.05).timeout
		return 2
	return 1


# ---------------------------------------------------------------- 순차 vs 병렬

func _demo_sequential_vs_parallel() -> void:
	Log.section("순차 await vs 병렬 await")
	var t0: int = Time.get_ticks_msec()
	await get_tree().create_timer(0.2).timeout
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	Log.info("순차: 0.2s 타이머 뒤 0.3s 타이머 → %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	var short_timer: SceneTreeTimer = get_tree().create_timer(0.2)
	var long_timer: SceneTreeTimer = get_tree().create_timer(0.3)
	await short_timer.timeout
	if not is_inside_tree():
		return
	await long_timer.timeout
	if not is_inside_tree():
		return
	Log.info("병렬: 타이머 둘을 먼저 만들고 짧은 것부터 await → %d ms" % (Time.get_ticks_msec() - t0))
	Log.warn("함정: 이미 timeout 을 낸 SceneTreeTimer 를 나중에 await 하면 영원히 깨어나지 않는다 (시그널은 한 번뿐). 긴 것을 먼저 기다렸다면 짧은 것은 놓친다.")


# ---------------------------------------------------------------- 취소 패턴

func _start_cancellable_loop() -> void:
	if _loop_running:
		Log.warn("루프가 이미 실행 중이다.")
		return
	_cancel_requested = false
	_loop_running = true
	_loop_ticks = 0
	Log.section("취소 패턴: 플래그 + 매 프레임 await")
	Log.info("코루틴은 밖에서 강제로 멈출 수 없다. 루프가 매 프레임 플래그를 확인해 스스로 return 한다. [취소 요청] 버튼을 누르자.")
	while not _cancel_requested:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		_loop_ticks += 1
		_status.text = "루프 진행 중: %d 프레임 (취소 요청 버튼을 누르세요)" % _loop_ticks
	_loop_running = false
	_status.text = "루프가 %d 프레임 뒤 취소됨" % _loop_ticks
	Log.info("루프가 %d 프레임 뒤 취소됨" % _loop_ticks)


func _request_cancel() -> void:
	if not _loop_running:
		Log.warn("실행 중인 루프가 없다.")
		return
	_cancel_requested = true
