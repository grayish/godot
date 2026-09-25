extends Control
## 데모 4: Variant 내부 — Packed 배열 COW, Array/Dictionary 참조, String vs StringName, NodePath, RID, 직렬화.
## 엔진: core/variant/variant.h (Variant 24바이트, PackedArrayRef), core/templates/cowdata.h (_copy_on_write),
##       core/string/string_name.h (인터닝 테이블), core/string/node_path.h, core/templates/rid_owner.h,
##       core/variant/variant_parser.cpp (var_to_str), core/io/marshalls.cpp (var_to_bytes).
## 2장 2.3 "Variant" 와 2.6 "컨테이너" 를 코드로 옮긴 것.

const BIG_N: int = 2_000_000
const BENCH_N: int = 200_000


func _ready() -> void:
	_build_ui()
	Log.section("Variant 내부")
	_demo_packed_vs_array()
	_demo_dictionary()
	_demo_string_vs_stringname()
	_demo_nodepath()
	_demo_rid()
	_demo_packing()
	_demo_serialization()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var title := Label.new()
	title.text = "Variant / 컨테이너 실험 — 버튼으로 각 실험을 다시 실행 (시간은 마이크로초, GDScript 루프 오버헤드 포함)"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	var items: Array = [
		["Packed vs Array", _demo_packed_vs_array], ["Dictionary", _demo_dictionary],
		["String vs StringName", _demo_string_vs_stringname], ["NodePath", _demo_nodepath],
		["RID", _demo_rid], ["Color/Vector 패킹", _demo_packing], ["직렬화 왕복", _demo_serialization],
	]
	for item: Array in items:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		grid.add_child(button)


func _demo_packed_vs_array() -> void:
	Log.section("PackedInt32Array (COW Vector<T>) vs Array (참조)")
	var packed := PackedInt32Array([1, 2, 3])
	var packed_alias := packed
	packed_alias.append(4)
	Log.info("PackedInt32Array 대입 후 alias.append(4) → 원본=%s (GDScript 대입은 PackedArrayRef 공유, variant.h)" % str(packed))
	var packed_copy := packed.duplicate()
	packed_copy[0] = 99
	Log.info("duplicate() 후 copy[0]=99 → 원본=%s, 사본=%s (사본 쓰기는 원본에 닿지 않음)" % [str(packed), str(packed_copy)])
	var arr: Array = [1, 2, 3]
	var arr_alias := arr
	arr_alias.append(4)
	var arr_copy := arr.duplicate()
	arr_copy[0] = 99
	Log.info("Array 도 대입은 공유(원본=%s), duplicate() 는 독립(%s) — 그러면 둘의 차이는? 아래 실측으로 본다" % [str(arr), str(arr_copy)])

	# 둘 다 내부는 COW Vector (Packed: Vector<int32_t>, Array: Vector<Variant>) 라서 duplicate() 는 버퍼 공유(refcount+1)로 끝나고
	# 실제 복사는 첫 쓰기(CowData::_copy_on_write)에서 일어난다. 차이는 원소 표현: 원시 4바이트 vs Variant 24바이트.
	var packed_times := _measure_cow(PackedInt32Array(), BIG_N)
	var array_times := _measure_cow([], BIG_N)
	Log.info("PackedInt32Array %d개(%dMB): duplicate()=%dus / 첫 쓰기=%dus (여기서 실제 복사) / 두 번째 쓰기=%dus" % [
		BIG_N, BIG_N * 4 / 1_000_000, packed_times[0], packed_times[1], packed_times[2]])
	Log.info("Array %d개(%dMB, Variant 24바이트): duplicate()=%dus / 첫 쓰기=%dus / 두 번째 쓰기=%dus" % [
		BIG_N, BIG_N * 24 / 1_000_000, array_times[0], array_times[1], array_times[2]])
	Log.info("→ Packed 배열의 이점은 '복사 방식' 이 아니라 원소가 원시 타입이라 메모리가 1/6 이고 순회·직렬화(to_byte_array)가 싸다는 것 (core/templates/cowdata.h)")


