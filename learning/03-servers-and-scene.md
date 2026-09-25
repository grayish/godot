# 3장. 서버(`servers/`)와 씬(`scene/`)

Godot을 이해하는 가장 중요한 한 문장: **씬 트리는 편의 계층이고, 실제 일은 서버가 한다.**
이 장은 서버 패턴(RID, 명령 큐, 렌더 스레드), 그리고 그 위에 얹힌 `SceneTree`/`Node`/`Viewport`의 동작을 소스 기준으로 설명합니다.

## 3.1 서버 패턴

### 3.1.1 서버 목록

| 서버 | 헤더 | 구현 선택 방식 |
|---|---|---|
| `RenderingServer` (`RS`) | `servers/rendering/rendering_server.h` | 구체 클래스 `RenderingServerDefault` 하나. 백엔드는 `RendererCompositor::make_current()`로 교체 (6장) |
| `PhysicsServer2D/3D` | `servers/physics_2d/`, `servers/physics_3d/` | `PhysicsServer3DManager::register_server()`에 모듈이 후보 등록 → `physics/3d/physics_engine` 설정으로 선택 |
| `NavigationServer2D/3D` | `servers/navigation_2d/`, `servers/navigation_3d/` | 물리와 같은 매니저 패턴 (`modules/navigation_3d`) |
| `AudioServer` | `servers/audio/audio_server.h` | 하나. 출력 드라이버는 `AudioDriverManager::add_driver()` (ALSA/Pulse/WASAPI/CoreAudio/OpenSL/Web) |
| `DisplayServer` | `servers/display/display_server.h` | `register_create_function()`에 플랫폼이 등록 (5장) |
| `AccessibilityServer`, `NativeMenu` | `servers/display/` | 스크린리더(AccessKit), 네이티브 메뉴 |
| `TextServerManager` → `TextServer` | `servers/text/text_server.h` | `modules/text_server_adv`(HarfBuzz/ICU), `text_server_fb`(폴백)가 인터페이스 추가 |
| `XRServer` | `servers/xr/xr_server.h` | `add_interface()` (openxr, webxr, mobile_vr 모듈) |
| `CameraServer` | `servers/camera/camera_server.h` | `modules/camera`가 `make_default<T>()` |
| `MovieWriter` | `servers/movie_writer/` | 리스트 (`--write-movie`) |

각 서버에는 **Dummy 구현**이 있습니다: `servers/rendering/dummy/`(RID는 할당하지만 아무것도 안 그림), `PhysicsServer3DDummy`, `NavigationServer3DDummy`, `TextServerDummy`, `AudioDriverDummy`. `--headless`는 `DisplayServerHeadless` + `RasterizerDummy` 조합이고, 단위 테스트(`Main::test_setup`)도 이것을 씁니다. **CI/서버 빌드가 GPU 없이 도는 이유**입니다.

등록의 중심은 📌 `servers/register_server_types.cpp` — `register_server_types()`(클래스 등록, Dummy 서버 등록)와 `register_server_singletons()`(스크립트 노출).

### 3.1.2 RID: 불투명 핸들

`core/templates/rid.h`의 `RID`는 `uint64_t` 하나입니다. 하위 32비트는 로컬 인덱스, 상위는 validator. 서버는 `RID_Owner<T>`/`RID_PtrOwner<T>`(`rid_owner.h`)로 RID → 내부 객체를 관리합니다.

```cpp
// modules/godot_physics_3d/godot_physics_server_3d.h:58
RID_PtrOwner<GodotBody3D, true> body_owner{65536, 1048576};
// servers/rendering/renderer_rd/storage_rd/texture_storage.h:211
RID_Owner<Texture, true> texture_owner;
```

서버 API는 철저히 **절차적**입니다: `xxx_create() → RID`, `xxx_set_*(RID, ...)`, `free_rid(RID)`.
`rendering_server.h`에서 `texture_2d_create`(112), `shader_create`(167), `material_create`(183), `mesh_create`(200), `viewport_create`(551), `scenario_create`(730), `instance_create`(741), `canvas_create`(794), `canvas_item_create`(814), `free_rid`(966), `draw/sync`(981-982)를 훑어보면 렌더러가 다루는 개념 전체가 보입니다.

왜 포인터 대신 RID인가?
- 씬(메인 스레드)과 서버(렌더 스레드)가 같은 메모리를 가리키지 않아도 됨.
- validator 덕분에 해제 후 사용을 감지.
- GDScript에 그대로 노출 가능 (`Variant::RID`).

### 3.1.3 RenderingServerDefault와 명령 큐

📌 `servers/rendering/rendering_server_default.h`

```cpp
class RenderingServerDefault : public RenderingServer {
    mutable CommandQueueMT command_queue;            // :80
    Thread::ID server_thread = Thread::MAIN_ID;      // :82
#define ASYNC_COND_PUSH (Thread::get_caller_id() != server_thread)   // :117
```

