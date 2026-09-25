# 7장. 그래픽스 백엔드별 튜닝

이 장은 **프로젝트 설정 키 → 소스 위치 → 효과 → 백엔드별 권장값**을 정리합니다.
설정은 대부분 `servers/rendering/rendering_server.cpp`의 `RenderingServer::init()` (약 3670-3840줄)에서 `GLOBAL_DEF`로 등록되며, 일부는 `scene/main/scene_tree.cpp`(ST), `core/config/project_settings.cpp`(PS), `main/main.cpp`에 있습니다. 에디터에서 키를 검색하면 그대로 나옵니다.

`.mobile`, `.web`, `.ios` 같은 접미사는 **기능 태그 오버라이드**입니다: 해당 태그를 가진 플랫폼에서 그 값이 우선합니다 (2장 2.8).

## 7.1 튜닝의 원칙: 무엇이 병목인가부터

| 증상 | 확인 도구 | 의심 대상 |
|---|---|---|
| GPU 시간 > 프레임 예산 | `--gpu-profile`, 에디터 Debugger → Visual Profiler, RenderDoc | 해상도(`scaling_3d/scale`), 그림자 크기, SSAO/SSIL/SSR, GI, MSAA |
| CPU 메인 스레드 | Debugger → Profiler, `--print-fps` | 드로우콜 수(노드 수), 물리, 스크립트 |
| 렌더 스레드 대기 | Profiler의 "Rendering" 항목 | `thread_model`, 리소스 생성, 셰이더 컴파일 |
| 첫 진입 시 끊김 | `--verbose` 셰이더 로그 | 파이프라인 컴파일 → 캐시·베이커·우버셰이더 |
| VRAM 부족 | Debugger → Monitors → Video RAM | 텍스처 압축, 아틀라스 크기, 리플렉션 아틀라스 |

## 7.2 공통 설정 (모든 백엔드)

### 텍스처
| 키 | 기본 | 설명 |
|---|---|---|
| `rendering/textures/vram_compression/import_s3tc_bptc` | 데스크톱 true | 데스크톱용 BC1-7 압축 임포트 |
| `.../import_etc2_astc` | 모바일 true | 모바일용. 둘 다 켜면 임포트 파일이 2배 |
| `.../compress_with_gpu`, `cache_gpu_compressor` | | Betsy(컴퓨트) GPU 압축기 사용 |
| `rendering/textures/default_filters/anisotropic_filtering_level` | 4x | 비등방 필터링. 16x는 대역폭 증가 |
| `.../texture_mipmap_bias` | 0 | 음수면 선명·앨리어싱, 양수면 흐림·대역폭 절약. FSR 사용 시 자동 보정 |
| `.../use_nearest_mipmap_filter` | false | 픽셀아트 |
| `rendering/textures/lossless_compression/force_png` | false | WebP 대신 PNG (호환성) |
| `rendering/textures/decals/filter`, `light_projectors/filter` | | 데칼/프로젝터 샘플링 |

### 조명과 그림자
| 키 | 기본 (.mobile) | 설명 |
|---|---|---|
| `rendering/lights_and_shadows/directional_shadow/size` | 4096 (2048) | 방향광 그림자 맵. 가장 큰 VRAM/필레이트 소비자 중 하나 |
| `.../directional_shadow/soft_shadow_filter_quality` | Soft Low (Hard) | PCF 샘플 수. Soft Very High는 매우 비쌈 |
| `.../directional_shadow/16_bits` | true | 깊이 16비트. 대역폭 절약, 아티팩트 가능 |
| `.../positional_shadow/atlas_size` (ST) | 4096 (2048) | 옴니/스팟 그림자 아틀라스 |
| `.../positional_shadow/atlas_quadrant_0..3_subdiv` (ST) | | 사분면별 분할. 조명 수 vs 해상도 |
| `.../positional_shadow/soft_shadow_filter_quality` | | |
| `.../use_physical_light_units` | false | 물리 단위(lux, lumen) + 카메라 노출 |
| `.../contact_shadow/*` | | 스크린 스페이스 접촉 그림자 (Forward+) |
| `.../tighter_shadow_caster_culling` | | 캐스터 컬링 강화 |
| `rendering/2d/shadow_atlas/size` | 2048 | 2D 조명 그림자 |

