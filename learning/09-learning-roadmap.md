# 9장. 학습 로드맵: 튜토리얼에서 엔진 내부까지

이 장은 "무엇을 어떤 순서로" 배울지에 대한 제안입니다. 각 단계는 **사용자 관점의 목표 → 그 뒤에 있는 소스 → 실습**의 3단 구조입니다.
단계를 건너뛰어도 되지만, 각 단계의 "소스" 항목은 다음 단계의 전제가 됩니다.

```
Stage 0  환경 준비            (0장)
Stage 1  사용자로서의 Godot    공식 튜토리얼 "Your first 2D/3D game"
Stage 2  씬 트리와 노드 내부   3장
Stage 3  스크립트 언어 내부    4장
Stage 4  코어 계층           2장
Stage 5  서버와 렌더링 파이프라인  3장, 6장, 7장
Stage 6  플랫폼과 빌드        5장
Stage 7  엔진 기여 / 모듈 작성  CONTRIBUTING.md, 4장
```

---

## Stage 1. 사용자로서 익히기 (1~2주)

**목표**: 에디터 UI, 노드/씬/시그널, GDScript 기초, 리소스와 임포트.

**공식 자료 (docs.godotengine.org)**
1. Getting Started → "Step by step" (노드와 씬, 시그널, 스크립팅 언어)
2. "Your first 2D game" (Dodge the Creeps) → "Your first 3D game" (Squash the Creeps)
3. Manual의 "Best practices" 섹션: *Scene organization*, *Autoloads versus regular nodes*, *When to use scenes versus scripts* — Godot의 설계 철학이 그대로 드러나는 부분입니다.

**이 저장소에서 같이 볼 것**
- `doc/classes/Node.xml`, `doc/classes/Node2D.xml` — 에디터 도움말과 온라인 API 문서의 원본. 문서를 읽다가 "이 메서드가 실제로 뭘 하지?" 싶으면 같은 이름을 `scene/`에서 grep 하세요.
- `CHANGELOG.md` — 4.x 버전별 큰 변화 목록.

🧪 **실습**: 튜토리얼의 Dodge the Creeps를 완성한 뒤, `Player` 씬을 `.tscn` 텍스트로 열어 노드 트리·속성·시그널 연결이 어떻게 직렬화되는지 읽어 보세요. `[node name="..." type="..." parent="..."]`, `[connection signal=...]` 형식이 3장에서 배우는 `SceneState`/`PackedScene`입니다.

**체크포인트**: "시그널은 왜 필요한가?", "`_ready`와 `_enter_tree`의 차이는?", "`_process`와 `_physics_process`는 언제 각각 호출되나?"에 답할 수 있으면 통과.

---

## Stage 2. 씬 트리 내부 (1주)

**목표**: 내가 쓴 `_process()`가 호출되기까지의 경로를 소스에서 추적한다.

**읽는 순서** (3장과 병행)
1. `main/main.cpp` `Main::iteration()` — 프레임 한 번의 골격 (1장 1.4)
2. `scene/main/scene_tree.cpp` `SceneTree::process()` → `_process(ProcessGroup)` → `Node::_call_process()`
3. `scene/main/node.h`의 `NOTIFICATION_*` 목록과 `Node::_propagate_ready()`, `_propagate_enter_tree()`
4. `scene/main/viewport.cpp` — 입력 이벤트가 `Window → Viewport → Node::_input()`으로 흐르는 경로 (`Viewport::push_input`)
5. `scene/resources/packed_scene.cpp` — `.tscn`이 노드 트리로 인스턴스화되는 과정 (`SceneState::instantiate`)

🧪 **실습**: `dev_build`로 빌드한 에디터에서 `SceneTree::_process`에 브레이크포인트를 걸고, 내 GDScript `_process`까지 콜스택을 따라가 보세요. `GDScriptInstance::notification` → `GDScriptFunction::call`로 이어지는 것을 확인하는 것이 목표입니다.

**체크포인트**: "노드 그룹(`add_to_group`)은 어디에 저장되나?", "`call_deferred`는 왜 다음 프레임에 실행되나(`MessageQueue`)?"

---

## Stage 3. 스크립트 언어 내부 (1~2주)

