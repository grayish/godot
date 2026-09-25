# Stage 5 — 서버와 렌더링 파이프라인 실습

`learning/03-servers-and-scene.md`(3.1, 3.6, 3.7), `06-graphics-backends.md`, `07-graphics-tuning.md` 를 코드로 확인하는 Godot 4 프로젝트입니다.

## 목적

- **씬 트리는 편의 계층이고 실제 일은 서버가 한다**는 문장을 손으로 확인합니다. RenderingServer / PhysicsServer2D / AudioServer 를 노드 없이 RID 만으로 직접 부르고, 같은 일을 하는 노드와 나란히 비교합니다.
- RenderingDevice(RD)로 컴퓨트 셰이더를 돌려 보고, 로컬 디바이스와 렌더 스레드 소유의 메인 디바이스가 어떻게 다른지 봅니다.
- 7장의 프로젝트 설정 키들을 실시간 패널로 바꿔 보며 어떤 것이 뷰포트 속성이고 어떤 것이 RenderingServer 전역 설정인지 구분합니다.
- 셰이더 파일 → 전처리 → 파싱 → 컴파일 → 드라이버 사슬과 세 종류(일반/인스턴스/전역)의 유니폼을 다룹니다.

## 실행 방법

에디터에서 열기: 프로젝트 매니저 → 가져오기 → `learning/projects/05-servers-rendering-lab/project.godot`.
처음 열면 `demos/rendering_device_compute/double.glsl` 이 `RDShaderFile` 로 임포트됩니다(없어도 데모가 런타임 컴파일로 대체합니다).

명령행:

```bash
cd /home/user/godot
# 기본: project.godot 의 rendering_method = forward_plus (Vulkan/D3D12/Metal 위 RD 렌더러)
bin/godot.linuxbsd.editor.x86_64 --path learning/projects/05-servers-rendering-lab

# 렌더러를 바꿔 같은 데모를 비교 (6.2 절의 선택/폴백 로직을 명령행으로 강제)
bin/godot.linuxbsd.editor.x86_64 --path learning/projects/05-servers-rendering-lab --rendering-method mobile
bin/godot.linuxbsd.editor.x86_64 --path learning/projects/05-servers-rendering-lab --rendering-method gl_compatibility
bin/godot.linuxbsd.editor.x86_64 --path learning/projects/05-servers-rendering-lab --verbose   # 드라이버/셰이더/폴백 로그

# 헤드리스 셀프테스트 (GPU/창 없이 서버 API 만 검사)
bin/godot.linuxbsd.editor.x86_64 --headless --path learning/projects/05-servers-rendering-lab -s res://selftest.gd

# 전체 검증 (셀프테스트 + 허브 5프레임 + 모든 데모 인스턴스화)
learning/projects/tools/verify.sh learning/projects/05-servers-rendering-lab
```

`forward_plus` 는 GPU 가 Vulkan 1.0 / D3D12 / Metal 을 지원해야 합니다. 못 만들면 각 플랫폼의 DisplayServer 생성자가 `gl_compatibility` 로 폴백합니다 (`platform/linuxbsd/x11/display_server_x11.cpp:7160-7250`, Windows 는 `display_server_windows.cpp:8119-8343`; 6.2 절). 허브 상단 로그와 5번 데모 헤더에서 실제로 선택된 `get_current_rendering_method()` / `get_current_rendering_driver_name()` 을 확인하세요. `--headless` 는 항상 더미 래스터라이저입니다.

## 데모 목록

