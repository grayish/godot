# 4장. 모듈과 스크립팅 (`modules/`)

`modules/`는 "있어도 되고 없어도 되는" 기능의 집합입니다. GDScript조차 모듈입니다. 이 장은 모듈의 구조, GDScript 컴파일러 파이프라인, C#, 그리고 물리 백엔드 모듈을 다룹니다.

## 4.1 모듈의 구조

`methods.py:303-306 is_module()`이 요구하는 세 파일:

```
modules/foo/
├── config.py          # can_build(env, platform), configure(env), [get_doc_classes(), is_enabled(), get_opts()]
├── SCsub              # env_modules.Clone(); add_source_files(env.modules_sources, "*.cpp")
├── register_types.h/.cpp   # initialize_foo_module(ModuleInitializationLevel), uninitialize_foo_module(...)
├── doc_classes/*.xml  # 노출 클래스 문서 (선택)
└── ...
```

- 초기화 레벨 (`modules/register_module_types.h:35-40`): `CORE`, `SERVERS`, `SCENE`, `EDITOR`. `main.cpp`가 각 시점에 `initialize_modules(LEVEL)`을 호출 (1장). GDExtension의 레벨과 동일한 의미.
- 빌드 시 `modules/modules_builders.py`가 `register_module_types.gen.cpp`(모듈별 `initialize_x_module(level)` 호출 나열)와 `modules_enabled.gen.h`(`MODULE_X_ENABLED` 정의)를 생성.
- `SConstruct:1127-1160`: 각 모듈의 `config.can_build(env, platform)`가 true일 때만 포함. 예:
  - `glslang`: `env["vulkan"] or env["d3d12"] or env["metal"]` (OpenGL엔 불필요)
  - `openxr`: linuxbsd/windows/android/macos, `disable_xr` 아님
  - `lightmapper_rd`: 에디터 빌드 + RenderingDevice
  - `mono`: `is_enabled()`가 False → `module_mono_enabled=yes` 명시 필요
  - `gdscript`: `env.module_add_dependencies("gdscript", ["jsonrpc", "websocket"], True)` — LSP를 위한 선택 의존성
- 저장소 밖 모듈: `scons custom_modules=../my_modules`.

### 예: `modules/jolt_physics`
- `config.py`: `not env["disable_physics_3d"]`
- `SCsub`: `thirdparty/jolt_physics/Jolt/*.cpp`를 경고 끄고 컴파일, `JPH_DOUBLE_PRECISION`(precision=double 시), `JPH_DEBUG_RENDERER`(에디터), `JPH_ENABLE_ASSERTS`(dev)
- `register_types.cpp:53-62`: SERVERS 레벨에서 `jolt_initialize()`, `PhysicsServer3DManager::register_server("Jolt Physics", ...)`, `JoltProjectSettings::register_settings()`
- 본체: `jolt_physics_server_3d.{h,cpp}` + `joints/ objects/ shapes/ spaces/`

### 예: `modules/gdscript`
- `SCsub`: `*.cpp`; 에디터 빌드면 `editor/*.cpp`, `language_server/*.cpp`(없으면 `GDSCRIPT_NO_LSP`); `tests=yes`면 `tests/*.cpp`
- `register_types.cpp:138-176`: SERVERS 레벨에서 `GDScript` 클래스 등록, `memnew(GDScriptLanguage)`, `ScriptServer::register_language()`, 리소스 로더/세이버. EDITOR 레벨에서 문법 강조기·번역 파서·LSP.

## 4.2 GDScript 컴파일러 파이프라인

GDScript는 엔진 내장 바이트코드 VM 언어입니다. `GDScript::reload()` (`gdscript.cpp:741`)가 전체를 구동합니다:

```
소스 텍스트
  │  GDScriptTokenizerText   (gdscript_tokenizer.cpp, 1.7k줄)   — 들여쓰기 → INDENT/DEDENT 토큰
  ▼
토큰 스트림
  │  GDScriptParser::parse() (gdscript_parser.cpp, 6.5k줄)      — AST: ClassNode / FunctionNode / ExpressionNode…
  ▼
AST
  │  GDScriptAnalyzer::analyze() (gdscript_analyzer.cpp, 6.7k줄) — 상속 해석, 타입 추론, 정적 타입 검사, 상수 접기,
  │                                                                 경고(gdscript_warning), 에디터 자동완성의 근거
  ▼
타입이 붙은 AST
  │  GDScriptCompiler::compile() (gdscript_compiler.cpp, 3.3k줄) — 함수마다 GDScriptByteCodeGenerator 생성
  │  GDScriptByteCodeGenerator (gdscript_byte_codegen.cpp)       — 스택 슬롯 할당, 상수 풀, opcode 방출
  ▼
GDScriptFunction (gdscript_function.h: enum Opcode, :153-311)
  │  GDScriptFunction::call() (gdscript_vm.cpp:499, 4k줄)       — computed-goto 디스패치 (OPCODES_TABLE)
  ▼
실행
```

주요 포인트:
- **타입이 성능을 만든다**: 분석기가 피연산자 타입을 확정하면 컴파일러는 `OPCODE_OPERATOR`(런타임에 `Variant::evaluate` 테이블 조회) 대신 `OPCODE_OPERATOR_VALIDATED`(함수 포인터 직접 호출), `OPCODE_CALL_METHOD_BIND_VALIDATED` 등을 방출합니다. `var x: int` 한 줄의 효과를 `gdscript_byte_codegen.cpp`의 `write_binary_operator`에서 확인할 수 있습니다.
- **익스포트 시 토큰 버퍼**: 텍스트 대신 `GDScriptTokenizerBuffer`(바이너리 토큰, `.gdc`)로 저장해 파싱 비용을 줄이고 소스를 감춥니다 (`gdscript_parser.cpp:482/541`에서 선택).
- **await**: `GDScriptFunctionState`(`gdscript_function.h:506`)가 스택을 힙에 저장해 코루틴을 구현합니다.
- **캐시**: `GDScriptCache`/`GDScriptParserRef`가 파싱 결과를 스크립트 간에 공유해 순환 의존을 처리합니다.
- **디스어셈블러**: `gdscript_disassembler.cpp` (`DEBUG_ENABLED`). `tests=yes` 빌드에서 `godot --test gdscript-compiler script.gd` (`modules/gdscript/tests/test_gdscript.cpp`의 `TEST_COMPILER`가 컴파일 후 `recursively_disassemble_functions()`를 호출. `gdscript-bytecode` 명령은 아직 "Not implemented.").
- **에디터 지원**: `gdscript_editor.cpp`(자동완성은 분석기 재사용), `language_server/`(LSP, 외부 에디터용), `gdscript_linter`.
- **ScriptInstance 연결**: 스크립트를 노드에 붙이면 `GDScriptInstance`가 `Object::script_instance`에 들어가고, `Object::set/get/call/notification`이 먼저 스크립트 인스턴스에 기회를 줍니다. `_process` 호출은 `GDScriptInstance::notification()` → `GDScriptFunction::call()`.

## 4.3 C# (`modules/mono`)

- 이름은 mono지만 실제로는 **.NET CoreCLR을 hostfxr로 호스팅**합니다 (`mono_gd/gd_mono.cpp:69-72`, `hostfxr_initialize_for_runtime_config`).
- SCENE 레벨에서 `memnew(CSharpLanguage)` + `ScriptServer::register_language()` (`register_types.cpp:47-57`).
- `csharp_script.{h,cpp}`: `CSharpLanguage`, `CSharpScript`, `CSharpInstance`(= ScriptInstance 구현).
- `glue/runtime_interop.cpp`가 C++ 쪽 interop, `glue/GodotSharp/`가 C# 솔루션(`GodotSharp`, `GodotSharpEditor`, `Godot.SourceGenerators`). 소스 생성기가 `[Export]`, 시그널 등을 위한 glue를 컴파일 타임에 만듭니다.
- 마샬링: `Variant` ↔ .NET 값은 `managed_callable`, `mono_gc_handle`, `runtime_interop`의 `godotsharp_*` 함수를 거칩니다. GDScript보다 호출 경계 비용이 크지만 JIT 덕에 순수 연산은 훨씬 빠릅니다.

