# 0장. 소스를 따라가며 배우기 위한 준비

엔진 소스를 "읽기만" 하면 금방 길을 잃습니다. **빌드해서 디버거로 한 줄씩 밟아 보는 것**이 가장 빠른 학습법입니다.
이 장은 그 환경을 만드는 최소한의 절차입니다.

## 0.1 저장소 한눈에 보기

```
godot/
├── SConstruct          # 빌드 진입점 (SCons, Python)
├── methods.py          # 빌드 헬퍼 (컴파일러 플래그, 코드 생성)
├── version.py          # major=4, minor=8, status=dev
├── core/               # 엔진의 기반: Object, Variant, ClassDB, OS 추상화, I/O, 컨테이너
├── servers/            # 렌더링·물리·오디오·디스플레이·텍스트 등 "서버" (씬과 독립)
├── scene/              # 노드 트리, 노드 타입(2d/3d/gui/animation/audio), 리소스
├── editor/             # 에디터 (Godot 노드로 만든 Godot 앱)
├── main/               # main.cpp: 부팅 시퀀스와 메인 루프
├── platform/           # OS별 진입점·윈도우·익스포트 (windows, linuxbsd, macos, android, ios, web, visionos)
├── drivers/            # 백엔드 구현: vulkan, d3d12, metal, gles3, 오디오, 입력(sdl), unix/windows 공통
├── modules/            # 선택적 기능: gdscript, mono, jolt_physics, gltf, openxr, ... (config.py로 on/off)
├── thirdparty/         # 벤더 라이브러리 (glslang, jolt, freetype, mbedtls, ...)
├── doc/classes/        # 833개 클래스의 XML 레퍼런스 (에디터 내 도움말과 공식 API 문서의 원천)
├── tests/              # doctest 기반 단위 테스트
└── misc/               # 스크립트, 포매터 설정, 배포 자료
```

## 0.2 빌드

의존성은 공식 문서 "Compiling" 섹션을 따르되, 핵심은 Python 3 + SCons + 플랫폼 컴파일러입니다.

```bash
# 에디터 빌드 (기본 target=editor). 학습용으로는 dev_build=yes 로 assert/디버그 코드 활성화
scons platform=linuxbsd target=editor dev_build=yes debug_symbols=yes compiledb=yes -j$(nproc)

# 단위 테스트 포함
scons platform=linuxbsd target=editor tests=yes dev_build=yes

# 익스포트 템플릿 (게임 실행 전용 바이너리, 에디터 코드 제외)
scons platform=linuxbsd target=template_release production=yes
scons platform=linuxbsd target=template_debug
```

주요 옵션(`SConstruct:161-299`):

| 옵션 | 값 | 의미 |
|---|---|---|
| `platform` / `p` | windows, linuxbsd, macos, android, ios, web, visionos | 타깃 플랫폼 (`platform/*/detect.py`가 도구 체인 감지) |
| `target` | editor, template_debug, template_release | 에디터 포함 여부·디버그 코드 포함 여부 (`TOOLS_ENABLED`, `DEBUG_ENABLED`) |
| `dev_build` | yes/no | `DEV_ENABLED`: 개발자용 assert, 최적화 끔 |
| `optimize` | auto/none/debug/speed/speed_trace/size/size_extra | 최적화 수준 |
| `lto` | none/auto/thin/full | 링크 타임 최적화 |
| `production` | yes | 배포용 기본값 묶음 (LTO 등) |
| `precision` | single/double | `real_t`를 float/double로. 대규모 월드용 |
| `vulkan`, `d3d12`, `metal`, `opengl3`, `angle` | yes/no | 렌더링 드라이버 포함 여부 |
| `forward_plus_renderer`, `forward_mobile_renderer` | yes/no | RD 기반 렌더 메서드 포함 여부 |
| `disable_2d`, `disable_3d`, `disable_physics_*`, `disable_xr` … | yes | 기능을 통째로 빼서 바이너리 축소 |
| `build_profile` | 파일 경로 | 에디터의 "Engine Compilation Configuration"으로 만든 기능 프로파일 |
| `custom_modules` | 경로 | 저장소 밖의 모듈 디렉터리 추가 |
| `module_<name>_enabled` | yes/no | 개별 모듈 on/off (`modules/*/config.py`) |
| `compiledb` | yes | `compile_commands.json` 생성 → clangd/VS Code 코드 탐색 |
| `tests` | yes | doctest 단위 테스트 빌드 |
| `profiler` | none/tracy/perfetto/instruments | 엔진 내부 프로파일링 존(`GodotProfileZone`) 활성화 |
| `scu_build` | yes | 단일 컴파일 단위(SCU) 빌드로 풀 빌드 가속 (`scu_builders.py`) |

