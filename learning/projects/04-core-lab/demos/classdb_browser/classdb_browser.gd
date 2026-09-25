extends Control
## 데모 1: ClassDB 브라우저 — 엔진에 등록된 모든 클래스를 런타임 리플렉션으로 들여다본다.
## 엔진: core/object/class_db.h  static HashMap<StringName, ClassInfo> classes (이름 → 부모/creation_func/API 종류)
##       각 클래스의 _bind_methods() 가 ClassDB::bind_method / ADD_PROPERTY / ADD_SIGNAL / BIND_ENUM_CONSTANT 로
##       이 테이블(4.x 후반에는 GDType, core/object/gdtype.h)을 채운다. GDREGISTER_CLASS(Foo) → initialize_class() 가
##       클래스당 한 번 _bind_methods() 를 지연 호출한다 (core/object/object.h GDCLASS 매크로).
##       스크립트에서 보이는 ClassDB 싱글턴은 core/core_bind.h 의 CoreBind::ClassDB 래퍼다.

const DEFAULT_CLASS: StringName = &"Node2D"
const MAX_LINES_PER_GROUP: int = 40

var _filter: LineEdit
var _list: ItemList
var _count_label: Label
var _detail: RichTextLabel
var _spawn_area: VBoxContainer
var _all_classes: PackedStringArray
var _selected: StringName = &""


func _ready() -> void:
	_build_ui()
	_all_classes = ClassDB.get_class_list()
	_all_classes.sort()
	_refresh_list("")
	Log.section("ClassDB 브라우저")
	Log.info("ClassDB.get_class_list(): 등록 클래스 %d개 (class_db.cpp ClassDB::get_class_list — classes 맵의 키)" % _all_classes.size())
	var singletons := Engine.get_singleton_list()
	Log.info("Engine.get_singleton_list(): %d개 — 예: %s" % [singletons.size(), ", ".join(singletons.slice(0, 8))])
	Log.info("싱글턴은 Engine::add_singleton() 으로 등록된 Object 인스턴스(core/config/engine.cpp). ClassDB 는 정적 클래스 테이블 — 둘은 다른 개념.")
	_select_class(DEFAULT_CLASS)
	_instantiate_selected()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	columns.add_child(left)
	_filter = LineEdit.new()
	_filter.placeholder_text = "클래스 이름 필터 (대소문자 무시)"
	_filter.text_changed.connect(_refresh_list)
	left.add_child(_filter)
	_count_label = Label.new()
	left.add_child(_count_label)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	left.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.selection_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_detail)
	var spawn_button := Button.new()
	spawn_button.text = "인스턴스 생성 (ClassDB.instantiate)"
	spawn_button.pressed.connect(_instantiate_selected)
	right.add_child(spawn_button)
	_spawn_area = VBoxContainer.new()
	_spawn_area.custom_minimum_size = Vector2(0, 80)
	right.add_child(_spawn_area)


func _refresh_list(filter: String) -> void:
	_list.clear()
	for cls: String in _all_classes:
		if filter.is_empty() or cls.containsn(filter):
			_list.add_item(cls)
	_count_label.text = "%d / %d 클래스" % [_list.item_count, _all_classes.size()]


func _on_item_selected(index: int) -> void:
	_select_class(StringName(_list.get_item_text(index)))


