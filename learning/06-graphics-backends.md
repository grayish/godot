# 6장. 그래픽스 백엔드: 종류, 구조, 셰이더 파이프라인

## 6.1 두 개의 축: 렌더링 메서드 × 렌더링 드라이버

Godot 4의 그래픽스 스택은 **두 개의 독립된 선택**으로 구성됩니다.

```
                     rendering_method (렌더러, "무엇을 어떻게 그리나")
                ┌──────────────┬──────────────┬────────────────────┐
                │ forward_plus │   mobile     │  gl_compatibility  │
                │ (Forward+)   │ (Forward     │  (OpenGL 3.3 /     │
                │ 클러스터 조명 │  Mobile)     │   ES 3.0 / WebGL2) │
                └──────┬───────┴──────┬───────┴─────────┬──────────┘
                       │              │                 │
              servers/rendering/renderer_rd/        drivers/gles3/
              (RenderingDevice 위에 구현)            (GL 직접 호출)
                       │                                 │
       ┌───────────────┼───────────────┐                 │
   rendering_device/driver (드라이버, "어떤 API로")   gl_compatibility/driver
   ┌────────┐  ┌────────┐  ┌────────┐      ┌─────────┐ ┌────────────┐ ┌───────────────┐
   │ vulkan │  │ d3d12  │  │ metal  │      │ opengl3 │ │ opengl3_es │ │ opengl3_angle │
   └────────┘  └────────┘  └────────┘      └─────────┘ └────────────┘ └───────────────┘
   drivers/vulkan  drivers/d3d12  drivers/metal        WGL/GLX/NSGL   EGL/GLES     ANGLE(D3D11/Metal 위 GLES)
```

| | Forward+ | Mobile | GL Compatibility |
|---|---|---|---|
| 구현 | `renderer_rd/forward_clustered/` | `renderer_rd/forward_mobile/` | `drivers/gles3/` |
| 드라이버 | Vulkan / D3D12 / Metal | Vulkan / D3D12 / Metal | OpenGL 3.3 / GLES 3.0 / WebGL 2 / ANGLE |
| 조명 | 클러스터(타일+깊이 슬라이스) — 조명 수 제한 거의 없음 | 오브젝트당 최대 8개 조명, 유니폼 | 오브젝트당 조명 제한(`max_lights_per_object`) |
| GI | SDFGI, VoxelGI, 라이트맵, 리플렉션 프로브 | VoxelGI, 라이트맵, 리플렉션 프로브 (SDFGI·볼류메트릭 안개 없음) | 라이트맵, 리플렉션 프로브 |
| 스크린 스페이스 효과 | SSAO, SSIL, SSR, SSS, 볼류메트릭 안개 | 없음 (서브패스 유지 위해) | 간이 SSAO(S4AO)만 |
| AA | MSAA, FXAA, SMAA, TAA | MSAA, FXAA, SMAA | MSAA, FXAA |
| 업스케일 | FSR 1.0, FSR 2.2, MetalFX Spatial/Temporal | FSR 1.0, MetalFX | 없음(bilinear/nearest) |
| 강점 | 데스크톱 고품질 | 모바일·VR: 단일 렌더 패스(서브패스) + 타일 GPU 대역폭 절약 | 구형 하드웨어, 웹, 초저사양, 2D 전용 게임 |
| 스레드 | 별도 렌더 스레드, 비동기 리소스 생성 | 동일 | 리소스 생성은 GL 컨텍스트 스레드에서만 |

⚠️ 이름 주의: `servers/rendering/rendering_method.h`의 `class RenderingMethod`는 씬 컬링 인터페이스(`RendererSceneCull`이 구현)이고, 프로젝트 설정 `rendering_method`와는 무관합니다.

## 6.2 선택과 폴백 로직

📌 `main/main.cpp:2489-2660`