빌드 결과물은 `bin/` 아래에 `godot.<platform>.<target>[.dev].<arch>` 형태로 생성됩니다.

## 0.3 실행과 유용한 플래그

```bash
bin/godot.linuxbsd.editor.dev.x86_64 --help            # 전체 옵션
bin/godot.linuxbsd.editor.dev.x86_64 -e --path my_proj # 에디터로 프로젝트 열기
bin/godot.linuxbsd.editor.dev.x86_64 --path my_proj    # 게임 실행
bin/godot.linuxbsd.editor.dev.x86_64 --headless --path my_proj  # DisplayServer 없이 (서버/CI)

# 렌더러/드라이버 강제 지정 (6장)
--rendering-method forward_plus|mobile|gl_compatibility
--rendering-driver vulkan|d3d12|metal|opengl3|opengl3_es|opengl3_angle
--gpu-validation            # Vulkan validation layer 등
--test-rd-support           # RenderingDevice 생성 가능 여부만 확인하고 종료

# 진단
--verbose  --debug-canvas-item-redraw  --print-fps  --gpu-profile
--test                      # tests=yes 로 빌드한 경우 doctest 실행 (--test --help)
```

플래그 파싱 전체는 `main/main.cpp`의 `Main::setup()` (약 1100~2300줄)에 있습니다. 새 플래그가 궁금하면 `print_help_option(` 을 grep 하세요.

## 0.4 디버깅 환경

- **compile_commands.json**: `compiledb=yes`로 생성 → clangd 기반 에디터에서 정의로 점프.
- **디버거 브레이크포인트 추천 지점**
  - `main/main.cpp` `Main::setup()`, `Main::setup2()`, `Main::start()`, `Main::iteration()` — 부팅과 프레임 루프 (1장)
  - `scene/main/scene_tree.cpp` `SceneTree::process()`, `SceneTree::physics_process()` — 노드 콜백 분배 (3장)
  - `servers/rendering/rendering_server_default.cpp` `RenderingServerDefault::draw()` — 렌더 프레임 시작 (6장)
  - `modules/gdscript/gdscript_vm.cpp` `GDScriptFunction::call()` — 스크립트 실행 (4장)
- **`dev_build=yes`** 에서는 `DEV_ASSERT()`가 활성화되고, `ERR_FAIL_*` 매크로(`core/error/error_macros.h`)가 파일/줄을 출력합니다.
- **`--verbose`** 는 `print_verbose()` 출력을 켭니다. 드라이버 선택 과정을 볼 때 특히 유용합니다.

## 0.5 코드 스타일과 규칙 (읽을 때 알아두면 좋은 것)

- STL 컨테이너 대신 자체 컨테이너(`Vector`, `HashMap`, `List`, `String`)를 씁니다 (2장 2.5).
- 예외를 쓰지 않습니다(`disable_exceptions=yes` 기본). 오류는 `Error` enum + `ERR_FAIL_COND_V()` 매크로.
- 힙 할당은 `memnew()`/`memdelete()` (`core/os/memory.h`). `new`를 직접 쓰지 않습니다.
- 클래스 노출은 `GDCLASS(Foo, Parent)` 매크로 + `static void _bind_methods()` (2장 2.1).
- 파일 상단의 라이선스 헤더, `clang-format`(`.clang-format`), `pre-commit` 훅이 강제됩니다. `CONTRIBUTING.md` 참조.

🧪 **실습 0**: `dev_build=yes tests=yes`로 빌드하고 `--test`를 실행해 보세요. 그다음 `tests/core/variant/test_variant.cpp`에 간단한 `TEST_CASE`를 하나 추가해 통과시켜 보세요. `tests/` 아래의 `test_*.cpp`는 `tests/test_builders.py`가 자동으로 수집해 `force_link.gen.h`로 링크하므로 별도 등록이 필요 없습니다.
