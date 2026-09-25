# 8장. 다른 엔진과 무엇이 다른가

이 장은 Godot의 설계 선택을 Unity, Unreal Engine, Bevy, Defold 등과 대비해 설명합니다.
"어느 쪽이 더 좋다"가 아니라 **왜 Godot이 그런 선택을 했고, 그 결과 소스 구조가 어떻게 달라졌는지**에 초점을 둡니다.

## 8.1 한눈에 보는 비교표

| 축 | Godot 4 | Unity | Unreal Engine 5 | Bevy | Defold |
|---|---|---|---|---|---|
| 라이선스 / 소스 | MIT, 전체 소스 공개 | 독점, 소스 유료 열람 | 소스 공개(독점 라이선스), 로열티 | MIT/Apache, 공개 | 공개(독자 라이선스, 무료) |
| 구현 언어 | C++17 (STL 거의 미사용, 자체 컨테이너) | C++ 엔진 + C# 사용자 계층 | C++ (UObject 리플렉션 + UBT) | Rust | C++ 코어 + Lua |
| 씬 모델 | **노드 트리** (모든 것이 Node) | GameObject + Component | Actor + Component | ECS (Entity Component System) | GameObject + Component (Lua 스크립트) |
| 스크립팅 | GDScript(내장), C#, GDExtension(C/C++/Rust 등) | C# | C++, Blueprint | Rust | Lua |
| 렌더러 추상화 | RenderingServer → RenderingDevice(Vulkan/D3D12/Metal) + GL Compatibility | SRP(URP/HDRP) 위 그래픽스 API 추상화 | RHI(Render Hardware Interface) | wgpu | OpenGL/Vulkan(단일 경로) |
| 에디터 | 엔진 자체로 만든 에디터 (`editor/`가 곧 Godot 앱) | 별도 C# 에디터 | Slate UI 프레임워크 | 없음(외부/써드파티) | 별도 에디터 |
| 바이너리 크기 | 수십 MB 단일 실행 파일 | 수백 MB ~ GB | 수 GB | 작음 | 매우 작음 |
| 2D | **전용 2D 엔진** (픽셀 단위 좌표, 별도 물리) | 3D 위에 2D 얹음 | 3D 위에 2D(Paper2D) | 2D/3D 통합 | 2D 중심 |

## 8.2 "모든 것이 노드"와 "컴포지션 vs 상속"

Unity/Unreal은 **엔티티(GameObject/Actor)에 컴포넌트를 붙이는** 모델입니다. Godot은 반대로 **노드 자체가 기능**이며, 기능을 조합하려면 **자식 노드로 붙입니다**.

```
Unity:  GameObject{Transform, SpriteRenderer, Rigidbody2D, Collider2D, PlayerScript}
Godot:  CharacterBody2D
          ├─ Sprite2D
          ├─ CollisionShape2D
          └─ (스크립트는 CharacterBody2D에 attach)
```

이 결정이 소스에 미친 영향:

- `scene/main/node.h`의 `Node`가 부모/자식/그룹/알림(notification)을 모두 소유하고, `SceneTree`가 트리를 순회하며 `_process`/`_physics_process` 를 호출합니다 (3장 참조).
- 상속 깊이가 깊습니다: `Object → Node → CanvasItem → Node2D → CollisionObject2D → PhysicsBody2D → CharacterBody2D`. Unity에서는 컴포넌트를 분리했을 것을 Godot은 클래스 계층으로 풉니다.
- 씬(`.tscn`)은 **노드 트리의 직렬화**이고, 씬을 다른 씬에 인스턴스화하는 것이 Unity의 프리팹(prefab)에 대응합니다. 프리팹 변형(variant)은 "상속된 씬(inherited scene)"에 대응합니다.
- 타입 정보는 `ClassDB`(2장)가 담당하며, 에디터 인스펙터는 `_get_property_list()`를 통해 노드가 스스로 노출하는 속성을 읽습니다. Unity의 `[SerializeField]` 리플렉션, Unreal의 `UPROPERTY()` 매크로에 해당하는 것이 Godot의 `ADD_PROPERTY` + `_bind_methods()` 입니다.