**목표**: GDScript 한 줄이 토큰 → AST → 바이트코드 → VM 실행으로 바뀌는 과정 이해.

**읽는 순서** (4장 4.2)
1. `modules/gdscript/gdscript_tokenizer.cpp` — 토큰과 들여쓰기 처리
2. `gdscript_parser.cpp` — AST (`GDScriptParser::ClassNode`, `FunctionNode`, ...)
3. `gdscript_analyzer.cpp` — 타입 추론, 정적 타입 검사 (에디터 자동완성도 여기서)
4. `gdscript_compiler.cpp` + `gdscript_byte_codegen.cpp` — 바이트코드 생성
5. `gdscript_vm.cpp` — `GDScriptFunction::call()`의 거대한 `switch`/computed-goto 루프

🧪 **실습**: `tests=yes`로 빌드한 바이너리에서 `godot --test gdscript-compiler path/to/script.gd`를 실행하면 `gdscript_disassembler.cpp`가 각 함수의 바이트코드를 덤프합니다 (`modules/gdscript/register_types.cpp:230-234`의 `REGISTER_TEST_COMMAND`로 등록되며 `tests/test_main.cpp:104`가 `--test <명령>`을 여기로 보냅니다. `gdscript-tokenizer`, `gdscript-parser`도 같은 방식이고, `gdscript-bytecode`는 현재 "Not implemented."만 출력합니다 — 디스어셈블리는 `TEST_COMPILER` 경로에 있습니다). 타입 힌트(`var x: int`)를 넣었을 때 opcode가 `OPCODE_OPERATOR` 에서 `OPCODE_OPERATOR_VALIDATED`류로 바뀌는지 비교하면 "정적 타이핑이 왜 빠른가"를 체감할 수 있습니다.

**병행**: C#이 필요하면 `modules/mono/` — .NET 호스팅과 glue 생성(`modules/mono/glue/`), GDExtension이 필요하면 2장 2.6.

---

## Stage 4. 코어 계층 (1~2주)

**목표**: `Object`/`Variant`/`ClassDB`가 스크립트·에디터·직렬화의 공통 기반임을 이해.

**읽는 순서** (2장)
1. `core/object/object.h` — `GDCLASS` 매크로 펼쳐 읽기, `_bind_methods`, 시그널, 알림
2. `core/object/class_db.h` — `ClassDB::bind_method` 가 `MethodBind`를 만들어 이름→함수 테이블에 넣는 과정
3. `core/variant/variant.h` — `Variant::Type`, 크기, `Variant::call`/`Variant::evaluate`
4. `core/io/resource.h`, `resource_loader.h` — 리소스 참조 카운팅과 로더 플러그인 패턴
5. `core/templates/` — `Vector`(COW), `LocalVector`, `HashMap`, `RID_Owner`, `PagedAllocator`, `CommandQueueMT`
6. `core/os/os.h`, `core/os/main_loop.h` — 플랫폼 추상화 계약

🧪 **실습**: `core/`에 작은 클래스(예: `Counter : RefCounted`)를 추가하고 `register_core_types.cpp`에 등록해 GDScript에서 `Counter.new().increment()`가 되게 만들어 보세요. `doc/classes/Counter.xml`을 `--doctool`로 생성하는 것까지 해 보면 문서 파이프라인도 이해됩니다.

---

## Stage 5. 서버와 렌더링 파이프라인 (2~4주)

**목표**: 노드가 RID로 서버에 명령을 보내고, 렌더러가 프레임을 그리는 전 과정을 설명할 수 있다.

**읽는 순서** (3장 3.1, 6장, 7장)
1. `servers/rendering/rendering_server.h` — 공개 API 전체 훑기 (texture_*, mesh_*, instance_*, viewport_*, canvas_*)
2. `servers/rendering/rendering_server_default.h/.cpp` — 명령 큐와 렌더 스레드
3. `servers/rendering/renderer_viewport.cpp` `RendererViewport::draw_viewports()` — 프레임의 시작
4. `servers/rendering/renderer_scene_cull.cpp` — 컬링과 인스턴스 관리 (여기가 3D "씬"의 실체)
5. `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp` `_render_scene()` — 패스 순서
6. `servers/rendering/rendering_device.h` → `drivers/vulkan/rendering_device_driver_vulkan.cpp` — 추상화와 구현
7. `drivers/gles3/rasterizer_scene_gles3.cpp` — 위와 비교해 GL 경로가 얼마나 다른지 확인
8. `servers/rendering/shader_language.cpp`, `shader_compiler.cpp` — Godot 셰이더 → GLSL

