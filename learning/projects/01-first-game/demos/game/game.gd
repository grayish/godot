extends Node2D
## 게임 루트 (Dodge / 닷지). 공식 "Your first 2D game" 구조를 텍스트/폴리곤 비주얼로 옮긴 것.
## 트리: Game(Node2D) ─ Player(씬 인스턴스) ─ MobSpawner(Node ─ SpawnTimer) ─ ScoreTimer ─ StartTimer ─ HUD(CanvasLayer)
## 시그널은 전부 game.tscn 의 [connection] 블록으로 연결된다 (에디터의 Node 독 → Signals 탭이 만드는 것).
## 벽과 배경은 _ready 에서 코드로 만든다 — 같은 노드를 .tscn 으로도, 코드로도 만들 수 있음을 보여 주기 위해.

## 아레나 크기. 허브의 오른쪽 영역에 맞춘 고정값 (뷰포트 크기에 기대지 않는다: 헤드리스에선 창이 100x100).
const ARENA := Rect2(0, 0, 960, 520)
const WALL_THICKNESS := 16.0
const BACKGROUND_COLOR := Color(0.09, 0.1, 0.14, 1)
const WALL_COLOR := Color(0.32, 0.36, 0.5, 1)

## 자식 스크립트를 preload 상수로 가리키면 player.arena 처럼 정적 타입으로 접근할 수 있다
## (class_name 전역 이름은 에디터 캐시가 있어야 보인다 — mob_stats.gd 주석 참고).
const PlayerScript: GDScript = preload("res://demos/game/player.gd")
const SpawnerScript: GDScript = preload("res://demos/game/mob_spawner.gd")
const HudScript: GDScript = preload("res://demos/game/hud.gd")

var score: int = 0
var playing: bool = false

@onready var player: PlayerScript = $Player
@onready var spawner: SpawnerScript = $MobSpawner
@onready var hud: HudScript = $HUD
@onready var score_timer: Timer = $ScoreTimer
@onready var start_timer: Timer = $StartTimer


func _ready() -> void:
	_build_arena()
	# 자식 씬의 변수는 부모 _ready 에서 안전하게 만질 수 있다 (자식이 먼저 _ready 됨).
	player.arena = ARENA.grow(-WALL_THICKNESS)
	spawner.arena = ARENA
	Log.info("Game 트리:\n" + get_tree_string_pretty())
	new_game()


func _process(_delta: float) -> void:
	# HUD(CanvasLayer)는 부모 트랜스폼을 무시하므로, 허브 컨테이너 안에 있을 때 아레나 원점에 맞춰 준다.
	if hud.offset != global_position:
		hud.offset = global_position


func new_game() -> void:
	score = 0
	playing = false
	# 그룹 호출: "mobs" 그룹의 모든 노드에 queue_free 를 부른다. 스포너가 몇 마리를 만들었는지 몰라도 된다.
	# 엔진: scene/main/scene_tree.cpp call_group() → group_map 순회.
	get_tree().call_group("mobs", "queue_free")
	player.start(ARENA.get_center())
	hud.update_score(0)
	hud.show_message("준비...")
	hud.hide_restart()
	start_timer.start()
	Log.info("새 게임. WASD / 방향키로 움직이세요. %.1f초 뒤 몹이 나옵니다." % start_timer.wait_time)


## game.tscn: [connection signal="timeout" from="StartTimer" to="." method="_on_start_timer_timeout"]
func _on_start_timer_timeout() -> void:
	playing = true
	hud.hide_message()
	score_timer.start()
	spawner.start()


## game.tscn: [connection signal="timeout" from="ScoreTimer" to="." method="_on_score_timer_timeout"]
func _on_score_timer_timeout() -> void:
	score += 1
	hud.update_score(score)


## game.tscn: [connection signal="hit" from="Player" to="." method="_on_player_hit"]
## Player 는 "맞았다"만 알리고, 무엇을 할지는 여기서 정한다 — 느슨한 결합.
func _on_player_hit() -> void:
	game_over()


func game_over() -> void:
	if not playing:
		return
	playing = false
	score_timer.stop()
	spawner.stop()
	get_tree().call_group("mobs", "queue_free")
	hud.show_game_over(score)
	Log.info("게임 오버! 점수 %d. '다시 시작' 버튼은 씬을 새로 인스턴스화합니다." % score)


## game.tscn: [connection signal="pressed" from="HUD/RestartButton" to="." method="_on_restart_pressed"]
func _on_restart_pressed() -> void:
	restart()


## 재시작. 두 가지 방법을 모두 보여 준다.
## - 단독 실행(F6, 이 씬이 current_scene)이면 get_tree().reload_current_scene().
## - 허브 안(current_scene 은 허브)이면 같은 .tscn 을 다시 인스턴스화해 형제로 넣고 자신은 queue_free.
func restart() -> void:
	var tree: SceneTree = get_tree()
	if tree.current_scene == self:
		Log.info("재시작: reload_current_scene()")
		tree.reload_current_scene()
		return
	# scene_file_path 는 PackedScene.instantiate() 가 루트 노드에 적어 둔 원본 경로.
	var packed: PackedScene = load(scene_file_path)
	if packed == null:
		Log.warn("재시작 실패: scene_file_path 가 비어 있음 (코드로 만든 노드?)")
		return
	Log.info("재시작: %s 를 다시 instantiate() 해서 교체" % scene_file_path)
	var fresh: Node = packed.instantiate()
	var parent: Node = get_parent()
	# 먼저 트리에서 빠져야 새 인스턴스가 "Game" 이름을 그대로 쓴다 (형제 이름이 겹치면 @Node2D@N 으로 바뀐다).
	parent.remove_child(self)
	parent.add_child(fresh)
	queue_free()  # 트리 밖이어도 SceneTree 싱글톤이 프레임 끝에 지워 준다


## 배경 ColorRect + 4 개의 벽(StaticBody2D). 플레이어(collision_mask = 2)만 벽(collision_layer = 2)에 막힌다.
func _build_arena() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND_COLOR
	background.position = ARENA.position
	background.size = ARENA.size
	background.z_index = -1  # 코드로 나중에 add_child 해도 Player 뒤에 그려지도록
	add_child(background)

	var half := WALL_THICKNESS / 2.0
	var center := ARENA.get_center()
	_add_wall("WallTop", Vector2(center.x, ARENA.position.y + half), Vector2(ARENA.size.x, WALL_THICKNESS))
	_add_wall("WallBottom", Vector2(center.x, ARENA.end.y - half), Vector2(ARENA.size.x, WALL_THICKNESS))
	_add_wall("WallLeft", Vector2(ARENA.position.x + half, center.y), Vector2(WALL_THICKNESS, ARENA.size.y))
	_add_wall("WallRight", Vector2(ARENA.end.x - half, center.y), Vector2(WALL_THICKNESS, ARENA.size.y))


func _add_wall(wall_name: String, center: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.position = center
	wall.collision_layer = 2
	wall.collision_mask = 0  # 벽은 아무것도 감지할 필요가 없다
	var shape := CollisionShape2D.new()
	shape.name = "Shape"  # 이름을 안 주면 @CollisionShape2D@N 같은 자동 이름이 붙는다
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.color = WALL_COLOR
	visual.size = size
	visual.position = -size / 2.0
	wall.add_child(visual)
	add_child(wall)