모든 API 메서드는 `servers/server_wrap_mt_common.h`의 매크로로 생성됩니다:

```cpp
// FUNC1: void 반환, 인자 1개
virtual void m_type(m_arg1 p1) override {
    if (ASYNC_COND_PUSH) { command_queue.push(server_name, &ServerName::m_type, p1); }   // 다른 스레드 → 큐에 넣음
    else { command_queue.flush_if_pending(); server_name->m_type(p1); }                 // 서버 스레드 → 직접 호출
}
```

- `FUNC1R` 등 반환값이 있는 함수는 `push_and_ret`로 **블로킹** — 렌더 스레드 모드에서 getter 호출이 느린 이유.
- `FUNCRIDSPLIT(mesh)`: `mesh_create()`를 `mesh_allocate()`(호출 스레드에서 즉시 RID 발급) + `mesh_initialize(rid)`(큐)로 분리. **RID 생성은 절대 블로킹하지 않습니다.**
- `FUNCRIDTEX*`: 텍스처 생성은 `RSG::rasterizer->can_create_resources_async()`가 true(RD 렌더러)면 어느 스레드에서든 직접, false(GLES3)면 큐로.

렌더 스레드 (`rendering_server_default.cpp`):
- `init()` (`:276-289`): `create_thread`면 `WorkerThreadPool`에 "Rendering Server pump task"를 추가하고 `_thread_loop()`(`:419`: `while(!exit){ yield(); command_queue.flush_all(); }`)를 돌림.
- `draw()` (`:447`): 큐에 `_draw` 푸시. `sync()` (`:439`): 큐 동기화.
- `create_thread`는 `OS::is_separate_thread_rendering_enabled()` = 프로젝트 설정 `rendering/driver/threads/thread_model` (7장).

내부 계층 (`_init()`, `:240-260`): `RSG` 전역(`rendering_server_globals.h`)에 `RendererCanvasCull`, `RendererViewport`, `RendererSceneCull`(컬링·BVH·LOD, 백엔드 독립), 그리고 `RendererCompositor::create()`(백엔드: RD 또는 GLES3)가 들어갑니다. 프레임 흐름은 `_draw()` → `RSG::viewport->draw_viewports()` → `RendererSceneCull::_render_scene()` → `RendererSceneRender::render_scene()`(백엔드) → `blit_render_targets_to_screen()`. 6장에서 이어집니다.

물리 서버도 같은 구조입니다: `PhysicsServer3DWrapMT` (`servers/physics_3d/physics_server_3d_wrap_mt.h`)가 `physics/3d/run_on_separate_thread`에 따라 명령 큐를 씁니다.

### 3.1.4 DisplayServer (`servers/display/display_server.h`)

창, 입력 이벤트, 클립보드, IME, 화면 정보, 커서, TTS, 네이티브 다이얼로그, 서브윈도우, vsync — "OS의 GUI 셸과 관련된 모든 것"의 추상화입니다. 헤더는 주석으로 섹션이 나뉘어 있습니다(`MAIN`, `WINDOW`(362), `CLIPBOARD`(295), `SCREEN`(305), `DIALOGS`(504) …).

등록 메커니즘 (`:79-96`): `static DisplayServerCreate server_create_functions[64]`에 `{name, create_function, get_rendering_drivers_function}`을 넣습니다. `"headless"`는 항상 마지막(`display_server.cpp:2045-2052`가 마지막 앞에 삽입). `Main::setup2()`는 선택된 것을 만들다 실패하면 나머지를 순서대로 시도합니다.

### 3.1.5 물리 백엔드 플러그인 구조

`servers/physics_3d/physics_server_3d_manager.h`: `register_server(name, create_callable)`, `set_default_server(name, priority)`, 설정 키 `physics/3d/physics_engine`. `initialize_server()`는 설정된 이름 → 기본 서버 → `PhysicsServer3DDummy` 순으로 시도.

```cpp
// modules/godot_physics_3d/register_types.cpp:41-59
PhysicsServer3DManager::get_singleton()->register_server(GODOT_PHYSICS_3D_NAME, callable_mp_static(_createGodotPhysics3DCallback));
PhysicsServer3DManager::get_singleton()->set_default_server(GODOT_PHYSICS_3D_NAME);
// modules/jolt_physics/register_types.cpp:53-62
PhysicsServer3DManager::get_singleton()->register_server(JOLT_PHYSICS_NAME, callable_mp_static(create_jolt_physics_server));
```

⚠️ Jolt는 `set_default_server`를 부르지 않습니다. 새 프로젝트의 기본이 Jolt인 이유는 `EditorNode::get_initial_settings()`(`editor/editor_node.cpp:8485`)가 `physics/3d/physics_engine = "Jolt Physics"`를 써 넣기 때문입니다. GDExtension으로도 `PhysicsServer3DExtension`을 상속해 물리 엔진을 통째로 교체할 수 있습니다.

