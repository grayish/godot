extends Control
## 데모 4: PCK 와 리소스 — PCKPacker 로 DLC 팩을 만들고 ProjectSettings.load_resource_pack 으로 res:// 에 합친다.
## 엔진: core/io/pck_packer.cpp (쓰기), core/io/file_access_pack.cpp PackedSourcePCK::try_open_pack (읽기, "GDPC" 매직),
## core/config/project_settings.cpp _load_resource_pack (res:// 의 DirAccess 를 DirAccessPack 으로 교체).
## 익스포트한 게임이 자기 PCK 를 찾는 순서는 같은 파일의 _setup() 에 있다 (README 참고).

const PCK_PATH: String = "user://dlc.pck"
const SOURCE_DIR: String = "res://dlc_source"
const TARGET_DIR: String = "res://dlc"
const TXT_PATH: String = "res://dlc/greeting.txt"
const TRES_PATH: String = "res://dlc/palette.tres"
const PACK_MAGIC: int = 0x43504447 # core/io/file_access_pack.h PACK_HEADER_MAGIC ("GDPC")

var _status: Label
var _swatches: HBoxContainer


func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)
	var row := HBoxContainer.new()
	vbox.add_child(row)
	_button(row, "1) 로드 전 상태", _check_state)
	_button(row, "2) PCK 만들기 (PCKPacker)", _build_pack)
	_button(row, "3) 헤더 읽기 (GDPC)", _read_header)
	_button(row, "4) load_resource_pack", _load_pack)
	_button(row, "5) 읽기 / .tres 로드", _read_contents)
	_button(row, "6) DirAccess.get_files_at", _list_dir)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)
	_swatches = HBoxContainer.new()
	vbox.add_child(_swatches)
	Log.info("헤드리스로 팩 만들기: godot --headless --path <프로젝트> -s res://tools/make_pack.gd  (→ user://dlc.pck)")
	_check_state()


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _set_status(lines: PackedStringArray) -> void:
	_status.text = "\n".join(lines)
	for l: String in lines:
		Log.info(l)


func _check_state() -> void:
	var lines: PackedStringArray = []
	lines.append("user://dlc.pck = %s, 존재: %s" % [ProjectSettings.globalize_path(PCK_PATH), str(FileAccess.file_exists(PCK_PATH))])
	lines.append("FileAccess.file_exists(\"%s\") = %s  (txt 는 Resource 가 아니므로 ResourceLoader.exists 대신 FileAccess 로 확인)" % [
		TXT_PATH, str(FileAccess.file_exists(TXT_PATH))])
	lines.append("ResourceLoader.exists(\"%s\") = %s" % [TRES_PATH, str(ResourceLoader.exists(TRES_PATH))])
	if not FileAccess.file_exists(PCK_PATH):
		Log.warn("아직 PCK 가 없다 — 2) 버튼 또는 tools/make_pack.gd 로 만들 것")
	_set_status(lines)


func _build_pack() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(SOURCE_DIR)
	var packer := PCKPacker.new()
	# 엔진: pck_start 는 헤더 자리를 비워 두고, add_file 이 데이터를 바로 쓰고, flush 가 디렉터리(경로·오프셋·MD5)를 쓴다.
	var err: Error = packer.pck_start(PCK_PATH)
	if err != OK:
		Log.warn("pck_start 실패: " + error_string(err))
		return
	var lines: PackedStringArray = []
	for f: String in files:
		var target: String = TARGET_DIR.path_join(f)
		err = packer.add_file(target, SOURCE_DIR.path_join(f))
		lines.append("add_file(%s ← %s) = %s" % [target, SOURCE_DIR.path_join(f), error_string(err)])
	err = packer.flush()
	lines.append("flush() = %s → %s" % [error_string(err), ProjectSettings.globalize_path(PCK_PATH)])
	_set_status(lines)


