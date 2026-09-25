extends Control

## 데모 3: PhysicsServer2D 를 노드 없이 직접 쓴다 (body/shape RID). RigidBody2D 노드와 나란히 비교.
## 엔진: servers/physics_2d/physics_server_2d_wrap_mt.h — 스크립트가 부르는 PhysicsServer2D 싱글톤은 이 래퍼.
##       physics/2d/run_on_separate_thread 가 켜지면 CommandQueueMT(:68) 에 명령을 쌓고, 아니면 직접 호출한다.
##       main/main.cpp Main::iteration — 물리 틱마다
##         PhysicsServer2D::sync()(:4992) → flush_queries()(:4993) → SceneTree::physics_process()
##         → end_sync()(:5036) → step(physics_step)(:5037)
##       즉 _physics_process 는 "이전 step 결과가 sync 된 뒤, 다음 step 전" 에 실행된다.
##       그래서 direct_space_state 는 _physics_process 안에서만 안전하게 접근할 수 있다.
##       scene/2d/physics/rigid_body_2d.cpp — RigidBody2D 도 결국 body_create + body_set_state_sync_callback 이다.
##       scene/resources/world_2d.cpp:70 — 중력은 space RID 를 기본 area 로 삼아 area_set_param 으로 준다.

const BALL_RADIUS: float = 14.0
const ARENA: Rect2 = Rect2(0, 0, 640, 400)
const WALL: float = 12.0

var world: Node2D
var space: RID
var circle_shape: RID
var ground_body: RID
var ground_shapes: Array[RID] = []
var bodies: Array[RID] = []
var body_items: Array[RID] = []
var spawn_positions: PackedVector2Array = PackedVector2Array()
var ground_item: RID
var ray_item: RID
var node_bodies: Array[RigidBody2D] = []
var spawned: bool = false
var physics_ticks: int = 0
var last_hit: String = "-"
var default_gravity: float = 980.0
var stats_label: Label
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 5
	world = Node2D.new()
	world.position = Vector2(20, 90)
	add_child(world)
	# CanvasItem.get_world_2d(): 뷰포트의 World2D → 서버 space RID (씬 노드들도 같은 space 를 쓴다).
	space = get_world_2d().space
	default_gravity = float(PhysicsServer2D.area_get_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY))
	circle_shape = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(circle_shape, BALL_RADIUS)
	ground_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(ground_item, world.get_canvas_item())
	ray_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(ray_item, world.get_canvas_item())
	_build_ui()
	Log.info("주황 공 = PhysicsServer2D body RID (그리기는 RS 캔버스 아이템), 파랑 공 = RigidBody2D 노드.")
	Log.info("몸체 생성은 첫 _physics_process 에서 합니다: 컨테이너 레이아웃이 끝난 뒤의 전역 트랜스폼이 필요해서입니다.")
	Log.info("빨간 선은 매 물리 틱 intersect_ray. 중력 슬라이더는 area_set_param(space, AREA_PARAM_GRAVITY).")


func _exit_tree() -> void:
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, default_gravity)
	for body: RID in bodies:
		PhysicsServer2D.free_rid(body)
	if ground_body.is_valid():
		PhysicsServer2D.free_rid(ground_body)
	for shape: RID in ground_shapes:
		PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(circle_shape)
	for item: RID in body_items:
		RenderingServer.free_rid(item)
	RenderingServer.free_rid(ground_item)
	RenderingServer.free_rid(ray_item)


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(8, 8)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var add_server := Button.new()
	add_server.text = "공 추가 (서버 RID)"
	add_server.pressed.connect(_spawn_server_ball)
	row.add_child(add_server)
	var add_node := Button.new()
	add_node.text = "공 추가 (RigidBody2D)"
	add_node.pressed.connect(_spawn_node_ball)
	row.add_child(add_node)
	var gravity_label := Label.new()
	gravity_label.text = "중력"
	row.add_child(gravity_label)
	var gravity := HSlider.new()
	gravity.min_value = 0.0
	gravity.max_value = 2000.0
	gravity.step = 10.0
	gravity.value = default_gravity
	gravity.custom_minimum_size = Vector2(160, 0)
	gravity.value_changed.connect(func(v: float) -> void: PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, v))
	row.add_child(gravity)
	stats_label = Label.new()
	box.add_child(stats_label)


