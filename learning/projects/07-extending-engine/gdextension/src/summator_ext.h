// godot-cpp 기반 GDExtension 클래스. 엔진 헤더가 아니라 godot-cpp 가 extension_api.json 에서
// 생성한 래퍼(godot_cpp/classes/ref_counted.hpp)를 상속한다 — 접근 범위는 공개 API 뿐이다 (4장 4.6 표).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

class SummatorExt : public RefCounted {
	// godot-cpp 의 GDCLASS 는 엔진의 것과 이름이 같지만, 내부적으로는 ObjectGDExtension 콜백 묶음
	// (create_instance, free_instance, set/get...) 을 만들어 ClassDB::register_extension_class() 로 넘긴다
	// (엔진: core/object/class_db.cpp, core/object/object.h ObjectGDExtension).
	GDCLASS(SummatorExt, RefCounted)

	int count = 0;

protected:
	static void _bind_methods();

public:
	void add(int p_value);
	void reset();
	int get_total() const;

	SummatorExt();
	~SummatorExt();
};

} // namespace godot
