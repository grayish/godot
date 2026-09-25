extends Control
## 데모 4: 클래스 시스템과 타입 — class_name/내부 클래스, _init(인자), static, super, is/as, 덕 타이핑,
## enum + match, @export 변형, setter/getter, Array[T] / Dictionary[K, V].
## 엔진: modules/gdscript/gdscript_analyzer.cpp (상속 해석, is/as 타입 검사), gdscript.cpp (static 변수, 내부 클래스),
##       core/object/object.cpp Object::get_property_list (@export 메타데이터가 인스펙터에 가는 길).

# class_name Animal 이 있지만 헤드리스에는 전역 클래스 캐시가 없어 preload 로 참조한다 (README '흔한 함정').
const Animals := preload("res://demos/classes_and_typing/animals.gd")

## @export 변형들. 값 자체보다 get_property_list() 에 실리는 hint / hint_string 을 보는 것이 목적이다.
@export_range(0, 10, 1) var max_pets: int = 3
@export_enum("Small", "Medium", "Large") var size_class: int = 1
@export_node_path("Label") var title_label_path: NodePath
@export var linked_node: Node
@export var tint: Color = Color.CORNFLOWER_BLUE
@export_multiline var notes: String = "인스펙터에서 여러 줄로 편집"

## setter 가 값을 걸러 주는 프로퍼티. 대입은 항상 setter 를 지난다 (본문 안에서만 백킹 필드 직접 접근).
var score: int = 0:
	set(value):
		score = maxi(value, 0)
		_score_writes += 1
	get:
		return score
var _score_writes: int = 0

var zoo: Array[Animals] = []
var counts: Dictionary[String, int] = {}
var _title: Label


func _ready() -> void:
	_build_ui()
	title_label_path = get_path_to(_title)
	linked_node = _title
	_run()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	_title = Label.new()
	_title.text = "클래스와 타입 — 결과는 로그 패널에"
	column.add_child(_title)
	var rerun := Button.new()
	rerun.text = "다시 실행"
	rerun.pressed.connect(_run)
	column.add_child(rerun)


func _run() -> void:
	Animals.reset_population()
	zoo.clear()
	counts.clear()
	_show_classes()
	_show_inheritance()
	_show_duck_typing()
	_show_enum_match()
	_show_properties_and_containers()
	_show_exports()


func _show_classes() -> void:
	Log.section("class_name + 내부 클래스 + _init(인자) + static")
	var rex: Animals.Dog = Animals.Dog.new("렉스")
	var tom: Animals.Cat = Animals.Cat.new("톰")
	var tweety: Animals.Bird = Animals.Bird.new("트위티")
	zoo.append(rex)
	zoo.append(tom)
	zoo.append(tweety)
	for animal: Animals in zoo:
		Log.info("  %s → speak(): %s" % [animal.describe(), animal.speak()])
	Log.info("Dog.speak() 의 super() 가 부모의 \"...\" 를 앞에 붙였다.")
	Log.info("static var population=%d — 인스턴스가 아니라 스크립트 객체가 가진 값" % Animals.population)
	var made: Animals = Animals.create("cat", "나비")
	Log.info("static func create(\"cat\") → %s ; create(\"fish\") → %s" % [made.describe(), Animals.create("fish", "니모")])


func _show_inheritance() -> void:
	Log.section("상속 체인: is / as")
	var any: Variant = zoo[0] # Dog
	Log.info("Dog 인스턴스: is Animal=%s, is Dog=%s, is Cat=%s, is RefCounted=%s, is Object=%s" % [any is Animals, any is Animals.Dog, any is Animals.Cat, any is RefCounted, any is Object])
	var as_cat: Animals.Cat = any as Animals.Cat
	var as_dog: Animals.Dog = any as Animals.Dog
	Log.info("as Cat → %s (실패하면 null, 예외 없음) ; as Dog → %s" % [as_cat, as_dog.display_name if as_dog != null else "null"])
	var dog_script: Script = zoo[0].get_script()
	Log.info("get_class()=%s (네이티브 베이스), 내부 클래스의 get_script().get_base_script().get_global_name()=%s" % [zoo[0].get_class(), dog_script.get_base_script().get_global_name()])
	Log.info("is_instance_of(dog, Animal)=%s — 스크립트 타입에도 쓸 수 있는 전역 함수" % is_instance_of(zoo[0], Animals))


