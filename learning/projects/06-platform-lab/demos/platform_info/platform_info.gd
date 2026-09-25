extends Control
## 데모 1: 플랫폼 정보.
## OS(core/os/os.h) · Engine(core/config/engine.h) · RenderingServer · DisplayServer(servers/display/display_server.h)
## 네 싱글턴이 "지금 이 바이너리·이 기기" 에 대해 무엇을 답하는지 표로 보여준다.
## 실제 값은 platform/<name>/os_*.cpp, platform/<name>/display_server_*.cpp 가 채운다 (학습 5장 5.2, 5.4).

## OS.has_feature 로 검사할 기능 태그. core/os/os.cpp OS::has_feature() 와 platform/*/os_*.cpp
## _check_internal_feature_support(), drivers/gles3/storage/utilities.cpp has_os_feature() 에 실제로 있는 이름만 넣었다.
const FEATURE_TAGS: Array[Array] = [
	["windows", "Windows 빌드 (OS::get_identifier() 와 같은 이름)"],
	["linuxbsd", "Linux/BSD 빌드 (platform/linuxbsd, get_identifier)"],
	["linux", "Linux 커널 (os_linuxbsd.cpp get_name().to_lower())"],
	["bsd", "BSD 계열 (FreeBSD/NetBSD/OpenBSD 에서 true)"],
	["macos", "macOS 빌드"],
	["android", "Android 빌드"],
	["ios", "iOS 빌드"],
	["web", "Web(Emscripten) 빌드 (os_web.cpp)"],
	["pc", "데스크톱 계열 (windows/linuxbsd/macos 가 true)"],
	["mobile", "모바일 계열 (android/ios 가 true)"],
	["editor", "에디터 빌드 (TOOLS_ENABLED)"],
	["editor_hint", "에디터 안에서 tool 스크립트로 실행 중"],
	["editor_runtime", "에디터 빌드지만 게임으로 실행 중"],
	["template", "익스포트 템플릿 빌드 (에디터 아님)"],
	["template_debug", "디버그 템플릿"],
	["template_release", "릴리스 템플릿"],
	["debug", "DEBUG_ENABLED (에디터 또는 디버그 템플릿)"],
	["release", "릴리스 템플릿 (template_release 와 같음)"],
	["double", "precision=double 빌드"],
	["single", "precision=single 빌드 (기본)"],
	["64", "64비트 포인터"],
	["32", "32비트 포인터"],
	["x86_64", "x86-64 아키텍처"],
	["x86", "x86 계열 (32/64 공통)"],
	["arm64", "AArch64"],
	["arm", "ARM 계열 (32/64 공통)"],
	["wasm32", "WebAssembly 32비트"],
	["threads", "THREADS_ENABLED (웹 nothreads 템플릿은 false)"],
	["nothreads", "스레드 없는 빌드"],
	["movie", "--write-movie 로 실행 중"],
	["system_fonts", "시스템 폰트 접근 가능 (fontconfig/DirectWrite 등)"],
	["s3tc", "S3TC/DXT 텍스처 압축 (RenderingServer.has_os_feature 경유)"],
	["etc2", "ETC2 텍스처 압축 (RenderingServer 경유)"],
	["astc", "ASTC 텍스처 압축 (RenderingServer 경유)"],
]

var _vbox: VBoxContainer


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_vbox)
	_show_os()
	_show_engine()
	_show_rendering()
	_show_feature_tags()
	_show_display_server()


