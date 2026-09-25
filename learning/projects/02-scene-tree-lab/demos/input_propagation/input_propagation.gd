extends Control
## 데모 5: 입력 전파 순서.
## 엔진: scene/main/window.cpp Window::_window_input() ← DisplayServer 콜백 → scene/main/viewport.cpp Viewport::push_input():
##   1) _input            : input_group 노드들 (SceneTree::_call_input_pause)
##   2) GUI               : _gui_input_event() — 마우스는 gui_find_control() 로 찾은 Control 부터, 키는 포커스 소유자부터
##                          _gui_call_input() 이 부모 Control 체인을 올라간다 (IGNORE 는 건너뜀, STOP 은 포인터 이벤트만 멈춤).
##                          Control::_call_gui_input(): gui_input 시그널 → GDVIRTUAL _gui_input → C++ gui_input()(버튼 클릭 처리)
##   3) _push_unhandled_input_internal(): _shortcut_input(Key/Shortcut/JoypadButton 만) → _unhandled_key_input(Key 만) → _unhandled_input
##   단계 사이마다 is_input_handled() 를 확인하므로 set_input_as_handled() 는 그 뒤 단계를 모두 막는다.
##   마우스 클릭은 _gui_call_input() 체인에서 STOP 인 Control 을 만나거나 핸들러가 accept_event() 를 부를 때만 handled 가 된다
##   (Button 은 BaseButton::gui_input 이 스스로 accept_event). 체인이 전부 PASS/IGNORE 면 _unhandled_input 까지 간다.
##   그 지점에 Control 이 하나도 없으면(모두 IGNORE) _gui_input_event() 가 `if (!gui.mouse_focus) return` 으로 GUI 단계를 통째로 건너뛴다.

const GuiProbeScript: GDScript = preload("res://demos/input_propagation/gui_probe.gd")
const STAGES: Array[String] = ["_input", "_gui_input", "_shortcut_input", "_unhandled_key_input", "_unhandled_input"]
const FILTER_NAMES: Array[String] = ["STOP", "PASS", "IGNORE"]

## 마지막 이벤트가 거친 단계 이름 (selftest 가 순서를 검사한다).
var stage_log: Array[String] = []
## 단계 이름 → 그 단계에서 set_input_as_handled() 를 부를지.
var handle_at: Dictionary = {}

var _panel: Control
var _button: Control


func _ready() -> void:
	_build_ui()
	Log.section("데모 5: 입력 전파")
	Log.info("순서: _input → _gui_input → _shortcut_input → _unhandled_key_input → _unhandled_input (viewport.cpp push_input / _push_unhandled_input_internal).")
	Log.info("키를 누르거나 버튼·패널·빈 곳을 클릭하세요. 마우스 이동은 기록하지 않습니다. SPACE 는 [input] 액션 lab_ping 입니다.")


## 1) 가장 먼저. 모든 노드의 _input 이 이 단계에 속한다.
func _input(event: InputEvent) -> void:
	_report("_input", "루트 노드", event)


## 2) GUI 단계. 루트 Control 자신도 _gui_input 을 받을 수 있다 (mouse_filter 가 IGNORE 가 아닐 때).
func _gui_input(event: InputEvent) -> void:
	_report("_gui_input", "루트 Control", event)


## 3-1) 키/단축키/조이패드 버튼 이벤트만 온다. 마우스 클릭은 절대 오지 않는다.
func _shortcut_input(event: InputEvent) -> void:
	_report("_shortcut_input", "루트 노드", event)


## 3-2) 키 이벤트만 온다 (마우스 이동 등을 걸러 성능을 아끼기 위한 단계).
func _unhandled_key_input(event: InputEvent) -> void:
	_report("_unhandled_key_input", "루트 노드", event)


## 3-3) 마지막. 여기까지 온 마우스 클릭은 어떤 Control 도 받지 않은 것이다.
func _unhandled_input(event: InputEvent) -> void:
	_report("_unhandled_input", "루트 노드", event)


func _on_probe_gui_input(who: String, event: InputEvent) -> void:
	_report("_gui_input", who, event)


