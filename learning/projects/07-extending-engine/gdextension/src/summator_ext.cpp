#include "summator_ext.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void SummatorExt::_bind_methods() {
	// 엔진 모듈과 같은 D_METHOD/bind_method 문법 — 다만 이 ClassDB 는 godot_cpp::ClassDB 이고,
	// 결국 gdextension_interface 의 classdb_register_extension_class_method 를 이름으로 찾아 호출한다.
	ClassDB::bind_method(D_METHOD("add", "value"), &SummatorExt::add);
	ClassDB::bind_method(D_METHOD("reset"), &SummatorExt::reset);
	ClassDB::bind_method(D_METHOD("get_total"), &SummatorExt::get_total);
}

void SummatorExt::add(int p_value) {
	count += p_value;
}

void SummatorExt::reset() {
	count = 0;
}

int SummatorExt::get_total() const {
	return count;
}

SummatorExt::SummatorExt() {
}

SummatorExt::~SummatorExt() {
}
