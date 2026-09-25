extends Control
## 데모 5: 창과 디스플레이 — Window 노드(scene/main/window.cpp) 와 DisplayServer 의 관계.
## 루트 Window 는 MAIN_WINDOW_ID(0) 에 붙어 있다. 새 Window 노드가 보이면 _make_window() 가
## DisplayServer::create_sub_window() 로 네이티브 창 ID 를 받고 (window.cpp:778), _update_window_size() 가
## RS.viewport_attach_to_screen(뷰포트 RID, rect, window_id) 로 뷰포트를 그 창에 붙인다 (window.cpp:1482).
## 임베디드 창(gui_embed_subwindows=true)은 부모 뷰포트 안에 Control 처럼 그려지고 부모의 window_id 를 그대로 쓴다.

const MODES: Array[Array] = [
	["WINDOWED", DisplayServer.WINDOW_MODE_WINDOWED], ["MAXIMIZED", DisplayServer.WINDOW_MODE_MAXIMIZED],
	["FULLSCREEN", DisplayServer.WINDOW_MODE_FULLSCREEN], ["EXCLUSIVE_FULLSCREEN", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN],
]
const VSYNC: Array[Array] = [
	["DISABLED", DisplayServer.VSYNC_DISABLED], ["ENABLED", DisplayServer.VSYNC_ENABLED],
	["ADAPTIVE", DisplayServer.VSYNC_ADAPTIVE], ["MAILBOX", DisplayServer.VSYNC_MAILBOX],
]
const SCALE_MODES: Array[Array] = [
	["DISABLED", Window.CONTENT_SCALE_MODE_DISABLED], ["CANVAS_ITEMS", Window.CONTENT_SCALE_MODE_CANVAS_ITEMS],
	["VIEWPORT", Window.CONTENT_SCALE_MODE_VIEWPORT],
]
const ASPECTS: Array[Array] = [
	["IGNORE", Window.CONTENT_SCALE_ASPECT_IGNORE], ["KEEP", Window.CONTENT_SCALE_ASPECT_KEEP],
	["KEEP_WIDTH", Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH], ["KEEP_HEIGHT", Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT],
	["EXPAND", Window.CONTENT_SCALE_ASPECT_EXPAND],
]
const REFRESH_INTERVAL: float = 0.5

var _info: Label
var _popup: Window = null
var _accum: float = 0.0


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_title(vbox, "창 모드 — DisplayServer.window_set_mode(mode, MAIN_WINDOW_ID)  (Window.mode 프로퍼티는 같은 호출을 감싼다)")
	var modes := HBoxContainer.new()
	vbox.add_child(modes)
	for m: Array in MODES:
		_button(modes, String(m[0]), _set_mode.bind(int(m[1])))

	_title(vbox, "V-Sync — DisplayServer.window_set_vsync_mode (Compatibility 에서는 ENABLED 외 값이 ENABLED 처럼 동작)")
	var row := HBoxContainer.new()
	vbox.add_child(row)
	var vsync := OptionButton.new()
	for v: Array in VSYNC:
		vsync.add_item(String(v[0]))
	vsync.selected = 1
	vsync.item_selected.connect(_set_vsync)
	row.add_child(vsync)
	_button(row, "borderless 토글", _toggle_flag.bind(DisplayServer.WINDOW_FLAG_BORDERLESS, "BORDERLESS"))
	_button(row, "always_on_top 토글", _toggle_flag.bind(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, "ALWAYS_ON_TOP"))

	_title(vbox, "콘텐츠 스케일 — root.content_scale_mode / aspect / factor (window.cpp _update_window_size 가 viewport_attach_to_screen rect 를 계산)")
	var scale_row := HBoxContainer.new()
	vbox.add_child(scale_row)
	var mode_pick := OptionButton.new()
	for s: Array in SCALE_MODES:
		mode_pick.add_item(String(s[0]))
	mode_pick.selected = 0
	mode_pick.item_selected.connect(_set_scale_mode)
	scale_row.add_child(mode_pick)
	var aspect_pick := OptionButton.new()
	for a: Array in ASPECTS:
		aspect_pick.add_item(String(a[0]))
	aspect_pick.selected = 1
	aspect_pick.item_selected.connect(_set_aspect)
	scale_row.add_child(aspect_pick)
	var factor := HSlider.new()
	factor.min_value = 0.5
	factor.max_value = 2.0
	factor.step = 0.1
	factor.value = 1.0
	factor.custom_minimum_size = Vector2(200, 0)
	factor.value_changed.connect(_set_factor)
	scale_row.add_child(factor)

	_title(vbox, "서브윈도우 — 임베디드(부모 뷰포트가 그림) vs 네이티브(DisplayServer.create_sub_window, FEATURE_SUBWINDOWS 필요)")
	var win_row := HBoxContainer.new()
	vbox.add_child(win_row)
	_button(win_row, "임베디드 Window 열기", _open_popup.bind(true))
	_button(win_row, "네이티브 Window 열기", _open_popup.bind(false))
	_button(win_row, "닫기", _close_popup)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info)
	Log.info("루트 Window 는 DisplayServer MAIN_WINDOW_ID=0. 버튼은 DisplayServer 를 직접 호출하고, 정보 표는 0.5초마다 갱신된다.")
	if not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		Log.warn("이 DisplayServer(%s) 는 FEATURE_SUBWINDOWS 가 없다 → 네이티브 창 요청은 임베디드로 대체된다." % DisplayServer.get_name())
	_refresh_info()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_INTERVAL:
		return
	_accum = 0.0
	_refresh_info()


