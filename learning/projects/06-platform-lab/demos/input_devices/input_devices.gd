extends Control
## 데모 3: 입력 장치 — Input 싱글턴(core/input/input.h), InputMap(core/input/input_map.h), 마우스 모드.
## 조이패드: 데스크톱/Apple 은 drivers/sdl/joypad_sdl.cpp(SDL3) 가 Input::joy_connection_changed() 로 등록하고
## 매핑은 core/input/gamecontrollerdb.txt(빌드 시 default_controller_mappings.gen.cpp) 를 쓴다 (학습 5장 5.5).
## 이벤트 흐름: DisplayServer → Input::parse_input_event → SceneTree → Viewport::push_input → 이 노드의 _input().

const AXES: Array[Array] = [
	["LX", JOY_AXIS_LEFT_X], ["LY", JOY_AXIS_LEFT_Y], ["RX", JOY_AXIS_RIGHT_X],
	["RY", JOY_AXIS_RIGHT_Y], ["LT", JOY_AXIS_TRIGGER_LEFT], ["RT", JOY_AXIS_TRIGGER_RIGHT],
]
const MOUSE_MODES: Array[Array] = [
	["VISIBLE", Input.MOUSE_MODE_VISIBLE], ["HIDDEN", Input.MOUSE_MODE_HIDDEN],
	["CAPTURED", Input.MOUSE_MODE_CAPTURED], ["CONFINED", Input.MOUSE_MODE_CONFINED],
	["CONFINED_HIDDEN", Input.MOUSE_MODE_CONFINED_HIDDEN],
]

var _joy_list: Label
var _live: Label
var _actions: Label
var _remap_pick: OptionButton
var _remap_status: Label
var _waiting: bool = false
var _project_actions: Array[StringName] = []


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	_build_joypad_section(vbox)
	_build_inputmap_section(vbox)
	_build_mouse_section(vbox)
	Input.joy_connection_changed.connect(_on_joy_changed)
	_refresh_joypads()
	_refresh_actions()


func _build_joypad_section(parent: VBoxContainer) -> void:
	_title(parent, "조이패드 — Input.get_connected_joypads / get_joy_name / get_joy_guid / get_joy_info / joy_connection_changed")
	_joy_list = _label(parent)
	_live = _label(parent)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var vib := Button.new()
	vib.text = "진동 0.5초 (start_joy_vibration)"
	vib.pressed.connect(_vibrate)
	row.add_child(vib)
	var refresh := Button.new()
	refresh.text = "다시 조회"
	refresh.pressed.connect(_refresh_joypads)
	row.add_child(refresh)


func _refresh_joypads() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		_joy_list.text = "연결된 조이패드 없음"
		Log.warn("조이패드 없음 — 헤드리스/서버에서는 정상. 연결하면 joy_connection_changed 시그널로 목록이 갱신된다.")
		return
	var lines: PackedStringArray = []
	for dev: int in pads:
		lines.append("[%d] %s  guid=%s  info=%s  진동=%s" % [
			dev, Input.get_joy_name(dev), Input.get_joy_guid(dev), str(Input.get_joy_info(dev)), str(Input.has_joy_vibration(dev))])
	_joy_list.text = "\n".join(lines)
	Log.info("조이패드 %d개: %s" % [pads.size(), "; ".join(lines)])


func _on_joy_changed(device: int, connected: bool) -> void:
	Log.info("joy_connection_changed: device=%d connected=%s" % [device, str(connected)])
	_refresh_joypads()


func _process(_delta: float) -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		_live.text = "축/버튼 실시간 값: (장치 없음)"
		return
	var lines: PackedStringArray = []
	for dev: int in pads:
		var parts: PackedStringArray = []
		for a: Array in AXES:
			parts.append("%s=%.2f" % [String(a[0]), Input.get_joy_axis(dev, a[1])])
		var pressed: PackedStringArray = []
		for b: int in JOY_BUTTON_SDL_MAX:
			if Input.is_joy_button_pressed(dev, b as JoyButton):
				pressed.append(str(b))
		lines.append("[%d] %s  buttons=[%s]" % [dev, " ".join(parts), ",".join(pressed)])
	_live.text = "\n".join(lines)


func _vibrate() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		Log.warn("진동: 조이패드 없음")
		return
	for dev: int in pads:
		# 엔진: core/input/input.cpp start_joy_vibration → 플랫폼 조이패드 드라이버(drivers/sdl/joypad_sdl.cpp)가 실제 모터를 돌린다.
		Input.start_joy_vibration(dev, 0.4, 0.8, 0.5)
		Log.info("start_joy_vibration(%d, weak=0.4, strong=0.8, 0.5s)" % dev)


