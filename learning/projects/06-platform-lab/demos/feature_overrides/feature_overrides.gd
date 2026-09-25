extends Control
## 데모 2: 기능 태그 오버라이드 (ProjectSettings feature overrides).
## project.godot 의 `greeting.mobile="…"` 처럼 `키.태그` 로 쓴 설정은 core/config/project_settings.cpp _set() 이
## feature_overrides[키] 에 (태그, 전체이름) 쌍으로 쌓고(:327-343), get_setting_with_override() 가
## OS.has_feature(태그) 가 참인 첫 항목의 값을 돌려준다(:419-435). get_setting() 은 오버라이드를 무시한다.
## 엔진 자신도 같은 장치를 쓴다: rendering/renderer/rendering_method.mobile, display/display_server/driver.linuxbsd …

const SETTINGS: Array[String] = ["demo/greeting", "demo/quality"]
const SIM_TAGS: Array[String] = ["pc", "mobile", "web", "editor", "lowend", "template"]
const OVERRIDE_EXAMPLE: String = "res://override_example.cfg"

var _vbox: VBoxContainer
var _sim_label: Label


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)
	for setting: String in SETTINGS:
		_show_setting(setting)
	_build_simulation()
	_show_override_cfg()
	_show_custom_features()


func _show_setting(setting: String) -> void:
	var g := _grid("%s — get_setting vs get_setting_with_override" % setting)
	var base: Variant = ProjectSettings.get_setting(setting)
	var eff: Variant = ProjectSettings.get_setting_with_override(setting)
	_row(g, "get_setting()", str(base), "오버라이드 무시, project.godot 의 원래 값")
	_row(g, "get_setting_with_override()", str(eff), "지금 참인 기능 태그의 값")
	# 어떤 오버라이드 키가 있고 무엇이 이기는지: 이름이 "키." 로 시작하는 설정을 모두 찾는다 (선언 순서 = 우선순위).
	var winner: String = ""
	for key: String in _override_keys(setting):
		var tag: String = key.substr(setting.length() + 1)
		var hit: bool = OS.has_feature(tag)
		var note: String = "OS.has_feature(\"%s\") = %s" % [tag, str(hit)]
		if hit and winner.is_empty():
			winner = key
			note += "  ← 첫 번째로 참 → 채택"
		_row(g, key, str(ProjectSettings.get_setting(key)), note)
	Log.info("%s: 기본 \"%s\" → 적용 \"%s\" (%s)" % [
		setting, str(base), str(eff), ("채택된 오버라이드 " + winner) if not winner.is_empty() else "참인 오버라이드 없음"])


func _override_keys(setting: String) -> PackedStringArray:
	var keys: PackedStringArray = []
	# 엔진: ProjectSettings::_get_property_list() 가 모든 설정을 프로퍼티로 노출하므로 접두사로 거를 수 있다.
	for prop: Dictionary in ProjectSettings.get_property_list():
		var pname: String = String(prop["name"])
		if pname.begins_with(setting + "."):
			keys.append(pname)
	return keys


func _build_simulation() -> void:
	_title("가상 기능 태그로 시뮬레이션 — get_setting_with_override_and_custom_features(이름, [태그]) 는 현재 OS 태그 대신 주어진 태그만 본다")
	var hbox := HBoxContainer.new()
	_vbox.add_child(hbox)
	for tag: String in SIM_TAGS:
		var b := Button.new()
		b.text = tag
		b.pressed.connect(_simulate.bind(tag))
		hbox.add_child(b)
	_sim_label = Label.new()
	_sim_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_sim_label)
	_simulate("mobile")


func _simulate(tag: String) -> void:
	var feats := PackedStringArray([tag])
	var lines: PackedStringArray = []
	for setting: String in SETTINGS:
		var value: Variant = ProjectSettings.get_setting_with_override_and_custom_features(setting, feats)
		lines.append("%s with [%s] = \"%s\"" % [setting, tag, str(value)])
	_sim_label.text = "\n".join(lines)
	Log.info("시뮬레이션 [%s]: %s" % [tag, " | ".join(lines)])


func _show_override_cfg() -> void:
	_title("override.cfg — project.godot 을 읽은 뒤 같은 포맷의 파일로 덮어쓴다 (core/config/project_settings.cpp _setup)")
	var text: String = FileAccess.get_file_as_string(OVERRIDE_EXAMPLE)
	var body := Label.new()
	body.text = text if not text.is_empty() else "(override_example.cfg 를 읽지 못함)"
	body.add_theme_color_override("font_color", Color.WHEAT)
	_vbox.add_child(body)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "\n".join([
		"어디에 두나: PCK 로 실행할 때는 res://override.cfg 와 <실행 파일 폴더>/override.cfg (project_settings.cpp:771-772),",
		"--path 나 에디터로 실행할 때는 <프로젝트 폴더>/override.cfg (:821). 익스포트 뒤에도 실행 파일 옆에 놓기만 하면 설정을 바꿀 수 있어",
		"QA/현장 튜닝에 쓴다. 이 프로젝트는 실제로 적용되지 않도록 override_example.cfg 라는 이름을 썼다 (override.cfg 로 복사하면 바로 적용).",
		"주의: override.cfg 도 기능 태그를 그대로 탄다. 위 예시의 greeting 은 에디터에서 greeting.editor 에 밀리므로, 모든 플랫폼에서 바꾸려면 .태그 키도 함께 써야 한다.",
	])
	_vbox.add_child(note)
	Log.info("override_example.cfg %d 바이트 표시. 실제 파일 이름이 override.cfg 여야 적용된다." % text.length())


func _show_custom_features() -> void:
	_title("익스포트 프리셋의 \"Custom Features\" 필드 (export_presets.cfg custom_features=\"lowend\")")
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "\n".join([
		"쉼표로 적은 임의 태그는 editor/export/editor_export_platform.cpp:784 가 프리셋에서 읽어, 팩에 넣는 project.binary 의",
		"_custom_features 항목으로 저장한다. 실행 시 core/config/project_settings.cpp:317 이 이를 custom_features 집합에 넣고,",
		"OS.has_feature() 는 내장 태그가 모두 아니면 마지막에 ProjectSettings::has_custom_feature() 를 본다 (core/os/os.cpp 끝부분).",
		"그래서 demo/quality.lowend 처럼 엔진이 모르는 태그 오버라이드가 특정 프리셋으로 익스포트했을 때만 살아난다.",
		"에디터/--path 실행은 프리셋을 거치지 않으므로 lowend 는 항상 false 다. 위 [lowend] 버튼이 그 결과를 미리 보여준다.",
	])
	_vbox.add_child(note)
	Log.info("OS.has_feature(\"lowend\") = %s (익스포트 프리셋을 거치지 않았으므로 false 가 정상)" % str(OS.has_feature("lowend")))


func _title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color.SKY_BLUE)
	_vbox.add_child(lbl)


func _grid(title: String) -> GridContainer:
	_title(title)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	_vbox.add_child(g)
	return g


func _row(g: GridContainer, a: String, b: String, c: String) -> void:
	_cell(g, a, Color.WHEAT)
	_cell(g, b, Color.WHITE)
	_cell(g, c, Color.GRAY)


func _cell(g: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", color)
	g.add_child(l)