func _refresh_info() -> void:
	var root: Window = get_tree().root
	var lines: PackedStringArray = []
	var screens: int = DisplayServer.get_screen_count()
	lines.append("DisplayServer \"%s\": 화면 %d개, 주 화면 %d, 창이 있는 화면 %d" % [
		DisplayServer.get_name(), screens, DisplayServer.get_primary_screen(), DisplayServer.window_get_current_screen()])
	for i: int in screens:
		lines.append("  screen %d: size=%s pos=%s usable=%s dpi=%d scale=%.2f refresh=%.1fHz" % [
			i, DisplayServer.screen_get_size(i), DisplayServer.screen_get_position(i), DisplayServer.screen_get_usable_rect(i),
			DisplayServer.screen_get_dpi(i), DisplayServer.screen_get_scale(i), DisplayServer.screen_get_refresh_rate(i)])
	lines.append("main window: size=%s pos=%s mode=%d vsync=%d borderless=%s always_on_top=%s" % [
		DisplayServer.window_get_size(), DisplayServer.window_get_position(), DisplayServer.window_get_mode(),
		DisplayServer.window_get_vsync_mode(DisplayServer.MAIN_WINDOW_ID),
		str(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)), str(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP))])
	lines.append("root Window: size=%s content_scale_size=%s scale_mode=%d aspect=%d factor=%.2f gui_embed_subwindows=%s" % [
		root.size, root.content_scale_size, root.content_scale_mode, root.content_scale_aspect, root.content_scale_factor, str(root.gui_embed_subwindows)])
	lines.append("DisplayServer.get_window_list() = %s (네이티브 창 ID 목록)" % str(DisplayServer.get_window_list()))
	_info.text = "\n".join(lines)


func _set_mode(mode: int) -> void:
	DisplayServer.window_set_mode(mode as DisplayServer.WindowMode)
	Log.info("window_set_mode(%d) → 실제 모드 %d (headless 는 무시하고 MINIMIZED 를 돌려준다)" % [mode, DisplayServer.window_get_mode()])


func _set_vsync(index: int) -> void:
	var mode: int = VSYNC[index][1]
	# 엔진: 기본 DisplayServer::window_set_vsync_mode 는 "not supported" 경고만 찍고, X11/Windows/macOS 가 실제 구현한다.
	DisplayServer.window_set_vsync_mode(mode as DisplayServer.VSyncMode)
	Log.info("window_set_vsync_mode(%s) → 실제 %d. 기본값은 project.godot display/window/vsync/vsync_mode." % [String(VSYNC[index][0]), DisplayServer.window_get_vsync_mode(DisplayServer.MAIN_WINDOW_ID)])


func _toggle_flag(flag: int, label: String) -> void:
	var f := flag as DisplayServer.WindowFlags
	var on: bool = not DisplayServer.window_get_flag(f)
	DisplayServer.window_set_flag(f, on)
	Log.info("window_set_flag(%s, %s) → 지금 %s (Window.borderless / always_on_top 프로퍼티와 동일)" % [label, str(on), str(DisplayServer.window_get_flag(f))])


func _set_scale_mode(index: int) -> void:
	get_tree().root.content_scale_mode = SCALE_MODES[index][1] as Window.ContentScaleMode
	Log.info("root.content_scale_mode = %s. CANVAS_ITEMS 는 2D 를 확대해 그리고, VIEWPORT 는 낮은 해상도로 그린 뒤 늘린다." % String(SCALE_MODES[index][0]))


func _set_aspect(index: int) -> void:
	get_tree().root.content_scale_aspect = ASPECTS[index][1] as Window.ContentScaleAspect
	Log.info("root.content_scale_aspect = %s (project.godot display/window/stretch/aspect 와 같은 값)" % String(ASPECTS[index][0]))


func _set_factor(value: float) -> void:
	get_tree().root.content_scale_factor = value
	Log.info("root.content_scale_factor = %.1f (UI 전체 배율; HiDPI 대응에 쓴다)" % value)


func _open_popup(embedded: bool) -> void:
	_close_popup()
	var root: Window = get_tree().root
	if not embedded and not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		Log.warn("FEATURE_SUBWINDOWS 없음 → 임베디드 창으로 대체")
		embedded = true
	# gui_embed_subwindows 는 자식 창이 떠 있는 동안 못 바꾼다 (viewport.cpp set_embedding_subwindows) — 위에서 먼저 닫았다.
	root.gui_embed_subwindows = embedded
	_popup = Window.new()
	_popup.title = "임베디드 Window" if embedded else "네이티브 Window"
	_popup.size = Vector2i(420, 160)
	_popup.transient = true
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text = "임베디드: 부모 Viewport 가 서브윈도우로 그린다 (Viewport::_sub_window_register)." if embedded \
		else "네이티브: DisplayServer.create_sub_window 가 OS 창을 만들고 RS.viewport_attach_to_screen 으로 뷰포트를 붙인다."
	_popup.add_child(lbl)
	_popup.close_requested.connect(_close_popup)
	add_child(_popup)
	_popup.popup_centered()
	Log.info("Window 열림: is_embedded()=%s, get_window_id()=%d (임베디드면 부모 창 ID, 네이티브면 DisplayServer 가 준 새 ID)" % [
		str(_popup.is_embedded()), _popup.get_window_id()])


func _close_popup() -> void:
	if _popup == null:
		return
	_popup.hide()
	remove_child(_popup)
	_popup.queue_free()
	_popup = null
	Log.info("Window 닫음 → 네이티브였다면 DisplayServer.delete_sub_window 로 OS 창이 사라진다")


func _title(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color.SKY_BLUE)
	parent.add_child(lbl)


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