| # | 디렉터리 | 보여 주는 개념 |
|---|---|---|
| 1 | `demos/rs_no_nodes_3d/` | 같은 박스 N개(100~20000)를 (a) MeshInstance3D 노드 (b) MultiMeshInstance3D (c) `RS.instance_create()` + `instance_set_scenario/base/transform` 으로 그리고 FPS, `RENDER_TOTAL_OBJECTS_IN_FRAME`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `TIME_PROCESS`, `OBJECT_NODE_COUNT` 를 비교. (b)(c)가 (a)보다 빠른 이유(Object/Node 오버헤드 vs 서버 배열)와 모든 호출이 `CommandQueueMT` 를 거친다는 점. |
| 2 | `demos/rs_canvas_2d/` | `RS.canvas_item_create/set_parent/add_rect/add_circle/add_line/add_polygon/set_transform/clear` 로 직접 그린 그림과 `_draw()` 로 그린 같은 그림. `_draw` 는 `queue_redraw()` 때만 불린다는 것을 호출 횟수로 확인. `RendererCanvasCull`(명령 저장) 과 `RendererCanvasRender`(백엔드 래스터화) 구분. |
| 3 | `demos/physics_server_direct/` | `PhysicsServer2D.body_create/body_set_mode/body_add_shape/circle_shape_create/shape_set_data/body_set_space/body_set_state` 로 만든 공과 RigidBody2D 노드의 공을 같은 space 에서 굴림. `body_get_state` 로 읽어 RS 캔버스 아이템으로 그리기, `direct_space_state.intersect_ray`, `area_set_param(space, AREA_PARAM_GRAVITY)`. `PhysicsServer2DWrapMT` 와 `Main::iteration` 의 sync/step 순서. |
| 4 | `demos/rendering_device_compute/` | `double.glsl`(`#[compute]` 섹션) 을 로컬 RD 에서 `shader_create_from_spirv → storage_buffer_create → RDUniform → uniform_set_create → compute_pipeline_create → compute_list_* → submit/sync → buffer_get_data` 로 실행. 메인 RD 는 `call_on_render_thread` 안에서만 쓰는 이유(렌더 스레드 소유, submit/sync 금지). RD 가 없으면(gl_compatibility/헤드리스) 경고만. |
| 5 | `demos/quality_tuning_panel/` | 40개의 박스/구, 방향광+옴니광 3개 그림자, 절차적 하늘, SSAO/SSIL/SSR/Glow/볼류메트릭 안개/SDFGI 토글. 패널의 각 컨트롤이 `Viewport.scaling_3d_mode/scale, msaa_3d, screen_space_aa, use_taa, use_debanding, use_occlusion_culling, positional_shadow_atlas_size, mesh_lod_threshold, debug_draw` 와 RS 전역 `directional_shadow_atlas_set_size / environment_set_ssao_quality / directional_soft_shadow_filter_set_quality` 에 묶여 있고 툴팁이 7장의 프로젝트 설정 키를 보여 줌. 헤더에 렌더링 메서드/드라이버/GPU 이름과 `viewport_get_measured_render_time_cpu/gpu`. |
| 6 | `demos/shader_pipeline/` | `wave.gdshader`(spatial, `instance uniform`), `pulse.gdshader`(canvas_item), 둘 다 `#include "common.gdshaderinc"`. `set_shader_parameter`, `set_instance_shader_parameter`, `global_shader_parameter_add/set/get/remove`, `RS.get_shader_parameter_list(shader.get_rid())`, `shader.get_mode()`. 컴파일 사슬과 `user://shader_cache`. |
| 7 | `demos/audio_server/` | `AudioServer.add_bus/set_bus_name/add_bus_effect(AudioEffectReverb)/set_bus_volume_db/set_bus_effect_enabled`, `AudioStreamGenerator` + `AudioStreamGeneratorPlayback.push_frame/get_frames_available` 로 사인파 생성, `get_mix_rate/get_output_latency/get_driver_name`. 더미 드라이버(헤드리스)에서도 같은 경로가 동작. |

허브(`main.tscn`)의 왼쪽 버튼으로 데모를 열면 이전 데모는 트리에서 떼어 낸 뒤 `queue_free()` 되고, 각 데모의 `_exit_tree` 가 서버 RID/버스/전역 유니폼을 반납합니다. 아래 로그 패널은 `Log` 오토로드(`log.gd`)의 `message` 시그널을 그대로 보여 줍니다.

## 함께 읽을 엔진 소스