func _read_header() -> void:
	var f: FileAccess = FileAccess.open(PCK_PATH, FileAccess.READ)
	if f == null:
		Log.warn("PCK 를 열 수 없음: " + error_string(FileAccess.get_open_error()))
		return
	# 엔진: try_open_pack 은 (a) 오프셋 0 의 매직 → (b) 실행 파일의 'pck' 섹션 → (c) 파일 끝의 매직(뒤에 덧붙인 팩) 순으로 찾는다.
	var magic: int = f.get_32()
	var version: int = f.get_32()
	var major: int = f.get_32()
	var minor: int = f.get_32()
	var patch: int = f.get_32()
	var flags: int = f.get_32()
	var file_base: int = f.get_64()
	f.seek(0)
	var ascii: String = f.get_buffer(4).get_string_from_ascii()
	f.close()
	var lines: PackedStringArray = []
	lines.append("magic 0x%08X (\"%s\") %s PACK_HEADER_MAGIC" % [magic, ascii, "==" if magic == PACK_MAGIC else "!="])
	lines.append("format version %d (V4 = 현재), 만든 엔진 %d.%d.%d, flags=%d (bit0 DIR_ENCRYPTED, bit1 REL_FILEBASE, bit2 SPARSE_BUNDLE), file_base=%d" % [
		version, major, minor, patch, flags, file_base])
	lines.append("파일 항목 플래그(file_access_pack.h): ENCRYPTED, REMOVAL(패치가 파일을 지움), DELTA(패치 PCK 차분)")
	_set_status(lines)


func _load_pack() -> void:
	if not FileAccess.file_exists(PCK_PATH):
		Log.warn("PCK 없음 — 먼저 2) 로 만들 것")
		return
	# replace_files=true: 같은 경로가 이미 res:// 에 있으면 팩 쪽이 이긴다 — 패치/DLC 의 핵심.
	var ok: bool = ProjectSettings.load_resource_pack(PCK_PATH, true)
	var lines: PackedStringArray = []
	lines.append("ProjectSettings.load_resource_pack(\"%s\", true) = %s" % [PCK_PATH, str(ok)])
	lines.append("이후 FileAccess.file_exists(\"%s\") = %s, ResourceLoader.exists(\"%s\") = %s" % [
		TXT_PATH, str(FileAccess.file_exists(TXT_PATH)), TRES_PATH, str(ResourceLoader.exists(TRES_PATH))])
	lines.append("엔진: PackedData::add_pack → PackedSourcePCK::try_open_pack; 이제 FileAccess::open(res://…) 은 PackedData 를 먼저 본다 (core/io/file_access.cpp).")
	_set_status(lines)


func _read_contents() -> void:
	if not FileAccess.file_exists(TXT_PATH):
		Log.warn("%s 없음 — 4) 로 팩을 먼저 로드할 것" % TXT_PATH)
		return
	var text: String = FileAccess.get_file_as_string(TXT_PATH)
	var lines: PackedStringArray = []
	lines.append("greeting.txt 내용: " + text.strip_edges())
	var res: Resource = load(TRES_PATH)
	var grad := res as Gradient
	if grad == null:
		lines.append("palette.tres 로드 실패")
	else:
		var colors: PackedStringArray = []
		for i: int in grad.get_point_count():
			colors.append("#" + grad.get_color(i).to_html(false))
		lines.append("palette.tres → Gradient 포인트 %d개: %s (텍스트 .tres 는 ResourceFormatLoaderText 가 팩 안에서도 그대로 읽는다)" % [
			grad.get_point_count(), " ".join(colors)])
		_show_gradient(grad)
	_set_status(lines)


func _show_gradient(grad: Gradient) -> void:
	for child: Node in _swatches.get_children():
		child.queue_free()
	for i: int in grad.get_point_count():
		var rect := ColorRect.new()
		rect.color = grad.get_color(i)
		rect.custom_minimum_size = Vector2(48, 24)
		_swatches.add_child(rect)


func _list_dir() -> void:
	# 엔진: _load_resource_pack 은 에디터/--path 실행에서도 PackedSourceDirectory 를 추가하고 DirAccess 기본을
	# DirAccessPack 으로 바꾼다 (project_settings.cpp:599-606). 그래서 팩 안의 디렉터리도 나열된다.
	if not DirAccess.dir_exists_absolute(TARGET_DIR):
		Log.warn("%s 디렉터리가 아직 없다 — 4) 로 팩을 먼저 로드할 것" % TARGET_DIR)
		return
	var files: PackedStringArray = DirAccess.get_files_at(TARGET_DIR)
	var lines: PackedStringArray = []
	lines.append("DirAccess.get_files_at(\"%s\") = %s" % [TARGET_DIR, str(files)])
	lines.append("DirAccess.get_files_at(\"%s\") = %s (원본 폴더)" % [SOURCE_DIR, str(DirAccess.get_files_at(SOURCE_DIR))])
	_set_status(lines)
