extends Control
## 데모 6: 오류 처리와 디버깅.
## 엔진: core/error/error_macros.h (ERR_FAIL_* 매크로, _err_print_error), core/variant/variant_utility.cpp (push_error/push_warning),
##       modules/gdscript/gdscript_vm.cpp (런타임 오류 → "SCRIPT ERROR" + 백트레이스), core/debugger/engine_debugger.cpp,
##       modules/gdscript/gdscript_utility_functions.cpp (print_stack / get_stack / print_debug).
## 오류를 실제로 내는 버튼들은 _ready 에서 실행하지 않는다 — 헤드리스 검증은 "ERROR:" 줄이 하나라도 있으면 실패로 본다.

var _last_text: String = ""
var _status: Label


func _ready() -> void:
	_build_ui()
	_show_environment()
	_show_error_enum_pattern()
	_show_assert_and_warnings()
	_show_stack()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "아래 버튼은 콘솔(stdout/stderr)과 에디터 디버거 탭에 실제 경고/오류를 낸다. 실행은 계속된다."
	column.add_child(_status)
	var row := HBoxContainer.new()
	column.add_child(row)
	_add_button(row, "push_warning() 호출", _press_push_warning)
	_add_button(row, "push_error() 호출", _press_push_error)
	_add_button(row, "assert(false) 호출", _press_assert_false)
	_add_button(row, "없는 메서드 call()", _press_bad_call)
	_add_button(row, "printerr() 호출", _press_printerr)


