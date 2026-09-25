class_name VirtualPropBox
extends RefCounted
## _get_property_list / _get / _set 로 "가상 프로퍼티"를 노출하는 객체.
## 엔진: core/object/object.cpp Object::get_property_list() 는 ClassDB 프로퍼티 다음에
##       script_instance->get_property_list() 를 합치고, 그 안에서 GDScriptInstance 가 스크립트의 _get_property_list 를 부른다.
##       Object::set()/get() 도 script_instance->set()/get() 에 먼저 기회를 주므로 _set/_get 이 먼저 불린다.

const VIRTUAL_NAME: StringName = &"virtual_prop"

## 진짜 스크립트 변수 — get_property_list() 에서 PROPERTY_USAGE_SCRIPT_VARIABLE 플래그가 붙는다.
var real_value: int = 1

var _virtual_storage: int = 0


func _get_property_list() -> Array[Dictionary]:
	# 여기서 돌려준 항목에는 SCRIPT_VARIABLE 플래그가 자동으로 붙지 않는다 (doc/classes/@GlobalScope.xml 참고).
	return [{
		"name": String(VIRTUAL_NAME),
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,100,1",
		"usage": PROPERTY_USAGE_DEFAULT,
	}]


func _get(property: StringName) -> Variant:
	if property == VIRTUAL_NAME:
		return _virtual_storage
	return null # null = "내가 처리하지 않음" → 엔진이 일반 경로(스크립트 변수, 네이티브 프로퍼티)로 계속 찾는다


func _set(property: StringName, value: Variant) -> bool:
	if property == VIRTUAL_NAME:
		_virtual_storage = int(value)
		return true
	return false
