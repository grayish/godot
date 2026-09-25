extends Control
## 데모 6: export_presets.cfg 읽기 — 익스포트 프리셋은 ConfigFile 포맷이다.
## 엔진: editor/export/editor_export.cpp save_presets()/load_config() 가 [preset.N] 과 [preset.N.options] 를 쓰고 읽는다.
## 옵션 키는 각 플랫폼 플러그인 get_export_options() 가 정의한다 (platform/*/export/export_plugin.cpp,
## editor/export/editor_export_platform_pc.cpp 등). 익스포트는 컴파일이 아니다: 템플릿 바이너리 복사 + PCK 패킹 (학습 5장 5.7).

const CFG_PATH: String = "res://export_presets.cfg"
const HEADERS: Array[String] = ["name", "platform", "custom_features", "export_filter", "embed_pck", "architecture", "texture", "shader_baker", "#options"]

var _vbox: VBoxContainer
var _detail: Label
var _presets: Array[Dictionary] = []


## 순수 파서 (selftest 에서도 호출). ConfigFile.get_value 에 항상 기본값을 넘겨 없는 키가 오류를 찍지 않게 한다.
static func parse_presets(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	var index: int = 0
	while cfg.has_section("preset.%d" % index):
		var s: String = "preset.%d" % index
		var o: String = s + ".options"
		var keys: PackedStringArray = cfg.get_section_keys(o) if cfg.has_section(o) else PackedStringArray()
		var texture: String
		if keys.has("texture_format/s3tc_bptc"):
			texture = "s3tc_bptc=%s etc2_astc=%s" % [str(cfg.get_value(o, "texture_format/s3tc_bptc", false)), str(cfg.get_value(o, "texture_format/etc2_astc", false))]
		elif keys.has("vram_texture_compression/for_desktop"):
			texture = "desktop=%s mobile=%s" % [str(cfg.get_value(o, "vram_texture_compression/for_desktop", false)), str(cfg.get_value(o, "vram_texture_compression/for_mobile", false))]
		else:
			texture = "(프로젝트 설정 rendering/textures/vram_compression 을 따름)"
		out.append({
			"name": str(cfg.get_value(s, "name", "")),
			"platform": str(cfg.get_value(s, "platform", "")),
			"custom_features": str(cfg.get_value(s, "custom_features", "")),
			"export_filter": str(cfg.get_value(s, "export_filter", "")),
			"export_path": str(cfg.get_value(s, "export_path", "")),
			"embed_pck": str(cfg.get_value(o, "binary_format/embed_pck", "n/a")),
			"architecture": str(cfg.get_value(o, "binary_format/architecture", "n/a")),
			"texture": texture,
			"shader_baker": str(cfg.get_value(o, "shader_baker/enabled", "n/a")),
			"#options": str(keys.size()),
			"options": keys,
			"section": o,
		})
		index += 1
	return out


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)

	_presets = parse_presets(CFG_PATH)
	if _presets.is_empty():
		Log.warn("export_presets.cfg 를 읽지 못했거나 프리셋이 없다")
		return
	_title("export_presets.cfg — 프리셋 %d개 (섹션 [preset.N] + [preset.N.options])" % _presets.size())
	var g := GridContainer.new()
	g.columns = HEADERS.size()
	g.add_theme_constant_override("h_separation", 12)
	_vbox.add_child(g)
	for h: String in HEADERS:
		_cell(g, h, Color.SKY_BLUE)
	for p: Dictionary in _presets:
		for h: String in HEADERS:
			_cell(g, String(p[h]), Color.WHITE)
		Log.info("프리셋 \"%s\" (%s): filter=%s embed_pck=%s arch=%s shader_baker=%s custom=\"%s\" → %s" % [
			String(p["name"]), String(p["platform"]), String(p["export_filter"]), String(p["embed_pck"]),
			String(p["architecture"]), String(p["shader_baker"]), String(p["custom_features"]), String(p["export_path"])])

	_title("프리셋을 고르면 [preset.N.options] 전체를 보여준다 — 키 이름은 platform/*/export/export_plugin.cpp 의 PropertyInfo 그대로")
	var pick := OptionButton.new()
	for p: Dictionary in _presets:
		pick.add_item("%s (%s)" % [String(p["name"]), String(p["platform"])])
	pick.selected = 0
	pick.item_selected.connect(_show_options)
	_vbox.add_child(pick)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_detail)
	_show_options(0)
	_show_cli_notes()


func _show_options(index: int) -> void:
	var p: Dictionary = _presets[index]
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	var section: String = String(p["section"])
	var lines: PackedStringArray = []
	for key: String in p["options"]:
		lines.append("%s = %s" % [key, str(cfg.get_value(section, key, ""))])
	_detail.text = "[%s]\n%s" % [section, "\n".join(lines)]
	Log.info("[%s] 옵션 %d개 표시" % [section, lines.size()])


func _show_cli_notes() -> void:
	var v: Dictionary = Engine.get_version_info()
	var templates_dir: String = OS.get_data_dir().path_join("godot/export_templates/%d.%d.%s" % [int(v["major"]), int(v["minor"]), String(v["status"])])
	_title("명령행 익스포트와 템플릿")
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "\n".join([
		"godot --headless --export-release \"Linux\" build/linux/platform_lab.x86_64   ← 프리셋 이름(name 필드)과 출력 경로 (main/main.cpp --export-release)",
		"godot --headless --export-debug \"Web\" build/web/index.html            ← 디버그 템플릿 사용",
		"godot --headless --export-pack \"Linux\" build/only_data.pck              ← 바이너리 없이 PCK/ZIP 만",
		"템플릿 위치 (Linux 예): %s/  (editor/file_system/editor_paths.cpp get_export_templates_dir = 데이터 폴더/export_templates/<버전>)" % templates_dir,
		"익스포트 = 미리 빌드된 템플릿 바이너리 복사 + 프로젝트를 PCK 로 패킹 (+ embed_pck 면 바이너리의 'pck' 섹션에 내장). 컴파일이 아니므로",
		"C++ 모듈·disable_3d·precision=double 같은 변경은 scons 로 직접 템플릿을 만들어 custom_template/debug|release 에 지정해야 한다.",
	])
	_vbox.add_child(note)
	Log.info("익스포트 CLI: godot --headless --export-release \"Linux\" build/linux/platform_lab.x86_64 ; 템플릿은 %s" % templates_dir)


func _title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color.SKY_BLUE)
	_vbox.add_child(lbl)


func _cell(g: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", color)
	g.add_child(l)