| 데모 | 소스 | 학습 가이드 |
|---|---|---|
| 공통 | `servers/register_server_types.cpp`, `core/templates/rid.h`, `core/templates/rid_owner.h` | 3.1.1, 3.1.2 |
| 공통 | `servers/rendering/rendering_server_default.h` (`command_queue`, `FUNCn` 매크로, `call_on_render_thread` :1230), `servers/server_wrap_mt_common.h`, `core/templates/command_queue_mt.h` | 3.1.3, 6.6 |
| 1 | `servers/rendering/renderer_scene_cull.cpp` (`instance_allocate` :568, `instance_set_base` :606, `instance_set_scenario` :849, `instance_set_transform` :1012), `scene/3d/visual_instance_3d.cpp`, `scene/3d/multimesh_instance_3d.cpp`, `scene/resources/world_3d.cpp` | 3.3 "노드 계층과 서버 RID", 3.6, 3.7 |
| 2 | `servers/rendering/renderer_canvas_cull.cpp` (`canvas_item_set_transform` :636, `canvas_item_add_rect` :1300, `canvas_item_clear` :1945), `servers/rendering/renderer_canvas_render.h`, `servers/rendering/renderer_rd/renderer_canvas_render_rd.cpp`, `drivers/gles3/rasterizer_canvas_gles3.cpp`, `scene/main/canvas_item.cpp` (`_redraw_callback` :143, `queue_redraw` :540) | 3.3, 6.4 |
| 3 | `servers/physics_2d/physics_server_2d_wrap_mt.h`, `main/main.cpp` `Main::iteration` (sync :4992, flush_queries :4993, end_sync :5036, step :5037), `modules/godot_physics_2d/godot_physics_server_2d.cpp`, `scene/2d/physics/rigid_body_2d.cpp`, `scene/resources/world_2d.cpp` (:70 중력) | 3.1.3, 3.1.5, 1장 1.4 |
| 4 | `servers/rendering/rendering_device.cpp` (`storage_buffer_create` :1513, `uniform_set_create` :4471, `compute_pipeline_create` :5152, `compute_list_begin` :6783, `compute_list_dispatch` :6935, `submit` :8135, `sync` :8145, `buffer_get_data` :1356, `create_local_device` :9286), `servers/rendering/rendering_device_binds.cpp` (`RDShaderFile::parse_versions_from_text` :40), `servers/rendering/rendering_device_graph.h`, `servers/rendering/rendering_server.cpp:1891`, `editor/import/resource_importer_shader_file.cpp`, `modules/glslang/` | 6.3 |
| 5 | `servers/rendering/rendering_server.cpp` `RenderingServer::init()` (GLOBAL_DEF, :3670-3840), `scene/main/viewport.cpp`, `servers/rendering/renderer_viewport.cpp` (`viewport_set_measure_render_time` :1576), `servers/rendering/renderer_rd/effects/` (FSR/FSR2/TAA/SMAA/SSEffects), `servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp` | 7.1-7.6, 6.4 |
| 6 | `scene/resources/shader.cpp` (`_check_shader_rid` :52), `scene/resources/material.cpp` (`ShaderMaterial::set_shader_parameter` :420), `scene/3d/visual_instance_3d.cpp` (:421), `servers/rendering/shader_preprocessor.cpp` (:1368), `servers/rendering/shader_language.cpp` (:11534), `servers/rendering/shader_compiler.cpp` (:1558), `servers/rendering/renderer_rd/shader_rd.cpp` (셰이더 캐시 :610), `drivers/gles3/shader_gles3.cpp`, `servers/rendering/renderer_rd/storage_rd/material_storage.cpp` (`global_shader_parameter_add` :1827, `global_shader_parameters_load_settings` :1974) | 3.6, 6.5 |
| 7 | `servers/audio/audio_server.cpp` (`_mix_step` :131, `add_bus` :677, `set_bus_volume_db` :821, `add_bus_effect` :923), `servers/audio/audio_driver_dummy.h`, `scene/resources/audio/audio_stream_generator.cpp` (`push_frame` :112, `get_frames_available` :154, `_mix_internal` :168) | 3.1.1 |
| 헤드리스 | `servers/rendering/dummy/` (`rasterizer_dummy.h`, `storage/material_storage.cpp`, `storage/mesh_storage.h`), `servers/display/display_server_headless.h` | 3.1.1 |

## 연습 과제

