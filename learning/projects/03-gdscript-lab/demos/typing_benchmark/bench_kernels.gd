class_name BenchKernels
extends RefCounted
## 타입 벤치마크의 커널(측정 대상 루프) 모음. UI 와 분리해 두어 selftest 가 그대로 호출한다.
## 각 커널은 {"result": 계산값, "usec": 걸린 마이크로초} 를 돌려준다.
## "비타입" 버전은 일부러 타입 표기를 뺐다 (이 프로젝트에서 유일하게 정적 타입을 안 쓰는 함수들).
## 분석기(gdscript_analyzer.cpp resolve_assignable)는 `var acc = 0` 을 INFERRED(soft) 타입으로만 기록하고,
## 컴파일러(gdscript_compiler.cpp _gdtype_from_datatype)는 hard 타입이 아니면 Variant 로 취급한다. 그래서
##   `var acc = 0`      → OPCODE_OPERATOR: 런타임에 Variant::evaluate() 로 (타입A, 타입B, 연산자) 테이블 조회
##   `var acc: int = 0` → OPCODE_OPERATOR_VALIDATED: 컴파일 시점에 고른 함수 포인터를 직접 호출
## (gdscript_byte_codegen.cpp write_binary_operator() 의 `if (valid)` 분기). 메서드 호출도 같은 원리로
## OPCODE_CALL(이름 조회) 대신 OPCODE_CALL_METHOD_BIND_VALIDATED_RETURN 이 된다.

## 2의 거듭제곱: `i & (KEY_COUNT - 1)` 로 나눗셈 없이 순환한다.
## write_binary_operator() 는 int % int, int / int 를 0 나눗셈 검사 때문에 검증 연산자로 만들지 않는다.
const KEY_COUNT: int = 1024

## 스크립트 메서드 호출 벤치마크의 대상. 내부 클래스로 둔 이유: 같은 파일에서 `BenchKernels.new()` 처럼
## 바깥 class_name 을 값으로 쓰면 컴파일러가 전역 클래스 맵을 찾는데(gdscript_compiler.cpp IDENTIFIER),
## 헤드리스에는 그 캐시가 없어 "Identifier not found" 가 된다. 내부 클래스는 파일 안에서 바로 해석된다.
class Counter:
	var bumps: int = 0

	func bump(x: int) -> int:
		bumps += 1
		return x + 1


static func _now() -> int:
	return Time.get_ticks_usec()


# ---------------------------------------------------------------- 1. 정수 산술

@warning_ignore("untyped_declaration", "inferred_declaration")
static func int_untyped(n: int) -> Dictionary:
	var t0: int = _now()
	var acc = 0
	var i = 0
	var limit = n
	while i < limit:
		acc += i * 3 + 1
		i += 1
	return {"result": acc, "usec": _now() - t0}


static func int_typed(n: int) -> Dictionary:
	var t0: int = _now()
	var acc: int = 0
	var i: int = 0
	while i < n:
		acc += i * 3 + 1
		i += 1
	return {"result": acc, "usec": _now() - t0}


# ---------------------------------------------------------------- 2. Vector2 수학

@warning_ignore("untyped_declaration", "inferred_declaration")
static func vector2_untyped(n: int) -> Dictionary:
	var t0: int = _now()
	var acc = Vector2.ZERO
	var step = Vector2(0.5, -0.25)
	var i = 0
	var limit = n
	while i < limit:
		acc = acc * 0.999 + step
		i += 1
	return {"result": acc, "usec": _now() - t0}


static func vector2_typed(n: int) -> Dictionary:
	var t0: int = _now()
	var acc: Vector2 = Vector2.ZERO
	var step: Vector2 = Vector2(0.5, -0.25)
	var i: int = 0
	while i < n:
		acc = acc * 0.999 + step
		i += 1
	return {"result": acc, "usec": _now() - t0}


# ---------------------------------------------------------------- 3. Array vs Array[int]

## 같은 내용의 배열 두 개: Variant 원소 Array 와 Array[int]. Array[int] 는 원소 타입을 알기에
## `acc += arr[i]` 의 덧셈이 검증 연산자가 된다 (원소 접근은 OPCODE_GET_KEYED_VALIDATED).
static func make_arrays(size: int) -> Dictionary:
	var plain: Array = []
	plain.resize(size)
	for i: int in size:
		plain[i] = i
	var typed: Array[int] = []
	typed.assign(plain)
	return {"plain": plain, "typed": typed}


@warning_ignore("untyped_declaration", "inferred_declaration")
static func array_untyped(arr: Array) -> Dictionary:
	var t0: int = _now()
	var acc = 0
	var i = 0
	var count = arr.size()
	while i < count:
		acc += arr[i]
		i += 1
	return {"result": acc, "usec": _now() - t0}


static func array_typed(arr: Array[int]) -> Dictionary:
	var t0: int = _now()
	var acc: int = 0
	var i: int = 0
	var count: int = arr.size()
	while i < count:
		acc += arr[i]
		i += 1
	return {"result": acc, "usec": _now() - t0}


