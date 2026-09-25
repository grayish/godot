/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "register_types.h"

#include "summator.h"

#include "core/object/class_db.h"

void initialize_summator_module(ModuleInitializationLevel p_level) {
	// SCENE 레벨: 씬 클래스들이 등록된 뒤. RefCounted 파생이라 CORE 레벨에서도 가능하지만
	// 관례상 게임플레이/스크립트용 클래스는 SCENE 에 둔다 (modules/jsonrpc/register_types.cpp 와 동일한 패턴).
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	// GDREGISTER_CLASS → ClassDB::register_class<Summator>() (core/object/class_db.h).
	// 이 시점부터 ClassDB.class_exists("Summator") 가 true 가 된다.
	GDREGISTER_CLASS(Summator);
}

void uninitialize_summator_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	// 클래스 등록 해제는 ClassDB::cleanup() 이 일괄 처리하므로 여기서 할 일은 없다.
}