func _select_class(cls: StringName) -> void:
	_selected = cls
	_detail.clear()
	# 상속 사슬: get_parent_class 를 빈 이름이 나올 때까지 따라간다 (ClassInfo::inherits_ptr 체인).
	var chain: PackedStringArray = PackedStringArray()
	var current: StringName = cls
	while current != &"":
		chain.append(String(current))
		current = ClassDB.get_parent_class(current)
	_line("[b]%s[/b]" % cls)
	_line("상속: " + " → ".join(chain))
	_line("can_instantiate=%s  is_class_enabled=%s  api=%s" % [
		str(ClassDB.can_instantiate(cls)), str(ClassDB.is_class_enabled(cls)), _api_name(ClassDB.class_get_api_type(cls))])

	var methods := ClassDB.class_get_method_list(cls, true)
	_line("\n[b]메서드 %d개 (직접 정의분, class_get_method_list)[/b]" % methods.size())
	for i: int in mini(methods.size(), MAX_LINES_PER_GROUP):
		var m: Dictionary = methods[i]
		var args: PackedStringArray = PackedStringArray()
		for a: Dictionary in m["args"]:
			args.append("%s: %s" % [a["name"], _type_name(a)])
		_line("  %s(%s) -> %s" % [m["name"], ", ".join(args), _type_name(m["return"])])

	var props := ClassDB.class_get_property_list(cls, true)
	var shown: int = 0
	_line("\n[b]프로퍼티 (class_get_property_list — ADD_PROPERTY 로 등록된 setter/getter 쌍)[/b]")
	for p: Dictionary in props:
		var usage: int = p["usage"]
		if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY):
			continue
		if shown < MAX_LINES_PER_GROUP:
			_line("  %s: %s" % [p["name"], _type_name(p)])
		shown += 1

	var signals := ClassDB.class_get_signal_list(cls, true)
	_line("\n[b]시그널 %d개 (ADD_SIGNAL)[/b]" % signals.size())
	for s: Dictionary in signals:
		var args: PackedStringArray = PackedStringArray()
		for a: Dictionary in s["args"]:
			args.append(String(a["name"]))
		_line("  %s(%s)" % [s["name"], ", ".join(args)])

	var constants := ClassDB.class_get_integer_constant_list(cls, true)
	_line("\n[b]정수 상수 %d개 (BIND_CONSTANT / BIND_ENUM_CONSTANT)[/b]" % constants.size())
	for i: int in mini(constants.size(), MAX_LINES_PER_GROUP):
		_line("  %s = %d" % [constants[i], ClassDB.class_get_integer_constant(cls, constants[i])])

	var enums := ClassDB.class_get_enum_list(cls, true)
	_line("\n[b]enum %d개 (class_get_enum_list)[/b]" % enums.size())
	for e: String in enums:
		_line("  %s { %s }" % [e, ", ".join(ClassDB.class_get_enum_constants(cls, e, true))])

	Log.info("%s: 상속 %s | 메서드 %d, 프로퍼티 %d, 시그널 %d, 상수 %d, enum %d (직접 정의분)" % [
		cls, " → ".join(chain), methods.size(), shown, signals.size(), constants.size(), enums.size()])


func _instantiate_selected() -> void:
	if _selected == &"":
		return
	if not ClassDB.can_instantiate(_selected):
		# ClassInfo::creation_func == nullptr (추상 클래스, register_abstract_class) 이거나 싱글턴/가상 클래스.
		Log.warn("%s 는 인스턴스화 불가 — 추상/가상 클래스이거나 서버 싱글턴 (ClassInfo::creation_func 없음)" % _selected)
		return
	var created: Variant = ClassDB.instantiate(_selected)
	if created == null:
		Log.warn("%s: ClassDB.instantiate 가 null 을 돌려줌" % _selected)
		return
	var obj: Object = created as Object
	if obj is Window:
		# 창 계열은 새 OS 창을 열 수 있으니 트리에 넣지 않는다.
		Log.info("%s 는 Window 계열 → 트리에 넣지 않고 바로 free()" % _selected)
		obj.free()
	elif obj is Node:
		var node := obj as Node
		_spawn_area.add_child(node)
		var marker := Label.new()
		marker.text = "생성됨: %s (id=%d)" % [node.get_class(), node.get_instance_id()]
		_spawn_area.add_child(marker)
		Log.info("ClassDB.instantiate(\"%s\") → Node 계열, 트리에 추가 (id=%d). 내부는 ClassInfo::creation_func() 호출 = .tscn 로딩과 같은 경로" % [
			_selected, node.get_instance_id()])
	elif obj is RefCounted:
		Log.info("ClassDB.instantiate(\"%s\") → RefCounted 계열 (%s). 참조가 사라지면 자동 해제" % [_selected, obj.get_class()])
	else:
		Log.info("ClassDB.instantiate(\"%s\") → 순수 Object (%s). 수동 free() 필요 → 바로 해제" % [_selected, obj.get_class()])
		obj.free()


func _line(text: String) -> void:
	_detail.append_text(text + "\n")


func _type_name(info: Dictionary) -> String:
	var type: int = info["type"]
	if type == TYPE_OBJECT and not String(info["class_name"]).is_empty():
		return String(info["class_name"])
	if type == TYPE_NIL:
		return "Variant" if (int(info["usage"]) & PROPERTY_USAGE_NIL_IS_VARIANT) else "void"
	return type_string(type)


func _api_name(api: int) -> String:
	match api:
		ClassDB.API_CORE:
			return "CORE"
		ClassDB.API_EDITOR:
			return "EDITOR"
		ClassDB.API_EXTENSION:
			return "EXTENSION"
		ClassDB.API_EDITOR_EXTENSION:
			return "EDITOR_EXTENSION"
	return "NONE"