1. **데모 1**: (c) 모드에서 매 프레임 `RS.instance_set_transform` 을 20000번 부르는 대신, 100개씩 나눠 5프레임에 걸쳐 갱신하도록 바꾸고 `TIME_PROCESS` 가 어떻게 변하는지 기록하세요. 그다음 `rendering/driver/threads/thread_model` 을 `Separate` 로 바꿔 `CommandQueueMT` 가 실제로 큐잉하도록 하고 같은 측정을 반복하세요 (`rendering_server_default.h` 의 `ASYNC_COND_PUSH`).
2. **데모 2**: `DrawSide` 에 `rotation` 을 주어 `_draw` 를 다시 부르지 않고 회전시키세요. 그런 다음 `RS.canvas_item_add_texture_rect` 로 `PlaceholderTexture2D` 를 그리고 `RendererCanvasCull::canvas_item_add_texture_rect` 에서 명령이 어떻게 저장되는지 읽어 보세요.
3. **데모 3**: `PhysicsServer2D.body_set_state_sync_callback` 을 서버 공에 등록해 `_physics_process` 에서 `body_get_state` 를 폴링하는 대신 콜백으로 트랜스폼을 받아 보세요 (`rigid_body_2d.cpp` 의 `_body_state_changed` 와 비교). `physics/2d/run_on_separate_thread` 를 켰을 때 `direct_space_state` 접근이 언제 실패하는지도 확인하세요.
4. **데모 4**: `double.glsl` 에 `#[versions]` 섹션을 추가해 `mul2 = "#define FACTOR 2.0";`, `mul4 = "#define FACTOR 4.0";` 두 버전을 만들고 `RDShaderFile.get_spirv("mul4")` 로 골라 실행하세요. 그리고 `rd.compute_list_set_push_constant` 로 계수를 넘기는 버전으로 바꿔 보세요.
5. **데모 5**: `--gpu-profile` 로 (a) 기본 (b) `scaling_3d_scale = 0.5` (c) 방향광 그림자 1024 (d) SSAO off 의 GPU 시간을 재서 표로 만드세요 (7장 실습 7). 패널이 SubViewport 속성을 바꾸는 것과 프로젝트 설정 키를 바꾸는 것(루트 뷰포트 기본값)의 관계를 `scene/main/scene_tree.cpp` 의 `GLOBAL_DEF` 에서 찾으세요.
6. **데모 6**: `Shader.inspect_native_shader_code()` 를 호출해 `ShaderCompiler` 가 만든 GLSL 조각을 출력하고, `wave.gdshader` 의 `instance uniform` 이 어느 유니폼 버퍼로 들어가는지 `render_forward_clustered.cpp` 의 `instance_uniforms` 에서 확인하세요.
7. **데모 7**: `AudioServer.get_bus_peak_volume_left_db` 로 간단한 레벨 미터를 그리고, `AudioEffectSpectrumAnalyzer` 를 버스에 추가해 `get_bus_effect_instance` 로 스펙트럼을 읽어 보세요.

## 흔한 함정

- **RID 는 스스로 반납되지 않습니다.** 노드는 `NOTIFICATION_PREDELETE` 에서 자기 RID 를 반납하지만 `RS.instance_create()` / `PhysicsServer2D.body_create()` / `canvas_item_create()` 로 직접 만든 RID 는 `free_rid` 를 불러야 합니다. 이 프로젝트는 `_exit_tree` 에서 반납합니다. 셰이프 RID 는 몸체보다 나중에 해제하세요.
- **`direct_space_state` 는 `_physics_process` 안에서만** 안전합니다. 물리 서버가 `step()` 중이면 "Space state is inaccessible" 오류가 납니다 (`Main::iteration` 의 sync/step 순서).
- **컨테이너 안의 전역 좌표**: `_ready` 시점에는 부모 컨테이너의 레이아웃이 아직 적용되지 않았을 수 있습니다. 데모 3 은 그래서 첫 `_physics_process` 에서 몸체를 만듭니다.
- **`global uniform` 은 셰이더 컴파일 전에 등록**되어야 합니다. 파일 셰이더가 참조하는 전역은 `project.godot [shader_globals]` 에 두고, 런타임에 `global_shader_parameter_add` 한 전역은 그 뒤에 만든 셰이더만 참조하세요. 같은 이름을 두 번 add 하면 오류입니다(목록으로 확인).
- **메인 RenderingDevice 에서 `submit()/sync()` 를 부르지 마세요.** 프레임 끝에 엔진이 합니다. RD 접근은 `call_on_render_thread` 콜러블 안에서만 하고, 결과는 `call_deferred` 로 메인 스레드에 넘기세요. `create_local_rendering_device()` 는 gl_compatibility 와 headless 에서 `null` 입니다.
- **`.glsl` 은 임포트가 필요합니다.** 에디터를 한 번도 열지 않았다면 `load("res://...glsl")` 이 실패합니다. 데모 4 는 `ResourceLoader.exists(path, "RDShaderFile")` 로 확인하고 없으면 `RDShaderSource` 로 런타임 컴파일합니다.
- **RS 전역 설정은 데모를 넘어 영향을 줍니다.** `directional_shadow_atlas_set_size`, `environment_set_ssao_quality`, `directional_soft_shadow_filter_set_quality` 는 뷰포트와 무관한 전역이라 데모 5 는 `_exit_tree` 에서 프로젝트 설정값으로 되돌립니다.
- **버스 인덱스는 변합니다.** 버스를 추가/삭제하면 인덱스가 밀리므로 이름(`get_bus_index`)으로 다시 찾으세요. 플레이어를 멈춘 뒤 버스를 지우세요.
- **`config/features=PackedStringArray("4.4")`** 는 이 저장소의 4.8 dev 바이너리에서 경고만 냅니다. 프로젝트를 저장하면 에디터가 갱신합니다.
