extends SceneTree
## 헤드리스 셀프테스트. 창 없이 게임의 비-UI 로직을 검사한다.
##   godot --headless --path learning/projects/01-first-game -s res://selftest.gd
## SceneTree 를 상속한 스크립트는 그 자체가 MainLoop 가 된다 (엔진: main/main.cpp 의 -s 처리,
## scene/main/scene_tree.cpp SceneTree::process 가 매 프레임 MainLoop::process → 이 _process 를 부른다).
## 테스트를 프레임마다 하나씩 실행하는 이유: queue_free 는 프레임 끝(_flush_delete_queue)에야 지워지므로
## "지운 뒤 0 개" 같은 검사는 다음 프레임에 해야 한다.
##
## 주의: -s 스크립트는 오토로드가 등록되기 전에 컴파일된다. 그래서 (1) 여기서 "Log" 라는 전역 이름을 직접 쓸 수 없고
## (2) Log 를 쓰는 데모 스크립트를 preload 하면 함께 컴파일되다 실패한다 → 그런 씬/스크립트는 테스트 안에서 load() 한다.
## Log 를 쓰지 않는 player.gd / mob_stats.gd / log.gd 만 preload 상수로 타입을 잡는다.

const PROJECT_DIR := "learning/projects/01-first-game"
const GAME_SCENE_PATH := "res://demos/game/game.tscn"

const LogScript: GDScript = preload("res://log.gd")
const MobStatsScript: GDScript = preload("res://demos/game/mob_stats.gd")
const PlayerScript: GDScript = preload("res://demos/game/player.gd")

var tests: Array[Callable] = []
var failures: Array[String] = []
var next_test: int = 0

var game: Node2D = null
var old_game_id: int = 0
var hit_count: int = 0
var log_received: Array[String] = []


func _initialize() -> void:
	tests = [
		_test_player_scene,
		_test_mob_scene,
		_test_mob_stats,
		_test_input_actions,
		_test_log_autoload,
		_test_card_export_before_add_child,
		_test_game_spawn_three_mobs,
		_test_mobs_gone_after_frame,
		_test_restart_reinstantiates,
		_test_restart_after_frame,
	]
	print("SELFTEST start: %d tests" % tests.size())


## 프레임마다 테스트 하나. true 를 돌려주면 메인 루프가 끝난다.
func _process(_delta: float) -> bool:
	if next_test < tests.size():
		var test: Callable = tests[next_test]
		next_test += 1
		print("[%d/%d] %s" % [next_test, tests.size(), test.get_method()])
		test.call()
		return false
	_cleanup()
	if failures.is_empty():
		print("SELFTEST PASS " + PROJECT_DIR)
		quit(0)
	else:
		print("SELFTEST FAIL %s: %s" % [PROJECT_DIR, str(failures)])
		quit(1)
	return true


func check(condition: bool, message: String) -> void:
	if condition:
		print("    ok   " + message)
	else:
		failures.append(message)
		print("    FAIL " + message)


func _cleanup() -> void:
	for child: Node in get_root().get_children():
		if child.scene_file_path == GAME_SCENE_PATH:
			child.queue_free()


# ---------------------------------------------------------------- 씬 로드 / 인스턴스화

func _test_player_scene() -> void:
	var packed: PackedScene = load("res://demos/game/player.tscn")
	check(packed != null, "player.tscn 로드")
	var player: PlayerScript = packed.instantiate() as PlayerScript
	check(player is CharacterBody2D, "Player 루트는 CharacterBody2D")
	check(player.has_signal("hit"), "Player 는 커스텀 시그널 hit 을 가진다")
	check(player.is_in_group("player"), "Player 는 그룹 player 에 속한다 (.tscn groups=)")
	var shape: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	check(shape != null and shape.shape is CircleShape2D, "CollisionShape2D 의 shape 는 CircleShape2D (sub_resource)")
	check(player.get_node_or_null("Polygon2D") is Polygon2D, "Polygon2D 삼각형이 있다")
	# take_hit() 은 hit 을 정확히 한 번만 낸다 (두 번째 호출은 무시).
	get_root().add_child(player)
	player.hit.connect(func() -> void: hit_count += 1)
	player.take_hit()
	player.take_hit()
	check(hit_count == 1, "take_hit() 두 번 → hit 시그널은 한 번 (count=%d)" % hit_count)
	check(player.alive == false, "take_hit() 뒤 alive == false")
	player.free()