## 3.2 SceneTree: MainLoop의 구현 (`scene/main/scene_tree.h`)

`class SceneTree : public MainLoop` (`:92`). 1장의 `Main::iteration()`이 `main_loop->physics_process()`/`process()`를 부르면 여기서 노드에게 분배됩니다.

- `Window *root` (`:136`) — 생성자에서 `memnew(Window)`, 이름 "root". 오토로드와 메인 씬이 이 아래에 붙습니다.
- `group_map` (`:151`) — `add_to_group`의 저장소. `call_group`, `get_nodes_in_group`.
- `ProcessGroup` (`:103-112`) — `Node::set_process_thread_group()`으로 노드 묶음을 **서브 스레드에서 process** 하기 위한 구조.
- `physics_process()` (`scene_tree.cpp:640-687`): `flush_transform_notifications` → `physics_frame` 시그널 → `_process(true)` → 타이머/트윈 → `_flush_delete_queue`(queue_free 실행) → idle 콜백.
- `process()` (`:689-790`): 같은 순서, `process_frame` 시그널, `_process(false)`.
- `_process_group()` (`:1184-1243`): 노드를 (physics) priority로 정렬한 뒤
  ```cpp
  if (n->is_physics_processing_internal()) n->notification(Node::NOTIFICATION_INTERNAL_PHYSICS_PROCESS);
  if (n->is_physics_processing())          n->notification(Node::NOTIFICATION_PHYSICS_PROCESS);
  ```
  `Node::_notification()` (`node.cpp:99-105`)이 이를 `GDVIRTUAL_CALL(_physics_process, delta)`로 바꿔 스크립트의 `_physics_process`가 실행됩니다.

즉 **`_process`는 가상 함수 호출이 아니라 "알림 정수 → 스크립트 가상 호출" 2단 변환**입니다. `set_process(false)`면 애초에 목록에서 빠지므로 비용이 0입니다.

## 3.3 Node의 생명주기 (`scene/main/node.h`, `node.cpp`)

알림 코드(`node.h:457-517`): `ENTER_TREE=10`, `EXIT_TREE=11`, `READY=13`, `PAUSED/UNPAUSED=14/15`, `PHYSICS_PROCESS=16`, `PROCESS=17`, `PARENTED=18`, `SCENE_INSTANTIATED=20`, `INTERNAL_PROCESS=25`, `POST_ENTER_TREE=27`, `WM_*`(1002-1013), `EDITOR_PRE_SAVE=9001` 등.

`add_child()` 이후의 순서:
1. `_propagate_enter_tree()` (`node.cpp:341-379`) — **부모 → 자식(top-down)**. `data.tree`, `depth`, `viewport` 설정, 그룹 재등록, `NOTIFICATION_ENTER_TREE` → `_enter_tree()` → `tree_entered` 시그널 → 자식 재귀.
2. `_propagate_ready()` (`:323-339`) — **자식 → 부모(bottom-up)**. `POST_ENTER_TREE`, 그리고 첫 번째에만(`data.ready_first`) `NOTIFICATION_READY` → `_ready()` → `ready` 시그널.
3. 제거 시 `_propagate_exit_tree()` (`:410`)는 역순(자식 먼저). `queue_free()`는 `SceneTree::queue_delete`에 넣고 프레임 끝 `_flush_delete_queue`에서 삭제.

이 순서가 "부모의 `_ready`에서 자식의 `@onready` 변수를 안전하게 쓸 수 있는" 이유이고, "`_enter_tree`에서는 자식이 아직 트리에 없는" 이유입니다.

### 노드 계층과 서버 RID

```
Node
 ├─ CanvasItem (scene/main/canvas_item.h)  ── RID canvas_item = RS::canvas_item_create()
 │   ├─ Node2D  (scene/2d/node_2d.h)         2D 트랜스폼
 │   └─ Control (scene/gui/control.h)        앵커/레이아웃/테마/포커스
 ├─ Node3D (scene/3d/node_3d.h)             트랜스폼만, RID 없음
 │   └─ VisualInstance3D                     RID instance = RS::instance_create()  (MeshInstance3D, Light3D, …)
 │   └─ CollisionObject3D                    RID = PhysicsServer3D::body_create()/area_create()
 └─ Viewport (scene/main/viewport.h)        RID viewport = RS::viewport_create()
     └─ Window (scene/main/window.h)         DisplayServer WindowID + RS::viewport_attach_to_screen()
```

