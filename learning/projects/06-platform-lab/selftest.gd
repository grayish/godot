extends SceneTree
## 헤드리스 셀프테스트: godot --headless --path <dir> -s res://selftest.gd
## UI 없이 프로젝트의 비-UI 로직만 검사한다. 한 프레임에 테스트 하나씩 돌려(_process) 지연 호출이 필요한
## 테스트도 수용한다. 마지막에 "SELFTEST PASS/FAIL <dir>" 을 찍고 quit(0/1).
## 엔진: -s 스크립트가 SceneTree 를 상속하면 main/main.cpp Main::start() 가 메인 씬 대신 이 MainLoop 를 띄운다.

const PROJECT_DIR: String = "06-platform-lab"
const PRESETS_PATH: String = "res://export_presets.cfg"
const KNOWN_PLATFORMS: Array[String] = ["Linux", "Windows Desktop", "macOS", "Android", "iOS", "Web", "visionOS"]
const PACK_MAGIC: int = 0x43504447 # core/io/file_access_pack.h PACK_HEADER_MAGIC ("GDPC")

var _tests: Array[Callable] = []
var _index: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_tests = [
		_test_engine_version,
		_test_os_features,
		_test_feature_override,
		_test_pck_roundtrip,
		_test_make_pack_tool,
		_test_export_presets,
		_test_inputmap_remap,
		_test_headless_report,
	]
	print("SELFTEST start: %d tests" % _tests.size())


func _process(_delta: float) -> bool:
	if _index < _tests.size():
		var test: Callable = _tests[_index]
		_index += 1
		print("-- %s" % test.get_method())
		test.call()
		return false
	if _failures.is_empty():
		print("SELFTEST PASS " + PROJECT_DIR)
		quit(0)
	else:
		print("SELFTEST FAIL %s: %s" % [PROJECT_DIR, ", ".join(_failures)])
		quit(1)
	return true


func _check(cond: bool, what: String) -> void:
	if cond:
		print("   ok   " + what)
	else:
		print("   FAIL " + what)
		_failures.append(what)


func _test_engine_version() -> void:
	var v: Dictionary = Engine.get_version_info()
	_check(int(v["major"]) == 4, "Engine.get_version_info().major == 4 (%s)" % String(v["string"]))
	_check(not Engine.get_architecture_name().is_empty(), "Engine.get_architecture_name() = " + Engine.get_architecture_name())


## 데스크톱 태그는 단정하지 않고 출력만 한다 (CI 가 어떤 OS 인지 모르므로).
func _test_os_features() -> void:
	var desktop: bool = OS.has_feature("linuxbsd") or OS.has_feature("windows") or OS.has_feature("macos")
	print("   info OS.get_name()=%s desktop_tag=%s pc=%s editor=%s 64=%s" % [
		OS.get_name(), str(desktop), str(OS.has_feature("pc")), str(OS.has_feature("editor")), str(OS.has_feature("64"))])
	_check(OS.has_feature(OS.get_name().to_lower()) or OS.has_feature("web"), "OS.has_feature(get_name().to_lower()) 가 참")
	_check(not OS.has_feature("headless"), "\"headless\" 는 OS 기능 태그가 아니다 (DisplayServer.get_name() 으로 판별)")


func _test_feature_override() -> void:
	var base: Variant = ProjectSettings.get_setting("demo/greeting")
	var eff: Variant = ProjectSettings.get_setting_with_override("demo/greeting")
	_check(base is String and base == "데스크톱 기본값", "get_setting(demo/greeting) 은 기본값")
	_check(eff is String, "get_setting_with_override(demo/greeting) 은 String (= %s)" % str(eff))
	var mobile: Variant = ProjectSettings.get_setting_with_override_and_custom_features("demo/greeting", PackedStringArray(["mobile"]))
	_check(mobile == "모바일 값", "custom features [mobile] → greeting.mobile")
	var web: Variant = ProjectSettings.get_setting_with_override_and_custom_features("demo/quality", PackedStringArray(["web"]))
	_check(web == "medium", "custom features [web] → quality.web")
	var lowend: Variant = ProjectSettings.get_setting_with_override_and_custom_features("demo/quality", PackedStringArray(["lowend"]))
	_check(lowend == "low", "custom features [lowend] → quality.lowend (임의 태그)")
	var none: Variant = ProjectSettings.get_setting_with_override_and_custom_features("demo/quality", PackedStringArray())
	_check(none == "high", "태그 없음 → 기본값")
	_check(not OS.has_feature("lowend"), "프리셋을 거치지 않았으므로 OS.has_feature(\"lowend\") 는 false")


