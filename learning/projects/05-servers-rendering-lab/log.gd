extends Node

## 허브와 데모가 공유하는 로그 싱글톤 (project.godot [autoload] Log="*res://log.gd").
## stdout 에 print() 하고, 같은 내용을 message 시그널로 내보내 허브의 RichTextLabel 이 받는다.
## 엔진: main/main.cpp Main::start() "Load Autoloads" — 오토로드는 메인 씬보다 먼저 root 에 붙는다.

signal message(text: String, level: int)

enum Level { INFO, WARN, SECTION }


func info(text: String) -> void:
	_emit(text, Level.INFO)


func warn(text: String) -> void:
	_emit("[경고] " + text, Level.WARN)


func section(title: String) -> void:
	_emit("== " + title + " ==", Level.SECTION)


func _emit(text: String, level: int) -> void:
	print(text)
	message.emit(text, level)
