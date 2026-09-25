extends Control

## 데모 1: 커스텀 모듈(Summator) / GDExtension(SummatorExt) 클래스가 ClassDB 에 등록되었는지 확인.
## 두 방식 모두 결과는 "ClassDB 에 클래스가 하나 더 생기는 것"이다 (4장 4.6).
##   모듈:       GDREGISTER_CLASS → ClassDB::register_class<T>()            (core/object/class_db.h)
##   GDExtension: 확장이 넘긴 콜백 묶음 → ClassDB::register_extension_class() (core/object/class_db.cpp)
## 차이는 ClassInfo.gdextension 포인터가 null 인지 아닌지 — 스크립트에서는 class_get_api_type() 으로 보인다.

const CANDIDATES: Array[String] = ["Summator", "SummatorExt"]
## 이 빌드에 실제로 들어 있는 작은 모듈 클래스 (modules/jsonrpc) — 모듈 등록의 "살아 있는" 예.
const REFERENCE_MODULE_CLASS: String = "JSONRPC"

const MODULE_BUILD_CMD: String = "scons platform=linuxbsd target=editor custom_modules=learning/projects/07-extending-engine/custom_modules"
const EXT_BUILD_CMDS: Array[String] = [
	"cd learning/projects/07-extending-engine/gdextension",
	"git clone -b 4.4 https://github.com/godotengine/godot-cpp",
	"scons platform=linuxbsd target=template_debug",
	"mv summator_ext.gdextension.example summator_ext.gdextension",
]

var _report: RichTextLabel


static func api_type_name(api: int) -> String:
	match api:
		ClassDB.API_CORE:
			return "API_CORE (엔진에 정적 링크: 코어/씬/모듈)"
		ClassDB.API_EDITOR:
			return "API_EDITOR (에디터 빌드 전용)"
		ClassDB.API_EXTENSION:
			return "API_EXTENSION (GDExtension 이 등록)"
		ClassDB.API_EDITOR_EXTENSION:
			return "API_EDITOR_EXTENSION (에디터용 GDExtension)"
		_:
			return "API_NONE"


## 인스턴스 하나로 add/get_total 을 호출해 본다. 클래스가 컴파일 시점에 없을 수 있으므로 call() 로 동적 호출.
static func exercise_summator(obj: Object) -> int:
	obj.call("reset")
	obj.call("add", 5)
	obj.call("add", 7)
	return int(obj.call("get_total"))


func _ready() -> void:
	_build_ui()
	Log.info("ClassDB 는 core/object/class_db.cpp 의 HashMap<StringName, ClassInfo> 하나다. 모듈도 확장도 결국 여기에 들어간다.")
	for cls: String in CANDIDATES:
		_check_class(cls)
	_show_reference_module_class()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "확장 클래스 확인: ClassDB.class_exists / instantiate / class_get_api_type"
	box.add_child(title)
	_report = RichTextLabel.new()
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.selection_enabled = true
	box.add_child(_report)


func _line(text: String) -> void:
	_report.append_text(text + "\n")


func _check_class(cls: String) -> void:
	var exists: bool = ClassDB.class_exists(cls)
	if not exists:
		Log.warn("%s: ClassDB 에 없음 — 이 바이너리는 해당 모듈/확장 없이 빌드되었습니다." % cls)
		_line("[%s] 없음" % cls)
		if cls == "Summator":
			_line("  모듈 빌드: " + MODULE_BUILD_CMD)
			Log.info("모듈 빌드 명령: " + MODULE_BUILD_CMD)
		else:
			_line("  확장 빌드: " + " && ".join(EXT_BUILD_CMDS))
			Log.info("확장 빌드 명령: " + " && ".join(EXT_BUILD_CMDS))
		return

	var api: int = ClassDB.class_get_api_type(cls)
	var parent: String = String(ClassDB.get_parent_class(cls))
	Log.info("%s: 있음. 부모=%s, %s" % [cls, parent, api_type_name(api)])
	_line("[%s] 있음 — 부모 %s, %s" % [cls, parent, api_type_name(api)])
	if not ClassDB.can_instantiate(cls):
		Log.warn("%s: 인스턴스화 불가(추상 클래스?)" % cls)
		return
	var obj: Variant = ClassDB.instantiate(cls)
	if obj is Object:
		var total: int = exercise_summator(obj)
		Log.info("%s: add(5), add(7) → get_total() = %d" % [cls, total])
		_line("  add(5) + add(7) = %d" % total)
		_free_if_needed(obj)


## 모듈 등록의 실제 예: modules/jsonrpc (이 프로젝트의 모듈 골격이 따라 한 바로 그 모듈).
func _show_reference_module_class() -> void:
	if not ClassDB.class_exists(REFERENCE_MODULE_CLASS):
		Log.warn("%s 가 없는 빌드입니다 (module_jsonrpc_enabled=no?)" % REFERENCE_MODULE_CLASS)
		return
	var api: int = ClassDB.class_get_api_type(REFERENCE_MODULE_CLASS)
	Log.info("참고: %s 는 modules/jsonrpc/register_types.cpp 의 GDREGISTER_CLASS 로 등록된 모듈 클래스 → %s" % [REFERENCE_MODULE_CLASS, api_type_name(api)])
	_line("[%s] 내장 모듈 클래스 — %s" % [REFERENCE_MODULE_CLASS, api_type_name(api)])
	var methods: Array[Dictionary] = ClassDB.class_get_method_list(REFERENCE_MODULE_CLASS, true)
	var names: PackedStringArray = PackedStringArray()
	for m: Dictionary in methods:
		names.append(String(m["name"]))
	Log.info("  _bind_methods 로 노출된 메서드: " + ", ".join(names))
	_line("  메서드: " + ", ".join(names))
	var obj: Variant = ClassDB.instantiate(REFERENCE_MODULE_CLASS)
	if obj is Object:
		_free_if_needed(obj)


## ClassDB.instantiate 는 소유권을 넘긴다. RefCounted 는 참조가 끊기면 스스로 사라지지만
## 순수 Object(JSONRPC 등)는 free() 하지 않으면 종료 시 "ObjectDB instance leaked" 경고가 난다.
func _free_if_needed(obj: Object) -> void:
	if obj is RefCounted:
		return
	if obj is Node:
		(obj as Node).queue_free()
		return
	obj.free()
