# 1장. 전체 구조: 계층 모델, 부팅 순서, 메인 루프

## 1.1 계층(layer) 모델

Godot 소스는 아래에서 위로 쌓이는 계층 구조이며, **위 계층은 아래 계층만 안다**는 규칙이 비교적 잘 지켜집니다.

```
┌──────────────────────────────────────────────────────────────┐
│  editor/            에디터 (Godot 노드로 만든 Godot 앱)       │  ← TOOLS_ENABLED 에서만
├──────────────────────────────────────────────────────────────┤
│  scene/             Node 트리 · 노드 타입 · 리소스 · GUI       │  ← 사용자가 만지는 API
├──────────────────────────────────────────────────────────────┤
│  servers/           RenderingServer · PhysicsServer · Audio   │  ← RID 핸들 기반, 씬 모름
│                     DisplayServer · TextServer · Navigation   │
├──────────────────────────────────────────────────────────────┤
│  core/              Object · Variant · ClassDB · OS 추상화     │  ← 엔진의 "표준 라이브러리"
│                     I/O · 수학 · 컨테이너 · GDExtension        │
└──────────────────────────────────────────────────────────────┘
       ▲                       ▲                        ▲
  platform/              drivers/                   modules/
  OS별 진입점,          백엔드 구현체              선택적 기능 (스크립트 언어,
  DisplayServer 구현    (Vulkan/D3D12/Metal/GLES3,   물리 엔진, 포맷 로더, XR…)
  익스포트 플러그인      오디오, 입력, 파일)          어느 계층에든 끼어들 수 있음
```

각 계층의 책임을 한 문장으로 요약하면:

| 계층 | 책임 | 대표 파일 |
|---|---|---|
| `core/` | 타입 시스템(`Object`, `Variant`), 리플렉션(`ClassDB`), OS/파일 추상화, 컨테이너, 확장 ABI | 📌 `core/object/object.h`, `core/variant/variant.h`, `core/os/os.h` |
| `servers/` | 씬 구조와 무관한 "엔진 기능"을 RID 핸들 API로 제공. 별도 스레드에서 돌 수 있음 | 📌 `servers/rendering/rendering_server.h`, `servers/physics_3d/physics_server_3d.h`, `servers/display/display_server.h` |
| `scene/` | `Node` 트리와 라이프사이클, 사용자가 조합하는 노드 타입, 리소스 타입 | 📌 `scene/main/node.h`, `scene/main/scene_tree.h`, `scene/main/viewport.h` |
| `editor/` | 에디터 UI, 임포터, 익스포트, 디버거 클라이언트 | `editor/editor_node.h`, `editor/export/` |
| `main/` | 부팅 시퀀스와 프레임 루프 | 📌 `main/main.cpp` |
| `platform/` | OS 진입점(`main()`), `OS` 서브클래스, `DisplayServer` 구현, 익스포트 플러그인 | `platform/linuxbsd/os_linuxbsd.cpp` |
| `drivers/` | 그래픽스/오디오/입력/파일 백엔드 | `drivers/vulkan/`, `drivers/gles3/`, `drivers/unix/` |
| `modules/` | 빌드 시 켜고 끌 수 있는 기능 묶음 | `modules/gdscript/`, `modules/jolt_physics/` |

⚠️ `servers/`는 `scene/`을 include 하지 않습니다. 반대로 `scene/`의 노드는 `RS::get_singleton()` 등을 통해 서버를 호출합니다. 이 단방향 의존이 "씬 없이 서버만으로 게임 만들기"와 렌더 스레드 분리를 가능하게 합니다 (3장).

## 1.2 전체 흐름 한 장 요약

```
platform/*/godot_*.cpp  main()
   │
   ├─ OS_XXX os;                       // OS 싱글턴 (스택 객체)
   ├─ Main::setup(argv)                // core 초기화, 인자 파싱, project.godot 로드
   │     └─ Main::setup2()             // servers → DisplayServer → RenderingServer → scene → editor 등록
   ├─ Main::start()                    // MainLoop(SceneTree) 생성, autoload, 메인 씬 or EditorNode
   ├─ os.run()                         // 플랫폼 이벤트 루프:  process_events(); Main::iteration();
   │     └─ Main::iteration()          // 물리 N틱 + process 1회 + RenderingServer::draw()
   └─ Main::cleanup()
```

