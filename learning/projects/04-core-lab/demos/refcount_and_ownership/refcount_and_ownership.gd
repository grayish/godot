extends Control
## 데모 3: 참조 카운트와 소유권 — RefCounted/Ref<T>, 순환 참조 누수, Node 소유권 트리, Resource 복제.
## 엔진: core/object/ref_counted.h (reference/unreference → 0 이면 memdelete), core/object/object.h ObjectDB,
##       scene/main/node.cpp Node::~Node() (자식 memdelete), core/io/resource.cpp Resource::duplicate(),
##       scene/resources/packed_scene.cpp (resource_local_to_scene → duplicate_for_local_scene).
## 핵심 규칙: Resource 는 RefCounted(참조 카운트 소유), Node 는 아니다(부모가 소유, queue_free).

## RefCounted 실험 대상.
class Payload extends RefCounted:
	var label: String
	var other: RefCounted = null
	var weak: WeakRef = null

	func _init(p_label: String = "") -> void:
		label = p_label


## Resource 복제 실험 대상. @export 만 PROPERTY_USAGE_STORAGE 를 가져 duplicate() 대상이 된다.
class Stats extends Resource:
	@export var hp: int = 10
	@export var tags: Array[String] = []
	@export var inner: Resource = null
	var runtime_only: int = 0


func _ready() -> void:
	_build_ui()
	Log.section("참조 카운트와 소유권")
	_demo_refcount()
	_demo_cycle_leak()
	_demo_node_ownership()
	_demo_resource_duplicate()
	_demo_local_to_scene()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "RefCounted / 순환 참조 / Node 소유권 / Resource duplicate — 버튼으로 각 실험을 다시 실행"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	var items: Array = [
		["참조 카운트", _demo_refcount], ["순환 참조 누수", _demo_cycle_leak], ["Node 소유권", _demo_node_ownership],
		["Resource duplicate", _demo_resource_duplicate], ["local_to_scene", _demo_local_to_scene],
	]
	for item: Array in items:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		row.add_child(button)


func _demo_refcount() -> void:
	Log.section("RefCounted.get_reference_count()")
	var a := Payload.new("A")
	Log.info("Payload.new() → count=%d (지역 변수의 Ref<T> 하나)" % a.get_reference_count())
	var b := a
	Log.info("var b := a → count=%d (Ref 복사 = reference(), SafeRefCount 원자 증가)" % a.get_reference_count())
	var list: Array = [a]
	Log.info("Array 에 넣음 → count=%d (Array 원소 Variant 도 Ref 를 든다)" % a.get_reference_count())
	b = null
	list.clear()
	Log.info("b = null, list.clear() → count=%d (unreference())" % a.get_reference_count())
	var id: int = a.get_instance_id()
	a = null
	Log.info("마지막 참조 해제 → is_instance_id_valid=%s (unreference 가 0 을 돌려주면 memdelete)" % str(is_instance_id_valid(id)))


func _demo_cycle_leak() -> void:
	Log.section("순환 참조 누수와 WeakRef")
	var x := Payload.new("X")
	var y := Payload.new("Y")
	x.other = y
	y.other = x
	var x_id: int = x.get_instance_id()
	var y_id: int = y.get_instance_id()
	x = null
	y = null
	Log.warn("X↔Y 강한 참조 고리: 지역 변수를 다 놓았는데 X 살아있음=%s, Y=%s → 누수 (카운트가 0 이 되지 않음)" % [
		str(is_instance_id_valid(x_id)), str(is_instance_id_valid(y_id))])
	# ObjectDB 로 다시 찾아 고리를 끊는다 — 실제 코드라면 애초에 한쪽을 WeakRef 로 만들어야 한다.
	var rescued: Payload = instance_from_id(x_id) as Payload
	(rescued.other as Payload).other = null
	rescued.other = null
	rescued = null
	Log.info("고리를 끊고 참조를 놓으니 X=%s, Y=%s (둘 다 해제)" % [str(is_instance_id_valid(x_id)), str(is_instance_id_valid(y_id))])

	var p := Payload.new("P")
	var q := Payload.new("Q")
	p.weak = weakref(q)
	q.other = p
	var p_id: int = p.get_instance_id()
	var q_id: int = q.get_instance_id()
	p = null
	q = null
	Log.info("P→Q 를 WeakRef 로: 놓은 뒤 P=%s, Q=%s (WeakRef 는 카운트를 올리지 않아 고리가 생기지 않는다)" % [
		str(is_instance_id_valid(p_id)), str(is_instance_id_valid(q_id))])