1. 프로젝트 매니저는 항상 `opengl3 / gl_compatibility` (어디서나 뜨도록).
2. `--rendering-method`, `--rendering-driver` 명령행 검증. 드라이버만 주면 메서드 추론(`opengl3*` → gl_compatibility, 그 외 → forward_plus).
3. 조합 검증 (`:2581-2630`): forward_plus/mobile ⇔ {vulkan, d3d12, metal}, gl_compatibility ⇔ {opengl3, opengl3_angle, opengl3_es}.
4. 명령행이 없으면 프로젝트 설정: `rendering/renderer/rendering_method` (+`.mobile`, `.web` 오버라이드), 드라이버는 메서드에 따라 `rendering/rendering_device/driver` 또는 `rendering/gl_compatibility/driver` (+플랫폼 접미사).
5. `OS::set_current_rendering_driver_name/method`에 출처(DEFAULT/COMMANDLINE/PROJECT_SETTING/FALLBACK)와 함께 저장.

**런타임 폴백은 각 플랫폼 DisplayServer 생성자에 있습니다** (`main.cpp`가 아님):
- Windows (`display_server_windows.cpp:8119-8343`): d3d12↔vulkan 순서로 시도(`fallback_to_d3d12/vulkan`) → 둘 다 실패 + `fallback_to_opengl3`면 **메서드까지 gl_compatibility로 바꿈** → WGL < 3.3 이거나 `force_angle_on_devices` 목록(구형 AMD/Intel Gen7-9.5)이거나 Windows on ARM이면 ANGLE → ANGLE 실패 시 `fallback_to_native`.
- Linux X11 (`display_server_x11.cpp:7160-7250`): Vulkan 실패 → opengl3/gl_compatibility; GLX 실패 + `fallback_to_gles` → opengl3_es. Wayland 동일.
- macOS (`display_server_macos.mm:3866-3896`): Intel Mac에서는 Metal 대신 Vulkan(MoltenVK); RD 실패 → opengl3.
- Android (`display_server_android.cpp:704-718`): Vulkan 실패 → opengl3.
- 추가로 `RendererCompositorRD` (`renderer_compositor_rd.cpp:374-392`)는 `LIMIT_MAX_TEXTURES_PER_SHADER_STAGE < 48`인 GPU에서 **Forward+ 요청을 Mobile로 자동 강등**합니다.

`--verbose`로 실행하면 이 과정이 로그로 보입니다. "왜 내 게임이 Compatibility로 돌지?"는 여기서 답을 찾습니다.

## 6.3 RenderingDevice: 백엔드 중립 GPU API

📌 `servers/rendering/rendering_device.h` (2,088줄), `rendering_device_driver.h`, `rendering_context_driver.h`

`RenderingDevice`(RD)는 Vulkan에 가까운 명시적 API를 백엔드 중립으로 노출합니다. GDScript에서도 직접 쓸 수 있습니다(컴퓨트 셰이더 튜토리얼이 이것).

| 개념 | RD API | 비고 |
|---|---|---|
| 텍스처/샘플러/프레임버퍼 | `texture_create`(469), `sampler_create`(732), `framebuffer_create`(716) | |
| 버퍼 | `vertex_buffer_create`, `index_buffer_create`, `uniform_buffer_create`, `storage_buffer_create` | 업/다운로드는 스테이징 버퍼 경유 |
| 셰이더 | `shader_compile_spirv_from_source`(GLSL→SPIR-V), `shader_create_from_spirv`, `shader_create_from_bytecode` | 모든 백엔드의 공용어는 **SPIR-V** |
| 파이프라인 | `render_pipeline_create`(specialization constants 포함), `compute_pipeline_create`, `raytracing_pipeline_create` | PSO 캐시 지원 |
| 유니폼 | `uniform_set_create` | |
| 명령 | `draw_list_begin/…/end`, `compute_list_begin/dispatch/end`, `raytracing_list_*` | |
| 프레임 | `swap_buffers`, `submit/sync`, `create_local_device()`(오프스크린/컴퓨트용 보조 디바이스) | |
| 가속 구조 | BLAS/TLAS (1343-1370) | 레이트레이싱(실험) |

세 계층:
1. **`RenderingContextDriver`** — 인스턴스/어댑터/서피스: `initialize`, `device_get_count`, `driver_create`, `surface_create`, `surface_set_vsync_mode`, HDR 출력.
2. **`RenderingDeviceDriver`** — 순수 가상 백엔드 인터페이스: 타입이 있는 핸들 ID(`BufferID`, `TextureID`, `PipelineID`…), `buffer_create`, `texture_create`, `command_pipeline_barrier`, `command_queue_execute_and_present`, `swap_chain_create`, `shader_create_from_container`, `pipeline_cache_*`, `command_render_draw`, `command_compute_dispatch`, `has_feature`, `get_shader_container_format`.
3. **`RenderingDevice`** — 위를 감싸 프레임 관리, 스테이징, 리소스 추적, **렌더 그래프**를 제공.