## PCKPacker 왕복: res://dlc_source 의 파일을 user://selftest.pck 에 넣고 load_resource_pack 후 다시 읽는다.
func _test_pck_roundtrip() -> void:
	var pck_path: String = "user://selftest.pck"
	var src_txt: String = "res://dlc_source/greeting.txt"
	var dst_txt: String = "res://selftest_dlc/greeting.txt"
	var dst_tres: String = "res://selftest_dlc/palette.tres"
	var packer := PCKPacker.new()
	_check(packer.pck_start(pck_path) == OK, "PCKPacker.pck_start(user://selftest.pck)")
	_check(packer.add_file(dst_txt, src_txt) == OK, "add_file(greeting.txt)")
	_check(packer.add_file(dst_tres, "res://dlc_source/palette.tres") == OK, "add_file(palette.tres)")
	_check(packer.flush() == OK, "flush()")
	_check(FileAccess.file_exists(pck_path), "user://selftest.pck 생성됨")
	var f: FileAccess = FileAccess.open(pck_path, FileAccess.READ)
	if f != null:
		var magic: int = f.get_32()
		var version: int = f.get_32()
		f.close()
		_check(magic == PACK_MAGIC, "헤더 매직 == GDPC (0x%08X)" % magic)
		_check(version == 4, "PCK 포맷 버전 == 4 (%d)" % version)
	_check(not FileAccess.file_exists(dst_txt), "로드 전 %s 없음" % dst_txt)
	_check(ProjectSettings.load_resource_pack(pck_path, true), "ProjectSettings.load_resource_pack()")
	_check(FileAccess.file_exists(dst_txt), "로드 후 %s 있음" % dst_txt)
	var expected: String = FileAccess.get_file_as_string(src_txt)
	var got: String = FileAccess.get_file_as_string(dst_txt)
	_check(not got.is_empty() and got == expected, "팩에서 읽은 내용 == 원본 (%d 바이트)" % got.length())
	_check(ResourceLoader.exists(dst_tres), "ResourceLoader.exists(팩 안의 .tres)")
	var res: Resource = load(dst_tres)
	_check(res is Gradient and (res as Gradient).get_point_count() == 4, "팩 안의 .tres 가 Gradient(4 포인트) 로 로드됨")
	print("   info DirAccess.get_files_at(res://selftest_dlc) = %s" % str(DirAccess.get_files_at("res://selftest_dlc")))


## tools/make_pack.gd 의 static 함수만 호출한다 (SceneTree 상속 스크립트는 인스턴스화하지 않는다).
func _test_make_pack_tool() -> void:
	var script: GDScript = load("res://tools/make_pack.gd")
	_check(script != null, "tools/make_pack.gd 로드")
	if script == null:
		return
	var out: String = "user://selftest_make.pck"
	var err: Error = script.build_pack(out)
	_check(err == OK, "make_pack.build_pack(%s) == OK (%s)" % [out, error_string(err)])
	_check(FileAccess.file_exists(out), "user://selftest_make.pck 생성됨")


func _test_export_presets() -> void:
	var cfg := ConfigFile.new()
	_check(cfg.load(PRESETS_PATH) == OK, "export_presets.cfg 가 ConfigFile 로 파싱됨")
	var count: int = 0
	for section: String in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			count += 1
			var platform: String = str(cfg.get_value(section, "platform", ""))
			_check(KNOWN_PLATFORMS.has(platform), "%s platform=\"%s\" 는 export_plugin get_name() 값" % [section, platform])
			_check(cfg.has_section(section + ".options"), section + ".options 섹션 존재")
	_check(count >= 6, "프리셋 섹션 %d개 >= 6" % count)
	var script: GDScript = load("res://demos/export_presets_reader/export_presets_reader.gd")
	var presets: Array[Dictionary] = script.parse_presets(PRESETS_PATH)
	_check(presets.size() == count, "parse_presets() 가 %d개 반환" % presets.size())
	var names: PackedStringArray = []
	for p: Dictionary in presets:
		names.append(String(p["platform"]))
	for expected: String in ["Linux", "Windows Desktop", "macOS", "Android", "iOS", "Web"]:
		_check(names.has(expected), "프리셋 플랫폼 포함: " + expected)


func _test_inputmap_remap() -> void:
	var action := StringName("jump")
	_check(InputMap.has_action(action), "project.godot [input] jump 액션이 InputMap 에 로드됨")
	var before: int = InputMap.action_get_events(action).size()
	_check(before == 1, "jump 이벤트 1개 (%d)" % before)
	InputMap.action_erase_events(action)
	_check(InputMap.action_get_events(action).is_empty(), "action_erase_events 후 비어 있음")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	InputMap.action_add_event(action, ev)
	_check(InputMap.action_has_event(action, ev), "action_add_event(W) 반영")
	var text: String = InputMap.action_get_events(action)[0].as_text()
	_check(not text.is_empty(), "as_text() = " + text)
	InputMap.load_from_project_settings()
	_check(InputMap.action_get_events(action).size() == before, "load_from_project_settings() 로 복원")


func _test_headless_report() -> void:
	var script: GDScript = load("res://tools/headless_task.gd")
	_check(script != null, "tools/headless_task.gd 로드")
	if script == null:
		return
	var report: Dictionary = script.build_report()
	for key: String in ["engine", "os", "display_server", "rendering", "features"]:
		_check(report.has(key), "report 에 \"%s\" 키" % key)
	var json: String = JSON.stringify(report, "\t")
	var back: Variant = JSON.parse_string(json)
	_check(back is Dictionary and (back as Dictionary).has("os"), "JSON 왕복 (%d 바이트)" % json.length())
	_check(String(report["display_server"]) == DisplayServer.get_name(), "report.display_server == " + DisplayServer.get_name())