⚠️ ECS 엔진(Bevy, Unity DOTS)과 달리 Godot은 **데이터 지향 병렬 처리에 최적화된 씬 모델이 아닙니다**. 대신 성능이 중요한 부분(렌더링/물리)은 서버 계층이 내부적으로 데이터 지향 구조(RID 배열, `PagedAllocator`, 스레드 컬링)를 씁니다. "씬 트리는 편의성, 서버는 성능"이 Godot의 분업입니다. 대량 인스턴스가 필요하면 `MultiMeshInstance3D`나 서버 API를 직접 호출하는 방식으로 우회합니다 (3장 3.6).

## 8.3 서버(Server) 아키텍처 vs 컴포넌트가 직접 렌더링

Unity의 `MeshRenderer`나 Unreal의 `UPrimitiveComponent`는 렌더링 파이프라인과 비교적 직접 얽혀 있습니다.
Godot은 씬 노드가 렌더러 객체를 **절대 직접 만지지 않습니다**. 노드는 `RenderingServer::get_singleton()->instance_set_transform(rid, xform)` 같은 **핸들(RID) 기반 명령**만 보냅니다.

- 장점: 씬 계층 없이도 `RenderingServer`만으로 게임을 만들 수 있고(공식 문서의 "Optimization using Servers"), 렌더 스레드 분리가 자연스럽습니다(`RenderingServerDefault` + `CommandQueueMT`, 3장/6장).
- 단점: 씬 객체와 서버 객체가 이중으로 존재하고, RID 수명 관리를 노드가 책임집니다.

Unreal의 게임 스레드/렌더 스레드 분리(`FPrimitiveSceneProxy`)와 개념적으로 유사하지만, Godot은 프록시 클래스를 만들지 않고 **명령 큐 + 불투명 핸들**로 단순화했습니다.

## 8.4 렌더러 추상화: RenderingDevice vs RHI vs wgpu

| | Godot RenderingDevice | Unreal RHI | Unity | Bevy/wgpu |
|---|---|---|---|---|
| 추상화 수준 | Vulkan에 가까운 명시적 API (버퍼/텍스처/파이프라인/드로우리스트/컴퓨트리스트) | Vulkan/D3D12에 가까운 명시적 API | 사용자에게 거의 노출 안 됨 (`CommandBuffer`, SRP) | WebGPU 스펙 기반 |
| 셰이더 언어 | Godot 셰이더 언어 → GLSL → SPIR-V (glslang) | HLSL → 각 백엔드 | HLSL/ShaderLab | WGSL |
| 백엔드 | Vulkan, D3D12, Metal (+ 별도 GL Compatibility 렌더러) | D3D11/12, Vulkan, Metal 등 | 거의 모든 API | Vulkan, D3D12, Metal, WebGPU, GL |
| 스크립트에서 접근 | GDScript로 `RenderingDevice` 직접 호출 가능(컴퓨트 셰이더 등) | C++ 전용 | C# `CommandBuffer` | Rust |

Godot만의 특징은 **두 개의 완전히 다른 렌더러**가 공존한다는 점입니다.

1. **RenderingDevice(RD) 기반**: `servers/rendering/renderer_rd/` — Forward+ / Mobile 메서드. 드라이버는 Vulkan/D3D12/Metal.
2. **GL Compatibility**: `drivers/gles3/` — OpenGL 3.3 / ES 3.0 / WebGL 2 직접 호출. RD를 거치지 않는 별개 구현.

Unreal은 하나의 RHI 위에 하나의 렌더러를 두고, 저사양은 "Mobile Renderer"라는 셰이딩 경로 차이로 처리합니다. Godot은 저사양·웹을 위해 아예 별도 렌더러를 유지하는 비용을 감수했습니다 (6장에서 상세히).

## 8.5 스크립팅: 내장 언어를 가진 이유

GDScript는 **엔진에 내장된 인터프리터**(`modules/gdscript/`)입니다. Unity의 C#(Mono/IL2CPP), Unreal의 C++/Blueprint와 달리 외부 런타임이 필요 없고, `Variant`(2장)를 그대로 값으로 씁니다. 그래서:

- 엔진 API와 스크립트 사이의 마샬링이 거의 없습니다 (`Variant` ↔ `Variant`).
- 핫 리로드, 에디터 통합(자동완성은 `gdscript_analyzer.cpp`가 담당)이 엔진 내부에서 이루어집니다.
- 반대로 성능은 JIT 없는 바이트코드 VM 수준입니다. 무거운 로직은 C#(`modules/mono`)이나 GDExtension으로 옮기는 것이 정석입니다.

GDExtension(`core/extension/`)은 Unreal의 플러그인이나 Unity의 네이티브 플러그인과 달리 **엔진을 재컴파일하지 않고 C ABI만으로 새 클래스를 ClassDB에 등록**합니다. 함수 포인터 테이블(`gdextension_interface.h`)만 안정적으로 유지하면 되므로 Rust(godot-rust), Swift, Zig 등의 바인딩이 가능합니다.

## 8.6 에디터가 엔진 그 자체

`editor/` 디렉터리는 Godot 씬 노드(`Control`, `Tree`, `ItemList` 등)로 만들어진 **그냥 하나의 Godot 애플리케이션**입니다. `main/main.cpp`의 `Main::start()`가 `-e` 플래그를 보면 `EditorNode`를 SceneTree의 루트에 붙입니다.

- 결과: 에디터 UI 위젯이 곧 게임 UI 위젯이고, 에디터 플러그인(`EditorPlugin`)을 GDScript로 작성할 수 있습니다.
- 대가: 에디터 코드 경로가 런타임 바이너리와 공유되어 `#ifdef TOOLS_ENABLED`가 소스 곳곳에 있습니다. 익스포트 템플릿은 이 부분을 빼고 빌드한 바이너리입니다 (5장).

## 8.7 2D가 1급 시민

Unity/Unreal의 2D는 3D 카메라로 스프라이트를 보는 구조지만 Godot은 `CanvasItem` 기반의 별도 2D 파이프라인(`servers/rendering/renderer_canvas_*.cpp`), 별도 2D 물리(`PhysicsServer2D`, `modules/godot_physics_2d`), 픽셀 단위 좌표계를 가집니다. 2D 게임에서 Godot이 특히 선호되는 이유가 이 구조에 있습니다.

## 8.8 빌드/배포 모델

| | Godot | Unity/Unreal |
|---|---|---|
| 빌드 도구 | SCons (Python), 단일 명령으로 모든 플랫폼 | 자체 빌드 파이프라인(UBT) / 에디터 내 빌드 |
| 익스포트 | 미리 빌드된 **템플릿 바이너리 + PCK(리소스 팩)** 결합 | 프로젝트별 컴파일 |
| 결과물 | 수십 MB | 수백 MB 이상 |

Godot의 익스포트는 "컴파일"이 아니라 **미리 만들어 둔 실행 파일에 데이터를 붙이는 것**입니다. 그래서 익스포트가 수 초 만에 끝나고, 사용자는 C++ 툴체인이 필요 없습니다. 반대로 엔진 기능을 빼거나 커스텀 모듈을 넣으려면 템플릿을 직접 빌드해야 합니다 (5장 5.6).

## 8.9 정리: Godot을 선택할 때의 트레이드오프

**강점**
- 작은 바이너리, 빠른 반복(iteration), 전체 소스 접근, 라이선스 걱정 없음
- 노드/씬 모델의 학습 용이성, 2D 전용 파이프라인
- 서버 패턴 덕분에 렌더러/물리 백엔드 교체가 구조적으로 쉬움 (Jolt 물리 도입이 그 예)

**약점 / 주의**
- AAA급 3D 기능(Nanite/Lumen 수준)은 없음. SDFGI/VoxelGI/라이트맵이 GI의 전부
- ECS가 아니므로 수만 개 엔티티의 게임 로직은 직접 최적화 필요
- 콘솔 플랫폼은 서드파티 포팅 회사 경유 (소스에 콘솔 코드가 없음)
- 렌더러가 둘이라 기능 매트릭스에 차이가 있음 (7장의 표 참조)