### 안티앨리어싱
| 키 | 설명 |
|---|---|
| `rendering/anti_aliasing/quality/msaa_3d` | 2x/4x/8x. Mobile 타일 GPU에선 거의 공짜, 데스크톱 Forward+에선 비쌈. GL도 지원 |
| `.../msaa_2d` | 2D 전용 |
| `.../screen_space_aa` (ST) | FXAA(싸고 흐림) / SMAA(RD 전용, 더 좋음) |
| `.../use_taa` (ST) | Forward+ 전용. 모션 벡터 필요, 고스팅 가능. FSR2/MetalFX Temporal과 배타 |
| `.../use_debanding` | 디더링으로 밴딩 제거 (거의 공짜) |
| `.../screen_space_roughness_limiter/*` | 스페큘러 앨리어싱 억제 |

### 해상도 스케일링
| 키 | 설명 |
|---|---|
| `rendering/scaling_3d/mode` | Bilinear / FSR 1.0(공간) / FSR 2.2(시간, Forward+) / MetalFX Spatial·Temporal(`.macos`, `.ios`) |
| `rendering/scaling_3d/scale` | 0.5 = 절반 해상도 렌더 후 업스케일. **GPU 바운드일 때 가장 효과 큰 단일 설정** |
| `rendering/scaling_3d/fsr_sharpness` | FSR 선명도 (기본 0.2) |

3D만 축소되고 2D/UI는 원해상도로 그려집니다. Godot이 뷰포트 단위로 3D 버퍼와 2D 버퍼를 분리하기 때문입니다.

### 환경/포스트프로세스 (Forward+, 일부 Mobile)
| 키 | 설명 |
|---|---|
| `rendering/environment/ssao/quality`, `half_size`, `adaptive_target`, `blur_passes`, `fadeout_*` | SSAO. `half_size=true`가 큰 절약 |
| `rendering/environment/ssil/*` | 스크린 스페이스 간접광. SSAO보다 비쌈 |
| `rendering/environment/screen_space_reflection/half_size` | SSR |
| `rendering/environment/glow/upscale_mode` (.mobile Linear) | Bicubic이 더 좋고 비쌈 |
| `rendering/environment/subsurface_scattering/*` | SSS 품질 |
| `rendering/environment/volumetric_fog/volume_size`, `volume_depth`, `use_filter` | 프러스텀 복셀 그리드 크기. 64×64×64 기본 |
| `rendering/camera/depth_of_field/*` | 보케 모양/품질/지터 |

### GI
| 키 | 설명 |
|---|---|
| `rendering/global_illumination/gi/use_half_resolution` | GI 버퍼 절반 해상도 |
| `rendering/global_illumination/sdfgi/probe_ray_count`, `frames_to_converge`, `frames_to_update_lights` | SDFGI 품질 vs 반응 속도 |
| `rendering/global_illumination/voxel_gi/quality` | 4 또는 6 콘 |
| `rendering/lightmapping/*`, `lightmapper_rd` 설정 | 베이크 품질 (에디터 시간) |

### 리플렉션
`rendering/reflections/sky_reflections/roughness_layers`, `texture_array_reflections`(.mobile false), `ggx_samples`(.mobile 16), `fast_filter_high_quality`; `reflection_atlas/reflection_size`(.mobile 128), `reflection_count`.

### 컬링과 LOD
| 키 | 설명 |
|---|---|
| `rendering/occlusion_culling/use_occlusion_culling` (ST) | Embree 소프트웨어 오클루전 (`OccluderInstance3D` 필요). CPU 비용 ↔ 드로우콜 절감 |
| `.../occlusion_rays_per_thread`, `bvh_build_quality`, `jitter_projection` | |
| `rendering/mesh_lod/lod_change/threshold_pixels` (ST) | 임포트 시 생성된 LOD 전환 임계값. 클수록 공격적 |
| `rendering/limits/spatial_indexer/threaded_cull_minimum_instances` | 이 수 이상이면 컬링을 멀티스레드로 |
| `.../update_iterations_per_frame` | BVH 갱신 예산 |