## Packed 배열이든 Array 든 같은 순서로 재서 돌려준다: [duplicate 시간, 첫 쓰기 시간, 두 번째 쓰기 시간] (usec).
func _measure_cow(container: Variant, count: int) -> PackedInt64Array:
	container.resize(count)
	var t0 := Time.get_ticks_usec()
	var copy: Variant = container.duplicate()
	var t1 := Time.get_ticks_usec()
	copy[0] = 1
	var t2 := Time.get_ticks_usec()
	copy[1] = 2
	var t3 := Time.get_ticks_usec()
	return PackedInt64Array([t1 - t0, t2 - t1, t3 - t2])


func _demo_dictionary() -> void:
	Log.section("Dictionary 는 참조 타입")
	var d: Dictionary = {"hp": 1, "inner": {"x": 1}}
	var alias := d
	alias["hp"] = 2
	Log.info("alias[\"hp\"]=2 → 원본 hp=%d (같은 HashMap 을 가리킴)" % int(d["hp"]))
	var shallow := d.duplicate(false)
	shallow["inner"]["x"] = 99
	Log.info("duplicate(false) 후 사본의 inner.x=99 → 원본 inner.x=%d (중첩 Dictionary 는 여전히 공유)" % int(d["inner"]["x"]))
	var deep := d.duplicate(true)
	Log.info("duplicate(true) 직후 deep == d ? %s (== 는 재귀 값 비교, 참조 비교가 아님)" % str(deep == d))
	deep["inner"]["x"] = 7
	Log.info("deep.inner.x=7 로 바꿔도 원본 inner.x=%d (재귀 복제라 분리됨), 이제 deep == d ? %s" % [int(d["inner"]["x"]), str(deep == d)])


func _demo_string_vs_stringname() -> void:
	Log.section("String == vs StringName == 마이크로 벤치마크")
	var base := "a_fairly_long_property_name_" + "x".repeat(48)
	var s1 := base + "_end"
	var s2 := base + "_end"
	var n1 := StringName(s1)
	var n2 := StringName(s2)
	var hits: int = 0
	var t0 := Time.get_ticks_usec()
	for i: int in BENCH_N:
		if s1 == s2:
			hits += 1
	var t1 := Time.get_ticks_usec()
	for i: int in BENCH_N:
		if n1 == n2:
			hits += 1
	var t2 := Time.get_ticks_usec()
	for i: int in BENCH_N / 10:
		var tmp := StringName(s1)
		hits += 1 if tmp == n1 else 0
	var t3 := Time.get_ticks_usec()
	Log.info("%d회 비교 (문자열 길이 %d): String==%dus, StringName==%dus — StringName 은 인터닝된 포인터 비교 (string_name.h)" % [
		BENCH_N, s1.length(), t1 - t0, t2 - t1])
	Log.info("StringName(문자열) 생성 %d회=%dus — 해시+테이블 조회 비용이 있으니 반복 생성 말고 상수(&\"name\")로 재사용" % [BENCH_N / 10, t3 - t2])
	Log.info("프로퍼티/메서드/시그널 이름이 모두 StringName 인 이유: set/get/call 의 HashMap 조회가 포인터 해시로 끝난다 (hits=%d)" % hits)


func _demo_nodepath() -> void:
	Log.section("NodePath 파싱 (core/string/node_path.h)")
	var path := ^"Player/Sprite2D:position:x"
	var names: PackedStringArray = PackedStringArray()
	for i: int in path.get_name_count():
		names.append(String(path.get_name(i)))
	var subnames: PackedStringArray = PackedStringArray()
	for i: int in path.get_subname_count():
		subnames.append(String(path.get_subname(i)))
	Log.info("%s → names=%s (get_name_count=%d), subnames=%s (get_subname_count=%d), absolute=%s" % [
		path, str(names), path.get_name_count(), str(subnames), path.get_subname_count(), str(path.is_absolute())])
	Log.info("get_concatenated_names=%s, get_concatenated_subnames=%s, get_as_property_path=%s" % [
		path.get_concatenated_names(), path.get_concatenated_subnames(), str(path.get_as_property_path())])
	Log.info("이름 조각은 StringName 이라 Node::get_node 의 자식 탐색이 포인터 비교로 끝난다. ':' 뒤는 프로퍼티 하위 경로 (애니메이션 트랙 형식)")


