extends Node
## 전역 로그 허브 (autoload "Log").
## 데모는 Log.info/warn/section 만 호출하고, 허브(main.gd)는 message 시그널을 받아 화면 패널에 비춘다.
## 엔진: core/object/object.cpp emit_signalp() — 시그널 슬롯은 HashMap<StringName, SignalData>,
##       print() 는 core/string/print_string.cpp → stdout (헤드리스 검증도 이 출력을 읽는다).

enum Level { INFO, WARN, SECTION }

signal message(text: String, level: int)


func info(text: String) -> void:
	_emit(text, Level.INFO)


func warn(text: String) -> void:
	# push_error/push_warning 대신 일반 출력을 쓴다: 헤드리스에서 "예상된 제약"은 오류가 아니다.
	_emit("[경고] " + text, Level.WARN)


func section(title: String) -> void:
	_emit("== " + title + " ==", Level.SECTION)


func _emit(text: String, level: int) -> void:
	print(text)
	message.emit(text, level)