func _test_mob_scene() -> void:
	var packed: PackedScene = load("res://demos/game/mob.tscn")
	check(packed != null, "mob.tscn 로드")
	var mob: Node = packed.instantiate()
	check(mob is Area2D, "Mob 루트는 Area2D")
	check(not mob.has_signal("hit"), "Mob 은 커스텀 시그널을 정의하지 않는다 (has_signal('hit') == false)")
	check(mob.has_signal("body_entered"), "Mob 은 Area2D 의 body_entered 를 쓴다")
	check(mob.is_in_group("mobs"), "Mob 은 그룹 mobs 에 속한다 (.tscn groups=)")
	var connections: Array[Dictionary] = mob.get_signal_connection_list("body_entered")
	check(connections.size() == 1, ".tscn [connection] 이 body_entered 를 1개 연결했다 (%d)" % connections.size())
	if connections.size() == 1:
		var callable: Callable = connections[0]["callable"]
		check(callable.get_method() == StringName("_on_body_entered"), "연결된 메서드는 _on_body_entered")
	mob.free()


func _test_mob_stats() -> void:
	var fast: Resource = load("res://demos/game/mob_stats_fast.tres")
	var slow: Resource = load("res://demos/game/mob_stats_slow.tres")
	check(fast != null and slow != null, "mob_stats_fast/slow.tres 로드")
	check(fast is MobStatsScript and slow is MobStatsScript, "두 .tres 모두 MobStats 스크립트 인스턴스")
	var fast_stats: MobStatsScript = fast as MobStatsScript
	var slow_stats: MobStatsScript = slow as MobStatsScript
	check(fast_stats.speed_min < fast_stats.speed_max, "fast: speed_min < speed_max")
	check(slow_stats.speed_min < slow_stats.speed_max, "slow: speed_min < speed_max")
	check(fast_stats.speed_min > slow_stats.speed_max, "fast 의 최저 속도가 slow 의 최고 속도보다 빠르다")
	check(fast_stats.color != slow_stats.color, "두 스탯의 색이 다르다")
	check(load("res://demos/game/mob_stats_fast.tres") == fast, "같은 경로 load() 는 ResourceCache 로 같은 객체를 돌려준다")


# ---------------------------------------------------------------- 프로젝트 설정 / 오토로드

func _test_input_actions() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		check(InputMap.has_action(action), "입력 액션 %s 존재" % action)
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		check(events.size() == 2, "%s 에 이벤트 2개 (WASD + 방향키), 실제 %d" % [action, events.size()])
	check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "gl_compatibility",
		"rendering_method == gl_compatibility")


func _test_log_autoload() -> void:
	check(get_root().has_node("Log"), "오토로드 Log 가 root 아래에 있다")
	var log_node: LogScript = get_root().get_node("Log") as LogScript
	var handler: Callable = func(text: String, _level: int) -> void: log_received.append(text)
	log_node.message.connect(handler)
	log_node.info("selftest ping")
	log_node.message.disconnect(handler)
	check(log_received.size() == 1 and log_received[0] == "selftest ping", "Log.info 가 message 시그널을 방출한다")


