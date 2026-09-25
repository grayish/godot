#pragma once

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// 모듈의 initialize_*_module 과 같은 의미. 레벨 enum 도 같은 값이다
// (엔진: modules/register_module_types.h 가 GDEXTENSION_INITIALIZATION_* 를 그대로 쓴다).
void initialize_summator_ext_module(ModuleInitializationLevel p_level);
void uninitialize_summator_ext_module(ModuleInitializationLevel p_level);
