# 03 GDScript Lab — GDScript 언어 내부

`learning/04-modules-and-scripting.md` 4.2절(GDScript 컴파일러 파이프라인)과 `learning/02-core-layer.md` 2.3절(Variant)을
직접 만져 보는 실습 프로젝트입니다. 타입이 왜 성능을 만드는지, Variant/Callable/Signal 이 값으로서 어떻게 움직이는지,
`await` 가 실제로 무엇을 만드는지, 클래스·리플렉션·오류 처리가 엔진 어디를 거치는지를 6개의 데모로 봅니다.

## 목적

- `var x: int` 한 줄이 바이트코드를 `OPCODE_OPERATOR` → `OPCODE_OPERATOR_VALIDATED` 로 바꾸는 것을 숫자로 확인한다.
- Variant(39종 타입, 24바이트)와 Callable(16바이트), Signal 을 "값"으로 다루는 API 를 전부 한 번씩 써 본다.
- 코루틴이 `GDScriptFunctionState` + 시그널 ONE_SHOT 연결로 구현된다는 것을 관찰하고, 순차/병렬/취소 패턴을 익힌다.
- class_name·내부 클래스·static·super·is/as·@export·setter/getter·타입 컨테이너가 분석기와 리플렉션에서 어떻게 보이는지 본다.
- Expression, `get_property_list()`, `_get_property_list()/_get/_set` 로 런타임 리플렉션을 다룬다.
- 예외가 없는 언어의 오류 처리 관례(Error 열거형, push_error, assert)와 디버거/에디터 감지를 익힌다.

## 실행 방법

- 에디터에서 열기: 프로젝트 관리자 → 가져오기 → `learning/projects/03-gdscript-lab/project.godot` 선택 후 실행(F5).
- 명령행: `godot --path learning/projects/03-gdscript-lab`
- 헤드리스 셀프테스트 (창 없이 비UI 로직만 검사):
  `godot --headless --path learning/projects/03-gdscript-lab -s res://selftest.gd`
  → 마지막 줄이 `SELFTEST PASS 03-gdscript-lab` 이면 성공.
- 전체 검증 (셀프테스트 + 허브 5프레임 + 모든 데모 씬 인스턴스화):
  `learning/projects/tools/verify.sh learning/projects/03-gdscript-lab`
- 이 저장소의 헤드리스 바이너리: `bin/godot.linuxbsd.editor.x86_64` (에디터/디버그 빌드, DisplayServer "headless").

허브(`main.tscn`)는 왼쪽 버튼으로 데모를 고르고, 오른쪽 아래 로그 패널에 `Log` 오토로드(`log.gd`)가 받은 줄을 비춥니다.
같은 줄이 stdout 에도 찍히므로 헤드리스에서도 무엇이 일어났는지 읽을 수 있습니다.

## 데모 목록

| # | 디렉터리 | 보여주는 개념 |
|---|---|---|
| 1 | `demos/typing_benchmark/` | 같은 루프를 비타입/정적 타입으로 실행해 표로 비교: 정수 산술, Vector2, `Array` vs `Array[int]`, `PackedFloat32Array`, 네이티브 메서드 호출(Variant vs `RefCounted`), 스크립트 메서드 호출, `Dictionary` 조회(String 키 vs StringName 키). 반복 횟수 조절, 버튼으로 실행. 커널은 `bench_kernels.gd`. |
| 2 | `demos/variant_and_callable/` | `typeof`/`type_string` 표, 암시 변환과 `str()`/`var_to_str`, `Callable(obj, "m")`·`obj.m`·람다 캡처·`bind/unbind/bindv`·`call/callv/call_deferred`·`is_valid/get_object/get_method`, `Signal(obj, "name")`·`connect/emit/disconnect`·`add_user_signal`, 직접 호출 vs `Object.call("m")`. |
| 3 | `demos/coroutines/` | `await` 시그널/타이머/다른 코루틴(값 반환), 가끔만 기다리는 함수, 순차 vs 병렬 await 경과 시간, 정지된 호출의 정체(`GDScriptFunctionState`)를 `Signal.get_connections()` 로 관찰, 플래그 기반 취소 패턴. 정적 코루틴은 `frame_waiter.gd`. |
| 4 | `demos/classes_and_typing/` | `class_name` + 내부 클래스(`animals.gd`), `_init(인자)`, `static var/func`, `super()`, `is`/`as`/`is_instance_of`, `has_method` 덕 타이핑, enum + `match`(`var ... when` 가드), `@export_range/@export_enum/@export_node_path/@export var n: Node/@export_multiline`, setter/getter, `Array[Animal]`, `Dictionary[String, int]`. |
| 5 | `demos/expression_and_reflection/` | `Expression.parse/execute`(입력 이름, `base_instance`, `show_error=false`), `get_script().get_script_method_list()/get_script_property_list()`, `get_property_list()` 를 `PROPERTY_USAGE_SCRIPT_VARIABLE` 로 필터, `set/get/get_indexed`, `get_method_list()` 크기, `_get_property_list/_get/_set` 가상 프로퍼티(`virtual_props.gd`). 도우미는 `expression_kit.gd`. |
| 6 | `demos/errors_and_debugging/` | `OS.is_debug_build`/`Engine.is_editor_hint`/`EngineDebugger.is_active`/`DisplayServer.get_name`, `Error` 를 돌려주는 패턴(`FileAccess.get_open_error`, `JSON.parse`, `DirAccess.get_open_error`, `ResourceLoader.exists`), `assert`, `@warning_ignore`, `get_stack/print_stack/print_debug/print_rich`. 실제 오류를 내는 `push_warning/push_error/assert(false)/없는 메서드 call/printerr` 는 버튼으로만 실행. |

