# 5장. 멀티플랫폼 지원: `platform/` · `drivers/` · 빌드 · 익스포트

Godot은 **하나의 코드베이스, 하나의 빌드 명령**으로 7개 플랫폼을 지원합니다. 비결은 (1) `OS`/`DisplayServer`라는 두 추상 계약, (2) `drivers/`의 공유 구현, (3) SCons + `detect.py`의 플랫폼 감지, (4) "템플릿 바이너리 + PCK" 익스포트 모델입니다.

## 5.1 플랫폼 하나의 골격

모든 `platform/<name>/`은 같은 구조입니다.

```
platform/linuxbsd/
├── detect.py             # can_build(), get_opts(), get_flags(), configure(env): 툴체인·라이브러리·define
├── SCsub                 # 최종 실행 파일 링크: env.add_program("#bin/godot", ...)
├── platform_config.h     # 플랫폼별 컴파일 설정
├── godot_linuxbsd.cpp    # int main() 진입점
├── os_linuxbsd.{h,cpp}   # class OS_LinuxBSD : OS_Unix
├── x11/ wayland/         # DisplayServerX11, DisplayServerWayland
├── export/               # EditorExportPlatformLinuxBSD (에디터의 익스포트 플러그인)
├── doc_classes/          # 익스포트 클래스 XML 문서
└── *-so_wrap.c           # dbus/fontconfig/speechd/xkbcommon 을 dlopen 으로 (빌드 의존성 최소화)
```

## 5.2 플랫폼별 요약

| 플랫폼 | OS 클래스 | 진입점 | DisplayServer | 렌더링 드라이버 |
|---|---|---|---|---|
| windows | `OS_Windows : OS` (Unix 아님) | `godot_windows.cpp` `main`/`WinMain` | `DisplayServerWindows` (Win32, `WndProc` 5728) | vulkan, d3d12, opengl3(WGL), opengl3_angle, dummy |
| linuxbsd | `OS_LinuxBSD : OS_Unix` | `godot_linuxbsd.cpp:70` | `DisplayServerX11`, `DisplayServerWayland` | vulkan, opengl3, opengl3_es(EGL), dummy |
| macos | `OS_MacOS : OS_Unix` (`.mm`) | `godot_main_macos.mm` → `[NSApp run]` | `DisplayServerMacOS`, `DisplayServerMacOSEmbedded` | vulkan(MoltenVK), metal, opengl3, opengl3_angle, dummy |
| android | `OS_Android : OS_Unix` | 없음. Java → JNI `java_godot_lib_jni.cpp` (`GodotLib_setup` → `Main::setup`, `GodotLib_step` → `Main::iteration`) | `DisplayServerAndroid` | opengl3(GLES3), vulkan |
| ios | `OS_IOS : OS_AppleEmbedded` | Swift `app_ios.swift` → `main_ios.mm` | `DisplayServerIOS : DisplayServerAppleEmbedded` | metal, vulkan(MoltenVK), opengl3 |
| visionos | `OS_VisionOS : OS_AppleEmbedded` | `app_visionos.swift` | `DisplayServerVisionOS` | metal만 (`detect.py`가 vulkan/opengl3 강제 off) |
| web | `OS_Web : OS_Unix` (Emscripten) | `web_main.cpp` `godot_web_main` + `emscripten_set_main_loop` | `DisplayServerWeb` | opengl3(WebGL2)만. RD 빌드 자체가 꺼짐 |
| (공통) | | | `DisplayServerHeadless` (`servers/display/`) | dummy |

플랫폼별 기본 드라이버는 `main/main.cpp:2363-2384`의 `.windows`/`.macos` 등 기능 태그 오버라이드로 정해집니다: Windows `vulkan,d3d12`(기본 vulkan), macOS/iOS `metal,vulkan`(기본 metal), Linux/Android `vulkan`, Web `opengl3`.

### 이벤트 루프의 주체가 다르다
- **데스크톱**: Godot이 루프를 소유. `OS_LinuxBSD::run()`이 `while(true){ DisplayServer::process_events(); if (Main::iteration()) break; }`.
- **Android/iOS/Web**: OS가 콜백을 준다. Android는 Java의 렌더 스레드가 `GodotLib.step()`을 부르고, Web은 `emscripten_set_main_loop`의 콜백이 `Main::iteration()`을 부릅니다. 그래서 `Main::iteration()`이 "한 프레임"을 재진입 가능하게 캡슐화되어 있습니다 (1장 1.4).