🧪 **실습**
- (a) `--gpu-profile`과 에디터 Debugger의 Visual Profiler로 한 프레임의 패스별 시간 보기.
- (b) RenderDoc으로 Vulkan 프레임 캡처 → `render_forward_clustered.cpp`의 패스 이름(`DebugLabel`)과 대조.
- (c) 7장의 설정을 하나씩 바꿔 가며 캡처 결과가 어떻게 변하는지 확인 (예: `scaling_3d/mode`를 FSR2로).
- (d) 씬 노드 없이 `RenderingServer` API만으로 메시를 화면에 띄우는 GDScript 작성 (공식 문서 "Optimization using Servers").

---

## Stage 6. 플랫폼과 빌드 (1주)

**목표**: 새 플랫폼이 어떤 인터페이스를 구현해야 하는지, 익스포트가 무엇을 하는지 이해.

**읽는 순서** (5장)
1. `platform/linuxbsd/godot_linuxbsd.cpp` → `os_linuxbsd.cpp` — 가장 단순한 진입점
2. `servers/display/display_server.h` — 창/입력/클립보드 계약, `platform/linuxbsd/x11/display_server_x11.cpp`로 구현 예 보기
3. `platform/android/java/` + `java_godot_lib_jni.cpp` — JNI 경계, `platform/web/js/` — Emscripten 경계
4. `editor/export/editor_export_platform.cpp` + `core/io/file_access_pack.cpp` — PCK 생성과 로딩
5. `SConstruct`, `methods.py`, `platform/*/detect.py`, `modules/*/config.py`

🧪 **실습**: `scons platform=web`으로 웹 빌드를 만들고 `--rendering-driver`가 `opengl3`밖에 없는 이유(`platform/web/display_server_web.cpp:1013`)를 소스에서 확인. 그리고 `disable_3d=yes`로 빌드했을 때 바이너리 크기 차이를 재 보세요.

---

## Stage 7. 기여자 / 모듈 개발자 (지속)

- `CONTRIBUTING.md` → 버그 리포트·PR 규칙, `misc/scripts/`의 포매터.
- 작은 첫 기여: `doc/classes/*.xml` 문서 보강, `tests/` 추가, "good first issue" 라벨.
- 커스텀 모듈: `modules/` 아래에 `SCsub` + `config.py` + `register_types.cpp` (4장 4.1). 저장소 밖에서 `custom_modules=` 옵션으로 붙일 수도 있습니다.
- 물리 백엔드나 렌더러를 통째로 바꾸는 큰 작업의 예: `modules/jolt_physics/`가 `PhysicsServer3DManager::register_server()`로 자신을 등록하는 방식을 따라 하면 됩니다.
- 설계 논의는 `godot-proposals` 저장소에서, 렌더링/코어의 큰 변경은 Godot Rocket.Chat(개발자 채팅)에서 이루어집니다.

---

## 학습 중 막힐 때의 탐색 전략

1. **이름으로 grep**: 에디터에서 보이는 속성 이름(예: `shadow_atlas_size`)은 대부분 `ADD_PROPERTY(... "shadow_atlas_size")` 또는 `GLOBAL_DEF("rendering/.../atlas_size")`로 소스에 그대로 있습니다.
2. **`_bind_methods()`부터**: 클래스가 스크립트에 무엇을 노출하는지가 곧 그 클래스의 공개 계약입니다.
3. **NOTIFICATION 추적**: 노드의 동작은 대부분 `_notification(int p_what)`의 `switch`에 모여 있습니다.
4. **RID를 따라가기**: 노드 → `RS::get_singleton()->xxx_create()` → `RendererXxxStorage` → 드라이버. 어느 계층에서 끊기는지 보면 문제 위치를 알 수 있습니다.
5. **`--verbose` + `dev_build`**: 대부분의 "왜 이 드라이버가 선택됐지?"류 질문은 verbose 로그가 답해 줍니다.