### 드라이버 구현
| 드라이버 | 핵심 파일 | 특징 |
|---|---|---|
| Vulkan | `drivers/vulkan/rendering_device_driver_vulkan.cpp`, `rendering_context_driver_vulkan.cpp` | VMA(메모리), volk(로더), SPIR-V 그대로 사용. 가장 성숙. `max_descriptors_per_pool` 설정 |
| D3D12 | `drivers/d3d12/rendering_device_driver_d3d12.cpp`, `rendering_shader_container_d3d12.cpp` | SPIR-V → NIR → DXIL 변환(Mesa 유래) + DXIL 서명. D3D12MA. Agility SDK. `max_resource_descriptors` |
| Metal | `drivers/metal/rendering_device_driver_metal.cpp`(+`metal3` 서브클래스), `rendering_shader_container_metal.cpp` | SPIR-V → MSL(SPIRV-Cross). MoltenVK에서 파생한 부분 있음. MetalFX 업스케일러 |

셰이더 바이너리 포맷은 `RenderingShaderContainer` (`rendering_shader_container.h`)로 추상화되어, 각 드라이버가 자기 포맷(SPIR-V/DXIL/MSL)으로 `_set_code_from_spirv`를 구현합니다. 셰이더 캐시와 셰이더 베이커가 이 컨테이너를 저장합니다.

### 렌더 그래프 (`rendering_device_graph.h`)
RD는 명령을 즉시 API에 보내지 않고 `RenderingDeviceGraph`에 **기록**합니다. 각 명령의 리소스 사용을 `ResourceTracker`로 추적해 의존 그래프를 만들고, 레벨별로 정렬·재배열한 뒤 **필요한 배리어만** 삽입해 실행합니다(`_run_render_commands`). 이것이 4.3에서 도입된 "자동 배리어" 시스템이며, 사용자가 RD로 컴퓨트를 쓸 때 배리어를 직접 안 넣어도 되는 이유입니다. 컴파일 타임 플래그 `RENDER_GRAPH_REORDER`, `RENDER_GRAPH_FULL_BARRIERS`(디버그), `SECONDARY_COMMAND_BUFFERS_PER_FRAME`(워커 스레드 기록, 기본 off) — 디버그 빌드에선 `GODOT_RG_REORDER` 등 환경 변수로 토글.

## 6.4 렌더러 구현

### 프레임 시작점
`RenderingServerDefault::_draw()` (`rendering_server_default.cpp:76-213`): `begin_frame` → `scene->update` / `canvas->update` → 파티클 → `render_probes` → **`viewport->draw_viewports()`** → `canvas_render->update` → `end_frame`.

### RD 렌더러 (`servers/rendering/renderer_rd/`)
```
RendererCompositorRD                 백엔드 팩토리 (storages, canvas, scene)
├── storage_rd/                      TextureStorage, MaterialStorage, MeshStorage, LightStorage, ParticlesStorage, RenderSceneBuffersRD
├── renderer_scene_render_rd.*       두 렌더러의 공통 베이스: 포스트프로세스, 컴포지터 이펙트, VRS
│   ├── forward_clustered/           RenderForwardClustered + SceneShaderForwardClustered (Forward+)
│   └── forward_mobile/              RenderForwardMobile + SceneShaderForwardMobile
├── renderer_canvas_render_rd.*      2D
├── environment/                     GI(SDFGI, VoxelGI), Fog(볼류메트릭), SkyRD
├── effects/                         FSR, FSR2, MetalFX, TAA, SMAA, ToneMapper, Luminance(자동 노출), BokehDOF,
│                                    SSEffects(SSAO/SSIL/SSR/SSS), RoughnessLimiter, CopyEffects, VRS, MotionVectorsStore
├── shaders/**/*.glsl                scene_forward_clustered.glsl, scene_forward_mobile.glsl, tonemap.glsl(FXAA 포함), ...
├── shader_rd.*                      셰이더 변형(variant) 관리·병렬 컴파일·캐시
├── pipeline_hash_map_rd.*           파이프라인 비동기 컴파일 + 해시맵
└── cluster_builder_rd.*             Forward+ 조명 클러스터
```