# ---------------------------------------------------------------- 4. PackedFloat32Array

static func make_packed(size: int) -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	packed.resize(size)
	for i: int in size:
		packed[i] = float(i) * 0.5
	return packed


@warning_ignore("untyped_declaration", "inferred_declaration")
static func packed_untyped(packed: PackedFloat32Array) -> Dictionary:
	var t0: int = _now()
	var data = packed # soft 타입 로컬 → 코드젠에서는 Variant
	var acc = 0.0
	var i = 0
	var count = data.size()
	while i < count:
		acc += data[i]
		i += 1
	return {"result": acc, "usec": _now() - t0}


static func packed_typed(packed: PackedFloat32Array) -> Dictionary:
	var t0: int = _now()
	var acc: float = 0.0
	var i: int = 0
	var count: int = packed.size()
	while i < count:
		acc += packed[i]
		i += 1
	return {"result": acc, "usec": _now() - t0}


# ---------------------------------------------------------------- 5. 네이티브 메서드 호출 (Variant vs RefCounted)

## 타입이 있으면 컴파일러가 ClassDB 에서 MethodBind 를 찾아 OPCODE_CALL_METHOD_BIND_VALIDATED_RETURN 을 내고,
## Variant 면 OPCODE_CALL_RETURN → Variant::callp → Object::callp 의 이름 조회를 매번 거친다.
@warning_ignore("untyped_declaration", "inferred_declaration")
static func native_call_untyped(n: int) -> Dictionary:
	var t0: int = _now()
	var obj = RefCounted.new()
	var acc = 0
	var i = 0
	var limit = n
	while i < limit:
		acc += obj.get_reference_count()
		i += 1
	return {"result": acc, "usec": _now() - t0}


static func native_call_typed(n: int) -> Dictionary:
	var t0: int = _now()
	var obj: RefCounted = RefCounted.new()
	var acc: int = 0
	var i: int = 0
	while i < n:
		acc += obj.get_reference_count()
		i += 1
	return {"result": acc, "usec": _now() - t0}


# ---------------------------------------------------------------- 6. 스크립트 메서드 호출 (Variant vs Counter)

## 스크립트에 정의된 메서드는 타입이 있어도 MethodBind 가 없다. gdscript_compiler.cpp 는
## ClassDB::has_method() 가 실패하면 write_call() → OPCODE_CALL_RETURN 을 내므로 두 경우 모두
## GDScriptInstance::callp 의 HashMap 조회를 거친다. 차이가 작게 나오는 것이 정상이다.
@warning_ignore("untyped_declaration", "inferred_declaration")
static func script_call_untyped(n: int) -> Dictionary:
	var t0: int = _now()
	var obj = Counter.new()
	var acc = 0
	var i = 0
	var limit = n
	while i < limit:
		acc = obj.bump(acc)
		i += 1
	return {"result": acc, "usec": _now() - t0}


static func script_call_typed(n: int) -> Dictionary:
	var t0: int = _now()
	var obj: Counter = Counter.new()
	var acc: int = 0
	var i: int = 0
	while i < n:
		acc = obj.bump(acc)
		i += 1
	return {"result": acc, "usec": _now() - t0}


# ---------------------------------------------------------------- 7. Dictionary 조회: String 키 vs StringName 키

## 두 커널 모두 정적 타입이다. 차이는 키의 해시 비용뿐: String::hash() (core/string/ustring.cpp) 는 매번 문자를 훑고,
## StringName::hash() (core/string/string_name.h) 는 인터닝 테이블에 저장된 해시를 돌려준다.
## Dictionary 는 String 키와 StringName 키를 같은 키로 본다 (core/variant/dictionary.cpp VariantHasher).
static func make_dictionary() -> Dictionary:
	var dict: Dictionary = {}
	for i: int in KEY_COUNT:
		dict["key_%d" % i] = i
	return dict


static func make_string_keys() -> Array[String]:
	var keys: Array[String] = []
	for i: int in KEY_COUNT:
		keys.append("key_%d" % i)
	return keys


static func make_stringname_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for i: int in KEY_COUNT:
		keys.append(StringName("key_%d" % i))
	return keys


static func dict_string_keys(dict: Dictionary, keys: Array[String], n: int) -> Dictionary:
	var t0: int = _now()
	var acc: int = 0
	var mask: int = KEY_COUNT - 1
	for i: int in n:
		acc += dict[keys[i & mask]]
	return {"result": acc, "usec": _now() - t0}


static func dict_stringname_keys(dict: Dictionary, keys: Array[StringName], n: int) -> Dictionary:
	var t0: int = _now()
	var acc: int = 0
	var mask: int = KEY_COUNT - 1
	for i: int in n:
		acc += dict[keys[i & mask]]
	return {"result": acc, "usec": _now() - t0}
