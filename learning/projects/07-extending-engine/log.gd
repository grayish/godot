extends Node

## 프로젝트 전역 로그 (autoload "Log").
## print() 는 결국 엔진의 core/string/print_string.cpp print_line() 으로 들어가고,
## 허브(main.gd)는 message 시그널을 받아 화면 하단 패널에 같은 내용을 비춘다.
## 시그널 방출: core/object/object.cpp Object::emit_signalp()

signal message(text: String, level: int)

enum Level { INFO, WARN, SECTION }


func info(text: String) -> void:
	_emit(text, Level.INFO)


func warn(text: String) -> void:
	# push_warning 이 아니라 print 를 쓰는 이유: 헤드리스 검증에서 기대된 제약(창 없음 등)은
	# 오류가 아니므로 stderr 에 "WARNING:" 을 남기지 않는다.
	_emit("[경고] " + text, Level.WARN)


func section(title: String) -> void:
	_emit("== " + title + " ==", Level.SECTION)


func _emit(text: String, level: int) -> void:
	print(text)
	message.emit(text, level)
