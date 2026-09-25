extends Area2D
## 몹. Area2D 는 "겹침을 감지"만 하고 물리적으로 밀리지 않는다 — 벽을 통과해 들어와 플레이어만 감지한다
## (collision_mask = 1 은 플레이어 레이어만 본다; mob.tscn 참고).
## 스탯은 리소스(MobStats)로 분리: 같은 씬, 다른 .tres → 다른 속도/색.
## 이 씬은 자기 시그널을 정의하지 않는다. Area2D 가 이미 가진 body_entered 를 .tscn 의 [connection] 으로 받는다.

## MobStats 타입을 전역 이름 대신 preload 상수로 가리킨다 (mob_stats.gd 주석의 캐시 문제 참고).
const MobStatsScript: GDScript = preload("res://demos/game/mob_stats.gd")
## 아무 스탯도 안 꽂혀 있을 때(mob.tscn 을 단독 실행) 쓰는 기본값.
const DEFAULT_COLOR := Color(0.8, 0.8, 0.8, 1)

## 인스펙터에서 .tres 를 끌어다 놓거나, 스포너가 add_child 전에 코드로 넣는다.
@export var stats: MobStatsScript
var velocity: Vector2 = Vector2.ZERO
## 이 밖으로 나가면 스스로 사라진다. 스포너가 아레나를 넉넉히 키운 값으로 덮어쓴다.
## (VisibleOnScreenNotifier2D 는 렌더링이 필요해 헤드리스에선 신호가 오지 않으므로 좌표로 판단한다.)
var bounds: Rect2 = Rect2(-200, -200, 1360, 920)

@onready var body_polygon: Polygon2D = $Polygon2D


func _ready() -> void:
	_ensure_stats()
	body_polygon.color = stats.color


## 스포너가 add_child 뒤에 부른다. 시작점과 방향을 주면 스탯 범위에서 속도를 고른다.
func launch(from: Vector2, direction: Vector2) -> void:
	_ensure_stats()
	position = from
	var speed: float = randf_range(stats.speed_min, stats.speed_max)
	velocity = direction.normalized() * speed
	rotation = direction.angle()


func _process(delta: float) -> void:
	# 물리 몸체가 아니므로 위치를 직접 옮긴다. Area2D 의 겹침 검사는 다음 물리 프레임에 갱신된다.
	position += velocity * delta
	if not bounds.has_point(position):
		queue_free()


## mob.tscn [connection signal="body_entered" from="." to="." method="_on_body_entered"] 이 부른다.
## body 는 PhysicsBody2D — 마스크 덕에 플레이어만 들어온다. 그래도 덕 타이핑으로 한 번 더 확인.
func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_hit"):
		body.call("take_hit")


func _ensure_stats() -> void:
	if stats == null:
		Log.warn("Mob: stats 리소스가 없어 기본값을 씁니다 (mob.tscn 단독 실행?)")
		stats = MobStatsScript.new()
		stats.color = DEFAULT_COLOR