### 셰이딩 오버라이드 (저사양 프리셋용)
`rendering/shading/overrides/force_vertex_shading`, `force_lambert_over_burley`(.mobile true).

### 셰이더/파이프라인 캐시
| 키 | 기본 | 설명 |
|---|---|---|
| `rendering/shader_compiler/shader_cache/enabled` | true | `user://shader_cache`. 에디터에선 강제 on |
| `.../compress`, `use_zstd_compression` | true | |
| `.../strip_debug` (.release true) | | 릴리스에서 디버그 정보 제거 |
| `rendering/rendering_device/pipeline_cache/enable` (PS) | true | 드라이버 PSO 캐시 파일 |
| `.../pipeline_cache/save_chunk_size_mb` (PS) | 3.0 | 이 크기만큼 자라면 워커 스레드에서 저장 |

## 7.3 RenderingDevice 드라이버 공통 (Vulkan / D3D12 / Metal)

| 키 (모두 `rendering/rendering_device/`, PS) | 기본 | 설명 |
|---|---|---|
| `driver` (+`.windows` 등) | vulkan / metal | 드라이버 선택 |
| `fallback_to_vulkan`, `fallback_to_d3d12`, `fallback_to_opengl3` | true | 6장 6.2의 폴백 사슬. 배포 시 켜 두는 것이 안전 |
| `vsync/frame_queue_size` | 2 (2-3) | CPU가 앞서 준비할 프레임 수. 3이면 처리량↑ 지연↑ |
| `vsync/swapchain_image_count` | 3 (2-4) | 스왑체인 이미지. 2는 지연↓, 티어링/스톨 위험 |
| `staging_buffer/block_size_kb` | 256 | 업로드 스테이징 블록 |
| `staging_buffer/max_size_mb` | 128 | 스테이징 총량. 대량 텍스처 스트리밍이면 ↑ |
| `staging_buffer/texture_upload_region_size_px`, `texture_download_region_size_px` | 64 | 큰 텍스처를 나누는 단위 |
| `pipeline_cache/*` | | 위 참조 |

V-Sync 모드 자체는 `display/window/vsync/vsync_mode` (Disabled / Enabled / Adaptive / Mailbox). Mailbox는 Vulkan에서 지연 없는 vsync.

명령행: `--gpu-index N`(멀티 GPU), `--gpu-validation`(validation layer / D3D12 debug layer), `--gpu-abort`, `--generate-spirv-debug-info`, `--extra-gpu-memory-tracking`, `--accurate-breadcrumbs`(GPU 크래시 위치 추적), `--disable-vsync`.

### Vulkan 전용
| 키 | 기본 | 설명 |
|---|---|---|
| `rendering/rendering_device/vulkan/max_descriptors_per_pool` | 64 | 디스크립터 풀 크기. 유니폼 세트가 매우 많으면 ↑ (`rendering_device_driver_vulkan.cpp:1908`) |

빌드 옵션 `use_volk=yes`(기본): Vulkan 로더를 동적으로 로드해 Vulkan 없는 시스템에서도 실행 파일이 뜨고 폴백 가능.
검증 레이어는 Vulkan SDK 설치 후 `--gpu-validation`. 성능 분석은 RenderDoc, NVIDIA Nsight, AMD RGP.

### D3D12 전용
| 키 | 기본 | 설명 |
|---|---|---|
| `rendering/rendering_device/d3d12/max_resource_descriptors` | 65536 | CBV/SRV/UAV 힙 크기 |
| `.../d3d12/max_sampler_descriptors` | 1024 | 샘플러 힙 |
| `.../d3d12/agility_sdk_version` | 618 | Agility SDK 버전 (`misc/scripts/install_d3d12_sdk_windows.py`) |