func _demo_rid() -> void:
	Log.section("RID: 서버가 내부 객체를 노출하는 유일한 방법")
	var rid := RenderingServer.instance_create()
	Log.info("RenderingServer.instance_create() → RID valid=%s id=%d (rid_owner.h: 인덱스+validator 64비트 핸들)" % [str(rid.is_valid()), rid.get_id()])
	RenderingServer.free_rid(rid)
	Log.info("free_rid 후 같은 RID 값은 더 이상 유효하지 않지만 RID 자체는 값 타입이라 is_valid()=%s 로 남는다 (서버가 검증)" % str(rid.is_valid()))
	Log.info("RID() 기본값 is_valid=%s" % str(RID().is_valid()))
	var mesh := BoxMesh.new()
	Log.info("BoxMesh.get_rid() valid=%s — Resource::get_rid() 가 서버 대응 객체를 노출 (resource.h:184)" % str(mesh.get_rid().is_valid()))
	var mesh_instance := MeshInstance3D.new()
	add_child(mesh_instance)
	Log.info("MeshInstance3D.get_instance() valid=%s — Node3D 는 RS 인스턴스 RID 를 들고 위치만 밀어 넣는다" % str(mesh_instance.get_instance().is_valid()))
	mesh_instance.queue_free()
	if RenderingServer.get_rendering_device() == null:
		Log.warn("RenderingDevice 없음 (헤드리스/호환 렌더러) — RID 만 있을 뿐 GPU 자원은 만들지 않는다")


func _demo_packing() -> void:
	Log.section("Color / Vector 패킹과 Variant 크기")
	var color := Color(1.0, 0.5, 0.0, 1.0)
	Log.info("Color(1, .5, 0).to_rgba32()=0x%08X, to_html()=%s, Color.hex(0xFF8000FF)=%s, Color8(255,128,0)=%s" % [
		color.to_rgba32(), color.to_html(), str(Color.hex(0xFF8000FF)), str(Color8(255, 128, 0))])
	var v := Vector2(1.7, -2.2)
	Log.info("Vector2(1.7,-2.2) → Vector2i=%s, floor=%s, snapped(0.5)=%s" % [str(Vector2i(v)), str(v.floor()), str(v.snapped(Vector2(0.5, 0.5)))])
	Log.info("var_to_bytes 크기(헤더 4바이트 포함): int=%d, int64=%d, float=%d, Vector3=%d, Color=%d, \"abc\"=%d" % [
		var_to_bytes(1).size(), var_to_bytes(1 << 40).size(), var_to_bytes(1.5).size(),
		var_to_bytes(Vector3()).size(), var_to_bytes(Color()).size(), var_to_bytes("abc").size()])
	Log.info("Variant 는 24바이트(float 빌드): Type 4바이트 + 16바이트 union. Transform3D/Projection 같이 큰 값만 힙 포인터 (variant.h:255)")


func _demo_serialization() -> void:
	Log.section("var_to_str / str_to_var, var_to_bytes / bytes_to_var 왕복")
	var payload: Dictionary = {
		"name": "슬라임", "hp": 12, "pos": Vector2(3, 4), "tags": PackedStringArray(["a", "b"]), "nested": {"ok": true},
	}
	var text := var_to_str(payload)
	var back_text: Variant = str_to_var(text)
	Log.info("var_to_str → %d자, .tres 와 같은 VariantWriter 문법 (variant_parser.cpp). 왕복 같음? %s" % [text.length(), str(back_text == payload)])
	var bytes := var_to_bytes(payload)
	var back_bytes: Variant = bytes_to_var(bytes)
	Log.info("var_to_bytes → %d바이트 (marshalls.cpp encode_variant). 왕복 같음? %s" % [bytes.size(), str(back_bytes == payload)])
	var obj := Object.new()
	var stand_in: Variant = bytes_to_var(var_to_bytes(obj))
	Log.info("Object 는 ID 만 실린다 → bytes_to_var 결과=%s (var_to_bytes_with_objects 는 신뢰할 수 없는 입력에 쓰지 말 것)" % str(stand_in))
	obj.free()
