extends Control
## 시그널 101. "시그널은 왜 필요한가?" — 보내는 쪽(Button)이 받는 쪽(이 스크립트)을 몰라도 되게 하는 관찰자 패턴.
## 엔진: core/object/object.h  connect()/emit_signal() 선언, core/object/object.cpp emit_signalp() 가
## 연결된 Callable 목록을 순회하며 호출한다. 저장소는 HashMap<StringName, SignalData>.
##
## 여기서 보여 주는 것:
##  1) 에디터 연결   — signals_101.tscn 의 [connection ...] 블록 (인스턴스화 때 connect() 로 바뀐다)
##  2) 코드 연결     — button.pressed.connect(callable)
##  3) bind          — 시그널 인자 뒤에 추가 인자를 붙인다
##  4) 일회성 연결   — CONNECT_ONE_SHOT: 첫 방출 뒤 자동 disconnect
##  5) 커스텀 시그널 — 인자를 가진 signal 선언 + emit
##  6) await         — 시그널이 올 때까지 코루틴을 멈춘다

## 5) 인자를 가진 커스텀 시그널. 타입은 문서/자동완성용이며 방출 시 강제되지는 않는다.
signal score_changed(new_score: int, delta: int)
## 6) await 데모가 끝났을 때. (경과 밀리초)
signal countdown_finished(elapsed_ms: int)

var score: int = 0
var once_count: int = 0

var code_button: Button
var bind_button: Button
var once_button: Button
var custom_button: Button
var await_button: Button
var status_label: Label
## await 데모용 타이머. 이 노드의 자식이라 데모가 닫히면 같이 사라지고, 기다리던 코루틴은 그냥 깨어나지 않는다.
## (get_tree().create_timer() 는 트리가 소유하므로 데모가 사라진 뒤에도 신호를 보내 "instance is gone" 오류를 낸다.)
var wait_timer: Timer

@onready var editor_button: Button = $EditorButton


func _ready() -> void:
	Log.section("시그널 101")
	_build_ui()

	# 2) 코드 연결. Signal.connect(Callable). 같은 Callable 을 두 번 연결하면 오류 → is_connected 로 확인 가능.
	code_button.pressed.connect(_on_code_button_pressed)
	# 3) Callable.bind: pressed 는 인자가 없지만 핸들러는 (String, int) 를 받는다.
	bind_button.pressed.connect(_on_bind_button_pressed.bind("빨강", 3))
	# 4) 일회성: 플래그는 Object.ConnectFlags (CONNECT_DEFERRED = 1, CONNECT_ONE_SHOT = 4).
	once_button.pressed.connect(_on_once_button_pressed, CONNECT_ONE_SHOT)
	# 5) 커스텀 시그널: 버튼 → add_score() → score_changed.emit() → _on_score_changed()
	custom_button.pressed.connect(func() -> void: add_score(10))
	score_changed.connect(_on_score_changed)
	countdown_finished.connect(_on_countdown_finished)
	# 6) await
	await_button.pressed.connect(_on_await_button_pressed)

	Log.info("1) 은 .tscn 의 [connection] 블록이, 2)~6) 은 _ready 의 connect() 가 연결했습니다.")
	Log.info("   EditorButton.pressed 연결 수: %d, once_button 연결 수: %d" % [
		editor_button.pressed.get_connections().size(), once_button.pressed.get_connections().size()])
	_auto_demo()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 64)
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	code_button = _make_button(box, "2) 코드에서 pressed.connect() 로 연결된 버튼")
	bind_button = _make_button(box, "3) Callable.bind(\"빨강\", 3) 으로 인자를 붙인 버튼")
	once_button = _make_button(box, "4) CONNECT_ONE_SHOT: 한 번만 반응하는 버튼")
	custom_button = _make_button(box, "5) 커스텀 시그널 score_changed(new, delta) 방출")
	await_button = _make_button(box, "6) await wait_timer.timeout (1초)")

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "버튼을 눌러 보세요. 결과는 아래 로그에 찍힙니다."
	box.add_child(status_label)

	wait_timer = Timer.new()
	wait_timer.name = "WaitTimer"
	wait_timer.one_shot = true
	wait_timer.wait_time = 1.0
	add_child(wait_timer)


func _make_button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	parent.add_child(button)
	return button


## 버튼 없이도(헤드리스 검증 포함) 같은 흐름이 보이도록 시그널을 코드로 방출해 본다.
func _auto_demo() -> void:
	Log.info("--- 자동 시연: Signal.emit() 으로 버튼 pressed 를 직접 방출합니다 ---")
	editor_button.pressed.emit()
	code_button.pressed.emit()
	bind_button.pressed.emit()
	once_button.pressed.emit()
	once_button.pressed.emit()  # 두 번째는 아무 일도 없어야 한다
	Log.info("   one-shot 두 번 방출 후: 호출 횟수 %d, 아직 연결됨? %s" % [
		once_count, str(once_button.pressed.is_connected(_on_once_button_pressed))])
	add_score(10)
	_run_await_demo()


func _on_editor_button_pressed() -> void:
	Log.info("1) 에디터 연결: [connection signal=\"pressed\" from=\"EditorButton\" to=\".\" method=\"_on_editor_button_pressed\"]"
		+ " → 인스턴스화 때 connect() (엔진: scene/resources/packed_scene.cpp SceneState::instantiate 의 connections 루프)")


func _on_code_button_pressed() -> void:
	Log.info("2) 코드 연결: code_button.pressed.connect(_on_code_button_pressed)")


func _on_bind_button_pressed(color_name: String, amount: int) -> void:
	Log.info("3) bind: 시그널 인자(없음) 뒤에 bind 인자가 붙어 호출됨 → color_name=%s amount=%d" % [color_name, amount])


func _on_once_button_pressed() -> void:
	once_count += 1
	Log.info("4) CONNECT_ONE_SHOT 핸들러 %d번째 호출 — 이 호출이 끝나면 엔진이 자동으로 disconnect 합니다" % once_count)


func add_score(delta: int) -> void:
	score += delta
	# emit 은 동기 호출: 연결된 핸들러가 모두 돌고 나서야 다음 줄로 온다 (CONNECT_DEFERRED 가 아닌 한).
	score_changed.emit(score, delta)
	status_label.text = "score = %d" % score


func _on_score_changed(new_score: int, delta: int) -> void:
	Log.info("5) 커스텀 시그널 score_changed(new_score=%d, delta=%d) 수신" % [new_score, delta])


func _on_await_button_pressed() -> void:
	_run_await_demo()


## 코루틴: await 를 만나면 함수가 GDScriptFunctionState 로 얼어붙고, 시그널이 오면 그 자리부터 이어진다
## (엔진: modules/gdscript/gdscript_function.cpp GDScriptFunctionState::resume).
func _run_await_demo() -> void:
	if not wait_timer.is_stopped():
		Log.info("6) 이미 기다리는 중입니다.")
		return
	var started_ms: int = Time.get_ticks_msec()
	Log.info("6) await: WaitTimer.timeout 을 기다립니다 (1초)... 검증 실행에선 6프레임 뒤 닫혀 오지 않을 수 있습니다.")
	wait_timer.start()
	await wait_timer.timeout
	if not is_inside_tree():
		return  # 기다리는 동안 데모가 닫혔다면 아무것도 만지지 않는다
	countdown_finished.emit(Time.get_ticks_msec() - started_ms)


func _on_countdown_finished(elapsed_ms: int) -> void:
	Log.info("6) await 끝: %d ms 경과 → countdown_finished 시그널로 알림" % elapsed_ms)
	status_label.text = "await 완료 (%d ms)" % elapsed_ms
