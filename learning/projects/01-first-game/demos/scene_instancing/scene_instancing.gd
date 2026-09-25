extends Control
## 씬 인스턴스화. .tscn 은 "노드 트리의 직렬화"이고 PackedScene.instantiate() 가 그것을 되살린다
## (엔진: scene/resources/packed_scene.cpp SceneState::instantiate — ClassDB::instantiate 로 노드를 만들고
## 속성을 set 하고 [connection] 을 connect 한다).
## 보여 주는 것: preload, N 번 instantiate, owner/get_path/get_parent, add_child 전 @export 설정,
## queue_free vs free, reparent.

## preload 는 파싱 시점에 로드되는 상수 — 스크립트가 로드될 때 card.tscn 도 함께 메모리에 올라온다.
## load() 는 호출 시점에 로드한다 (ResourceCache 가 있어 두 번째부터는 같은 객체를 돌려준다).
const CARD_SCENE: PackedScene = preload("res://demos/scene_instancing/card.tscn")
const CardScript: GDScript = preload("res://demos/scene_instancing/card.gd")
const CARD_COLORS: Array[Color] = [
	Color(0.85, 0.35, 0.35), Color(0.35, 0.7, 0.4), Color(0.35, 0.5, 0.9), Color(0.85, 0.65, 0.3),
]

var deck_a: HBoxContainer
var deck_b: HBoxContainer
var spawned: int = 0


func _ready() -> void:
	Log.section("씬 인스턴스화")
	_build_ui()
	# 헤드리스 검증에서도 흐름이 보이도록 세 단계를 자동으로 한 번 실행한다.
	spawn_cards(3)
	demo_free()
	demo_reparent()
	Log.info("현재 트리:\n" + get_tree_string_pretty())


func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	column.add_child(buttons)
	_make_button(buttons, "카드 3장 instantiate", func() -> void: spawn_cards(3))
	_make_button(buttons, "queue_free vs free", demo_free)
	_make_button(buttons, "마지막 카드 reparent A→B", demo_reparent)
	_make_button(buttons, "트리 출력", func() -> void: Log.info(get_tree_string_pretty()))

	column.add_child(_make_label("Deck A (인스턴스가 처음 붙는 곳)"))
	deck_a = HBoxContainer.new()
	deck_a.name = "DeckA"
	deck_a.custom_minimum_size = Vector2(0, 90)
	column.add_child(deck_a)

	column.add_child(_make_label("Deck B (reparent 로 옮겨지는 곳)"))
	deck_b = HBoxContainer.new()
	deck_b.name = "DeckB"
	deck_b.custom_minimum_size = Vector2(0, 90)
	column.add_child(deck_b)


func _make_button(parent: Node, text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	parent.add_child(button)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


## 같은 PackedScene 에서 N 개의 독립된 인스턴스를 만든다.
func spawn_cards(count: int) -> void:
	for i: int in count:
		var card: CardScript = CARD_SCENE.instantiate() as CardScript
		# add_child 전에 @export 값을 채운다 → card._ready 가 이미 이 값을 본다.
		card.title = "카드 %d" % spawned
		card.number = spawned
		card.card_color = CARD_COLORS[spawned % CARD_COLORS.size()]
		card.name = "Card%d" % spawned
		spawned += 1
		# add_child: 이름 중복이면 자동으로 뒤에 숫자가 붙는다. 이 호출 안에서 _enter_tree → _ready 가 이어진다.
		deck_a.add_child(card)
		Log.info("instantiate #%d → get_parent()=%s, get_path()=%s, scene_file_path=%s" % [
			card.number, card.get_parent().name, card.get_path(), card.scene_file_path])


## queue_free: 프레임 끝(SceneTree::_flush_delete_queue)에 지워진다. 시그널 핸들러 안에서도 안전.
## free: 즉시 지워진다. 그 노드를 가리키던 변수는 곧바로 유효하지 않게 된다.
func demo_free() -> void:
	if deck_a.get_child_count() < 2:
		Log.warn("카드가 2장 이상 있어야 합니다. 먼저 instantiate 하세요.")
		return
	var queued: Node = deck_a.get_child(0)
	var freed: Node = deck_a.get_child(1)
	var queued_name: String = queued.name
	var freed_name: String = freed.name

	queued.queue_free()
	Log.info("%s.queue_free() 직후: is_instance_valid=%s, is_queued_for_deletion=%s, 아직 부모의 자식 수=%d" % [
		queued_name, str(is_instance_valid(queued)), str(queued.is_queued_for_deletion()), deck_a.get_child_count()])

	freed.free()
	Log.info("%s.free() 직후: is_instance_valid=%s, 부모의 자식 수=%d (즉시 사라짐)" % [
		freed_name, str(is_instance_valid(freed)), deck_a.get_child_count()])


## reparent: remove_child + add_child 를 한 번에. owner 는 새 위치에서도 닿을 수 있으면 유지된다.
func demo_reparent() -> void:
	var count: int = deck_a.get_child_count()
	var candidate: Node = null
	# queue_free 예약된 카드는 건너뛴다 (아직 자식 목록에 있다).
	for i: int in range(count - 1, -1, -1):
		var child: Node = deck_a.get_child(i)
		if not child.is_queued_for_deletion():
			candidate = child
			break
	if candidate == null:
		Log.warn("Deck A 에 옮길 카드가 없습니다.")
		return
	var before: NodePath = candidate.get_path()
	candidate.reparent(deck_b)
	Log.info("reparent: %s → %s (같은 노드 객체, 부모만 바뀜: instance_id=%d)" % [
		before, candidate.get_path(), candidate.get_instance_id()])