### 언어 경계
- **Android**: `platform/android/java/` (Gradle, ~156 .java + 63 .kt). `GodotLib.java`가 JNI 선언, `Godot.kt`/`GodotActivity.kt`가 라이프사이클. C++ 쪽 `java_godot_wrapper.cpp`, `jni_utils.cpp`. 파일 접근도 `file_access_android.cpp`(APK asset), `dir_access_jandroid.cpp`(SAF)로 JNI 경유.
- **iOS/visionOS/macOS**: Objective-C++ `.mm` + Swift(`app_*.swift`). 공통부는 `drivers/apple_embedded/`.
- **Web**: `platform/web/js/libs/library_godot_*.js`(오디오, 디스플레이, fetch, 입력, WebGL2, WebMIDI …)가 `godot_js.h`의 `extern godot_js_*` 함수를 JS로 구현. `platform/web/js/engine/`이 로더 API(`Engine` 클래스).

## 5.3 `drivers/`: 플랫폼 간 공유 구현

`drivers/SCsub`가 플랫폼과 옵션에 따라 포함할 하위 디렉터리를 고릅니다.

| 디렉터리 | 내용 | 사용 플랫폼 |
|---|---|---|
| `unix/` | `OS_Unix`, `FileAccessUnix`, `DirAccessUnix`, `NetSocketUnix`, `IPUnix`, `thread_posix` | linuxbsd, macos, android, ios, visionos, web |
| `windows/` | `FileAccessWindows`, `DirAccessWindows`, `NetSocketWinSock`, `thread_windows` | windows |
| `apple/` | Foundation 헬퍼, os_log 로거, `thread_apple` | macos, ios, visionos |
| `apple_embedded/` | `OS_AppleEmbedded`, `DisplayServerAppleEmbedded`, 앱 델리게이트, 뷰 컨트롤러, TTS | ios, visionos |
| `vulkan/`, `d3d12/`, `metal/` | RenderingDeviceDriver 구현 | 6장 |
| `gles3/`, `egl/`, `gl_context/` | GL Compatibility 렌더러, EGL 컨텍스트, GLAD 로더 | 6장 |
| `alsa/`, `pulseaudio/`, `wasapi/`, `xaudio2/`, `coreaudio/` | 오디오 출력 드라이버 | 각 OS |
| `alsamidi/`, `winmidi/`, `coremidi/` | MIDI 입력 | |
| `sdl/` | SDL3 조이패드 (`JoypadSDL`) | linuxbsd, macos, windows, ios, visionos |
| `accesskit/` | 스크린리더 접근성 서버 | 데스크톱 |
| `png/` | libpng 로더/세이버 | 전부 |
| `backtrace/` | libbacktrace (MinGW 크래시 스택) | |

플랫폼 계약이 실제로 꽂히는 지점 — `OS_Unix::initialize_core()` (`drivers/unix/os_unix.cpp:~154`):
```cpp
FileAccess::make_default<FileAccessUnix>(FileAccess::ACCESS_RESOURCES);
FileAccess::make_default<FileAccessUnix>(FileAccess::ACCESS_USERDATA);
FileAccess::make_default<FileAccessUnix>(FileAccess::ACCESS_FILESYSTEM);
DirAccess::make_default<DirAccessUnix>(DirAccess::ACCESS_RESOURCES);
NetSocketUnix::make_default();  IPUnix::make_default();
```
Windows는 `os_windows.cpp:283-322`에서 같은 일을 `FileAccessWindows` 등으로 합니다. **새 플랫폼 포팅 = `OS` 서브클래스 + `DisplayServer` 서브클래스 + 이 `make_default` 호출들**이 전부입니다 (콘솔 포팅 회사들이 하는 일).

## 5.4 DisplayServer 등록과 선택

- 저장소: `servers/display/display_server.cpp:67` `server_create_functions[]`는 `"headless"`만 갖고 시작. `register_create_function()`(`:2045`)이 마지막 앞에 삽입해 headless는 항상 폴백.
- 플랫폼 OS 생성자가 등록: `OS_LinuxBSD::OS_LinuxBSD()` (`os_linuxbsd.cpp:1347-1364`)에서 `DisplayServerX11::register_x11_driver()`, `DisplayServerWayland::register_wayland_driver()`. 순서: x11, wayland, headless.
- 선택: `display/display_server/driver.linuxbsd` (`default,x11,wayland,headless`), `--display-driver`, `--headless`. Wayland는 `WAYLAND_DISPLAY` 환경 변수가 있고 `prefer_wayland`일 때 (`main.cpp:3137-3157`).
- 실패 시 `main.cpp:3375-3395`가 다른 서버를 순서대로 시도(headless 제외).
- 테스트 빌드는 `DisplayServerMock` (`tests/display_server_mock.h`).

