extends CharacterBody2D
## 플레이어. 입력 액션(project.godot [input]) → velocity → move_and_slide().
## CharacterBody2D 는 "코드로 움직이고 충돌은 엔진이 풀어 주는" 몸체다
## (엔진: scene/2d/physics/character_body_2d.cpp move_and_slide()).
## 몹(Area2D)이 body_entered 로 우리를 감지하면 take_hit() 을 부르고, 우리는 hit 시그널을 낸다.
## 게임 로직은 이 시그널만 듣는다 — 플레이어는 "누가 듣는지" 모른다. 이것이 시그널을 쓰는 이유.

## 몹에 맞았을 때 방출. game.tscn 의 [connection] 블록이 Game._on_player_hit 에 연결한다.
signal hit

@export var speed: float = 420.0
## 움직일 수 있는 영역. game.gd 가 벽 안쪽 영역으로 덮어쓴다. 단독 실행(F6)이면 기본값을 쓴다.
var arena: Rect2 = Rect2(0, 0, 960, 520)
var alive: bool = true
## 반지름(player.tscn 의 CircleShape2D radius) + 여유. 벽이 있어도 clamp 로 이중 안전망을 둔다.
var radius: float = 20.0

# @onready: _ready 직전에 평가된다. 자식은 부모보다 먼저 _ready 되므로 이 시점엔 자식이 이미 트리에 있다
# (엔진: scene/main/node.cpp _propagate_ready() 는 자식 → 부모 순).
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var body_polygon: Polygon2D = $Polygon2D


func _physics_process(_delta: float) -> void:
	if not alive:
		return
	# 네 액션을 한 번에 벡터로: 대각선 길이가 1 로 정규화되고 데드존이 원형으로 적용된다.
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()
	position = position.clamp(arena.position + Vector2(radius, radius), arena.end - Vector2(radius, radius))
	if direction != Vector2.ZERO:
		# 삼각형의 꼭짓점(위쪽, -y)이 진행 방향을 보도록 90도 보정.
		rotation = direction.angle() + PI / 2.0


## 새 게임마다 game.gd 가 부른다.
func start(at: Vector2) -> void:
	position = at
	rotation = 0.0
	alive = true
	show()
	# 물리 콜백 도중 충돌 상태를 바꾸면 안 되므로 set_deferred 로 다음 idle 시점에 적용한다.
	collision_shape.set_deferred("disabled", false)


## 몹(mob.gd)이 body_entered 안에서 부른다. 한 번만 반응한다.
func take_hit() -> void:
	if not alive:
		return
	alive = false
	hide()
	collision_shape.set_deferred("disabled", true)
	hit.emit()
