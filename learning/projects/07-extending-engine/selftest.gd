extends SceneTree

## 헤드리스 셀프테스트: godot --headless --path <dir> -s res://selftest.gd
## 프레임마다 테스트 하나를 실행하는 작은 비동기 러너. MainLoop._process 가 true 를 돌려주면 루프가 끝난다
## (엔진: main/main.cpp Main::iteration() → MainLoop::process()).
## UI 가 아닌 로직만 검사한다: 플러그인 메타데이터, 소스 경로 휴리스틱, 모듈/확장 소스 골격, 데모 헬퍼.

const PROJECT_DIR: String = "07-extending-engine"
const ADDON_DIR: String = "res://addons/learning_tools/"
const MODULE_DIR: String = "res://custom_modules/summator/"
const EXT_DIR: String = "res://gdextension/"

# class_name 대신 preload: .godot/ 캐시가 없는 명령행 실행에서도 해석된다.
# 단, `Log` autoload 를 참조하는 스크립트(main.gd, 데모 루트)는 preload 하면 안 된다 — `-s` 스크립트는 autoload 가
# 등록되기 전에 컴파일되므로 그 시점에 함께 컴파일되는 preload 대상에서 "Identifier not found: Log" 가 난다.
# 그런 스크립트는 테스트 안에서 load() 하고 get()/call() 로 상수·정적 함수에 접근한다 (_load_script).
const SourceHint := preload("res://addons/learning_tools/source_hint.gd")
const ToolWidgetScript := preload("res://demos/tool_scripts/tool_widget.gd")
const LogScript := preload("res://log.gd")
const EXTENSION_CHECK_PATH: String = "res://demos/extension_check/extension_check.gd"
const CONTRIBUTING_GUIDE_PATH: String = "res://demos/contributing_guide/contributing_guide.gd"
const MAIN_PATH: String = "res://main.gd"

var _tests: Array[Callable] = []
var _index: int = 0
var _failures: Array[String] = []
var _current: String = ""


func _initialize() -> void:
	_tests = [
		test_plugin_cfg,
		test_plugin_enabled_in_project,
		test_addon_scripts_compile,
		test_source_hint_mapping,
		test_source_hint_chain,
		test_source_hint_repo_files,
		test_module_files,
		test_module_doc_xml,
		test_gdextension_example,
		test_classdb_report,
		test_log_autoload,
		test_tool_widget,
		test_demo_helpers,
	]
	print("SELFTEST start: %d tests" % _tests.size())


func _process(_delta: float) -> bool:
	if _index >= _tests.size():
		_finish()
		return true
	var test: Callable = _tests[_index]
	_current = String(test.get_method())
	_index += 1
	print("- " + _current)
	test.call()
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(_current + ": " + message)
		print("  FAIL " + message)


## Log 를 쓰는 스크립트는 런타임에 load 한다 (위 주석). 실패하면 null 을 돌려주고 실패를 기록한다.
func _load_script(path: String) -> GDScript:
	var script: GDScript = load(path)
	_check(script != null, "스크립트 로드 실패: " + path)
	return script


func _finish() -> void:
	if _failures.is_empty():
		print("SELFTEST PASS " + PROJECT_DIR)
		quit(0)
	else:
		print("SELFTEST FAIL %s: %s" % [PROJECT_DIR, str(_failures)])
		quit(1)


# --- A. 에디터 플러그인 ---------------------------------------------------------


func test_plugin_cfg() -> void:
	# 에디터는 EditorNode::set_addon_plugin_enabled() 에서 같은 ConfigFile 로 plugin.cfg 를 읽는다.
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(ADDON_DIR + "plugin.cfg")
	_check(err == OK, "plugin.cfg 로드 실패: " + error_string(err))
	if err != OK:
		return
	for key: String in ["name", "description", "author", "version", "script"]:
		_check(cfg.has_section_key("plugin", key), "plugin.cfg 에 plugin/%s 가 없음" % key)
	var script_rel: String = String(cfg.get_value("plugin", "script", ""))
	var script_path: String = ADDON_DIR.path_join(script_rel)
	_check(FileAccess.file_exists(script_path), "plugin/script 가 가리키는 파일이 없음: " + script_path)