func _spawn_ground() -> void:
	ground_body = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(ground_body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_set_space(ground_body, space)
	# 몸체 트랜스폼 = world 노드의 전역 트랜스폼. 그러면 shape 의 로컬 트랜스폼을 world 좌표로 쓸 수 있다.
	PhysicsServer2D.body_set_state(ground_body, PhysicsServer2D.BODY_STATE_TRANSFORM, world.get_global_transform())
	var rects: Array[Rect2] = [
		Rect2(0, ARENA.size.y - WALL, ARENA.size.x, WALL),
		Rect2(0, 0, WALL, ARENA.size.y),
		Rect2(ARENA.size.x - WALL, 0, WALL, ARENA.size.y),
	]
	for r: Rect2 in rects:
		var shape: RID = PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(shape, r.size * 0.5) # 사각형 데이터는 half extents
		PhysicsServer2D.body_add_shape(ground_body, shape, Transform2D(0.0, r.get_center()))
		ground_shapes.append(shape)
		RenderingServer.canvas_item_add_rect(ground_item, r, Color(0.35, 0.35, 0.4))


func _spawn_server_ball() -> void:
	var body: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(body, circle_shape) # shape RID 는 여러 몸체가 공유해도 된다
	PhysicsServer2D.body_set_space(body, space)
	PhysicsServer2D.body_set_param(body, PhysicsServer2D.BODY_PARAM_BOUNCE, 0.4)
	var local_pos := Vector2(rng.randf_range(60.0, ARENA.size.x - 60.0), rng.randf_range(20.0, 120.0))
	var xf: Transform2D = world.get_global_transform() * Transform2D(rng.randf_range(0.0, TAU), local_pos)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(rng.randf_range(-80.0, 80.0), 0.0))
	bodies.append(body)
	spawn_positions.append(local_pos)
	# 몸체마다 캔버스 아이템 하나: 명령은 한 번만 기록하고 물리 틱마다 transform 만 갱신한다.
	var item: RID = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, world.get_canvas_item())
	RenderingServer.canvas_item_add_circle(item, Vector2.ZERO, BALL_RADIUS, Color(0.95, 0.6, 0.2))
	RenderingServer.canvas_item_add_line(item, Vector2.ZERO, Vector2(BALL_RADIUS, 0.0), Color.BLACK, 2.0)
	body_items.append(item)


func _spawn_node_ball() -> void:
	var rb := RigidBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = BALL_RADIUS
	cs.shape = shape
	rb.add_child(cs)
	var poly := Polygon2D.new()
	poly.polygon = _circle_points(BALL_RADIUS, 20)
	poly.color = Color(0.3, 0.6, 0.95)
	rb.add_child(poly)
	rb.position = Vector2(rng.randf_range(60.0, ARENA.size.x - 60.0), rng.randf_range(20.0, 120.0))
	world.add_child(rb)
	node_bodies.append(rb)


func _physics_process(_delta: float) -> void:
	if not spawned:
		spawned = true
		_spawn_ground()
		for i: int in 6:
			_spawn_server_ball()
		for i: int in 3:
			_spawn_node_ball()
	physics_ticks += 1
	var inv: Transform2D = world.get_global_transform().affine_inverse()
	for i: int in bodies.size():
		var xf: Transform2D = PhysicsServer2D.body_get_state(bodies[i], PhysicsServer2D.BODY_STATE_TRANSFORM)
		RenderingServer.canvas_item_set_transform(body_items[i], inv * xf)
	# 레이캐스트: 위에서 아래로. direct_space_state 는 step 중이 아닐 때(=여기)만 접근 가능하다.
	var from: Vector2 = world.get_global_transform() * Vector2(ARENA.size.x * 0.5, 0.0)
	var to: Vector2 = world.get_global_transform() * Vector2(ARENA.size.x * 0.5, ARENA.size.y)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	var end_local: Vector2 = inv * to
	if hit.is_empty():
		last_hit = "없음"
	else:
		end_local = inv * Vector2(hit["position"])
		last_hit = "%s @ %s" % [_describe_rid(hit["rid"]), str(end_local.round())]
	RenderingServer.canvas_item_clear(ray_item)
	RenderingServer.canvas_item_add_line(ray_item, inv * from, end_local, Color(1.0, 0.3, 0.3), 2.0)
	RenderingServer.canvas_item_add_circle(ray_item, end_local, 5.0, Color(1.0, 0.3, 0.3))
	if physics_ticks % 10 == 0:
		_update_stats()


func _update_stats() -> void:
	var first: String = "-"
	if not bodies.is_empty():
		var xf: Transform2D = PhysicsServer2D.body_get_state(bodies[0], PhysicsServer2D.BODY_STATE_TRANSFORM)
		first = str((world.get_global_transform().affine_inverse() * xf).origin.round())
	stats_label.text = "물리 틱 %d | 서버 공 %d | 노드 공 %d | 활성 객체 %d\n서버 공 #0 위치 %s | 레이 명중: %s | 중력 %.0f" % [
		physics_ticks, bodies.size(), node_bodies.size(),
		PhysicsServer2D.get_process_info(PhysicsServer2D.INFO_ACTIVE_OBJECTS),
		first, last_hit,
		float(PhysicsServer2D.area_get_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY)),
	]


func _describe_rid(rid: RID) -> String:
	if rid == ground_body:
		return "정적 바닥/벽(서버)"
	var idx: int = bodies.find(rid)
	if idx >= 0:
		return "서버 공 #%d" % idx
	for i: int in node_bodies.size():
		if node_bodies[i].get_rid() == rid:
			return "RigidBody2D 노드 #%d" % i
	return "알 수 없는 RID"


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in segments:
		var a: float = TAU * i / segments
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points


func get_server_ball_local_positions() -> PackedVector2Array:
	var result := PackedVector2Array()
	var inv: Transform2D = world.get_global_transform().affine_inverse()
	for body: RID in bodies:
		var xf: Transform2D = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM)
		result.append((inv * xf).origin)
	return result


func get_server_ball_spawn_positions() -> PackedVector2Array:
	return spawn_positions


func get_last_hit() -> String:
	return last_hit
