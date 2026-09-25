extends Control

## 데모 2: 같은 그림을 (왼쪽) RenderingServer 캔버스 아이템 명령으로 직접, (오른쪽) CanvasItem._draw() 로 그린다.
## 핵심: 2D 그리기는 "명령 리스트를 서버(RendererCanvasCull)에 저장" 하는 것이지 매 프레임 다시 그리는 게 아니다.
##  - RS.canvas_item_add_rect 등은 Item::Command 를 쌓는다     (servers/rendering/renderer_canvas_cull.cpp:1300)
##  - canvas_item_set_transform 은 명령을 다시 쌓지 않고 트랜스폼만 바꾼다 (:636)
##  - canvas_item_clear 가 명령 리스트를 비운다                     (:1945)
##  - _draw() 는 queue_redraw() → call_deferred(_redraw_callback) (scene/main/canvas_item.cpp:540, :143)
##    에서 canvas_item_clear + NOTIFICATION_DRAW 로 호출되고, 그 안의 draw_* 는 같은 RS.canvas_item_add_* 다.
##  - 실제 래스터화는 백엔드의 RendererCanvasRender 가 프레임마다 명령 리스트를 배치해 수행한다
##    (servers/rendering/renderer_canvas_render.h, renderer_rd/renderer_canvas_render_rd.cpp,
##     drivers/gles3/rasterizer_canvas_gles3.cpp).


## 오른쪽 절반: _draw() 로 그리는 쪽. 호출 횟수를 센다.
class DrawSide extends Control:
	var draw_count: int = 0
	var tint: Color = Color(0.3, 0.8, 0.4)
	var angle: float = 0.0

	func _draw() -> void:
		draw_count += 1
		# draw_* 는 RS.canvas_item_add_* 의 얇은 래퍼. 회전은 명령에 구워지므로 다시 그리기 전엔 안 바뀐다.
		draw_set_transform(CENTER, angle)
		draw_rect(Rect2(-60, -40, 120, 80), tint)
		draw_circle(Vector2(0, -70), 25.0, tint.lightened(0.3))
		draw_line(Vector2(-80, 60), Vector2(80, 60), Color.WHITE, 4.0)
		draw_polygon(PackedVector2Array([Vector2(-70, -40), Vector2(70, -40), Vector2(0, -100)]), PackedColorArray([tint.darkened(0.3)]))


const CENTER: Vector2 = Vector2(150, 150)
const LEFT_ORIGIN: Vector2 = Vector2(20, 100)

var rs_item: RID
var rs_tint: Color = Color(0.95, 0.6, 0.2)
var rs_record_count: int = 0
var frame_count: int = 0
var angle: float = 0.0
var spin: bool = true
var redraw_every_frame: bool = false
var draw_side: DrawSide
var stats_label: Label
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 2
	# 서버 쪽 캔버스 아이템 하나. 이 노드의 canvas_item RID 를 부모로 삼으면 트리 트랜스폼을 물려받는다.
	rs_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(rs_item, get_canvas_item())
	_record_rs_commands()

	draw_side = DrawSide.new()
	draw_side.position = Vector2(360, 100)
	draw_side.size = Vector2(300, 300)
	add_child(draw_side)
	_build_ui()
	Log.info("왼쪽은 RS 캔버스 아이템(명령 1회 기록 + 매 프레임 transform 만 갱신), 오른쪽은 _draw() 입니다.")
	Log.info("오른쪽은 queue_redraw() 를 부르기 전엔 정지합니다. 그리기 명령이 서버에 저장되어 재사용되기 때문입니다.")
	Log.info("노드의 rotation 을 바꾸면 _draw 를 다시 부르지 않고도 RS 쪽처럼 돌릴 수 있습니다 (canvas_item_set_transform).")


func _exit_tree() -> void:
	RenderingServer.free_rid(rs_item)


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(8, 8)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var spin_check := CheckBox.new()
	spin_check.text = "회전 (매 프레임 transform 갱신)"
	spin_check.button_pressed = spin
	spin_check.toggled.connect(func(v: bool) -> void: spin = v)
	row.add_child(spin_check)
	var record_button := Button.new()
	record_button.text = "RS: 명령 다시 기록 (clear + add)"
	record_button.pressed.connect(_on_record_pressed)
	row.add_child(record_button)
	var redraw_button := Button.new()
	redraw_button.text = "_draw: queue_redraw() 한 번"
	redraw_button.pressed.connect(_on_redraw_pressed)
	row.add_child(redraw_button)
	var every_check := CheckBox.new()
	every_check.text = "매 프레임 queue_redraw()"
	every_check.toggled.connect(func(v: bool) -> void: redraw_every_frame = v)
	row.add_child(every_check)
	stats_label = Label.new()
	box.add_child(stats_label)


## 왼쪽 그림의 명령 리스트를 서버에 (다시) 기록한다. 원점 기준으로 기록하고 위치/회전은 transform 으로 준다.
func _record_rs_commands() -> void:
	RenderingServer.canvas_item_clear(rs_item)
	RenderingServer.canvas_item_add_rect(rs_item, Rect2(-60, -40, 120, 80), rs_tint)
	RenderingServer.canvas_item_add_circle(rs_item, Vector2(0, -70), 25.0, rs_tint.lightened(0.3))
	RenderingServer.canvas_item_add_line(rs_item, Vector2(-80, 60), Vector2(80, 60), Color.WHITE, 4.0)
	RenderingServer.canvas_item_add_polygon(rs_item, PackedVector2Array([Vector2(-70, -40), Vector2(70, -40), Vector2(0, -100)]), PackedColorArray([rs_tint.darkened(0.3)]))
	rs_record_count += 1


func _on_record_pressed() -> void:
	rs_tint = Color.from_hsv(rng.randf(), 0.7, 0.95)
	_record_rs_commands()
	Log.info("RS 명령 재기록 %d회 (canvas_item_clear 후 add_*)" % rs_record_count)


func _on_redraw_pressed() -> void:
	draw_side.tint = Color.from_hsv(rng.randf(), 0.7, 0.95)
	request_redraw()
	Log.info("queue_redraw() 요청 → 다음 메시지 큐 플러시에서 _draw 가 1회 실행됩니다.")


func _process(delta: float) -> void:
	frame_count += 1
	if spin:
		angle += delta
	# 왼쪽: 명령은 그대로, 트랜스폼만 갱신 (RendererCanvasCull::canvas_item_set_transform).
	RenderingServer.canvas_item_set_transform(rs_item, Transform2D(angle, LEFT_ORIGIN + CENTER))
	# 오른쪽: 값은 바꾸지만 queue_redraw 가 없으면 화면은 그대로다.
	draw_side.angle = angle
	if redraw_every_frame:
		draw_side.queue_redraw()
	if frame_count % 15 == 0:
		stats_label.text = "프레임 %d | RS 명령 기록 %d회 | _draw 호출 %d회" % [frame_count, rs_record_count, draw_side.draw_count]


func get_draw_count() -> int:
	return draw_side.draw_count


func request_redraw() -> void:
	draw_side.queue_redraw()