func _add_button(parent: Node, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	parent.add_child(button)


# ---------------------------------------------------------------- 실행 환경

func _show_environment() -> void:
	Log.section("실행 환경 감지")
	Log.info("OS.is_debug_build()=%s — false(릴리스 템플릿)면 assert 가 사라지고 VM 의 DEBUG_ENABLED 검사도 빠진다" % OS.is_debug_build())
	Log.info("Engine.is_editor_hint()=%s — @tool 스크립트가 에디터 안에서 도는지" % Engine.is_editor_hint())
	Log.info("EngineDebugger.is_active()=%s — 에디터에서 실행(F5)하면 원격 디버거가 붙어 true. Engine.has_singleton(\"EngineDebugger\")=%s (core/register_core_types.cpp 에서 등록)" % [EngineDebugger.is_active(), Engine.has_singleton("EngineDebugger")])
	Log.info("DisplayServer.get_name()=%s, OS.has_feature(\"editor\")=%s, OS.has_feature(\"debug\")=%s" % [DisplayServer.get_name(), OS.has_feature("editor"), OS.has_feature("debug")])
	if DisplayServer.get_name() == "headless":
		Log.warn("헤드리스 실행: 창도 디버거 패널도 없다. 오류는 stdout/stderr 로만 보인다.")


# ---------------------------------------------------------------- Error 열거형 반환 패턴

func _show_error_enum_pattern() -> void:
	Log.section("Error 열거형을 돌려주는 패턴 (예외가 없는 언어의 관례)")
	var err: Error = _read_text_file("res://does_not_exist.txt")
	Log.info("_read_text_file(없는 파일) → %d = %s ; FileAccess.get_open_error() 가 마지막 open 의 오류를 보관한다 (core/io/file_access.cpp last_file_open_error)" % [err, error_string(err)])
	err = _read_text_file("res://project.godot")
	Log.info("_read_text_file(project.godot) → %s, 읽은 길이 %d" % [error_string(err), _last_text.length()])

	# error_string(ERR_PARSE_ERROR) 의 문구는 헤드리스 검증 스크립트가 엔진 파싱 실패로 오인하므로 코드 번호로만 적는다.
	var json := JSON.new()
	var json_err: Error = json.parse("{\"ok\": tru}")
	Log.info("JSON.parse(잘못된 텍스트) → 코드 %d (ERR_PARSE_ERROR=%d), 줄 %d: %s" % [json_err, ERR_PARSE_ERROR, json.get_error_line(), json.get_error_message()])
	json_err = json.parse("{\"ok\": true}")
	Log.info("JSON.parse(정상) → %s, data=%s" % [error_string(json_err), json.data])

	var dir: DirAccess = DirAccess.open("res://no_such_dir")
	Log.info("DirAccess.open(없는 경로) → %s, get_open_error()=%s" % [dir, error_string(DirAccess.get_open_error())])
	Log.info("ResourceLoader.exists(\"res://nope.tres\")=%s — load() 전에 확인하면 콘솔의 ERROR 를 피할 수 있다" % ResourceLoader.exists("res://nope.tres"))
	Log.info("error_string(ERR_FILE_NOT_FOUND)=%s, OK=%d, FAILED=%d, ERR_UNAVAILABLE=%d (core/error/error_list.h)" % [error_string(ERR_FILE_NOT_FOUND), OK, FAILED, ERR_UNAVAILABLE])


func _read_text_file(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	_last_text = file.get_as_text()
	return OK


# ---------------------------------------------------------------- assert / 경고

func _show_assert_and_warnings() -> void:
	Log.section("assert 와 @warning_ignore")
	var answer: int = 42
	assert(answer == 42, "이 메시지는 실패할 때만 보인다")
	Log.info("assert(answer == 42) 통과. 릴리스 빌드에서는 컴파일러가 assert 문을 아예 내지 않는다 (gdscript_compiler.cpp, DEBUG_ENABLED).")
	@warning_ignore("integer_division")
	var half: int = 7 / 2
	Log.info("7 / 2 = %d — INTEGER_DIVISION 경고를 @warning_ignore 로 잠재웠다 (이름 목록: gdscript_warning.cpp)" % half)
	Log.info("경고는 컴파일 시점 산물이다: gdscript.cpp reload() 가 parser.get_warnings() 를 EngineDebugger::is_active() 일 때 디버거로 보낸다 — 헤드리스에선 보이지 않는다.")


# ---------------------------------------------------------------- 스택과 출력 함수

func _show_stack() -> void:
	Log.section("print_stack / get_stack / print_debug / print_rich")
	var frames: Array = get_stack()
	if frames.is_empty():
		Log.warn("get_stack() 이 비었다 — 릴리스 빌드거나 호출 스택 추적이 꺼진 상태")
	else:
		var top: Dictionary = frames[0]
		Log.info("get_stack(): %d 프레임, 최상위 %s:%d %s()" % [frames.size(), top["source"], top["line"], top["function"]])
	print_stack()
	Log.info("print_stack() 은 stdout 에 'Frame N - 파일:줄 in function' 으로 찍는다 (로그 패널엔 안 보임).")
	print_debug("print_debug 는 뒤에 파일:줄:함수 를 붙인다")
	print_rich("[color=green]print_rich[/color] — 터미널엔 ANSI 색, 에디터 출력창엔 BBCode 색으로")
	Log.info("get_stack/print_stack 은 GDScriptLanguage::debug_get_stack_level_* 을 읽는다 (DEBUG_ENABLED 빌드).")


# ---------------------------------------------------------------- 버튼 핸들러 (실제 오류를 낸다)

func _press_push_warning() -> void:
	push_warning("데모 경고 — 콘솔에는 'WARNING:', 에디터 디버거 탭에는 노란 항목")
	Log.info("push_warning() 뒤에도 실행은 계속된다.")


func _press_push_error() -> void:
	push_error("데모 오류 — 예외가 아니다: 콘솔에 'USER ERROR' 로 찍히고 함수는 계속된다")
	Log.info("push_error() 뒤에도 실행은 계속된다. 실행을 끊고 싶으면 return 하거나 Error 를 돌려준다.")


func _press_assert_false() -> void:
	if not OS.is_debug_build():
		Log.warn("릴리스 빌드에서는 assert 가 없어 아무 일도 일어나지 않는다.")
	assert(false, "데모: 의도적 실패")
	Log.info("이 줄은 디버그 빌드에서는 보이지 않는다 — assert 실패는 SCRIPT ERROR 로 함수를 중단한다.")


func _press_bad_call() -> void:
	Log.info("call(\"no_such_method\") 실행 — VM 이 'Invalid call. Nonexistent function' SCRIPT ERROR 를 내고 이 함수를 중단한다.")
	call("no_such_method")
	Log.info("이 줄은 실행되지 않는다.")


func _press_printerr() -> void:
	printerr("printerr 는 stderr 로 간다 (오류 매크로를 거치지 않으므로 'ERROR:' 접두어가 없다)")
	Log.info("printerr() 호출함 — 터미널의 stderr 를 보자.")
