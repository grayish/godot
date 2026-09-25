extends Node
## 전역 로그 오토로드 "Log" (project.godot [autoload]).
## print() 로 stdout 에 찍고, 동시에 message 시그널을 내보내 허브(main.gd)의 로그 패널이 받는다.
## 엔진: 오토로드는 main/main.cpp Main::start() 에서 root 의 자식으로 추가되고,
## ScriptServer::add_global_constant 로 스크립트 전역 이름 "Log" 가 된다 (트리 밖에서도 이름이 풀리는 이유).

signal message(text: String, level: int)

enum Level { INFO = 0, WARN = 1, SECTION = 2 }


func info(text: String) -> void:
	_emit(text, Level.INFO)


func warn(text: String) -> void:
	_emit("[경고] " + text, Level.WARN)


func section(title: String) -> void:
	_emit("── " + title + " ──", Level.SECTION)


func _emit(text: String, level: int) -> void:
	print(text)
	message.emit(text, level)