## 타입 벤치마크 숫자의 의미

표의 각 줄은 `Time.get_ticks_usec()` 차이(µs)이고 "배속"은 비타입 시간 ÷ 타입 시간입니다.

- **정수 산술 / Vector2**: 가장 큰 차이가 나는 곳. 비타입 `acc += i * 3 + 1` 은 연산마다 `OPCODE_OPERATOR` → `Variant::evaluate()` →
  `core/variant/variant_op.cpp` 의 (타입A, 타입B, 연산자) 테이블 조회 + Variant 생성/소멸을 거칩니다. 타입이 있으면
  `gdscript_byte_codegen.cpp write_binary_operator()` 가 `Variant::get_validated_operator_evaluator()` 로 함수 포인터를 미리 골라
  `OPCODE_OPERATOR_VALIDATED` 를 내고, 결과도 미리 타입이 정해진 임시 슬롯에 씁니다.
- **Array vs Array[int]**: `Array[int]` 는 원소 타입을 알기에 덧셈이 검증 연산자가 됩니다. 원소 접근 자체는 둘 다 `Array` 의 `operator[]` 입니다.
- **PackedFloat32Array**: 타입이 있으면 `OPCODE_GET_INDEXED_VALIDATED` + 검증 덧셈. 큰 수치 배열은 Packed 배열 + 정적 타입이 정석입니다.
- **네이티브 메서드 호출**: 타입이 있으면 컴파일러가 ClassDB 에서 `MethodBind` 를 찾아 `OPCODE_CALL_METHOD_BIND_VALIDATED_RETURN`
  (`ptrcall`, 인자 변환 없음)을 냅니다. Variant 면 `OPCODE_CALL_RETURN` → `Variant::callp` → `Object::callp` 이름 조회를 매번 합니다.
- **스크립트 메서드 호출**: 타입이 있어도 `MethodBind` 가 없으므로 `gdscript_compiler.cpp` 는 `write_call()` → `OPCODE_CALL_RETURN` 을 냅니다.
  두 경우 모두 `GDScriptInstance::callp` 의 HashMap 조회를 거치므로 차이가 작습니다. "타입 = 무조건 빠름"이 아니라 "타입 = 컴파일러가 더 특수한 opcode 를 고를 수 있음"입니다.
- **Dictionary String vs StringName 키**: 두 커널 모두 정적 타입입니다. 차이는 키 해시 비용뿐: `String::hash()` 는 매번 문자를 훑고,
  `StringName::hash()` 는 인터닝 테이블에 저장된 값을 돌려줍니다(2장 2.3). `Dictionary` 는 두 종류를 같은 키로 봅니다.
- 이 저장소의 바이너리는 **에디터(디버그) 빌드**라 VM 에 `DEBUG_ENABLED` 검사(호출 스택 추적, 타입 검사)가 더 들어 있습니다.
  릴리스 템플릿에서는 절대값이 줄지만 비율의 경향은 같습니다. 숫자는 매 실행 조금씩 다르므로 배속만 읽으세요.