**Forward+ 한 프레임의 패스 순서** (`render_forward_clustered.cpp`의 `RENDER_TIMESTAMP` 기준):
1. SDFGI 갱신 → 그림자(방향광/옴니/스팟, GI와 병렬)
2. SSAO/SSIL용 깊이 준비 → 볼류메트릭 안개 갱신
3. 3D 씬/스카이 셋업
4. **Depth Pre-Pass** (GI와 병렬 가능) → MSAA 깊이 리졸브
5. `_pre_opaque_render`: SSAO, SSIL, SSR, 스크린 스페이스 접촉 그림자
6. **Opaque Pass** → Motion Pass → **Sky** → MSAA 리졸브
7. SSS → Merge Specular → 스크린/깊이 텍스처 복사 (`SCREEN_TEXTURE`용)
8. **Transparent Pass** → 리졸브
9. **FSR2 / MetalFX Temporal / TAA** (택일)
10. `_render_buffers_post_process_and_tonemap`: DOF → 자동 노출 → Glow → **Tonemap**(+FXAA) → FSR1/MetalFX Spatial → SMAA

**Mobile**은 "Opaque + Transparent + Tonemap을 하나의 렌더 패스(서브패스)"로 묶어 타일 GPU의 메모리 대역폭을 아낍니다 (`render_forward_mobile.cpp:896-930` 주석에 서브패스가 깨지는 조건 — `SCREEN_TEXTURE`, 글로우, 컴포지터 콜백 등이 명시됨). `is_dynamic_gi_supported()`/`is_volumetric_supported()`가 false.

### GL Compatibility (`drivers/gles3/`)
`RasterizerGLES3 : RendererCompositor` + `RasterizerSceneGLES3`, `RasterizerCanvasGLES3`, `storage/`(Config, Texture/Material/Mesh/Light/Particles Storage), `effects/`(CopyEffects, CubemapFilter, Glow, PostEffects), `shaders/scene.glsl` 등. 패스: Shadows → Setup → Motion Vectors → Depth Prepass(`disable_for_vendors` 목록의 타일 GPU에선 생략) → Opaque → Sky → Transparent → 포스트(Glow, MSAA blit 리졸브, 톤맵). RD를 전혀 거치지 않는 **완전히 별개의 코드**입니다. `can_create_resources_async()`가 false라 리소스 생성이 GL 스레드로 마샬링됩니다.

## 6.5 셰이더 파이프라인

```
[사용자]  .gdshader (Godot 셰이더 언어)
   │  ShaderPreprocessor  (#include, #define)               servers/rendering/shader_preprocessor.cpp
   │  ShaderLanguage       (토크나이저·타입·AST, 12k줄)       servers/rendering/shader_language.cpp
   │  ShaderCompiler       (AST → GLSL 조각, 렌더러별 built-in 이름 치환)   servers/rendering/shader_compiler.cpp
   ▼
[엔진]  렌더러 기본 셰이더 .glsl  (#[vertex] / #[fragment] / #[compute] 섹션, 빌드 시 .glsl.gen.h 로 C++ 클래스화)
   │  ShaderRD::_compile_variant  — 사용자 코드 조각을 템플릿에 삽입, 변형(variant) × 스펙 상수
   ▼
   glslang (modules/glslang)  GLSL → SPIR-V
   ▼
   RenderingShaderContainer   SPIR-V → 드라이버 포맷 (Vulkan: 그대로 / D3D12: NIR→DXIL / Metal: MSL)
   ▼
   드라이버 shader_create_from_container → 파이프라인(PSO) 생성 (PipelineHashMapRD, 비동기)
```

GL Compatibility는 `gles3_builders.py`가 `#[modes]`/`#[specializations]` 섹션을 파싱해 `ShaderGLES3` 서브클래스를 만들고, 런타임에 GLSL 문자열을 `glCompileShader`로 컴파일하며 `glGetProgramBinary`로 캐시합니다.