func _demo_node_ownership() -> void:
	Log.section("Node 소유권 트리: 부모를 free 하면 자식도 사라진다")
	var parent := Node.new()
	var child := Node.new()
	var grandchild := Node.new()
	parent.add_child(child)
	child.add_child(grandchild)
	var child_id: int = child.get_instance_id()
	var grandchild_id: int = grandchild.get_instance_id()
	parent.free()
	Log.info("parent.free() → child 살아있음=%s, grandchild=%s (Node::~Node 가 자식들을 memdelete, node.cpp)" % [
		str(is_instance_id_valid(child_id)), str(is_instance_id_valid(grandchild_id))])
	var parent2 := Node.new()
	var orphan := Node.new()
	parent2.add_child(orphan)
	parent2.remove_child(orphan)
	parent2.free()
	Log.info("remove_child 로 떼어낸 노드는 부모가 죽어도 살아있음=%s → 직접 free() 해야 누수가 없다" % str(is_instance_valid(orphan)))
	orphan.free()
	Log.info("Node 는 RefCounted 가 아니다: get_reference_count 없음, 트리 밖 Node 는 소유자가 없으니 free/queue_free 책임은 만든 쪽")


func _demo_resource_duplicate() -> void:
	Log.section("Resource 공유 vs duplicate() vs duplicate(true)")
	var stats := Stats.new()
	stats.hp = 10
	stats.tags = ["fire"]
	stats.inner = Stats.new()
	stats.runtime_only = 7
	var shared := stats
	var shallow: Stats = stats.duplicate() as Stats
	var deep: Stats = stats.duplicate(true) as Stats
	shared.hp = 11
	Log.info("var shared := stats 는 같은 객체: shared.hp=11 → stats.hp=%d (Resource 는 참조 타입)" % stats.hp)
	shallow.hp = 99
	shallow.tags.append("ice")
	Log.info("duplicate(): shallow.hp=99 → stats.hp=%d (값 타입 복사) / shallow.tags.append → stats.tags=%s (Array 는 공유!)" % [
		stats.hp, str(stats.tags)])
	deep.tags.append("wind")
	Log.info("duplicate(true): deep.tags.append → stats.tags=%s (배열/딕셔너리도 재귀 복제)" % str(stats.tags))
	Log.info("내부 Resource: shallow.inner == stats.inner ? %s / deep.inner == stats.inner ? %s (deep 은 내장 서브리소스 복제)" % [
		str(shallow.inner == stats.inner), str(deep.inner == stats.inner)])
	Log.info("@export 아닌 runtime_only: 원본 %d, shallow %d → STORAGE 플래그가 있는 프로퍼티만 복사된다 (resource.cpp Resource::duplicate)" % [
		stats.runtime_only, shallow.runtime_only])


func _demo_local_to_scene() -> void:
	Log.section("resource_local_to_scene: 씬 인스턴스마다 리소스를 복제")
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = 20
	label.label_settings = settings
	var packed := PackedScene.new()
	packed.pack(label)
	var a := packed.instantiate() as Label
	var b := packed.instantiate() as Label
	Log.info("기본값(false): 두 인스턴스가 같은 LabelSettings 공유? %s (서브리소스는 씬 상태에 한 번만 저장)" % str(a.label_settings == b.label_settings))
	settings.resource_local_to_scene = true
	packed.pack(label)
	var c := packed.instantiate() as Label
	var d := packed.instantiate() as Label
	Log.info("local_to_scene=true: 같은 객체? %s → 인스턴스마다 복제 (packed_scene.cpp duplicate_for_local_scene)" % str(c.label_settings == d.label_settings))
	Log.info("쓰임새: 인스턴스별로 다른 머티리얼 색/셰이더 파라미터. 실행 중 플래그를 바꿔도 이미 만든 인스턴스엔 영향 없음")
	for node: Node in [label, a, b, c, d]:
		node.free()
