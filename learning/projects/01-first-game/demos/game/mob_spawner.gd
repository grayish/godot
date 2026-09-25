extends Node
## 몹 스포너. 자식 Timer(SpawnTimer)의 timeout 마다 아레나 가장자리 밖 임의 지점에서 몹을 만들어 안쪽으로 쏜다.
## 이 노드는 그림도 물리도 없는 순수 Node — "기능을 자식 노드로 붙인다"는 Godot 방식의 작은 예
## (8장 8.2: 컴포넌트 대신 노드).

const MOB_SCENE: PackedScene = preload("res://demos/game/mob.tscn")
const MobScript: GDScript = preload("res://demos/game/mob.gd")
## 스탯 풀. 스폰마다 임의로 하나를 고른다. 두 .tres 는 같은 스크립트, 다른 값.
const STATS_POOL: Array[Resource] = [
	preload("res://demos/game/mob_stats_fast.tres"),
	preload("res://demos/game/mob_stats_slow.tres"),
]
## 아레나 밖 이만큼 떨어진 곳에서 태어난다.
const SPAWN_MARGIN := 60.0

## game.gd 가 덮어쓴다.
var arena: Rect2 = Rect2(0, 0, 960, 520)
var spawned_total: int = 0

@onready var spawn_timer: Timer = $SpawnTimer


func start() -> void:
	spawned_total = 0
	spawn_timer.start()


func stop() -> void:
	spawn_timer.stop()


## game.tscn [connection signal="timeout" from="MobSpawner/SpawnTimer" to="MobSpawner" method="_on_spawn_timer_timeout"]
func _on_spawn_timer_timeout() -> void:
	spawn_mob()


## 몹 하나를 만들어 부모(Game) 아래에 넣고 발사한다. selftest 가 직접 부르기도 한다.
func spawn_mob() -> Node2D:
	var mob: MobScript = MOB_SCENE.instantiate() as MobScript
	# add_child 전에 값을 넣어 두면 _ready 에서 바로 쓸 수 있다.
	mob.stats = STATS_POOL[randi_range(0, STATS_POOL.size() - 1)]
	mob.bounds = arena.grow(SPAWN_MARGIN * 3.0)

	var from: Vector2
	match randi_range(0, 3):
		0:
			from = Vector2(randf_range(arena.position.x, arena.end.x), arena.position.y - SPAWN_MARGIN)
		1:
			from = Vector2(arena.end.x + SPAWN_MARGIN, randf_range(arena.position.y, arena.end.y))
		2:
			from = Vector2(randf_range(arena.position.x, arena.end.x), arena.end.y + SPAWN_MARGIN)
		_:
			from = Vector2(arena.position.x - SPAWN_MARGIN, randf_range(arena.position.y, arena.end.y))
	var target: Vector2 = arena.get_center() + Vector2(randf_range(-160.0, 160.0), randf_range(-100.0, 100.0))

	# 몹은 Game 노드의 자식으로 넣는다: 아레나 좌표계를 같이 쓰고, 게임이 사라지면 같이 사라진다.
	get_parent().add_child(mob)
	mob.launch(from, target - from)
	spawned_total += 1
	if spawned_total % 10 == 1:
		Log.info("몹 스폰 #%d: %s (그룹 mobs 크기 %d)" % [
			spawned_total, mob.stats.display_name, get_tree().get_nodes_in_group("mobs").size()])
	return mob
