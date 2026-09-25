# 부록. 용어집 & 자주 찾는 파일 색인

## A. 용어집

| 용어 | 뜻 | 관련 |
|---|---|---|
| **Object** | 모든 엔진 클래스의 루트. 동적 프로퍼티·메서드·시그널·알림 | `core/object/object.h` |
| **GDCLASS** | 클래스를 ClassDB에 연결하는 매크로. `_bind_methods()` 지연 호출 | 2장 |
| **ClassDB** | 런타임 리플렉션 레지스트리 (이름 → 클래스 정보, 메서드 바인드) | `core/object/class_db.h` |
| **GDType** | 클래스별 멤버(메서드/프로퍼티/시그널/상수) 테이블 (4.x 후반 도입) | `core/object/gdtype.h` |
| **Variant** | 39개 타입을 담는 동적 값 (24바이트) | `core/variant/variant.h` |
| **StringName** | 인터닝된 문자열. 포인터 비교 | `core/string/string_name.h` |
| **Callable / Signal** | 호출 가능 객체 / 시그널 참조 값 | `core/variant/callable.h` |
| **ObjectID / ObjectDB** | 해제 감지 가능한 64비트 객체 ID와 그 테이블 | 2장 2.1.3 |
| **RefCounted / Ref<T>** | 참조 카운트 객체와 스마트 포인터. Resource의 베이스 | `core/object/ref_counted.h` |
| **Resource** | 경로를 가진 공유 가능한 데이터. `get_rid()`로 서버 객체 노출 | `core/io/resource.h` |
| **RID** | 서버가 내부 객체를 노출하는 64비트 불투명 핸들 | `core/templates/rid.h` |
| **Server** | 씬과 독립된 기능 계층(Rendering/Physics/Audio/Display/Text/Navigation/XR) | 3장 |
| **CommandQueueMT** | 서버 호출을 다른 스레드로 넘기는 명령 큐 | `core/templates/command_queue_mt.h` |
| **MessageQueue** | `call_deferred`/deferred 시그널 저장소. 프레임 단계마다 flush | `core/object/message_queue.h` |
| **MainLoop / SceneTree** | 엔진 루프의 콜백 객체 / 그 기본 구현(노드 트리) | `core/os/main_loop.h`, `scene/main/scene_tree.h` |
| **Node** | 씬 트리의 단위. 부모/자식/그룹/알림 | `scene/main/node.h` |
| **Notification** | 정수 코드로 전파되는 라이프사이클 이벤트 (`NOTIFICATION_READY` 등) | 3장 3.3 |
| **GDVIRTUAL** | 스크립트가 오버라이드할 수 있는 가상 함수 선언 매크로 | `core/object/gdvirtual.gen.h` |
| **Viewport / Window** | 렌더 타깃 / OS 창에 연결된 뷰포트 | `scene/main/viewport.h`, `window.h` |
| **CanvasItem** | 2D 그리기 단위 (Node2D, Control의 베이스) | `scene/main/canvas_item.h` |
| **Scenario / Space / Canvas** | 서버 쪽 3D 월드 / 물리 월드 / 2D 월드 | `World3D`, `World2D` |
| **PackedScene / SceneState** | `.tscn`/`.scn`의 인메모리 표현 | `scene/resources/packed_scene.h` |
| **PCK** | 리소스 팩 파일 ("GDPC"). 익스포트 결과물 | `core/io/file_access_pack.h` |
| **Export template** | 에디터 코드 없이 빌드된 실행 파일. PCK와 결합해 배포 | 5장 5.7 |
| **Module** | 빌드 시 켜고 끄는 엔진 기능 묶음 (`config.py`, `register_types.cpp`) | 4장 |
| **GDExtension** | C ABI로 엔진 재빌드 없이 클래스를 추가하는 확장 | `core/extension/` |
| **RenderingDevice (RD)** | 백엔드 중립 저수준 GPU API (Vulkan/D3D12/Metal) | `servers/rendering/rendering_device.h` |
| **RenderingDeviceDriver** | RD의 백엔드 인터페이스 | `rendering_device_driver.h` |
| **RenderingContextDriver** | 인스턴스/어댑터/서피스 관리 | `rendering_context_driver.h` |
| **RendererCompositor** | 렌더러 백엔드 팩토리 (RD 또는 GLES3 또는 Dummy) | `renderer_compositor.h` |
| **RendererSceneCull** | 백엔드 독립 컬링/씬 관리 (`RenderingMethod` 구현) | `renderer_scene_cull.h` |
| **RendererSceneRender** | 백엔드 3D 렌더러 인터페이스 (ForwardClustered/ForwardMobile/GLES3) | `renderer_scene_render.h` |
| **Forward+ / Mobile / Compatibility** | 세 렌더링 메서드 | 6장 |
| **Render graph** | RD 명령을 기록·재정렬·자동 배리어 삽입 | `rendering_device_graph.h` |
| **ShaderRD / ShaderGLES3** | 엔진 셰이더 템플릿 + 변형 관리 클래스 | `renderer_rd/shader_rd.h`, `drivers/gles3/shader_gles3.h` |
| **Ubershader** | 특수화 파이프라인이 준비되기 전 쓰는 범용 셰이더 | 6장 6.5 |
| **Specialization constant** | SPIR-V 컴파일 후 파이프라인 생성 시 결정되는 상수 | RD |
| **Shader baker** | 익스포트 시 셰이더를 타깃 API용으로 선컴파일 | `editor/export/shader_baker/` |
| **Feature tag override** | 설정 키의 `.mobile`, `.web` 접미사 | `ProjectSettings::feature_overrides` |
| **TOOLS_ENABLED / DEBUG_ENABLED / DEV_ENABLED** | 에디터 빌드 / 디버그 검사 / 개발자 assert | 1장 1.6 |
| **doctest** | 단위 테스트 프레임워크 (`--test`) | `tests/` |
| **SCons / SCsub / detect.py** | 빌드 도구 / 디렉터리별 빌드 스크립트 / 플랫폼 감지 | 5장 5.6 |

