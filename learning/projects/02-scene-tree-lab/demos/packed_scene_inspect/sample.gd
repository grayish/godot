extends Node2D
## 데모 6 이 들여다보는 샘플 씬의 루트 스크립트.
## .tscn 의 "greeting = ..." 은 SceneState 의 노드 속성 표에 들어가고, [connection] 은 연결 표에 들어간다.
## 엔진: scene/resources/packed_scene.cpp SceneState::instantiate() — 노드를 만들고 속성을 set 한 뒤 owner 를 루트로, 마지막에 connect.

@export var greeting: String = "기본 인사"


func _ready() -> void:
	var owner_name: String = str(owner.name) if owner != null else "null"
	Log.info("Sample._ready(): greeting=\"%s\", owner=%s (씬 루트의 owner 는 null)" % [greeting, owner_name])


func _on_ping_timer_timeout() -> void:
	Log.info("Sample: Inner/PingTimer.timeout → _on_ping_timer_timeout() — [connection] 이 instantiate 때 connect 된 결과")