## 1.3 부팅 시퀀스 상세 (`main/main.cpp`)

### 진입점 (플랫폼)
`platform/linuxbsd/godot_linuxbsd.cpp:100-126` 이 가장 단순한 예입니다.

```cpp
OS_LinuxBSD os;                               // 생성자에서 OS::singleton 설정
Error err = Main::setup(argv[0], argc - 1, &argv[1]);
if (Main::start() == EXIT_SUCCESS) { os.run(); }
Main::cleanup();
```

`OS_LinuxBSD::run()` (`platform/linuxbsd/os_linuxbsd.cpp:987-1031`)은 `main_loop->initialize()` 후 `DisplayServer::process_events(); if (Main::iteration()) break;` 를 반복합니다. Android/iOS/Web은 OS가 콜백을 주는 구조라 루프의 주체가 바뀌지만 `Main::iteration()`을 호출한다는 점은 같습니다 (5장).

### `Main::setup()` — core와 설정 (`main/main.cpp:974-3020`)

| 줄 | 하는 일 |
|---|---|
| 976 | `Thread::make_main_thread()` |
| 979 | `OS::initialize()` |
| 1002 | `Engine` 싱글턴 생성 |
| 1006-1007 | `register_core_types()`, `register_core_driver_types()` — Object/Variant/리소스 로더 등 등록 (2장 2.8) |
| 1011-1017 | `InputMap`, `ProjectSettings`, `TranslationServer`, `Performance` |
| 1087-1100 | `PackedData`, `ZipArchive` — PCK/ZIP 리소스 팩 지원 |
| ~1104-2065 | 명령행 인자 파싱 (`--rendering-driver`, `--path`, `-e`, …) |
| 2071 | `globals->setup()` — `project.godot` 또는 PCK 로드 |
| 2109 | `WorkerThreadPool` 초기화 |
| 2223-2228 | `physics/common/physics_ticks_per_second`(60), `max_physics_steps_per_frame`(8), `application/run/max_fps` |
| 2489-2660 | **렌더링 메서드/드라이버 결정** (6장 6.2) |
| 2251-2253 | `register_early_core_singletons()`, 모듈 CORE 레벨 초기화, `register_core_extensions()`(GDExtension CORE 레벨) |
| 2949 | `MessageQueue` 생성 — `call_deferred`의 실체 |
| 2959 | `setup2()` 호출 |

### `Main::setup2()` — 서버, 씬, 에디터 (`main/main.cpp:3041-3917`)

```
3209  TextServerManager (+ dummy TextServer)
3217  PhysicsServer2D/3DManager, NavigationServer2D/3DManager 초기화
3230  register_server_types()             ← 서버 클래스들을 ClassDB에 등록
3234  모듈/GDExtension  SERVERS 레벨
3245  Input 싱글턴
3356  AccessibilityServer::create()
3376  DisplayServer::create(...)          ← 창 생성 + 그래픽스 컨텍스트 (실패 시 3390에서 다른 DisplayServer로 폴백)
3565  RenderingServerDefault(separate_thread) → init()
3593  AudioServer → init()
3605  XRServer
3618  register_core_singletons()
3644  부트 스플래시 (RenderingServer가 이미 있으므로 여기서 그림)
3697  주 TextServer 선택 (text_server_adv / text_server_fb)
3771  ThemeDB 초기화
3778  NavigationServer 실제 인스턴스 생성
3784  register_scene_types(), register_driver_types(), register_scene_singletons()
3792  모듈/GDExtension  SCENE 레벨
3810  register_editor_types()  (TOOLS_ENABLED) + EDITOR 레벨
3830  register_platform_apis()
3849  CameraServer
3854  PhysicsServer2D/3DManager::initialize_server()  ← 물리 서버는 이렇게 늦게 생성됨 (모듈이 백엔드를 등록한 뒤)
3863  ScriptServer::init_languages()      ← GDScript/C# 언어 초기화
3908  ClassDB::set_current_api(API_NONE)  ← "이 시점 이후 API 등록 없음"
```