func _is_interesting(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.is_pressed() and not event.is_echo()
	if event is InputEventMouseButton:
		return event.is_pressed()
	return false


func _report(stage: String, who: String, event: InputEvent) -> void:
	if not _is_interesting(event):
		return
	if stage == "_input":
		stage_log.clear()
		Log.section("이벤트: " + event.as_text())
	stage_log.append(stage)
	var extra: String = "  (액션 lab_ping)" if event.is_action_pressed("lab_ping") else ""
	Log.info("  %-22s ← %s%s" % [stage, who, extra])
	if bool(handle_at.get(stage, false)):
		# Viewport::set_input_as_handled() → local_input_handled = true. push_input 은 단계마다 is_input_handled() 를 본다.
		get_viewport().set_input_as_handled()
		Log.info("    → get_viewport().set_input_as_handled(): 이후 단계는 오지 않는다")


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)

	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "체크박스: 그 단계에서 get_viewport().set_input_as_handled() 를 부른다.\n마우스 클릭은 체인에서 STOP 인 Control 을 만날 때만 GUI 단계가 소비한다 (Button 은 스스로 accept_event). 루트와 Panel 을 PASS 로 두고 Panel 을 클릭하면 Panel → 루트 _gui_input 뒤에 _unhandled_input 까지 간다. 둘 다 IGNORE 면 GUI 단계 없이 곧장 _unhandled_input 으로 간다.\n키 이벤트는 포커스 소유자에서 시작해 mouse_filter≠IGNORE 인 조상으로 올라간다 (STOP 은 포인터 이벤트만 막는다)."
	vbox.add_child(info)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	filters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(filters)
	_add_filter_option(filters, "루트 Control mouse_filter", _on_root_filter_selected)
	_add_filter_option(filters, "Panel mouse_filter", _on_panel_filter_selected)

	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 10)
	checks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(checks)
	for stage: String in STAGES:
		var check := CheckBox.new()
		check.text = "handled @ " + stage
		check.toggled.connect(_on_handle_toggled.bind(stage))
		checks.add_child(check)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row)

	_button = Button.new()
	_button.name = "Button"
	_button.text = "버튼 (GuiProbe 스크립트)"
	_button.set_script(GuiProbeScript)
	_button.set("sink", _on_probe_gui_input)
	_button.pressed.connect(func() -> void: Log.info("    Button.pressed 시그널 — BaseButton::gui_input() 이 클릭을 처리하고 accept_event() 로 handled"))
	_button.focus_entered.connect(func() -> void: Log.info("    포커스 → Button (이제 키 이벤트가 Button._gui_input 으로 먼저 간다)"))
	row.add_child(_button)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(440, 110)
	_panel.focus_mode = Control.FOCUS_ALL
	_panel.set_script(GuiProbeScript)
	_panel.set("sink", _on_probe_gui_input)
	_panel.focus_entered.connect(func() -> void: Log.info("    포커스 → Panel (FOCUS_ALL 이라 클릭으로 포커스를 받는다)"))
	row.add_child(_panel)
	var panel_label := Label.new()
	panel_label.text = "Panel (GuiProbe 스크립트, FOCUS_ALL)\n클릭하면 포커스를 받고, 이후 키 입력이 _gui_input 으로 온다.\nLabel 은 기본 mouse_filter=IGNORE 라 클릭을 Panel 이 받는다."
	panel_label.position = Vector2(10, 10)
	_panel.add_child(panel_label)


func _add_filter_option(parent: Node, label_text: String, callback: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	for filter_name: String in FILTER_NAMES:
		option.add_item("MOUSE_FILTER_" + filter_name)
	option.select(0)
	option.item_selected.connect(callback)
	parent.add_child(option)


func _on_root_filter_selected(index: int) -> void:
	mouse_filter = index as Control.MouseFilter
	Log.info("루트 Control.mouse_filter = MOUSE_FILTER_%s" % FILTER_NAMES[index])


func _on_panel_filter_selected(index: int) -> void:
	_panel.mouse_filter = index as Control.MouseFilter
	Log.info("Panel.mouse_filter = MOUSE_FILTER_%s — STOP: 받고 handled / PASS: 받고 부모 체인으로 계속 / IGNORE: 안 받음(뒤의 Control 이 받거나, 없으면 GUI 단계 생략)" % FILTER_NAMES[index])


func _on_handle_toggled(enabled: bool, stage: String) -> void:
	handle_at[stage] = enabled
	Log.info("%s 에서 set_input_as_handled() %s" % [stage, "호출함" if enabled else "안 함"])