func test_plugin_enabled_in_project() -> void:
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	_check(enabled.has("res://addons/learning_tools/plugin.cfg"), "project.godot [editor_plugins] enabled 에 플러그인이 없음: %s" % [enabled])


func test_addon_scripts_compile() -> void:
	if not ClassDB.class_exists("EditorPlugin"):
		print("  (skip) 에디터 빌드가 아니라 EditorPlugin 클래스가 없음")
		return
	for f: String in ["plugin.gd", "inspector_plugin.gd", "export_plugin.gd", "source_hint_label_2d.gd", "source_hint.gd"]:
		var res: Resource = load(ADDON_DIR + f)
		_check(res is Script, "스크립트 컴파일 실패: " + f)
		if res is Script:
			_check((res as Script).can_instantiate(), "인스턴스화 불가(컴파일 오류?): " + f)
	var plugin: Script = load(ADDON_DIR + "plugin.gd")
	if plugin != null:
		_check(plugin.is_tool(), "plugin.gd 는 @tool 이어야 에디터가 인스턴스를 만든다")
		_check(plugin.get_instance_base_type() == &"EditorPlugin", "plugin.gd 의 베이스는 EditorPlugin 이어야 함")
	var label2d: Script = load(ADDON_DIR + "source_hint_label_2d.gd")
	if label2d != null:
		_check(label2d.is_tool() and label2d.get_instance_base_type() == &"Node2D", "source_hint_label_2d.gd 는 @tool Node2D 여야 add_custom_type 과 맞음")


func test_source_hint_mapping() -> void:
	var cases: Dictionary = {
		"Button": "scene/gui/button.h",
		"CharacterBody2D": "scene/2d/character_body_2d.h",
		"GPUParticles2D": "scene/2d/gpu_particles_2d.h",
		"Node3D": "scene/3d/node_3d.h",
		"MeshInstance3D": "scene/3d/mesh_instance_3d.h",
		"Node": "scene/main/node.h",
		"Resource": "scene/resources/resource.h",
		"BoxMesh": "scene/resources/box_mesh.h",
		"NoSuchClassXYZ": "scene/main/no_such_class_xyz.h",
	}
	for cls: String in cases:
		var got: String = SourceHint.engine_source_path(cls)
		_check(got == String(cases[cls]), "%s → %s (기대 %s)" % [cls, got, cases[cls]])
	_check(SourceHint.doc_xml_path("Node") == "doc/classes/Node.xml", "doc_xml_path")
	_check(SourceHint.engine_dir_for("Control") == "scene/gui/", "루트 클래스 자체도 자기 디렉터리로")


func test_source_hint_chain() -> void:
	var chain: String = " > ".join(SourceHint.inheritance_chain("Button"))
	_check(chain == "Button > BaseButton > Control > CanvasItem > Node > Object", "Button 상속 사슬: " + chain)
	_check(SourceHint.inheritance_chain("Object").size() == 1, "Object 의 사슬은 자기 자신뿐")
	_check(SourceHint.inheritance_chain("NoSuchClassXYZ").size() == 1, "모르는 클래스는 오류 없이 [이름] 만")
	var text: String = SourceHint.describe_text("Node2D")
	_check(text.contains("scene/2d/node_2d.h") and text.contains("doc/classes/Node2D.xml"), "describe_text 내용: " + text)


func test_source_hint_repo_files() -> void:
	var root: String = SourceHint.repo_root()
	if not DirAccess.dir_exists_absolute(root.path_join("doc/classes")):
		print("  (skip) 엔진 저장소 밖에서 실행됨: " + root)
		return
	_check(SourceHint.exists_in_repo("scene/gui/button.h"), "저장소에 scene/gui/button.h 가 있어야 함 (root=%s)" % root)
	_check(SourceHint.exists_in_repo("doc/classes/Button.xml"), "저장소에 doc/classes/Button.xml 이 있어야 함")
	_check(not SourceHint.exists_in_repo("scene/main/no_such_class_xyz.h"), "없는 파일은 false")
	var d: Dictionary = SourceHint.describe("Button")
	_check(bool(d["source_exists"]) and bool(d["doc_exists"]), "describe(Button) 의 존재 플래그")