func _test_card_export_before_add_child() -> void:
	var packed: PackedScene = load("res://demos/scene_instancing/card.tscn")
	var card: ColorRect = packed.instantiate() as ColorRect
	# card.gd 는 Log 를 쓰므로 타입으로 preload 할 수 없다 → Object.set() 으로 @export 값을 넣는다.
	card.set("title", "테스트")
	card.set("number", 7)
	get_root().add_child(card)
	var title_label: Label = card.get_node("Title") as Label
	check(title_label.text == "테스트\n#7", "add_child 전에 넣은 @export 값이 _ready 에서 보인다")
	check(card.owner == null and title_label.owner == card, "인스턴스 루트의 owner 는 null, 자식의 owner 는 루트")
	card.free()


# ---------------------------------------------------------------- 게임: 그룹 / 스폰 / 재시작

func _test_game_spawn_three_mobs() -> void:
	var packed: PackedScene = load(GAME_SCENE_PATH)
	check(packed != null, "game.tscn 로드")
	game = packed.instantiate() as Node2D
	get_root().add_child(game)
	check(game.scene_file_path == GAME_SCENE_PATH, "instantiate 된 루트의 scene_file_path 가 원본 경로")
	check(get_nodes_in_group("mobs").is_empty(), "시작 직후 mobs 그룹은 비어 있다")
	var spawner: Node = game.get_node("MobSpawner")
	for i: int in 3:
		var mob: Node2D = spawner.call("spawn_mob") as Node2D
		check(mob != null and mob.is_inside_tree() and mob.get_parent() == game,
			"스폰된 몹 %d 이(가) Game 의 자식으로 트리에 들어갔다" % i)
	check(get_nodes_in_group("mobs").size() == 3, "몹 3마리 스폰 → get_nodes_in_group('mobs').size() == 3")
	# 게임 오버와 같은 방식으로 그룹 호출. queue_free 는 프레임 끝에야 실제로 지워진다.
	call_group("mobs", "queue_free")
	check(get_nodes_in_group("mobs").size() == 3, "call_group(queue_free) 직후엔 아직 3마리 (지연 삭제)")


func _test_mobs_gone_after_frame() -> void:
	check(get_nodes_in_group("mobs").size() == 0, "한 프레임 뒤 mobs 그룹 크기 == 0")
	check(is_instance_valid(game) and game.is_inside_tree(), "Game 자체는 그대로 살아 있다")


func _test_restart_reinstantiates() -> void:
	old_game_id = game.get_instance_id()
	game.call("restart")
	# 옛 인스턴스는 즉시 트리에서 빠지고 queue_free 로 예약되며, 새 인스턴스가 같은 자리에 들어온다.
	check(not game.is_inside_tree() and game.is_queued_for_deletion(), "restart(): 옛 Game 은 트리에서 빠지고 queue_free 예약됨")
	check(is_instance_valid(game), "restart() 직후 옛 Game 객체는 아직 살아 있다 (프레임 끝에 삭제)")
	check(_count_game_instances() == 1, "restart() 직후 root 아래 Game 인스턴스는 새것 1개")
	check(get_root().get_node_or_null("Game") != null, "새 인스턴스가 'Game' 이름을 그대로 쓴다")


func _test_restart_after_frame() -> void:
	check(not is_instance_valid(instance_from_id(old_game_id)), "한 프레임 뒤 옛 Game 은 해제됨")
	check(_count_game_instances() == 1, "root 아래 Game 인스턴스는 정확히 1개")
	var fresh: Node2D = null
	for child: Node in get_root().get_children():
		if child.scene_file_path == GAME_SCENE_PATH:
			fresh = child as Node2D
	check(fresh != null and fresh.get("score") == 0 and fresh.get("playing") == false,
		"새 Game 은 점수 0, 아직 시작 전(StartTimer 대기)")
	check(fresh != null and fresh.get_node_or_null("WallTop") is StaticBody2D, "새 Game 에 코드로 만든 벽이 있다")


func _count_game_instances() -> int:
	var count: int = 0
	for child: Node in get_root().get_children():
		if child.scene_file_path == GAME_SCENE_PATH:
			count += 1
	return count
