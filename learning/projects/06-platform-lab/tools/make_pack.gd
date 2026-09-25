extends SceneTree
## DLC 팩 생성 도구 (헤드리스).
## 실행: godot --headless --path <프로젝트> -s res://tools/make_pack.gd [-- <출력 경로>]
## res://dlc_source/ 의 파일을 res://dlc/ 경로로 user://dlc.pck 에 담는다. 데모 4 가 이 팩을 로드한다.
## 엔진: core/io/pck_packer.cpp — pck_start() 가 헤더 자리를 예약하고, add_file() 이 데이터를 즉시 쓰고,
## flush() 가 파일 디렉터리(경로·오프셋·MD5)를 써서 닫는다. 결과 파일 첫 4바이트는 "GDPC".

const SOURCE_DIR: String = "res://dlc_source"
const TARGET_DIR: String = "res://dlc"
const DEFAULT_PCK: String = "user://dlc.pck"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = DEFAULT_PCK if args.is_empty() else args[0]
	var err: Error = build_pack(out)
	if err == OK:
		print("MAKE_PACK OK: %s -> %s" % [SOURCE_DIR, ProjectSettings.globalize_path(out)])
		quit(0)
	else:
		printerr("MAKE_PACK FAIL: %s (%s)" % [out, error_string(err)])
		quit(1)


## selftest 에서도 호출하는 순수 함수. SceneTree 인스턴스 없이 static 으로 쓴다.
static func build_pack(pck_path: String) -> Error:
	if not DirAccess.dir_exists_absolute(SOURCE_DIR):
		return ERR_DOES_NOT_EXIST
	var files: PackedStringArray = DirAccess.get_files_at(SOURCE_DIR)
	if files.is_empty():
		return ERR_DOES_NOT_EXIST
	var packer := PCKPacker.new()
	var err: Error = packer.pck_start(pck_path)
	if err != OK:
		return err
	for f: String in files:
		# 스크립트(.gd)는 넣지 않는다: 팩에서 온 스크립트는 보안·캐시 문제가 있어 데이터(.txt/.tres)만 담는다.
		if f.get_extension() == "gd" or f.get_extension() == "import":
			continue
		err = packer.add_file(TARGET_DIR.path_join(f), SOURCE_DIR.path_join(f))
		if err != OK:
			return err
	return packer.flush(true)