## 5.5 입력

- `core/input/input.h` `Input` 싱글턴: 액션(`is_action_pressed`), 조이패드(`joy_connection_changed`, `get_joy_axis`), 센서, 마우스 모드. `InputMap`은 `project.godot`의 `input/*` 액션을 로드.
- DisplayServer가 `Input::set_event_dispatch_function()`으로 이벤트를 넣고, `Input::parse_input_event()` → `SceneTree` → `Viewport::push_input`.
- 조이패드: 데스크톱/Apple은 SDL3(`drivers/sdl/joypad_sdl.cpp`, `SDL_Init(SDL_INIT_JOYSTICK|SDL_INIT_GAMEPAD)`), Android는 `android_input_handler.cpp`(Java `input/` 패키지), Web은 Gamepad API(`library_godot_input.js`). 컨트롤러 매핑 DB는 `core/input/gamecontrollerdb.txt`가 빌드 시 `default_controller_mappings.gen.cpp`로 변환.
- 키 매핑: `key_mapping_windows`, `x11/key_mapping_x11`, `wayland/key_mapping_xkb`, `key_mapping_macos.mm`, `android_keys_utils`, web `dom_keys.inc`.

## 5.6 빌드 시스템 (SCons)

### 흐름 (`SConstruct`)
1. `platform/*`를 글롭해 `detect.py`가 있는 디렉터리를 플랫폼으로 인식 (`:77-109`). `can_build()`가 true인 것만 옵션 노출.
2. 공통 옵션 등록 (`:161-381`, 0장 표).
3. `platform=` 미지정 시 호스트에서 추론 (`:395-458`).
4. `target` → define (`:548-576`): `editor` → `TOOLS_ENABLED`+`DEBUG_ENABLED`, `template_debug` → `DEBUG_ENABLED`, `template_release` → 둘 다 없음, `dev_build` → `DEV_ENABLED`.
5. SCU 파일 생성(`scu_build=yes`), `RD_ENABLED` 결정(web은 off), `detect.configure(env)`.
6. 바이너리 접미사 결정: `.<platform>.<target>[.dev][.double].<arch>[.nothreads]`.
7. 모듈 게이팅: 각 `config.can_build()` → `configure()` → `env.module_list` (`:1127-1160`).
8. 셰이더 빌더 등록 (`RD_GLSL`, `GLSL_HEADER`, `GLES3_GLSL` → `.glsl.gen.h`).
9. SConscript 순서: core → servers → scene → editor → drivers → platform → modules → tests → main → `platform/<p>/SCsub`(링크).

### `detect.py`가 하는 일
`get_name / can_build / get_opts / get_flags / configure(env)`. `get_flags()`는 플랫폼 기본값을 바꿉니다:
- windows: `d3d12=True`, `supported=[d3d12, dcomp, library, mono, xaudio2]`
- macos: `metal=True`, `use_volk=False`
- android: `arch=arm64`, `target=template_debug`
- web: `target=template_debug`, `rendering_device=False`, `optimize=size`

`configure()`는 툴체인(MSVC/MinGW/clang/emcc/NDK), 아키텍처 검증(`platform_methods.py:20 architectures`), define(`WINDOWS_ENABLED`, `X11_ENABLED`, `VULKAN_ENABLED`…), 링크 라이브러리를 설정합니다.

### 코드 생성기
| 스크립트 | 생성물 |
|---|---|
| `core/core_builders.py` | `disabled_classes.gen.h`, `version_hash.gen.cpp`, 라이선스/저자 헤더, 암호화 키 헤더 |
| `core/input/input_builders.py` | 컨트롤러 매핑 |
| `core/object/make_virtuals.py` | `gdvirtual.gen.h` (GDVIRTUAL 매크로) |
| `core/extension/make_interface_header.py` | `gdextension_interface.gen.h` |
| `glsl_builders.py`, `gles3_builders.py` | 셰이더 → C++ 클래스 헤더 (6장) |
| `modules/modules_builders.py` | 모듈 등록 코드 |
| `editor/editor_builders.py` | `register_exporters.gen.cpp`, `doc_data_compressed.gen.h`(833개 XML 압축 내장 → 에디터 F1 도움말), 번역 |
| `scu_builders.py` | `.scu/scu_*.gen.cpp` (여러 .cpp를 한 번에 컴파일) |

### 문서 파이프라인
`doc/classes/*.xml` + `modules/*/doc_classes` + `platform/*/doc_classes` → (에디터) 압축 내장, (웹) `doc/tools/make_rst.py` → docs.godotengine.org. XML 갱신은 `godot --doctool .` (저장소 루트에서). CI가 "class reference가 최신인지"를 검사하므로 API를 추가하면 XML도 함께 커밋해야 합니다 (`CONTRIBUTING.md` "Document your changes").

