class_name CallableKit
extends RefCounted
## 데모 2 와 selftest 가 함께 쓰는 작은 대상 객체: Callable/Signal 이 가리킬 메서드와 시그널을 가진다.
## 엔진: core/variant/callable.h — Callable 은 16바이트 고정 (ObjectID + StringName, 또는 CallableCustom*).
##       bind()/unbind() 는 CallableCustomBind/CallableCustomUnbind 로 감싼 새 Callable 을 만든다 (callable_bind.cpp).

signal pinged(value: int)

## 메서드가 몇 번 실제로 실행됐는지 — call_deferred 가 "나중에" 실행됨을 보이는 데 쓴다.
var call_count: int = 0


func add(a: int, b: int) -> int:
	call_count += 1
	return a + b


func greet(who: String, suffix: String = "!") -> String:
	call_count += 1
	return "안녕, %s%s" % [who, suffix]


func ping(value: int) -> void:
	pinged.emit(value)


## 값을 "값 (typeof 번호, 타입 이름)" 으로 설명한다.
## typeof() 는 Variant::Type 정수(core/variant/variant.h:97), type_string() 은 Variant::get_type_name().
static func describe(value: Variant) -> String:
	return "%s  (typeof=%d, %s)" % [str(value), typeof(value), type_string(typeof(value))]