func _build_inputmap_section(parent: VBoxContainer) -> void:
	_title(parent, "InputMap — project.godot [input] 액션 (InputMap.get_actions / action_get_events / InputEvent.as_text)")
	_actions = _label(parent)
	var row := HBoxContainer.new()
	parent.add_child(row)
	_remap_pick = OptionButton.new()
	row.add_child(_remap_pick)
	var wait := Button.new()
	wait.text = "다음 키로 재매핑 (ESC 취소)"
	wait.pressed.connect(_begin_remap)
	row.add_child(wait)
	var reset := Button.new()
	reset.text = "초기화 (InputMap.load_from_project_settings)"
	reset.pressed.connect(_reset_map)
	row.add_child(reset)
	_remap_status = _label(parent)


func _refresh_actions() -> void:
	_project_actions.clear()
	var builtin: int = 0
	var lines: PackedStringArray = []
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			builtin += 1
			continue
		_project_actions.append(action)
		var texts: PackedStringArray = []
		for ev: InputEvent in InputMap.action_get_events(action):
			texts.append(ev.as_text())
		lines.append("%s (deadzone %.2f): %s" % [action, InputMap.action_get_deadzone(action), " | ".join(texts)])
	Log.info("프로젝트 액션 %d개: %s" % [_project_actions.size(), "; ".join(lines)])
	lines.append("(+ 엔진 기본 ui_* 액션 %d개: core/input/input_map.cpp get_builtins())" % builtin)
	_actions.text = "\n".join(lines)
	_remap_pick.clear()
	for action: StringName in _project_actions:
		_remap_pick.add_item(String(action))


func _picked_action() -> StringName:
	return _project_actions[maxi(_remap_pick.selected, 0)]


func _begin_remap() -> void:
	if _project_actions.is_empty():
		Log.warn("재매핑할 액션 없음")
		return
	_waiting = true
	_remap_status.text = "'%s' 에 넣을 키를 누르세요… (ESC 취소)" % _picked_action()
	Log.info(_remap_status.text)


func _input(event: InputEvent) -> void:
	if not _waiting:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	_waiting = false
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_ESCAPE:
		_remap_status.text = "재매핑 취소"
		return
	var action: StringName = _picked_action()
	# 엔진: core/input/input_map.cpp action_erase_events → action_add_event. 런타임 InputMap 만 바뀌고
	# project.godot 은 그대로다 (영구 저장은 ProjectSettings.set_setting("input/…") + save() 가 필요).
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, key)
	_remap_status.text = "'%s' ← %s" % [action, key.as_text()]
	Log.info("재매핑: " + _remap_status.text)
	_refresh_actions()


func _reset_map() -> void:
	InputMap.load_from_project_settings()
	_remap_status.text = "project.godot 의 [input] 으로 복원"
	Log.info("InputMap.load_from_project_settings() — 런타임 변경을 모두 버리고 다시 읽음")
	_refresh_actions()


func _build_mouse_section(parent: VBoxContainer) -> void:
	_title(parent, "마우스 모드 / 터치 에뮬레이션 — Input.mouse_mode → DisplayServer::mouse_set_mode")
	var pick := OptionButton.new()
	for m: Array in MOUSE_MODES:
		pick.add_item(String(m[0]))
	pick.selected = 0
	pick.item_selected.connect(_on_mouse_mode)
	parent.add_child(pick)
	var info := _label(parent)
	info.text = "\n".join([
		"현재 Input.mouse_mode = %d" % Input.mouse_mode,
		"ProjectSettings input_devices/pointing/emulate_touch_from_mouse = %s" % str(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false)),
		"ProjectSettings input_devices/pointing/emulate_mouse_from_touch = %s" % str(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)),
		"Input.emulate_touch_from_mouse = %s / Input.emulate_mouse_from_touch = %s" % [str(Input.emulate_touch_from_mouse), str(Input.emulate_mouse_from_touch)],
		"DisplayServer.is_touchscreen_available() = %s" % str(DisplayServer.is_touchscreen_available()),
	])
	Log.info("마우스 모드 %d, 마우스→터치 에뮬레이션 %s, 터치스크린 %s" % [
		Input.mouse_mode, str(Input.emulate_touch_from_mouse), str(DisplayServer.is_touchscreen_available())])


func _on_mouse_mode(index: int) -> void:
	var mode: int = MOUSE_MODES[index][1]
	if DisplayServer.get_name() == "headless":
		Log.warn("headless DisplayServer 는 mouse_set_mode 가 빈 함수다 — 값만 기록된다")
	Input.mouse_mode = mode as Input.MouseMode
	Log.info("Input.mouse_mode = %s (%d). CAPTURED 는 커서가 창 밖으로 못 나가고 상대 이동만 온다." % [String(MOUSE_MODES[index][0]), mode])


func _title(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color.SKY_BLUE)
	parent.add_child(lbl)


func _label(parent: VBoxContainer) -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)
	return lbl