- 함정: `int % int`, `int / int` 는 0 나눗셈 검사 때문에 검증 연산자로 만들지 않습니다(`write_binary_operator` 의 주석). 커널이 `i & mask` 를 쓰는 이유입니다.

## 바이트코드 덤프 — 현재 소스 기준

`tests=yes` 로 빌드한 바이너리에서 다음 명령으로 각 함수의 바이트코드를 덤프할 수 있습니다.

```bash
bin/godot.linuxbsd.editor.x86_64 --test gdscript-compiler demos/typing_benchmark/bench_kernels.gd
```

- 디스어셈블러 본체: `modules/gdscript/gdscript_disassembler.cpp` `GDScriptFunction::disassemble()` (`DEBUG_ENABLED`).
  `OPCODE_OPERATOR_VALIDATED` 는 `validated operator`, `OPCODE_OPERATOR` 는 `operator` 로 찍히므로 두 문자열을 찾으면 됩니다.
- 진입점: `modules/gdscript/register_types.cpp` 의 `REGISTER_TEST_COMMAND("gdscript-compiler", ...)` (`TESTS_ENABLED`) → `tests/test_main.cpp:104` 가 `--test <명령>` 을 여기로 보냄 → `modules/gdscript/tests/test_gdscript.cpp` 의 `GDScriptTests::test(TestType)`.
  `test()` 는 `OS::get_cmdline_args()` 의 **마지막 인자**를 `.gd` 파일 경로로 씁니다.
- **디스어셈블리는 `TEST_COMPILER`** (`test_compiler()` → `recursively_disassemble_functions()`)이고, `gdscript-bytecode`(`TEST_BYTECODE`) 케이스는 `"Not implemented."` 만 출력합니다.
  `gdscript-tokenizer`, `gdscript-parser` 명령은 각각 토큰 스트림과 AST 를 출력합니다.

## modules/gdscript 읽기 순서

| 순서 | 파일 | 무엇을 찾아 읽나 |
|---|---|---|
| 1 | `gdscript_tokenizer.cpp` | `GDScriptTokenizerText::scan()`, `INDENT`/`DEDENT` 토큰 생성, `Token::Type` 열거형(`gdscript_tokenizer.h`) |
| 2 | `gdscript_parser.cpp` | `parse()`, `parse_class`, `parse_function`, `parse_variable`(setter/getter), `parse_match`(`WHEN` 가드), `parse_annotation`(@export 계열), `ClassNode/FunctionNode/ExpressionNode` (`gdscript_parser.h`) |
| 3 | `gdscript_analyzer.cpp` | `resolve_class_inheritance`(extends/내부 클래스), `resolve_assignable`(`INFERRED` vs `ANNOTATED_INFERRED` = soft/hard 타입), `reduce_call`(코루틴 호출 검사 `MISSING_AWAIT`), `reduce_binary_op`, `is_type_compatible`, `push_warning` |
| 4 | `gdscript_compiler.cpp` | `_gdtype_from_datatype`(hard 타입만 코드젠 타입이 됨), `_parse_expression` 의 `CALL` 분기(`write_call_method_bind_validated` vs `write_call`), `IDENTIFIER` 분기(전역 클래스 조회), `_parse_function`, `compile` |
| 5 | `gdscript_byte_codegen.cpp` | `write_binary_operator`(검증 연산자 선택), `write_call_*`, `write_await`, `add_temporary`(타입 있는 임시 슬롯), 상수 풀 |
| 6 | `gdscript_function.h` / `gdscript_vm.cpp` | `enum Opcode`(:153-311), `OPCODES_TABLE`(computed goto), `OPCODE_OPERATOR` vs `OPCODE_OPERATOR_VALIDATED`, `OPCODE_AWAIT`/`OPCODE_AWAIT_RESUME`, `GDScriptFunctionState`(:506) |
| 보조 | `gdscript.cpp` | `GDScript::reload()`(파이프라인 구동), `GDScriptInstance::callp/set/get/get_property_list`(스크립트 인스턴스가 Object 호출을 가로채는 곳), `~GDScriptInstance`(pending_func_states 정리), `static_variables` |
| 보조 | `gdscript_lambda_callable.cpp`, `gdscript_utility_functions.cpp`, `gdscript_warning.cpp`, `gdscript_disassembler.cpp` | 람다 Callable, `print_stack/get_stack/print_debug`, 경고 이름 목록, 디스어셈블러 |

