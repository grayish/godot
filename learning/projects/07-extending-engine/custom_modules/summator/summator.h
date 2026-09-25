/**************************************************************************/
/*  summator.h                                                            */
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

#pragma once

#include "core/object/ref_counted.h"

// 학습용 최소 모듈 클래스. RefCounted 를 상속하므로 스크립트에서 Summator.new() 로 만들고
// 참조가 사라지면 자동으로 해제된다 (core/object/ref_counted.cpp RefCounted::unreference).
// GDCLASS 매크로가 ClassDB 등록에 필요한 정적 정보(클래스 이름, 부모, _bind_methods 호출 훅)를 만든다
// (core/object/object.h GDCLASS).
class Summator : public RefCounted {
	GDCLASS(Summator, RefCounted);

	int count = 0;

protected:
	// ClassDB::register_class<Summator>() 가 호출한다 (core/object/class_db.h). 여기서 bind 한 것만 스크립트에 보인다.
	static void _bind_methods();

public:
	void add(int p_value);
	void reset();
	int get_total() const;

	Summator();
};