- `CanvasItem::queue_redraw()` (`canvas_item.cpp:540`) → 다음 프레임에 `canvas_item_clear()` + `NOTIFICATION_DRAW` → `_draw()`의 `draw_line()` 등은 `RS::canvas_item_add_*` 명령을 쌓습니다. 즉 2D 그리기는 **명령 리스트를 서버에 저장**해 두고, 변하지 않으면 다시 호출되지 않습니다.
- `World2D`(`canvas`, `PhysicsServer2D::space`)와 `World3D`(`scenario`, `PhysicsServer3D::space`)가 서버 쪽 "월드"를 소유. `Viewport::find_world_3d()->get_scenario()`가 `viewport_set_scenario`로 연결됩니다 (`viewport.cpp:612`).

## 3.4 Viewport와 Window

- `Viewport` 생성자 (`viewport.cpp:5597`): `viewport = RS::viewport_create(); texture_rid = RS::viewport_get_texture(viewport);` — 모든 Viewport는 서버의 렌더 타깃이며 `ViewportTexture`로 결과를 읽을 수 있습니다.
- `Window : Viewport`: `_make_window()`가 `DisplayServer::create_sub_window()`로 OS 창을 만들고(`window.cpp:778`), `RS::viewport_attach_to_screen(rid, rect, window_id)`(`:1482`)로 뷰포트를 그 창에 연결, `window_set_input_event_callback(_window_input)`(`:1501`)으로 입력을 받습니다. 루트는 `MAIN_WINDOW_ID`.
- 임베디드 서브윈도우: 부모 Viewport가 `embedder`가 되어 OS 창 없이 그립니다 (에디터 안에서 게임 창이 뜨는 방식).
- 입력 흐름: DisplayServer 콜백 → `Window::_window_input` → `Viewport::push_input()` → `_input` → GUI(`Control`) → `_unhandled_input` → `_shortcut_input`.

## 3.5 노드 타입 등록 (`scene/register_scene_types.cpp`)

473개 `GDREGISTER_*` (408 CLASS, 43 ABSTRACT, 22 VIRTUAL). 섹션별 대략: core/main 22, GUI 78, Animation 37, 3D 126, Shader 7, 2D 55, Resources 143. `ClassDB::add_compatibility_class` 171개는 3.x 이름 호환(`Spatial → Node3D`). `#ifndef _3D_DISABLED` 등으로 빌드 옵션에 따라 통째로 빠집니다.

## 3.6 리소스 → 서버 RID

`scene/resources`의 리소스는 대부분 **지연 생성되는 mutable RID**를 가집니다.

| 리소스 | RID 생성 | 갱신 |
|---|---|---|
| `Shader` | `_check_shader_rid()` → `RS::shader_create_from_code(code)` (`shader.cpp:52-57`) | `shader_set_code` |
| `ShaderMaterial` | `RS::material_create_from_shader(next_pass, priority, shader_rid)` (`material.cpp:475`) | `material_set_param` |
| `BaseMaterial3D` | 플래그 조합 → 셰이더 코드 생성 → `shader_create_from_code` (`material.cpp:2074`). `MaterialKey`로 같은 조합은 셰이더 공유(`shader_map`) | `dirty_materials` 큐 → `flush_changes()` (SceneTree idle 콜백) |
| `ArrayMesh` | `_create_if_empty()` → `RS::mesh_create()`; `mesh_add_surface` | |
| `ImageTexture` | `RS::texture_2d_create(image)` (`image_texture.cpp:82`) | `texture_replace` |

`Resource::get_rid()`(`core/io/resource.h:184`)가 공통 진입점이므로, 노드는 `RS::instance_set_base(instance, mesh->get_rid())`처럼 **리소스의 RID만 서버에 넘깁니다**. 씬 노드와 리소스 모두 서버 객체의 "리모컨"입니다.

## 3.7 씬 없이 서버만 쓰기

```gdscript
# 씬 노드 없이 3D 메시 하나 그리기 (개념 예시)
var scenario := get_world_3d().scenario
var inst := RenderingServer.instance_create()
RenderingServer.instance_set_scenario(inst, scenario)
RenderingServer.instance_set_base(inst, mesh.get_rid())
RenderingServer.instance_set_transform(inst, Transform3D(Basis(), Vector3(0, 1, 0)))
```

수만 개의 동일 객체(총알, 파티클 같은 것)는 노드 대신 이 방식이나 `MultiMesh`를 쓰는 것이 정석입니다. 노드 하나당 `Object` + 알림 + 시그널 맵 + 트리 순회 비용이 붙기 때문입니다.

🧪 **실습 3**: `RenderingServerDefault::_draw`에 브레이크포인트를 걸고 콜스택을 위로 따라가 `Main::iteration`까지, 아래로 `RendererSceneCull::_render_scene` → `RenderForwardClustered::_render_scene`까지 내려가 보세요. 그다음 `rendering/driver/threads/thread_model`을 `Separate`로 바꾼 뒤 같은 브레이크포인트에서 스레드 이름이 바뀌는지 확인하세요.