## 함께 읽을 엔진 소스

- `learning/04-modules-and-scripting.md` 4.2 — 파이프라인 그림과 "타입이 성능을 만든다" 항목. 데모 1 이 그 문장의 실측입니다.
- `learning/02-core-layer.md` 2.3 — Variant 39종/24바이트, `variant_op.cpp` 테이블, Callable 16바이트, StringName 인터닝. 데모 1(Dictionary 조회), 데모 2 가 대응합니다.
- `core/variant/variant.h` (`Variant::Type`), `core/variant/variant_op.cpp`, `core/variant/variant_call.cpp` — typeof/연산자/내장 메서드.
- `core/variant/callable.h`, `callable.cpp`, `callable_bind.cpp` — `bind/unbind` 가 만드는 `CallableCustomBind/Unbind`.
- `core/object/object.cpp` — `Object::callp`, `emit_signalp`, `get_property_list`, `set/get`(스크립트 인스턴스에 먼저 기회).
- `core/object/message_queue.cpp` — `call_deferred` 가 쌓이는 곳과 `flush()` 시점.
- `scene/main/scene_tree.cpp` — `process_frame` emit, `SceneTreeTimer`, `_flush_delete_queue`.
- `core/math/expression.cpp` — Expression 의 자체 토크나이저/파서/실행기.
- `core/error/error_macros.h`, `core/error/error_list.h`, `core/variant/variant_utility.cpp` — 오류 매크로, `Error` 열거형, `push_error/push_warning`.
- `core/debugger/engine_debugger.cpp`, `core/register_core_types.cpp` — `EngineDebugger` 싱글턴 등록과 활성 조건.
- `core/config/project_settings.cpp get_global_class_list()` — class_name 전역 클래스 캐시(아래 "흔한 함정" 1).

## 연습 과제

1. **검증 연산자 추적**: `bench_kernels.gd` 의 `int_typed` 에서 `acc += i * 3 + 1` 을 `acc += i % 7` 로 바꿔 배속이 어떻게 변하는지 재고,
   `gdscript_byte_codegen.cpp write_binary_operator()` 에서 `%` 가 검증 연산자에서 제외되는 코드를 찾아 이유를 설명하세요.
2. **호출 opcode 비교**: 데모 1 의 "네이티브 메서드 호출" 커널에서 `get_reference_count()` 를 `Node.new().get_child_count()` 처럼 다른 네이티브 메서드로,
   또 `Counter.bump()` 처럼 스크립트 메서드로 바꿔 보고, `gdscript_compiler.cpp` 의 `CALL` 분기에서 각각 어느 `write_call_*` 가 선택되는지 짚어 보세요.
3. **await 관찰 확장**: 데모 3 의 `_demo_await_signal` 을 본떠 `create_timer(1.0).timeout` 을 기다리는 코루틴을 만들고,
   기다리는 동안 `SceneTreeTimer.timeout.get_connections()` 를 찍어 `GDScriptFunctionState` 연결을 확인하세요. 그 다음 타이머가 이미 끝난 뒤 다시 `await` 하면
   왜 영원히 멈추는지 `scene_tree.cpp` 의 타이머 처리에서 찾으세요.
4. **가상 프로퍼티 확장**: `virtual_props.gd` 에 `PROPERTY_USAGE_SCRIPT_VARIABLE` 플래그를 `usage` 에 더해 보고 데모 5 의 필터 결과가 어떻게 바뀌는지,
   그리고 에디터 인스펙터에서 어떻게 보이는지 확인하세요. `_property_can_revert/_property_get_revert` 도 구현해 보세요.
5. **오류 패턴 리팩터링**: 데모 6 의 `_read_text_file` 을 본떠 JSON 설정 파일을 읽는 `load_settings(path) -> Error` 를 만들고,
   실패 원인을 `error_string()` 으로 로그에 남긴 뒤 `selftest.gd` 에 "없는 파일이면 `ERR_FILE_NOT_FOUND`" 테스트를 추가하세요.