## 4.4 물리·내비게이션·기타 서버 백엔드 모듈

| 모듈 | 서버 | 비고 |
|---|---|---|
| `godot_physics_2d`, `godot_physics_3d` | PhysicsServer2D/3D | 자체 구현. `set_default_server()` 호출 |
| `jolt_physics` | PhysicsServer3D | Jolt 래핑. 4.4+ 신규 프로젝트 기본 |
| `navigation_2d`, `navigation_3d` | NavigationServer | Recast/Detour 기반 |
| `text_server_adv`, `text_server_fb` | TextServer | HarfBuzz+ICU(복잡 스크립트) / 폴백 |
| `openxr`, `webxr`, `mobile_vr`, `visionos_xr` | XRServer | `add_interface()` |
| `camera` | CameraServer | 웹캠 |
| `glslang` | RenderingDevice | GLSL→SPIR-V (6장) |
| `lightmapper_rd`, `betsy`, `texture_streaming` | RenderingServer 보조 | 라이트맵 베이킹(컴퓨트), GPU 텍스처 압축, 스트리밍 |

## 4.5 포맷/코덱 모듈

`gltf`, `fbx`, `svg`, `webp`, `jpg`, `ktx`, `dds`, `tinyexr`, `hdr`, `bmp`, `tga` (이미지/모델), `ogg`, `vorbis`, `mp3`, `theora`, `interactive_music` (오디오/비디오), `basis_universal`, `astcenc`, `etcpak`, `cvtt`, `bcdec` (텍스처 압축), `zip`, `upnp`, `enet`, `websocket`, `webrtc`, `multiplayer`, `jsonrpc`, `mbedtls`(네트워크), `csg`, `gridmap`, `tilemap`, `noise`, `msdfgen`, `meshoptimizer`, `xatlas_unwrap`, `vhacd`, `raycast`(Embree), `visual_shader`, `objectdb_profiler`.

모두 2장 2.5의 `ResourceFormatLoader`/`ImageFormatLoader` 플러그인 패턴 또는 새 노드/리소스 클래스 등록으로 끼어듭니다. **새 파일 포맷을 지원하려면 로더 하나 등록하면 끝**이라는 것이 이 구조의 장점입니다.

## 4.6 모듈 vs GDExtension: 언제 무엇을?

| | 모듈 (`modules/`) | GDExtension |
|---|---|---|
| 엔진 재빌드 | 필요 | 불필요 |
| 접근 범위 | 엔진 내부 전부 (private 헤더 포함) | 공개 API(`extension_api.json`)만 |
| 언어 | C++ | C, C++, Rust, Swift, … |
| 배포 | 커스텀 익스포트 템플릿 필요 | `.gdextension` + 공유 라이브러리 |
| 적합 | 서버 백엔드 교체, 렌더러 수정, 코어 타입 추가 | 게임 로직, 서드파티 라이브러리 래핑, 플러그인 |

🧪 **실습 4**: `modules/summator/` 같은 최소 모듈(공식 문서 "Custom modules in C++")을 만들고 빌드한 뒤, 동일 기능을 godot-cpp로 GDExtension으로도 만들어 보세요. 두 경우 모두 `ClassDB.class_exists("Summator")`가 true가 되는데, `ClassDB::classes`의 `ClassInfo.gdextension` 포인터가 하나는 null, 하나는 non-null입니다.