func _show_os() -> void:
	var g := _grid("OS 싱글턴 — core/os/os.h, 구현 platform/<name>/os_*.cpp (drivers/unix/os_unix.cpp 공통부)", 2)
	_kv(g, "OS.get_name()", OS.get_name())
	_kv(g, "OS.get_distribution_name()", OS.get_distribution_name())
	_kv(g, "OS.get_version()", OS.get_version())
	_kv(g, "OS.get_version_alias()", OS.get_version_alias())
	_kv(g, "OS.get_model_name()", OS.get_model_name())
	_kv(g, "OS.get_processor_count()", str(OS.get_processor_count()))
	_kv(g, "OS.get_processor_name()", OS.get_processor_name())
	_kv(g, "OS.get_executable_path()", OS.get_executable_path())
	_kv(g, "OS.get_user_data_dir()", OS.get_user_data_dir())
	_kv(g, "OS.get_data_dir()", OS.get_data_dir())
	_kv(g, "OS.get_cache_dir()", OS.get_cache_dir())
	_kv(g, "OS.get_config_dir()", OS.get_config_dir())
	_kv(g, "OS.get_locale() / get_locale_language()", "%s / %s" % [OS.get_locale(), OS.get_locale_language()])
	_kv(g, "OS.get_cmdline_args()", str(OS.get_cmdline_args()))
	_kv(g, "OS.get_cmdline_user_args() (-- 뒤)", str(OS.get_cmdline_user_args()))
	_kv(g, "OS.get_environment(\"PATH\") 앞 60자", OS.get_environment("PATH").left(60) + "…")
	_kv(g, "OS.is_debug_build()", str(OS.is_debug_build()))
	Log.info("OS: %s %s (%s), CPU %d개 \"%s\", 사용자 데이터 %s" % [
		OS.get_name(), OS.get_version(), OS.get_distribution_name(), OS.get_processor_count(), OS.get_processor_name(), OS.get_user_data_dir()])


func _show_engine() -> void:
	var g := _grid("Engine 싱글턴 — core/config/engine.h, 버전은 core/version.h + version_hash.gen.cpp", 2)
	var v: Dictionary = Engine.get_version_info()
	_kv(g, "Engine.get_version_info().string", String(v["string"]))
	_kv(g, "major.minor.patch / status / build", "%d.%d.%d / %s / %s" % [
		int(v["major"]), int(v["minor"]), int(v["patch"]), String(v["status"]), String(v["build"])])
	_kv(g, "hash (앞 12자)", String(v["hash"]).left(12))
	_kv(g, "Engine.get_architecture_name()", Engine.get_architecture_name())
	_kv(g, "Engine.is_editor_hint()", str(Engine.is_editor_hint()))
	_kv(g, "Engine.get_frames_per_second()", str(Engine.get_frames_per_second()))
	Log.info("Engine %s, 아키텍처 %s, is_editor_hint=%s" % [String(v["string"]), Engine.get_architecture_name(), str(Engine.is_editor_hint())])