## B. "이건 어디 있지?" 색인

| 찾는 것 | 파일 |
|---|---|
| 부팅 순서, 명령행 플래그 | `main/main.cpp` (`Main::setup`, `setup2`, `start`) |
| 프레임 루프, 물리 틱 | `main/main.cpp` `Main::iteration`, `main/main_timer_sync.cpp` |
| 프로젝트 설정 기본값 | `GLOBAL_DEF(` grep — `main/main.cpp`, `servers/rendering/rendering_server.cpp`, `scene/main/scene_tree.cpp`, `core/config/project_settings.cpp` |
| 렌더링 메서드/드라이버 선택 | `main/main.cpp:2489-2660`, 폴백은 `platform/*/display_server_*.cpp` |
| 노드 라이프사이클 | `scene/main/node.cpp` (`_propagate_enter_tree`, `_propagate_ready`) |
| `_process` 분배 | `scene/main/scene_tree.cpp` (`_process_group`) |
| 입력 이벤트 경로 | `servers/display/display_server.h` → `scene/main/window.cpp` `_window_input` → `viewport.cpp` `push_input` |
| 씬 파일 파싱 | `scene/resources/resource_format_text.cpp`, `packed_scene.cpp` |
| 리소스 로더 등록 | `core/register_core_types.cpp`, 각 모듈 `register_types.cpp` |
| 시그널 방출 | `core/object/object.cpp` `emit_signalp` |
| 메서드 바인딩/마샬링 | `core/object/method_bind.h`, `core/variant/binder_common.h` |
| GDScript 각 단계 | `modules/gdscript/gdscript_{tokenizer,parser,analyzer,compiler,byte_codegen,vm}.cpp` |
| C# 호스팅 | `modules/mono/mono_gd/gd_mono.cpp` |
| GDExtension 로딩 | `core/extension/gdextension.cpp`, `gdextension_library_loader.cpp` |
| 렌더 스레드/명령 큐 | `servers/rendering/rendering_server_default.{h,cpp}`, `servers/server_wrap_mt_common.h` |
| 프레임 렌더 진입 | `rendering_server_default.cpp` `_draw` → `renderer_viewport.cpp` `draw_viewports` |
| 컬링 | `servers/rendering/renderer_scene_cull.cpp` |
| Forward+ 패스 순서 | `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp` `_render_scene` |
| Mobile 서브패스 조건 | `renderer_rd/forward_mobile/render_forward_mobile.cpp:896-930` |
| GLES3 패스 순서 | `drivers/gles3/rasterizer_scene_gles3.cpp` |
| 셰이더 언어 → GLSL | `servers/rendering/shader_language.cpp`, `shader_compiler.cpp` |
| GLSL → SPIR-V | `modules/glslang/register_types.cpp` |
| SPIR-V → DXIL / MSL | `drivers/d3d12/rendering_shader_container_d3d12.cpp`, `drivers/metal/rendering_shader_container_metal.cpp` |
| 우버셰이더 폴백 | `render_forward_clustered.cpp:506-541`, `renderer_rd/pipeline_hash_map_rd.h` |
| 셰이더 캐시 | `renderer_rd/shader_rd.cpp` `_load_from_cache/_save_to_cache`, `drivers/gles3/shader_gles3.cpp` |
| PSO 캐시 | `servers/rendering/rendering_device.cpp:8838-8910` |
| 렌더 그래프 | `servers/rendering/rendering_device_graph.cpp` |
| 각 플랫폼 진입점 | `platform/<p>/godot_<p>.cpp`, Android `java_godot_lib_jni.cpp`, Web `web_main.cpp` |
| 플랫폼 파일/소켓 구현 | `drivers/unix/`, `drivers/windows/` |
| DisplayServer 등록 | `platform/<p>/os_<p>.cpp` 생성자, `servers/display/display_server.cpp` |
| 익스포트 | `editor/export/editor_export_platform.cpp`, `platform/<p>/export/export_plugin.cpp` |
| PCK 포맷 | `core/io/file_access_pack.{h,cpp}`, `core/io/pck_packer.cpp` |
| 빌드 옵션 | `SConstruct:161-381`, `platform/<p>/detect.py`, `modules/<m>/config.py` |
| 클래스 문서 XML | `doc/classes/`, `modules/*/doc_classes/`, `godot --doctool .` |
| 단위 테스트 | `tests/`, `tests/test_main.cpp`, `godot --test` |
| CI | `.github/workflows/runner.yml` + `*_builds.yml` |

## C. 공식 자료 링크 (docs.godotengine.org 기준 경로)

- Getting started → Step by step / Your first 2D game / Your first 3D game
- Manual → Best practices (씬 구성, 오토로드, 씬 vs 스크립트)
- Manual → Performance (일반 최적화, CPU/GPU, 서버 사용)
- Manual → Rendering (렌더러 비교, 뷰포트, 컴포지터, 안티앨리어싱 등)
- Engine details → Architecture (core types, 이 자료의 컨테이너 설명 원본), Engine development (컴파일, 코드 스타일)
- Contributing → Engine development → "Custom modules in C++", "Unit testing"
- GDExtension → "What is GDExtension?", godot-cpp 예제
- Tutorials → Shaders → "Using compute shaders" (RenderingDevice 직접 사용)