func _show_duck_typing() -> void:
	Log.section("덕 타이핑: has_method 로 묻고 call 로 부른다")
	var things: Array = [zoo[0], zoo[2], Animals.Robot.new(), RefCounted.new()]
	for thing: Object in things:
		var label: String = thing.kind() if thing.has_method("kind") else thing.get_class()
		if thing.has_method("speak"):
			Log.info("  %s.speak() → %s" % [label, thing.call("speak")])
		else:
			Log.info("  %s 는 speak() 가 없다 — 그냥 건너뛴다" % label)
		if thing.has_method("fly"):
			Log.info("  %s.fly() → %s" % [label, thing.call("fly")])


func _show_enum_match() -> void:
	Log.section("enum + match")
	Log.info("Animal.Mood.keys()=%s, values()=%s — enum 은 상수 Dictionary 다" % [Animals.Mood.keys(), Animals.Mood.values()])
	for animal: Animals in zoo:
		var line: String
		match animal.mood:
			Animals.Mood.HAPPY:
				line = "행복해서 논다"
			Animals.Mood.HUNGRY:
				line = "배고파서 먹이를 찾는다"
			Animals.Mood.SLEEPY:
				line = "졸려서 잔다"
			_:
				line = "?"
		Log.info("  %s: %s" % [animal.display_name, line])
	match zoo.size():
		0:
			Log.info("동물원이 비었다")
		var n when n < 3:
			Log.info("동물이 %d마리 — 소규모 (match 의 var 바인딩 + when 가드)" % n)
		var n:
			Log.info("동물이 %d마리 — 가드 없는 var 패턴은 전부 받는다" % n)


func _show_properties_and_containers() -> void:
	Log.section("setter/getter, Array[T], Dictionary[K, V]")
	score = -5
	score += 10
	Log.info("score = -5 → %d (setter 가 0 으로 잘랐다), += 10 → %d, setter 호출 %d회" % [0, score, _score_writes])
	for animal: Animals in zoo:
		counts[animal.kind()] = counts.get(animal.kind(), 0) + 1
	Log.info("Dictionary[String, int]=%s, is_typed=%s, 키=%s, 값=%s" % [counts, counts.is_typed(), type_string(counts.get_typed_key_builtin()), type_string(counts.get_typed_value_builtin())])
	Log.info("Array[Animal]: size=%d, is_typed=%s, get_typed_class_name=%s, get_typed_script=%s" % [zoo.size(), zoo.is_typed(), zoo.get_typed_class_name(), zoo.get_typed_script()])
	Log.warn("타입 배열에 다른 타입을 append 하면 런타임 오류다 (core/variant/array.cpp _p->typed.validate). 여기선 시도하지 않는다.")


func _show_exports() -> void:
	Log.section("@export 변형 — 인스펙터가 읽는 메타데이터")
	for prop: Dictionary in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			Log.info("  %s: type=%s hint=%d hint_string=\"%s\" 값=%s" % [prop["name"], type_string(prop["type"]), prop["hint"], prop["hint_string"], get(prop["name"])])
	Log.info("PROPERTY_HINT_RANGE=%d, PROPERTY_HINT_ENUM=%d, PROPERTY_HINT_NODE_PATH_VALID_TYPES=%d, PROPERTY_HINT_NODE_TYPE=%d (core/object/object.h PropertyHint)" % [PROPERTY_HINT_RANGE, PROPERTY_HINT_ENUM, PROPERTY_HINT_NODE_PATH_VALID_TYPES, PROPERTY_HINT_NODE_TYPE])
	var target: Node = get_node_or_null(title_label_path)
	Log.info("@export_node_path 값 %s → get_node_or_null: %s ; @export var linked_node: Node → %s" % [title_label_path, target, linked_node])
