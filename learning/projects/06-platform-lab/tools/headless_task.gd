extends SceneTree
## CI 용 헤드리스 작업: 플랫폼 정보를 모아 user://report.json 으로 쓰고 종료한다.
## 실행: godot --headless --path <프로젝트> -s res://tools/headless_task.gd [-- --job=nightly]
## 창이 없으므로 DisplayServerHeadless(servers/display/display_server_headless.h) 와 dummy 래스터라이저가 쓰이고,
## --headless 는 main/main.cpp 가 display driver 를 "headless" 로 강제하는 것과 같다.

const REPORT_PATH: String = "user://report.json"
const TAGS: Array[String] = [
	"windows", "linuxbsd", "linux", "macos", "android", "ios", "web", "pc", "mobile",
	"editor", "template", "debug", "release", "64", "32", "x86_64", "arm64", "threads", "double", "single",
]


func _initialize() -> void:
	var report: Dictionary = build_report()
	var f: FileAccess = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("HEADLESS_TASK FAIL: cannot write %s (%s)" % [REPORT_PATH, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("HEADLESS_TASK OK -> " + ProjectSettings.globalize_path(REPORT_PATH))
	print(JSON.stringify(report))
	quit(0)


## selftest 에서도 호출하는 순수 함수.
static func build_report() -> Dictionary:
	var v: Dictionary = Engine.get_version_info()
	var features: PackedStringArray = []
	for tag: String in TAGS:
		if OS.has_feature(tag):
			features.append(tag)
	return {
		"generated_at": Time.get_datetime_string_from_system(true, true),
		"engine": {
			"version": String(v["string"]),
			"hash": String(v["hash"]),
			"architecture": Engine.get_architecture_name(),
		},
		"os": {
			"name": OS.get_name(),
			"distribution": OS.get_distribution_name(),
			"version": OS.get_version(),
			"processor_count": OS.get_processor_count(),
			"processor_name": OS.get_processor_name(),
			"locale": OS.get_locale(),
			"executable": OS.get_executable_path(),
			"user_data_dir": OS.get_user_data_dir(),
			"debug_build": OS.is_debug_build(),
		},
		"display_server": DisplayServer.get_name(),
		"rendering": {
			"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
		},
		"features": features,
		"user_args": OS.get_cmdline_user_args(),
		"project": {
			"name": String(ProjectSettings.get_setting("application/config/name", "")),
			"greeting": String(ProjectSettings.get_setting_with_override("demo/greeting")),
		},
	}