# --- B. 커스텀 C++ 모듈 ---------------------------------------------------------


func test_module_files() -> void:
	for f: String in ["config.py", "SCsub", "register_types.h", "register_types.cpp", "summator.h", "summator.cpp", "doc_classes/Summator.xml"]:
		_check(FileAccess.file_exists(MODULE_DIR + f), "모듈 파일 없음: " + f)
	var header: String = FileAccess.get_file_as_string(MODULE_DIR + "summator.h")
	_check(header.contains("GDCLASS(Summator, RefCounted)"), "summator.h 에 GDCLASS(Summator, RefCounted) 가 있어야 함")
	_check(header.contains("#pragma once"), "헤더는 #pragma once (header_guards.py 훅 규칙)")
	_check(header.begins_with("/****") and header.contains("Copyright (c) 2014-present Godot Engine contributors"), "라이선스 박스 주석 (copyright_headers.py 훅 규칙)")
	_check(header.contains("static void _bind_methods();"), "_bind_methods 선언")
	var reg: String = FileAccess.get_file_as_string(MODULE_DIR + "register_types.cpp")
	_check(reg.contains("GDREGISTER_CLASS(Summator)"), "register_types.cpp 의 GDREGISTER_CLASS(Summator)")
	_check(reg.contains("MODULE_INITIALIZATION_LEVEL_SCENE"), "SCENE 레벨에서 등록")
	_check(reg.contains("void initialize_summator_module(ModuleInitializationLevel") and reg.contains("void uninitialize_summator_module(ModuleInitializationLevel"), "initialize/uninitialize_summator_module 시그니처")
	var cfg: String = FileAccess.get_file_as_string(MODULE_DIR + "config.py")
	_check(cfg.contains("def can_build") and cfg.contains("def configure") and cfg.contains("def get_doc_classes") and cfg.contains("def get_doc_path"), "config.py 의 네 함수")
	_check(cfg.contains("\"Summator\"") and cfg.contains("\"doc_classes\""), "config.py 가 Summator / doc_classes 를 돌려줌")
	var scsub: String = FileAccess.get_file_as_string(MODULE_DIR + "SCsub")
	_check(scsub.contains("add_source_files(env.modules_sources, \"*.cpp\")"), "SCsub 가 *.cpp 를 env.modules_sources 에 추가")
	_check(not header.contains("\r"), "LF 줄바꿈 (file_format.py 훅 규칙)")


func test_module_doc_xml() -> void:
	# doc/class.xsd 스키마 검증은 xmllint 몫이고, 여기서는 XMLParser 로 구조만 확인한다.
	var parser := XMLParser.new()
	var err: Error = parser.open(MODULE_DIR + "doc_classes/Summator.xml")
	_check(err == OK, "Summator.xml 열기 실패: " + error_string(err))
	if err != OK:
		return
	var class_name_attr: String = ""
	var inherits: String = ""
	var methods: PackedStringArray = PackedStringArray()
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match parser.get_node_name():
			"class":
				class_name_attr = parser.get_named_attribute_value_safe("name")
				inherits = parser.get_named_attribute_value_safe("inherits")
			"method":
				methods.append(parser.get_named_attribute_value_safe("name"))
	_check(class_name_attr == "Summator" and inherits == "RefCounted", "class name=%s inherits=%s" % [class_name_attr, inherits])
	_check(methods.size() == 3 and methods.has("add") and methods.has("reset") and methods.has("get_total"), "메서드 문서: %s" % [methods])


# --- C. GDExtension ---------------------------------------------------------


