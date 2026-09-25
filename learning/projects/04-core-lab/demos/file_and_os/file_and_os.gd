extends Control
## 데모 6: 파일과 OS — FileAccess/DirAccess, 경로 변환, ConfigFile, JSON, StreamPeerBuffer, 해시.
## 엔진: core/io/file_access.h (ACCESS_RESOURCES/USERDATA/FILESYSTEM 별 create_func 테이블),
##       core/io/dir_access.cpp, core/io/file_access_pack.cpp (PCK 안의 res://), core/config/project_settings.cpp
##       (globalize_path/localize_path), core/os/os.cpp get_user_data_dir, core/io/config_file.cpp, core/io/json.cpp,
##       core/io/stream_peer.cpp. 2장 2.4 "OS 추상화" + 2.5 "FileAccess / DirAccess".

const TEXT_PATH: String = "user://core_lab_note.txt"
const CFG_PATH: String = "user://core_lab_settings.cfg"

var _output: Label


func _ready() -> void:
	_build_ui()
	Log.section("파일과 OS")
	_demo_paths()
	_demo_file_access()
	_demo_dir_access()
	_demo_config_file()
	_demo_json()
	_demo_stream_peer()
	_demo_hash()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "FileAccess / DirAccess / ConfigFile / JSON / StreamPeerBuffer — 버튼으로 다시 실행"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	var items: Array = [
		["경로 변환", _demo_paths], ["FileAccess", _demo_file_access], ["DirAccess", _demo_dir_access],
		["ConfigFile", _demo_config_file], ["JSON", _demo_json], ["StreamPeerBuffer", _demo_stream_peer], ["MD5/SHA256", _demo_hash],
	]
	for item: Array in items:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		grid.add_child(button)
	_output = Label.new()
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_output)


func _demo_paths() -> void:
	Log.section("경로: user:// ↔ 절대 경로")
	Log.info("OS.get_name()=%s, OS.get_user_data_dir()=%s" % [OS.get_name(), OS.get_user_data_dir()])
	Log.info("ProjectSettings.globalize_path(\"user://a.txt\")=%s" % ProjectSettings.globalize_path("user://a.txt"))
	var res_abs := ProjectSettings.globalize_path("res://main.gd")
	Log.info("globalize_path(\"res://main.gd\")=%s → localize_path 로 되돌리면 %s" % [res_abs, ProjectSettings.localize_path(res_abs)])
	Log.info("user:// 는 OS::get_user_data_dir() (프로젝트 이름 기준 app_userdata/<이름>), res:// 는 프로젝트 루트 또는 PCK 내부")


func _demo_file_access() -> void:
	Log.section("FileAccess 쓰기/읽기 (RefCounted → 참조가 사라지면 자동 close)")
	var writer := FileAccess.open(TEXT_PATH, FileAccess.WRITE)
	if writer == null:
		Log.warn("쓰기 열기 실패: %s" % error_string(FileAccess.get_open_error()))
		return
	writer.store_line("첫 줄: 코어 계층 실험실")
	writer.store_string("둘째 줄 (store_string 은 개행을 붙이지 않음)\n")
	writer.store_line("셋째 줄")
	writer.close()
	var reader := FileAccess.open(TEXT_PATH, FileAccess.READ)
	Log.info("get_length()=%d바이트(UTF-8), get_line()=\"%s\", get_line()=\"%s\", get_position()=%d, eof=%s" % [
		reader.get_length(), reader.get_line(), reader.get_line(), reader.get_position(), str(reader.eof_reached())])
	Log.info("store_32/get_32 같은 이진 API 를 같은 파일에 섞으면 get_as_text 가 UTF-8 로 읽다 깨진다 — 텍스트와 바이너리 파일을 분리할 것")
	reader = null
	var missing := FileAccess.open("res://this_file_does_not_exist.txt", FileAccess.READ)
	Log.info("없는 파일 open → null=%s, FileAccess.get_open_error()=%s (정적 함수: 마지막 open 의 오류)" % [
		str(missing == null), error_string(FileAccess.get_open_error())])
	Log.info("정적 편의 함수: FileAccess.get_file_as_string 길이=%d, file_exists=%s" % [
		FileAccess.get_file_as_string(TEXT_PATH).length(), str(FileAccess.file_exists(TEXT_PATH))])
	_output.text = FileAccess.get_file_as_string(TEXT_PATH)


