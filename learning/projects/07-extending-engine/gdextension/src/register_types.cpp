#include "register_types.h"

#include "summator_ext.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_summator_ext_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	// 엔진 입장에서는 ClassDB::register_extension_class() 로 들어온 클래스 — C++ 모듈 클래스와 구별되지 않지만
	// ClassInfo.gdextension 포인터가 non-null 이라 ClassDB.class_get_api_type() 이 API_EXTENSION 을 돌려준다.
	GDREGISTER_CLASS(SummatorExt);
}

void uninitialize_summator_ext_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
// .gdextension 의 entry_symbol 이 가리키는 진입점 (2장 2.7).
// 엔진: core/extension/gdextension.cpp GDExtension::open_library() 가 OS::get_dynamic_library_symbol_handle 로 찾아 호출.
// 확장은 p_get_proc_address 로 엔진 함수 포인터를 "이름으로" 얻는다 — 그래서 엔진 버전이 바뀌어도 ABI 가 유지된다.
GDExtensionBool GDE_EXPORT summator_ext_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_summator_ext_module);
	init_obj.register_terminator(uninitialize_summator_ext_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