6. **class_name 캐시 실험**: 에디터로 프로젝트를 한 번 연 뒤 `.godot/global_script_class_cache.cfg` 를 열어 보고,
   `selftest.gd` 의 `preload` 를 `BenchKernels` 직접 참조로 바꿔 헤드리스에서 되는지, 캐시를 지우면 다시 실패하는지 확인하세요.

## 흔한 함정

1. **`class_name` 은 에디터가 만든 캐시에 의존한다.** 전역 클래스 목록은 `.godot/global_script_class_cache.cfg` 에서 읽습니다
   (`core/config/project_settings.cpp get_global_class_list`). 에디터를 한 번도 열지 않은 체크아웃을 `--headless` 로 바로 실행하면
   다른 파일의 `class_name` 을 참조하는 스크립트가 `Identifier not declared` 로 실패합니다. 같은 파일 안에서도 `BenchKernels.new()` 처럼
   자기 class_name 을 값으로 쓰면 컴파일러가 전역 맵을 찾아 실패합니다. 이 프로젝트는 그래서 `const X := preload("...")` 와 내부 클래스만 씁니다
   (타입 힌트에는 여전히 `class_name` 이 유용합니다).
2. **`-s` 스크립트의 `preload` 는 오토로드보다 먼저 컴파일된다.** `selftest.gd` 가 `Log` 를 쓰는 데모 씬 스크립트를 preload 하면
   `Identifier not found: Log` 컴파일 오류가 납니다. 셀프테스트가 부르는 로직은 오토로드를 쓰지 않는 파일(`bench_kernels.gd`, `frame_waiter.gd`, `expression_kit.gd` 등)로 분리하세요.
3. **코루틴 반환값은 `await` 없이 받을 수 없다.** 이 빌드(4.8)에서 `var s = coroutine()` 은 파싱 오류, `Callable.call()` 로 받으면
   런타임 오류(`Trying to call an async function without "await"`)입니다. 문장으로만 호출하면(발사 후 잊기) `MISSING_AWAIT` 경고입니다.
   정지된 호출을 보고 싶으면 데모 3 처럼 기다리는 시그널의 `get_connections()` 를 보세요.
4. **await 뒤에는 트리 상태를 다시 확인한다.** 기다리는 사이 노드가 트리에서 빠지면 `get_tree()` 가 null 입니다. 데모는 모든 `await` 뒤에
   `if not is_inside_tree(): return` 을 둡니다. 인스턴스가 완전히 사라지면 `~GDScriptInstance` 가 대기 중인 상태를 정리하므로 누수는 없습니다.
5. **이미 끝난 `SceneTreeTimer` 를 await 하면 영원히 멈춘다.** 병렬 대기는 짧은 타이머부터 기다리거나, 타이머 대신 자신의 시그널을 쓰세요.
6. **`Expression.execute(..., show_error=true)` 는 실패 시 콘솔에 ERROR 를 찍는다.** 사용자 입력을 평가할 때는 `show_error=false` 로 두고
   `has_execute_failed()` / `get_error_text()` 를 읽으세요. `ResourceLoader.load` 도 없는 경로면 ERROR 를 찍으니 `exists()` 로 먼저 확인합니다.
7. **`int / int`, `int % int` 는 검증 연산자가 아니다.** 0 나눗셈 검사 때문입니다. 핫 루프에서는 2의 거듭제곱 마스크(`i & (n - 1)`)나 float 나눗셈을 고려하세요.
8. **`var x = 0` 은 "타입 추론"이 아니다.** 분석기는 이를 soft 타입(`INFERRED`)으로만 기록하고 컴파일러는 Variant 로 취급합니다.
   `var x := 0` 또는 `var x: int = 0` 이어야 hard 타입입니다. `for i in n` 의 `i` 는 `n` 이 int 면 hard 타입입니다.
9. **타입 배열에 다른 타입을 넣으면 런타임 오류다.** `Array[int]` 에 `append("a")` 는 `core/variant/array.cpp` 의 검증에서 실패합니다.
   untyped `Array` 를 `Array[int]` 파라미터에 넘기는 것도 실패하므로 `typed.assign(plain)` 으로 복사하세요.
10. **GDScript 경고는 디버거가 있을 때만 보인다.** `gdscript.cpp reload()` 는 `EngineDebugger::is_active()` 일 때만 경고를 보냅니다. 헤드리스/명령행 실행에서는 조용합니다.