func _show_rendering() -> void:
	var g := _grid("RenderingServer — servers/rendering/rendering_server_default.cpp, 드라이버 선택은 main/main.cpp", 2)
	_kv(g, "RS.get_current_rendering_method()", RenderingServer.get_current_rendering_method())
	_kv(g, "RS.get_current_rendering_driver_name()", RenderingServer.get_current_rendering_driver_name())
	_kv(g, "RS.get_video_adapter_name()", RenderingServer.get_video_adapter_name())
	_kv(g, "RS.get_video_adapter_vendor()", RenderingServer.get_video_adapter_vendor())
	_kv(g, "RS.get_video_adapter_api_version()", RenderingServer.get_video_adapter_api_version())
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	_kv(g, "RS.get_rendering_device()", "null (GL Compatibility 또는 headless 에서는 항상 null)" if rd == null else "RenderingDevice 사용 가능")
	_kv(g, "설정 rendering_method (오버라이드 적용)", String(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")))
	_kv(g, "설정 gl_compatibility/driver (오버라이드 적용)", String(ProjectSettings.get_setting_with_override("rendering/gl_compatibility/driver")))
	_kv(g, "설정 rendering_device/driver (오버라이드 적용)", String(ProjectSettings.get_setting_with_override("rendering/rendering_device/driver")))
	Log.info("렌더링: method=%s driver=%s adapter=\"%s\" RD=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), "없음" if rd == null else "있음"])


func _show_feature_tags() -> void:
	var g := _grid("OS.has_feature() 기능 태그 — core/os/os.cpp OS::has_feature(); 프로젝트 설정 오버라이드(키.태그)의 근거", 3)
	var on: PackedStringArray = []
	for row: Array in FEATURE_TAGS:
		var tag: String = row[0]
		var hit: bool = OS.has_feature(tag)
		_kv3(g, tag, String(row[1]), "O" if hit else "-")
		if hit:
			on.append(tag)
	Log.info("참인 기능 태그: " + ", ".join(on))
	Log.info("참고: \"headless\" 는 OS 기능 태그가 아니다. DisplayServer.get_name() == \"headless\" 로 판별한다 (servers/display/display_server_headless.h).")


func _show_display_server() -> void:
	var g := _grid("DisplayServer — servers/display/display_server.h, 구현 platform/<name>/display_server_*.cpp", 2)
	var ds_name: String = DisplayServer.get_name()
	_kv(g, "DisplayServer.get_name()", ds_name)
	var screens: int = DisplayServer.get_screen_count()
	_kv(g, "get_screen_count() / get_primary_screen()", "%d / %d" % [screens, DisplayServer.get_primary_screen()])
	if screens == 0:
		Log.warn("화면이 0개 — headless DisplayServer 는 화면/창 질의에 기본값(0, Vector2i(0,0), dpi 96)을 돌려준다 (display_server_headless.h).")
	for i: int in screens:
		_kv(g, "screen %d size / position" % i, "%s / %s" % [DisplayServer.screen_get_size(i), DisplayServer.screen_get_position(i)])
		_kv(g, "screen %d dpi / scale / refresh" % i, "%d / %.2f / %.1f Hz" % [
			DisplayServer.screen_get_dpi(i), DisplayServer.screen_get_scale(i), DisplayServer.screen_get_refresh_rate(i)])
	_kv(g, "window_get_size() / window_get_position()", "%s / %s" % [DisplayServer.window_get_size(), DisplayServer.window_get_position()])
	_kv(g, "window_get_mode()", _enum_name("WindowMode", DisplayServer.window_get_mode()))
	_kv(g, "window_get_vsync_mode()", _enum_name("VSyncMode", DisplayServer.window_get_vsync_mode(DisplayServer.MAIN_WINDOW_ID)))
	Log.info("DisplayServer \"%s\": 화면 %d개, 창 %s @ %s, 모드 %s" % [
		ds_name, screens, DisplayServer.window_get_size(), DisplayServer.window_get_position(), _enum_name("WindowMode", DisplayServer.window_get_mode())])

	# ClassDB 로 Feature 열거형 상수를 전부 순회하면 누락 없이 has_feature 표를 만들 수 있다.
	var fg := _grid("DisplayServer.has_feature(Feature) — 각 platform/*/display_server_*.cpp has_feature() 의 답", 2)
	var supported: PackedStringArray = []
	for cname: String in ClassDB.class_get_enum_constants("DisplayServer", "Feature"):
		var value: int = ClassDB.class_get_integer_constant("DisplayServer", cname)
		var hit: bool = DisplayServer.has_feature(value as DisplayServer.Feature)
		_kv(fg, cname, "O" if hit else "-")
		if hit:
			supported.append(cname.trim_prefix("FEATURE_"))
	Log.info("DisplayServer 지원 기능: %s" % (", ".join(supported) if not supported.is_empty() else "(없음 — headless 는 모두 false)"))


func _enum_name(enum_name: String, value: int) -> String:
	for cname: String in ClassDB.class_get_enum_constants("DisplayServer", enum_name):
		if ClassDB.class_get_integer_constant("DisplayServer", cname) == value:
			return "%s (%d)" % [cname, value]
	return str(value)


func _grid(title: String, columns: int) -> GridContainer:
	var lbl := Label.new()
	lbl.text = title
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color.SKY_BLUE)
	_vbox.add_child(lbl)
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 16)
	_vbox.add_child(g)
	return g


func _kv(g: GridContainer, key: String, value: String) -> void:
	_cell(g, key, Color.WHEAT)
	_cell(g, value, Color.WHITE)


func _kv3(g: GridContainer, a: String, b: String, c: String) -> void:
	_cell(g, a, Color.WHEAT)
	_cell(g, b, Color.WHITE)
	_cell(g, c, Color.LIGHT_GREEN if c == "O" else Color.GRAY)


func _cell(g: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", color)
	g.add_child(l)
