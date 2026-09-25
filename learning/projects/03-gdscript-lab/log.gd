extends Node
## 데모 공용 로그 허브 (오토로드 "Log").
## print() 로 stdout 에 찍고, 같은 줄을 message 시그널로 허브의 RichTextLabel 에 전달한다.
## 엔진: core/object/object.cpp emit_signalp() — 시그널은 연결된 Callable 을 순서대로 동기 호출한다.
## 그래서 Log.info() 가 반환되기 전에 허브 패널의 콜백이 이미 실행되어 있다.

signal message(text: String, level: int)

enum Level { INFO, WARN, SECTION }

const PREFIXES: Array[String] = ["[INFO] ", "[WARN] ", "== "]


func info(text: String) -> void:
	_emit(text, Level.INFO)


func warn(text: String) -> void:
	_emit(text, Level.WARN)


func section(title: String) -> void:
	_emit(title, Level.SECTION)


func _emit(text: String, level: int) -> void:
	print(PREFIXES[level] + text)
	message.emit(text, level)
