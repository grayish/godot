extends Node
## 전역 로그 허브. project.godot [autoload] 에 "Log" 로 등록되어 어느 스크립트에서나 Log.info(...) 로 쓴다.
## 오토로드는 메인 씬보다 먼저 SceneTree.root 아래에 add_child 된다 (엔진: main/main.cpp Main::start() 의 autoload 루프).
## print() 로 stdout(헤드리스 검증)에 찍는 동시에 message 시그널을 내보내 허브의 로그 패널이 화면에 옮겨 적는다.

## 로그 한 줄이 생길 때마다 방출. 허브(main.gd)가 받아 RichTextLabel 에 쓴다.
signal message(text: String, level: int)

enum Level { INFO, WARN, SECTION }


func info(text: String) -> void:
	_emit(text, Level.INFO)


func warn(text: String) -> void:
	# push_error/push_warning 이 아니라 print 를 쓰는 이유: 헤드리스 검증에서 "ERROR:" 줄은 실패로 취급되기 때문.
	_emit("[WARN] " + text, Level.WARN)


func section(title: String) -> void:
	_emit("== " + title + " ==", Level.SECTION)


func _emit(text: String, level: int) -> void:
	print(text)
	# 엔진: core/object/object.cpp emit_signalp() — 연결된 Callable 들을 순서대로 호출한다.
	message.emit(text, level)