### 테스트와 CI
- `tests=yes` → doctest. `godot --test`, `--test --test-case="*[AABB]*"`. 테스트 태그(`[SceneTree]`, `[Editor]`)에 따라 `GodotTestCaseListener`가 환경을 준비.
- `.github/workflows/`: `runner.yml`이 `static_checks.yml`(포매터, 문서 검증) 후 플랫폼별 빌드 매트릭스를 실행. Linux 잡에 단위 테스트, GDExtension 호환성 검사, godot-cpp 빌드, 프로젝트 익스포트 테스트가 포함됩니다.

## 5.7 익스포트: 템플릿 바이너리 + PCK

Godot의 익스포트는 컴파일이 아닙니다.

```
에디터 (EditorExportPlatformXxx::export_project)
  1. 익스포트 템플릿 바이너리 복사     ← 미리 빌드된 template_debug/release (find_export_template)
  2. 프로젝트 리소스를 PCK로 패킹     ← save_pack() → "GDPC" 매직, 파일 테이블 (+암호화 옵션)
  3. PCK를 옆에 두거나(.pck) 실행 파일에 내장(embed_pck)
```

- 기본 클래스 `editor/export/editor_export_platform.h`: 순수 가상 `get_export_options`, `export_project`, `get_binary_extensions`, `get_platform_features`… 중간 클래스 `EditorExportPlatformPC`(Windows/Linux), `EditorExportPlatformAppleEmbedded`(iOS/visionOS).
- 템플릿 이름: `linux_<target>.<arch>`, `windows_<target>_<arch>.exe`, `android_debug.apk`(또는 Gradle 소스 빌드), `macos.zip`, `ios.zip`, `web[_dlink][_nothreads]_<target>.zip`.
- **내장 PCK의 비밀**: 템플릿 빌드는 바이너리에 `"pck"` 섹션을 예약합니다.
  ```cpp
  // platform/linuxbsd/godot_linuxbsd.cpp:60-68
  #if !defined(TOOLS_ENABLED) && defined(__GNUC__)
  static const char dummy[8] __attribute__((section("pck"), used)) = { 0 };
  ```
  익스포트 시 `fixup_embedded_pck()`가 이 섹션을 실제 PCK로 패치하고, 실행 시 `OS::get_embedded_pck_offset()`으로 찾습니다.
- PCK 포맷 (`core/io/file_access_pack.h`): 매직 `0x43504447`("GDPC"), 버전 V4, 플래그(`PACK_DIR_ENCRYPTED`, `PACK_REL_FILEBASE`, `PACK_SPARSE_BUNDLE`), 파일 플래그(`ENCRYPTED`, `REMOVAL`, `DELTA` — 패치 PCK 지원). `PackedData`가 가상 파일 시스템, `PackedSourcePCK::try_open_pack`이 (a) 오프셋 0 매직, (b) `pck` 섹션, (c) 파일 끝 매직(append 방식) 순으로 검사.
- 실행 파일이 PCK를 찾는 순서 (`core/config/project_settings.cpp:693 _setup`): `--main-pack` → 실행 파일 내장 → (macOS) 번들 리소스 → `<exec_dir>/<basename>.pck` → cwd → (Android) `assets.sparsepck` → `OS::get_resource_dir()` → `--path`/`project.godot` 상위 탐색.
- 스크립트로 PCK 만들기: `PCKPacker` (`core/io/pck_packer.h`) — DLC/패치 배포에 사용.
- 셰이더 베이커: 익스포트 프리셋 `shader_baker/enabled`로 타깃 API용 셰이더를 미리 컴파일해 넣습니다 (`editor/export/shader_baker/`, 6장 6.5).

### 커스텀 템플릿이 필요한 경우
- `disable_3d=yes` 등으로 바이너리를 줄이고 싶을 때 (`build_profile`로 에디터에서 프로파일 생성 가능)
- C++ 모듈을 넣었을 때
- `precision=double`
익스포트 프리셋의 `custom_template/debug|release`에 직접 빌드한 템플릿을 지정합니다.

🧪 **실습 5**: `scons platform=linuxbsd target=template_release disable_3d=yes disable_advanced_gui=yes optimize=size lto=full`로 최소 템플릿을 만들고 크기를 기본 템플릿과 비교하세요. 그다음 간단한 2D 프로젝트를 이 템플릿으로 익스포트해 `strings binary | grep GDPC`로 내장 PCK를 확인해 보세요.