D3D12 빌드는 `scons d3d12=yes` + Agility SDK, DXC(NIR→DXIL 변환은 Mesa 코드가 내장). 셰이더 변환 비용이 Vulkan보다 크므로 **셰이더 캐시/베이커의 효과가 D3D12에서 특히 큽니다**. PIX 지원은 `use_pix=yes`.

### Metal 전용
- 설정 키는 별도로 없고 `scaling_3d/mode.macos`/`.ios`에 MetalFX Spatial/Temporal이 추가됩니다. Apple Silicon에서는 FSR2 대신 MetalFX Temporal이 품질/비용 모두 유리합니다.
- Intel Mac은 Metal 드라이버 미지원 → MoltenVK(Vulkan) 자동 사용.
- 디버깅: Xcode GPU Frame Capture, Metal API Validation(Xcode 스킴).
- iOS 시뮬레이터는 Metal/Vulkan 모두 미지원 → opengl3.

## 7.4 GL Compatibility 전용

| 키 | 기본 | 설명 |
|---|---|---|
| `rendering/gl_compatibility/driver` (+플랫폼 접미사) | opengl3 | `opengl3`(네이티브 GL 3.3), `opengl3_es`(EGL/GLES 3.0, Linux), `opengl3_angle`(ANGLE: D3D11/Metal 위 GLES) |
| `.../fallback_to_angle`, `fallback_to_native`, `fallback_to_gles` | true | 폴백 사슬 |
| `.../force_angle_on_devices` | 내장 목록 | 구형 AMD/Intel GPU에서 ANGLE 강제 (`main.cpp:2401-2457`) |
| `.../nvidia_disable_threaded_optimization` | true | NVIDIA "Threaded Optimization"이 GL에서 스터터를 유발하므로 끔 |
| `.../item_buffer_size` | 16384 | 2D 배칭 아이템 버퍼 |
| `rendering/limits/opengl/max_renderable_elements` | 65536 | 프레임당 렌더 요소 |
| `.../max_renderable_lights` | 32 | 씬 전체 조명 |
| `.../max_lights_per_object` | 8 | 오브젝트당 조명 (유니폼 크기) |
| `.../max_decals` | 32 | |
| `rendering/driver/depth_prepass/enable` | true | 깊이 프리패스. 오버드로우 많으면 이득 |
| `.../depth_prepass/disable_for_vendors` | PowerVR,Mali,Adreno,Apple | 타일 기반 GPU는 HSR/TBDR로 이미 오버드로우를 처리하므로 프리패스가 손해 (`drivers/gles3/storage/config.cpp:206-218`) |

특성:
- 스레드: 리소스 생성이 GL 컨텍스트 스레드로 직렬화되므로 대량 로딩 시 `thread_model=Separate`의 이득이 작고, 로더 스레드가 대기합니다.
- 셰이더 캐시는 `glGetProgramBinary` 기반이라 드라이버가 바뀌면 무효화됩니다.
- Web: `platform/web` 빌드 옵션 `wasm_simd`, `initial_memory`, threads 여부(`web_nothreads` 템플릿)가 성능에 큰 영향. WebGL2에는 컴퓨트가 없으므로 파티클은 CPU(`GPUParticles`도 GL에서는 transform feedback 경로).
- 2D 게임이라면 GL이 RD보다 **가볍고 호환성이 넓어** 데스크톱에서도 선택할 가치가 있습니다.

## 7.5 스레딩·프레임 페이싱
| 키 | 설명 |
|---|---|
| `rendering/driver/threads/thread_model` | Safe(기본): 렌더링 메인 스레드, 다른 스레드에서 RS 호출 허용 / Separate: 렌더 스레드 분리 (실험적, 에디터 불가) |
| `application/run/max_fps` | 프레임 끝 sleep. 배터리·발열 |
| `application/run/low_processor_mode` (+`_sleep_usec`) | 변화 있을 때만 그림. 도구/UI 앱 |
| `physics/common/physics_ticks_per_second`, `physics_jitter_fix`, `physics/common/physics_interpolation` | 렌더와 물리 분리 시 부드러움 (1장 1.4) |
| `display/window/vsync/vsync_mode` | Disabled/Enabled/Adaptive/Mailbox |