### 캐시와 스터터 방지 — 세 겹의 캐시
1. **셰이더 캐시** (`rendering/shader_compiler/shader_cache/*`, `user://shader_cache`): SPIR-V/드라이버 컨테이너를 디스크에 저장. 에디터에서는 강제 on.
2. **파이프라인(PSO) 캐시** (`rendering/rendering_device/pipeline_cache/*`, `user://vulkan/pipelines.<method>.<device>.cache`): 드라이버 수준 PSO 캐시. 워커 스레드에서 청크 단위로 저장.
3. **우버셰이더(ubershader) 폴백**: 씬 셰이더는 각 버전을 "특수화됨"과 `#define UBERSHADER` 두 번 컴파일합니다. 드로우 시 특수화 파이프라인이 아직 없으면 우버셰이더(특수화 값을 push constant로 전달, 컬링 off)로 그리고, 뒤에서 특수화 파이프라인을 비동기 컴파일합니다 (`render_forward_clustered.cpp:506-541`). 메시 로드 시 `_mesh_compile_pipelines_for_surface`로 선컴파일도 합니다. 4.4의 "셰이더 스터터 제거"가 이 메커니즘입니다.
4. **셰이더 베이커** (익스포트 시, `editor/export/shader_baker/`): 타깃 API용 컨테이너를 미리 만들어 PCK에 넣어 첫 실행 컴파일을 없앱니다.

## 6.6 스레딩 모델

- 설정: `rendering/driver/threads/thread_model` (Safe=1 기본 / Separate). CLI `--render-thread safe|separate`.
- Separate는 에디터/프로젝트 매니저에서 강제 off("crash on startup" 주석, `main.cpp:2766`), 활성화 시 "experimental" 경고.
- `RenderingServerDefault`가 WorkerThreadPool 태스크로 `_thread_loop`를 돌리며 `CommandQueueMT`를 flush (3장 3.1.3). `draw()`는 메인 스레드에서만 호출되어 `_draw`를 큐에 넣습니다.
- 다른 스레드의 리소스 생성: RD는 `can_create_resources_async()` = true라 로더 스레드가 GPU 텍스처를 직접 만듭니다. GLES3는 false → 큐로 마샬링. Separate 모드에서 GL 컨텍스트는 `release_rendering_thread()`로 메인에서 놓고 렌더 태스크에서 `gl_window_make_current`.
- 그 외 병렬화: `ShaderRD` 변형 병렬 컴파일("ShaderCompilation" 그룹 태스크), `PipelineHashMapRD` 비동기 PSO, 렌더 그래프의 보조 커맨드 버퍼(기본 off), `RendererSceneCull`의 스레드 컬링(`threaded_cull_minimum_instances`).

## 6.7 드라이버 선택 가이드

| 상황 | 권장 |
|---|---|
| Windows 데스크톱 | Vulkan 기본. D3D12는 Windows 전용 기능(Agility SDK, Xbox 계열 파이프라인, 일부 구형 드라이버 호환)이 필요할 때. `fallback_to_d3d12` 켜두기 |
| Linux | Vulkan. 구형 GPU(GL 3.3만)면 자동으로 opengl3 |
| macOS / iOS | Metal 기본(Apple Silicon). Intel Mac은 자동으로 MoltenVK |
| Android | 최신 기기·Forward Mobile → Vulkan. 넓은 기기 호환·2D → opengl3(GLES3) |
| Web | opengl3(WebGL2) + gl_compatibility 밖에 없음 |
| 서버/CI/헤드리스 | `--headless` (dummy) |
| 저사양·통합 GPU·2D 게임 | gl_compatibility가 오히려 빠른 경우가 많음 (RD 오버헤드·클러스터 조명 비용 없음) |

🧪 **실습 6**: RenderDoc(또는 Xcode GPU Frame Capture)으로 Forward+ 프레임을 캡처하고, 6.4의 패스 순서와 캡처 이벤트의 디버그 레이블을 대조하세요. 그다음 같은 씬을 `--rendering-method mobile`, `--rendering-method gl_compatibility`로 캡처해 패스 수와 렌더 타깃 수의 차이를 비교하세요.
