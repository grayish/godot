extends Node
## 모든 데모가 공유하는 로그 싱글턴 (project.godot [autoload] Log="*res://log.gd").
## 왜 autoload 인가: main/main.cpp Main::start() 가 메인 씬보다 먼저 autoload 를 루트에 붙이므로
## 어떤 데모 씬에서도 Log 가 이미 존재한다. print() 는 stdout(헤드리스 검증용), 시그널은 허브의 패널용.

signal message(text: String, level: int)

enum Level { INFO = 0, WARN = 1, SECTION = 2 }


func info(text: String) -> void:
	print(text)
	message.emit(text, Level.INFO)


## 헤드리스 등 "기대되는 제약" 은 push_error 가 아니라 warn 으로 알린다 (push_error 는 "ERROR:" 를 찍어 검증을 실패시킨다).
func warn(text: String) -> void:
	print("[warn] " + text)
	message.emit(text, Level.WARN)


func section(title: String) -> void:
	print("== " + title)
	message.emit(title, Level.SECTION)