## 7.6 플랫폼별 권장 프리셋 (출발점)

**데스크톱 고품질 (Forward+ / Vulkan·Metal)**
- `scaling_3d/mode = FSR 2.2` (또는 MetalFX Temporal), `scale = 0.77`, `use_taa` 끔(FSR2가 대체)
- `directional_shadow/size = 4096`, `soft_shadow_filter_quality = Soft Medium`
- `ssao/half_size = true`, SSIL은 필요할 때만
- `msaa_3d = 2x` + `screen_space_aa = SMAA` 는 TAA/FSR2 없이 쓸 때
- `shader_cache` + `pipeline_cache` on, 익스포트에 `shader_baker` 활성화

**데스크톱 저사양 / 통합 GPU (Forward+ 유지 시)**
- `scale = 0.5~0.67` + FSR 1.0, `directional_shadow/size = 2048`, `16_bits = true`
- SSAO/SSIL/SSR/볼류메트릭 안개 off, `use_occlusion_culling` on (드로우콜 병목 시)
- 또는 `rendering_method = gl_compatibility`로 전환

**모바일 (Mobile / Vulkan 또는 GLES3)**
- `.mobile` 오버라이드 기본값이 이미 보수적(그림자 2048, ggx 16, reflection 128, Lambert)
- `msaa_3d = 2x~4x` (타일 GPU에서 저렴), `screen_space_aa = Disabled`
- `depth_prepass`는 `disable_for_vendors`에 의해 자동 off
- 텍스처는 ASTC(`import_etc2_astc`), 미프맵 필수, `anisotropic_filtering_level = 2x`
- 셰이더 컴파일이 특히 느리므로 셰이더 베이커 필수, `shader_cache` on
- `application/run/max_fps = 60`, `vsync_mode = Enabled` (발열)

**웹 (GL Compatibility / WebGL2)**
- `optimize=size` 템플릿, threads 템플릿 여부는 호스팅의 COOP/COEP 헤더 가능 여부로 결정
- 텍스처는 WebP/PNG 대신 **압축 텍스처(S3TC+ETC2 둘 다)** — 브라우저/GPU에 따라 갈림
- `msaa_3d = 2x` 이하, 조명 수 ≤ `max_lights_per_object`
- 첫 로드 크기가 핵심: `disable_3d`(2D 게임), 오디오 압축, 폰트 서브셋

**VR (OpenXR, Mobile 렌더러 권장)**
- Mobile 렌더러 + 멀티뷰(스테레오 인스턴싱), `vrs/mode`(가변 셰이딩, 포비에이션), MSAA 4x, 포스트 프로세스 최소화

## 7.7 진단 명령 요약

```bash
godot --verbose --path proj                 # 드라이버/셰이더/폴백 로그
godot --gpu-profile --path proj             # 패스별 GPU 시간
godot --print-fps
godot --gpu-validation                      # API 검증 레이어 (느림)
godot --rendering-method mobile --path proj # 렌더러 교체 실험
godot --test-rd-support                     # RD 생성 가능 여부만 확인
GODOT_RG_REORDER=0 godot ...                # (디버그 빌드) 렌더 그래프 재정렬 끄고 비교
```

에디터 안: **Debugger → Visual Profiler**(CPU/GPU 패스), **Monitors**(드로우콜, 프리미티브, VRAM, 오브젝트 수), **뷰포트 디버그 드로우**(Overdraw, Wireframe, Shadow Atlas, Directional Shadow, SSAO, VoxelGI/SDFGI 시각화, Occluders, Motion Vectors, Internal Buffer).

🧪 **실습 7**: 같은 씬을 (a) 기본, (b) `scale=0.5`, (c) 그림자 1024, (d) SSAO off 로 각각 `--gpu-profile`로 재고, 어느 설정이 몇 ms를 줄이는지 표로 만드세요. 이 표가 곧 여러분 프로젝트의 "품질 프리셋" 설계 근거가 됩니다.
