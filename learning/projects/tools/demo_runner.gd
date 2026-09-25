extends SceneTree

## 헤드리스 데모 러너 (검증용).
## 프로젝트의 demos/*/*.tscn 을 하나씩 인스턴스화해 몇 프레임 돌리고 해제한다.
## 사용: godot --headless --path <project> -s <absolute path to this file>
## 각 데모에 대해 "DEMO OK <path>" 를 출력하고, 마지막에 "DEMO_RUNNER DONE n=<count>" 를 출력한다.
## 스크립트 오류는 Godot 이 stderr 에 "SCRIPT ERROR" 로 찍으므로 호출 측(verify.sh)이 grep 한다.

const FRAMES_PER_DEMO: int = 6

var scenes: Array[String] = []
var index: int = -1
var frame: int = 0
var current: Node = null


func _initialize() -> void:
	_load_all_scripts("res://")
	var demos_dir: String = "res://demos"
	var dir: DirAccess = DirAccess.open(demos_dir)
	if dir == null:
		print("DEMO_RUNNER DONE n=0 (no demos dir)")
		quit(0)
		return
	for sub: String in dir.get_directories():
		var sub_path: String = demos_dir.path_join(sub)
		for f: String in DirAccess.get_files_at(sub_path):
			if f.get_extension() == "tscn":
				scenes.append(sub_path.path_join(f))
	scenes.sort()
	print("DEMO_RUNNER scenes=%d" % scenes.size())


## 프로젝트의 모든 .gd 를 load() 해 컴파일 오류를 드러낸다 (씬에서 참조되지 않는 스크립트 포함).
func _load_all_scripts(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_load_all_scripts(path.path_join(sub))
	for f: String in dir.get_files():
		if f.get_extension() == "gd":
			var res: Resource = load(path.path_join(f))
			if res == null:
				printerr("SCRIPT LOAD FAIL %s" % path.path_join(f))
			else:
				print("SCRIPT OK %s" % path.path_join(f))


func _process(_delta: float) -> bool:
	if current == null:
		index += 1
		if index >= scenes.size():
			print("DEMO_RUNNER DONE n=%d" % scenes.size())
			quit(0)
			return true
		var packed: PackedScene = load(scenes[index])
		if packed == null:
			printerr("DEMO FAIL (load) %s" % scenes[index])
			return false
		current = packed.instantiate()
		get_root().add_child(current)
		frame = 0
		return false
	frame += 1
	if frame >= FRAMES_PER_DEMO:
		print("DEMO OK %s" % scenes[index])
		current.queue_free()
		current = null
	return false