📌 **왜 이 순서인가?**
- DisplayServer가 RenderingServer보다 먼저: 렌더링 컨텍스트(VkSurface, GL context)는 창에 속하기 때문.
- 물리 서버가 가장 늦게: `modules/jolt_physics`, `modules/godot_physics_3d`가 SERVERS 레벨에서 `PhysicsServer3DManager::register_server()`로 후보를 등록해야 매니저가 프로젝트 설정(`physics/3d/physics_engine`)에 따라 선택할 수 있음 (4장 4.4).
- 모듈과 GDExtension에 CORE → SERVERS → SCENE → EDITOR 네 단계 초기화 레벨이 있는 것도 같은 이유입니다. 각 단계에서 "그 계층까지 준비된 상태"를 보장합니다.

### `Main::start()` — 메인 루프 객체와 첫 씬 (`main/main.cpp:4011-4887`)

- 4043 `main_timer_sync.init()`
- 4360-4430 `MainLoop` 생성: 에디터면 `SceneTree`, 아니면 `application/run/main_loop_type` (기본 `"SceneTree"`, 스크립트 MainLoop도 가능)
- 4432 `OS::set_main_loop(main_loop)`
- 4496-4561 오토로드(autoload)를 `SceneTree::get_root()`에 추가
- 4606 `EditorNode` 생성 (에디터) / 4758 `ResourceLoader::load(main_scene)` (게임) / 4811 `ProjectManager` (프로젝트 매니저)

## 1.4 프레임 루프: `Main::iteration()` (`main/main.cpp:4917-5204`)

한 프레임은 **가변 개수의 물리 틱 + 정확히 한 번의 process + 한 번의 draw** 입니다.

```
iteration():
  ticks = OS::get_ticks_usec()
  physics_step = 1 / physics_ticks_per_second          // 기본 1/60
  advance = main_timer_sync.advance(physics_step, ...)  // physics_steps, process_step, interpolation_fraction
  if physics_steps > max_physics_steps_per_frame(8): 클램프 (spiral of death 방지, 4951)

  XRServer::_process()

  for i in 0 ..< advance.physics_steps:                 // ── 물리 틱 (고정 스텝) ──
      Engine._in_physics = true; _physics_frames++
      main_loop->iteration_prepare()                    // 물리 보간용 이전 트랜스폼 저장
      PhysicsServer3D/2D::sync(); flush_queries()
      main_loop->physics_process(step * time_scale)     // → SceneTree → Node::_physics_process()
      NavigationServer2D/3D::physics_process()
      message_queue->flush()                            // call_deferred 실행
      PhysicsServer3D/2D::end_sync(); step(step * time_scale)   // 실제 시뮬레이션
      message_queue->flush()
      main_loop->iteration_end()

  main_loop->process(process_step * time_scale)         // ── process (가변 스텝) → Node::_process() ──
  message_queue->flush()
  NavigationServer::process()
  RenderingServer::sync()                               // 이전 프레임 렌더 스레드 동기화
  RenderingServer::draw(wants_present, scaled_step)     // ── 렌더 ── (low_processor_usage_mode면 변화 있을 때만)
  GDExtensionManager::frame(); ScriptServer::frame(); AudioServer::update()
  _process_frames++
  OS::add_frame_delay()                                 // max_fps 는 여기서 "잠자기"로 구현 (core/os/os.cpp:706)
  return exit
```