func test_gdextension_example() -> void:
	var path: String = EXT_DIR + "summator_ext.gdextension.example"
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(path)
	_check(err == OK, ".gdextension.example 파싱 실패: " + error_string(err))
	if err != OK:
		return
	_check(cfg.has_section_key("configuration", "entry_symbol"), "[configuration] entry_symbol 없음")
	var entry: String = String(cfg.get_value("configuration", "entry_symbol", ""))
	_check(entry == "summator_ext_init", "entry_symbol = " + entry)
	_check(cfg.has_section_key("configuration", "compatibility_minimum"), "[configuration] compatibility_minimum 없음")
	_check(cfg.has_section("libraries"), "[libraries] 섹션 없음")
	var keys: PackedStringArray = cfg.get_section_keys("libraries")
	_check(keys.size() >= 6, "linux/windows/macos × debug/release 6개 이상 기대, 실제 %d" % keys.size())
	for key: String in keys:
		var lib: String = String(cfg.get_value("libraries", key, ""))
		_check(lib.begins_with("res://gdextension/bin/libsummator_ext."), "라이브러리 경로 규칙 위반: %s = %s" % [key, lib])
	for f: String in ["SConstruct", "src/register_types.h", "src/register_types.cpp", "src/summator_ext.h", "src/summator_ext.cpp"]:
		_check(FileAccess.file_exists(EXT_DIR + f), "확장 소스 없음: " + f)
	var header: String = FileAccess.get_file_as_string(EXT_DIR + "src/summator_ext.h")
	_check(header.contains("GDCLASS(SummatorExt, RefCounted)"), "summator_ext.h 의 GDCLASS(SummatorExt, RefCounted)")
	var reg: String = FileAccess.get_file_as_string(EXT_DIR + "src/register_types.cpp")
	_check(reg.contains("GDREGISTER_CLASS(SummatorExt)"), "register_types.cpp 의 GDREGISTER_CLASS(SummatorExt)")
	# entry_symbol 과 extern "C" 함수 이름이 어긋나는 것이 가장 흔한 실수다.
	_check(reg.contains("GDE_EXPORT " + entry + "("), "register_types.cpp 에 extern \"C\" %s 가 없음" % entry)
	_check(reg.contains("GDExtensionBinding::InitObject"), "godot-cpp InitObject 사용")
	if FileAccess.file_exists(EXT_DIR + "summator_ext.gdextension"):
		print("  (info) summator_ext.gdextension 이 있음 — 라이브러리를 빌드해 활성화한 상태")


func test_classdb_report() -> void:
	var probe: GDScript = _load_script(EXTENSION_CHECK_PATH)
	if probe == null:
		return
	var candidates: Array = probe.get("CANDIDATES")
	# 단언하지 않고 출력만: 이 바이너리에 모듈/확장이 들어 있는지는 빌드에 달렸다.
	for cls: String in candidates:
		var exists: bool = ClassDB.class_exists(cls)
		var extra: String = ""
		if exists:
			extra = ", " + String(probe.call("api_type_name", ClassDB.class_get_api_type(cls)))
		print("  ClassDB.class_exists(\"%s\") = %s%s" % [cls, exists, extra])
		if exists and ClassDB.can_instantiate(cls):
			var obj: Variant = ClassDB.instantiate(cls)
			if obj is Object:
				# 있다면 동작은 단언한다: add(5)+add(7) = 12.
				_check(int(probe.call("exercise_summator", obj)) == 12, "%s.get_total() 이 12 여야 함" % cls)
	# 내장 모듈 클래스(modules/jsonrpc)는 이 빌드에서 확인 가능하다.
	if ClassDB.class_exists("JSONRPC"):
		_check(ClassDB.class_get_api_type("JSONRPC") == ClassDB.API_CORE, "모듈 클래스는 API_CORE")
	else:
		print("  (skip) JSONRPC 모듈이 빠진 빌드")
	_check(String(probe.call("api_type_name", ClassDB.API_EXTENSION)).begins_with("API_EXTENSION"), "api_type_name(API_EXTENSION)")
	_check(String(probe.call("api_type_name", ClassDB.API_CORE)).begins_with("API_CORE"), "api_type_name(API_CORE)")


# --- D. 데모 헬퍼 / autoload -------------------------------------------------