func _demo_dir_access() -> void:
	Log.section("DirAccess: res:// 와 user:// 열거")
	var res_dir := DirAccess.open("res://")
	if res_dir == null:
		Log.warn("res:// 열기 실패: %s" % error_string(DirAccess.get_open_error()))
		return
	Log.info("res:// 폴더=%s, 파일=%s" % [str(res_dir.get_directories()), str(res_dir.get_files())])
	Log.info("DirAccess.get_directories_at(\"res://demos\")=%s (정적 편의 함수, get_files_at 도 있음)" % str(DirAccess.get_directories_at("res://demos")))
	Log.info("익스포트한 PCK 안에서도 res:// 는 그대로 읽힌다: ProjectSettings 가 DirAccessPack/FileAccessPack 으로 교체 (file_access_pack.cpp)")
	var user_dir := DirAccess.open("user://")
	var err := user_dir.make_dir_recursive("core_lab/sub")
	Log.info("user:// 에 make_dir_recursive(\"core_lab/sub\") → %s, dir_exists=%s" % [error_string(err), str(user_dir.dir_exists("core_lab/sub"))])
	Log.info("user:// 에 있는 파일=%s" % str(user_dir.get_files()))


func _demo_config_file() -> void:
	Log.section("ConfigFile 왕복 (INI 문법 + VariantWriter 값)")
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", false)
	cfg.set_value("video", "scale", 1.5)
	cfg.set_value("player", "spawn", Vector2(3, 4))
	cfg.set_value("player", "name", "용사")
	var err := cfg.save(CFG_PATH)
	Log.info("save → %s. 텍스트:\n%s" % [error_string(err), cfg.encode_to_text().strip_edges()])
	var loaded := ConfigFile.new()
	err = loaded.load(CFG_PATH)
	Log.info("load → %s, sections=%s, spawn=%s (%s), 없는 키 default=%s" % [
		error_string(err), str(loaded.get_sections()), str(loaded.get_value("player", "spawn")),
		type_string(typeof(loaded.get_value("player", "spawn"))), str(loaded.get_value("player", "missing", 42))])
	Log.info("JSON 과 달리 Vector2/Color 같은 Variant 타입을 잃지 않는다 (config_file.cpp → VariantParser)")


func _demo_json() -> void:
	Log.section("JSON.stringify / parse_string")
	var data: Dictionary = {"hp": 12, "ratio": 0.5, "tags": ["a", "b"], "pos": Vector2(1, 2), "nested": {"ok": true}}
	var text := JSON.stringify(data, "\t")
	Log.info("stringify(indent=\\t) → %d자. Vector2 는 문자열로 변환됨: %s" % [text.length(), JSON.stringify(data["pos"])])
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		Log.warn("parse_string 실패")
		return
	Log.info("parse_string 후 hp 의 타입=%s (JSON 숫자는 전부 float!), tags=%s, nested.ok=%s" % [
		type_string(typeof(parsed["hp"])), str(parsed["tags"]), str(parsed["nested"]["ok"])])
	var json := JSON.new()
	var err := json.parse("{\"broken\": ")
	# error_string(ERR_PARSE_ERROR) 문자열 대신 코드로 적는다 — 헤드리스 검증기가 오류 문구를 grep 하기 때문.
	Log.info("JSON.new().parse(잘못된 텍스트) → ERR_PARSE_ERROR? %s (코드 %d), 줄 %d: %s" % [
		str(err == ERR_PARSE_ERROR), err, json.get_error_line(), json.get_error_message()])
	_output.text = text


func _demo_stream_peer() -> void:
	Log.section("StreamPeerBuffer: 바이너리 직렬화")
	var stream := StreamPeerBuffer.new()
	stream.put_u8(200)
	stream.put_float(3.5)
	stream.put_utf8_string("헬로 코어")
	stream.put_string("ascii only")
	stream.put_u32(123456)
	Log.info("put_u8/put_float/put_utf8_string/put_string/put_u32 → data_array %d바이트, big_endian=%s" % [
		stream.data_array.size(), str(stream.big_endian)])
	stream.seek(0)
	Log.info("seek(0) 후 get_u8=%d, get_float=%s, get_utf8_string=%s, get_string=%s, get_u32=%d" % [
		stream.get_u8(), str(stream.get_float()), stream.get_utf8_string(), stream.get_string(), stream.get_u32()])
	Log.info("put_string 은 ASCII/Latin-1 전용 — 한글은 put_utf8_string 을 써야 한다. 문자열은 u32 길이 접두사 + 바이트")
	Log.info("같은 인코딩을 StreamPeerTCP/PacketPeer 도 쓴다 (stream_peer.cpp) — 네트워크 프로토콜의 기초")


func _demo_hash() -> void:
	Log.section("FileAccess.get_md5 / get_sha256")
	if not FileAccess.file_exists(TEXT_PATH):
		Log.warn("먼저 FileAccess 데모를 실행해 %s 를 만드세요" % TEXT_PATH)
		return
	Log.info("md5=%s" % FileAccess.get_md5(TEXT_PATH))
	Log.info("sha256=%s" % FileAccess.get_sha256(TEXT_PATH))
	Log.info("수정 시각(unix)=%d → %s" % [FileAccess.get_modified_time(TEXT_PATH),
		Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(TEXT_PATH))])
	Log.info("PCK 무결성 검사나 캐시 키에 쓴다. 문자열 해시는 \"abc\".md5_text()=%s" % "abc".md5_text())