핵심 파일:
- `main/main_timer_sync.cpp:349 advance_core()` — `time_accum`을 누적해 `physics_steps = floor(time_accum * tps)`를 계산하고, `physics/common/physics_jitter_fix`로 미세 지터를 흡수합니다.
- `Engine::get_effective_time_scale()` (`core/config/engine.cpp:150`) — `Engine.time_scale`이 물리·process 양쪽 델타에 곱해집니다.
- `MessageQueue`(`core/object/message_queue.h`) — `call_deferred`, `set_deferred`, `CONNECT_DEFERRED` 시그널이 여기에 쌓였다가 각 단계 끝에서 `flush()` 됩니다. "왜 deferred가 같은 프레임 안에서 실행되지?"의 답이 위 흐름에 있습니다 (물리 틱 뒤에도 flush 하기 때문).

⚠️ `max_fps`는 물리 틱 수를 바꾸지 않습니다. 프레임 끝에서 `OS::add_frame_delay()`로 잠들 뿐입니다. 반면 `physics_ticks_per_second`는 시뮬레이션 자체의 시간 해상도입니다.

## 1.5 싱글턴 지도

Godot은 전역 싱글턴을 적극적으로 씁니다. 디버깅할 때 "누가 이걸 갖고 있지?"의 답은 대부분 아래 표에 있습니다.

| 싱글턴 | 타입 | 생성 위치 | 접근 |
|---|---|---|---|
| OS | `OS` 서브클래스 | 플랫폼 `main()` | `OS::get_singleton()` |
| Engine | `Engine` (Object 아님) | `Main::setup` 1002 | `Engine::get_singleton()` |
| ProjectSettings | `ProjectSettings` | `Main::setup` 1012 | `GLOBAL_GET("key")`, `ProjectSettings::get_singleton()` |
| Input, InputMap | | setup2 3245 / setup 1011 | `Input::get_singleton()` |
| DisplayServer | 플랫폼별 | setup2 3376 | `DisplayServer::get_singleton()` |
| RenderingServer | `RenderingServerDefault` | setup2 3565 | `RS::get_singleton()` |
| PhysicsServer2D/3D | GodotPhysics or Jolt | setup2 3854 | `PhysicsServer3D::get_singleton()` |
| AudioServer, XRServer, CameraServer, NavigationServer2D/3D, TextServerManager | | setup2 | 각 `get_singleton()` |
| MainLoop / SceneTree | `SceneTree` | `Main::start` 4362 | `OS::get_singleton()->get_main_loop()`, `SceneTree::get_singleton()` |
| MessageQueue | `MessageQueue` | setup 2949 | `MessageQueue::get_singleton()` |
| ClassDB, ObjectDB, StringName 테이블 | static | `register_core_types()` | static 메서드 |

스크립트에 노출되는 싱글턴 목록(`Engine.get_singleton_list()`)은 `Engine::add_singleton()` (`core/config/engine.h:162`)으로 등록되며, `register_*_singletons()` 함수들이 이를 수행합니다.

## 1.6 코드에서 계층을 구분하는 실마리

- `#ifdef TOOLS_ENABLED` — 에디터 빌드에서만. 익스포트 템플릿에서 사라지는 코드.
- `#ifdef DEBUG_ENABLED` — `template_release`에서 빠지는 검사.
- `#ifdef DEV_ENABLED` — `dev_build=yes`에서만 (무거운 assert).
- `#ifndef _3D_DISABLED`, `PHYSICS_3D_DISABLED`, `XR_DISABLED` 등 — `disable_*` 빌드 옵션.
- `#ifdef RD_ENABLED`, `VULKAN_ENABLED`, `GLES3_ENABLED`, `D3D12_ENABLED`, `METAL_ENABLED` — 렌더링 백엔드 포함 여부.
- `GDVIRTUAL*` 매크로 — 스크립트/GDExtension이 오버라이드할 수 있는 가상 함수.

🧪 **실습 1**: `Main::iteration()`에 `print_line(vformat("phys=%d proc=%f", advance.physics_steps, process_step))` 를 넣고 빌드한 뒤 `--max-fps 30`, `--fixed-fps 10` 등으로 실행해 물리 틱과 process 관계를 눈으로 확인하세요. 그다음 `physics/common/physics_ticks_per_second`를 30으로 바꾸면 `physics_steps`가 어떻게 달라지는지 보세요.
