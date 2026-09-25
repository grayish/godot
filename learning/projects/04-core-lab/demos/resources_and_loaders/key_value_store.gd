class_name KeyValueStore
extends Resource
## 커스텀 Resource: 키-값 저장소.
## Resource 는 RefCounted 이므로 참조가 사라지면 자동 해제되고, resource_path 가 있으면 ResourceCache 에 등록된다
## (core/io/resource.h Resource : RefCounted, ResourceCache::resources).
## @export 된 프로퍼티만 PROPERTY_USAGE_STORAGE 를 가져 .tres 저장과 duplicate() 대상이 된다.
## 다른 스크립트는 class_name 대신 preload() 로 이 스크립트를 잡는다:
## 전역 클래스 이름은 에디터가 만든 .godot/global_script_class_cache.cfg 가 있어야 풀리기 때문이다.

@export var data: Dictionary = {}


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func set_value(key: String, value: Variant) -> void:
	data[key] = value
	# 값이 바뀌면 changed 시그널을 낸다 — 인스펙터/의존 노드가 이 시그널로 갱신한다 (resource.cpp emit_changed).
	emit_changed()