func test_log_autoload() -> void:
	# `-s` 로 실행되는 메인 루프 스크립트는 autoload 가 등록되기 전에 컴파일되므로 `Log` 식별자를 직접 쓰면
	# "Identifier not found: Log" 컴파일 오류가 난다 (main/main.cpp Main::start(): 스크립트 로드 → autoload 추가 순서).
	# 그래서 트리에서 노드를 찾아 동적으로(Variant) 호출한다 — 이 파일에서 정적 타입을 못 쓰는 유일한 곳.
	var log_node: Variant = get_root().get_node_or_null("Log")
	_check(log_node is Node, "Log autoload 가 /root 에 없음")
	if not (log_node is Node):
		return
	_check((log_node as Node).get_script() == LogScript, "/root/Log 의 스크립트는 res://log.gd")
	var received: Array[Array] = []
	var on_message: Callable = func(text: String, level: int) -> void:
		received.append([text, level])
	log_node.message.connect(on_message)
	log_node.info("selftest-info")
	log_node.warn("selftest-warn")
	log_node.section("selftest-section")
	log_node.message.disconnect(on_message)
	_check(received.size() == 3, "message 시그널 3회 기대, 실제 %d" % received.size())
	if received.size() == 3:
		_check(received[0][0] == "selftest-info" and int(received[0][1]) == LogScript.Level.INFO, "info 레벨/본문")
		_check(String(received[1][0]).contains("selftest-warn") and int(received[1][1]) == LogScript.Level.WARN, "warn 레벨/본문")
		_check(String(received[2][0]).contains("selftest-section") and int(received[2][1]) == LogScript.Level.SECTION, "section 레벨/본문")


func test_tool_widget() -> void:
	var widget := ToolWidgetScript.new()
	get_root().add_child(widget)
	_check(widget.get_script().is_tool(), "tool_widget.gd 는 @tool")
	_check(widget._get_configuration_warnings().size() == 1, "label_text 가 비면 경고 1개")
	widget.label_text = "채움"
	_check(widget._get_configuration_warnings().is_empty(), "label_text 를 채우면 경고 없음")
	_check(widget.recount_action.is_valid(), "@export_tool_button 의 Callable 이 유효")
	widget.add_child(Node.new())
	widget.recount_action.call()
	_check(widget.child_count == 1, "recount 후 child_count == 1, 실제 %d" % widget.child_count)
	_check(widget.runtime_ticks >= 0 and widget.editor_ticks == 0, "런타임에서는 editor_ticks 가 증가하지 않음")
	widget.queue_free()


func test_demo_helpers() -> void:
	var guide: GDScript = _load_script(CONTRIBUTING_GUIDE_PATH)
	var probe: GDScript = _load_script(EXTENSION_CHECK_PATH)
	var main_script: GDScript = _load_script(MAIN_PATH)
	if guide == null or probe == null or main_script == null:
		return
	var checklist: Array = guide.get("CHECKLIST")
	var links: Array = guide.get("LINKS")
	_check(checklist.size() >= 7, "체크리스트 7항목 이상")
	for link: Dictionary in links:
		_check(String(link["url"]).begins_with("https://") and not String(link["title"]).is_empty(), "링크 형식: %s" % [link])
	_check(bool(guide.call("can_open_urls")) == (DisplayServer.get_name() != "headless"), "can_open_urls 는 headless 에서 false")
	var candidates: Array = probe.get("CANDIDATES")
	_check(candidates.size() == 2 and candidates.has("Summator") and candidates.has("SummatorExt"), "확인 대상 클래스 목록")
	_check(String(probe.get("MODULE_BUILD_CMD")).contains("custom_modules=learning/projects/07-extending-engine/custom_modules"), "모듈 빌드 명령")
	var demos: Array = main_script.get("DEMOS")
	_check(demos.size() == 3, "허브 DEMOS 는 3개")
	for demo: Dictionary in demos:
		var scene_path: String = String(demo["scene_path"])
		_check(ResourceLoader.exists(scene_path), "허브 DEMOS 의 씬이 없음: " + scene_path)
		_check(not String(demo["title"]).is_empty() and not String(demo["description"]).is_empty(), "DEMOS 항목의 제목/설명")
