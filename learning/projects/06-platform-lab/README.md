# 06 Platform Lab — 플랫폼과 빌드/익스포트

학습 가이드 [5장 멀티플랫폼 지원](../../05-multiplatform.md) 과 [7장 7.6 플랫폼별 권장 프리셋](../../07-graphics-tuning.md) 을 따라가는 실습 프로젝트입니다.
Godot 이 "하나의 코드베이스로 7개 플랫폼" 을 지원하는 비결 — `OS`/`DisplayServer` 추상 계약, 기능 태그, 입력 장치 추상화,
PCK 가상 파일 시스템, 템플릿 + PCK 익스포트 모델, 헤드리스 스크립트 — 를 실행 중인 엔진에게 직접 물어보며 확인합니다.

## 목적

- `OS`, `Engine`, `RenderingServer`, `DisplayServer` 싱글턴이 **지금 이 바이너리·이 기기** 에 대해 무엇을 답하는지 표로 본다.
- `project.godot` 의 `키.태그=값` (기능 태그 오버라이드) 이 어떻게 해석되는지, `override.cfg` 와 익스포트 프리셋의 *Custom Features* 가 어디에 끼어드는지 안다.
- 조이패드/키보드/마우스가 `Input` → `InputMap` 으로 어떻게 추상화되는지 보고 런타임 재매핑을 해 본다.
- `PCKPacker` 로 DLC 팩을 만들고 `load_resource_pack` 으로 `res://` 에 합친 뒤, PCK 헤더(`"GDPC"`) 를 직접 읽는다.
- 창 모드/VSync/콘텐츠 스케일/서브윈도우 를 `DisplayServer` 로 직접 조작하며 `Window → WindowID → RS.viewport_attach_to_screen` 흐름을 익힌다.
- `export_presets.cfg` 를 파싱해 6개 플랫폼 프리셋의 진짜 옵션 키를 보고, 명령행 익스포트와 헤드리스 CI 스크립트를 실행한다.

## 실행 방법

```bash
# 에디터에서 열기: 프로젝트 관리자 → Import → 이 폴더의 project.godot
# 명령행으로 실행 (창 필요)
godot --path learning/projects/06-platform-lab

# 헤드리스 셀프테스트 (창 없이 비-UI 로직 검사, "SELFTEST PASS" 로 끝나야 한다)
godot --headless --path learning/projects/06-platform-lab -s res://selftest.gd

# 전체 검증 (셀프테스트 + 허브 5프레임 + 모든 데모 인스턴스화)
learning/projects/tools/verify.sh learning/projects/06-platform-lab

# 도구 스크립트
godot --headless --path learning/projects/06-platform-lab -s res://tools/make_pack.gd       # → user://dlc.pck
godot --headless --path learning/projects/06-platform-lab -s res://tools/headless_task.gd -- --job=nightly   # → user://report.json
```

`godot` 은 이 저장소에서 빌드한 `bin/godot.linuxbsd.editor.x86_64` 같은 에디터 바이너리입니다.
`user://` 는 Linux 에서 `~/.local/share/godot/app_userdata/06 Platform Lab/` 입니다 (`OS.get_user_data_dir()`, 데모 1 에서 확인).

## 데모 목록

| 데모 | 보여주는 개념 | 핵심 API |
|---|---|---|
| 1. `demos/platform_info/` | OS/Engine/RS/DisplayServer 가 답하는 플랫폼 정보, 기능 태그 표, `DisplayServer.Feature` 전체 지원 여부, 화면/창 정보 | `OS.get_name/get_version/get_distribution_name/get_model_name/get_processor_*/get_*_dir/get_locale*/get_cmdline_*`, `OS.has_feature`, `Engine.get_version_info/get_architecture_name`, `RenderingServer.get_current_rendering_method/driver_name`, `DisplayServer.has_feature/screen_get_*/window_get_*` |
| 2. `demos/feature_overrides/` | `demo/greeting.mobile` 같은 오버라이드가 어떻게 선택되는지, `get_setting` vs `get_setting_with_override`, 가상 태그 시뮬레이션, `override.cfg`, 프리셋 Custom Features | `ProjectSettings.get_setting`, `get_setting_with_override`, `get_setting_with_override_and_custom_features`, `get_property_list` |
| 3. `demos/input_devices/` | 조이패드 목록/GUID/정보, 실시간 축·버튼, 진동, `InputMap` 액션 목록과 런타임 재매핑, 마우스 모드, 터치 에뮬레이션 | `Input.get_connected_joypads/get_joy_name/get_joy_guid/get_joy_info/get_joy_axis/is_joy_button_pressed/start_joy_vibration`, `joy_connection_changed`, `InputMap.get_actions/action_get_events/action_erase_events/action_add_event/load_from_project_settings`, `InputEvent.as_text`, `Input.mouse_mode` |
| 4. `demos/pck_and_resources/` | PCK 만들기 → 헤더 읽기 → 로드 전/후 비교 → 팩 안의 txt/tres 읽기 → 디렉터리 나열 | `PCKPacker.pck_start/add_file/flush`, `ProjectSettings.load_resource_pack`, `FileAccess.file_exists/get_file_as_string`, `ResourceLoader.exists`, `DirAccess.get_files_at` |
| 5. `demos/window_and_display/` | 창 모드 4종, VSync 4종, 콘텐츠 스케일 모드/종횡비/배율, 임베디드 vs 네이티브 서브윈도우, borderless/always_on_top, 화면 정보 | `DisplayServer.window_set_mode/window_set_vsync_mode/window_set_flag/screen_get_*`, `Window.content_scale_*`, `Viewport.gui_embed_subwindows`, `Window.popup_centered/get_window_id/is_embedded` |
| 6. `demos/export_presets_reader/` | `export_presets.cfg` 의 6개 프리셋(Linux, Windows Desktop, macOS, Android, iOS, Web) 표와 옵션 전체, 익스포트 CLI/템플릿 경로 | `ConfigFile.load/get_sections/get_section_keys/get_value` |
| `tools/make_pack.gd` | `extends SceneTree` 헤드리스 도구: `res://dlc_source/*` → `user://dlc.pck` | `PCKPacker` |
| `tools/headless_task.gd` | CI 용 헤드리스 작업: 플랫폼 정보를 `user://report.json` 으로 | `JSON.stringify`, `FileAccess`, `OS.get_cmdline_user_args` |

허브(`main.tscn`) 왼쪽 버튼으로 데모를 고르면 오른쪽에 인스턴스되고, 아래 패널이 `Log` autoload(`log.gd`) 가 받은 메시지를 비춥니다. 같은 내용이 stdout 에도 찍히므로 헤드리스에서도 읽을 수 있습니다.

## project.godot 의 플랫폼별 설정 키

`[rendering]` 섹션에 넣은 키들은 모두 **기능 태그 오버라이드** 입니다. 엔진은 `main/main.cpp` 에서 이 키들을 `GLOBAL_DEF_RST(... "driver.windows" ...)` 로 등록하고, `ProjectSettings::get_setting_with_override()` 가 지금 참인 태그의 값을 고릅니다.

| 키 | 기본값 / 선택지 | 의미 | 엔진 |
|---|---|---|---|
| `renderer/rendering_method` | `gl_compatibility` (이 프로젝트) / `forward_plus`, `mobile` | 렌더러. `forward_plus`·`mobile` 은 RenderingDevice 위, `gl_compatibility` 는 GLES3 드라이버 위 | `main/main.cpp:2634` |
| `renderer/rendering_method.mobile` | `gl_compatibility` (이 프로젝트) / 엔진 기본 `mobile` | `mobile` 태그(Android/iOS)에서만 쓰는 렌더러 | `main/main.cpp:2635` |
| `renderer/rendering_method.web` | 항상 `gl_compatibility` | Web 은 WebGL2 만 가능 | `main/main.cpp:2636` |
| `rendering_device/driver.windows` | `vulkan` / `d3d12` | Windows 의 RD 드라이버 | `main/main.cpp:2364` |
| `rendering_device/driver.linuxbsd` | `vulkan` | Linux/BSD | `main/main.cpp:2365` |
| `rendering_device/driver.macos` | `metal` / `vulkan`(MoltenVK) | macOS. `driver.ios` 도 `metal,vulkan`, `driver.visionos` 는 `metal` 만 | `main/main.cpp:2367-2369` |
| `rendering_device/fallback_to_vulkan/d3d12/opengl3` | `true` | 드라이버 생성 실패 시 순서대로 대체 | `main/main.cpp:2371-2373` |
| `gl_compatibility/driver.windows` | `opengl3` / `opengl3_angle` | ANGLE(D3D11 위 GL) 로 대체 가능 | `main/main.cpp:2379` |
| `gl_compatibility/driver.linuxbsd` | `opengl3` / `opengl3_es` | EGL 기반 GLES 컨텍스트 | `main/main.cpp:2380` |
| `gl_compatibility/driver.macos` | `opengl3` / `opengl3_angle` | | `main/main.cpp:2384` |
| `gl_compatibility/fallback_to_angle/native/gles` | `true` | GL 컨텍스트 생성 실패 시 대체 | `main/main.cpp:2387-2389` |
| `display/display_server/driver.linuxbsd` (미포함) | `default,x11,wayland,headless` | DisplayServer 선택 (5장 5.4) | `main/main.cpp:2783` |

7장 7.6 의 권장 프리셋을 적용하려면 같은 방식으로 `rendering/scaling_3d/mode.mobile`, `rendering/textures/vram_compression/import_etc2_astc` 등을 `.mobile`/`.web` 태그와 함께 두면 됩니다. 데모 1 의 "설정 … (오버라이드 적용)" 행이 실제로 선택된 값을 보여줍니다.

## 기능 태그 (OS.has_feature)

`core/os/os.cpp OS::has_feature()` 의 순서: ① `get_identifier()` (플랫폼 이름) → ② `movie` → ③ `debug`/`editor`/`editor_hint`/`editor_runtime`/`embedded_in_editor` 또는 `template`/`template_debug`/`template_release`/`release` → ④ `double`/`single` → ⑤ `64`/`32`, 아키텍처(`x86_64`, `x86`, `arm64`, `arm`, `wasm32`, `rv64`, `ppc64`, `loongarch64` …) → ⑥ `threads`/`nothreads` → ⑦ 플랫폼별 `_check_internal_feature_support()` (`pc`, `mobile`, `linux`, `bsd`, `system_fonts`, `web_*` …) → ⑧ 서버 콜백(텍스처 압축 `s3tc`, `etc2`, `astc`, `bptc`, `rgtc` — `RenderingServer::has_os_feature`) → ⑨ **프리셋 Custom Features**.

`"headless"` 는 기능 태그가 **아닙니다**. 헤드리스 여부는 `DisplayServer.get_name() == "headless"` 로 판별합니다.

## PCK

- **포맷** (`core/io/file_access_pack.h`): 매직 `0x43504447` = ASCII `"GDPC"`, 포맷 버전 V4, 만든 엔진 버전, 팩 플래그(`PACK_DIR_ENCRYPTED`, `PACK_REL_FILEBASE`, `PACK_SPARSE_BUNDLE`), 파일 베이스 오프셋, 디렉터리(경로·오프셋·크기·MD5·파일 플래그 `ENCRYPTED`/`REMOVAL`/`DELTA`). 데모 4 의 "헤더 읽기" 가 앞부분을 `FileAccess.get_32/get_64` 로 직접 읽습니다.
- **찾는 순서** (`core/config/project_settings.cpp _setup()`, 5장 5.7): `--main-pack` → 실행 파일에 내장된 PCK(`OS::get_embedded_pck_offset`, `pck` 섹션) → (macOS) 번들 리소스 → `<실행파일 폴더>/<이름>.pck` → 현재 폴더의 `<이름>.pck` → (Android) `assets.sparsepck` → `OS::get_resource_dir()` → `--path`/`project.godot` 상위 탐색. 각 단계 뒤에 `override.cfg` 를 시도합니다.
- **embed_pck**: 익스포트 프리셋 `binary_format/embed_pck=true` 면 `fixup_embedded_pck()` 가 템플릿 바이너리의 `pck` 섹션에 PCK 를 써넣습니다 (`platform/linuxbsd/godot_linuxbsd.cpp:60-68` 의 `__attribute__((section("pck")))`). 이 프로젝트의 Windows 프리셋이 `true`, Linux 는 `false` 입니다.
- **런타임 로드**: `ProjectSettings.load_resource_pack(path, replace_files=true)` → `PackedData::add_pack` → `PackedSourcePCK::try_open_pack`. 에디터/`--path` 실행에서도 `res://` 의 DirAccess 가 `DirAccessPack` 으로 바뀌므로 (`project_settings.cpp:599-606`) `DirAccess.get_files_at("res://dlc")` 가 팩 안의 파일을 보여줍니다. `.txt` 는 Resource 가 아니므로 `ResourceLoader.exists` 대신 `FileAccess.file_exists` 로 확인합니다.

## 익스포트

**익스포트는 컴파일이 아닙니다** (5장 5.7). `EditorExportPlatformXxx::export_project()` 는 ① 미리 빌드된 템플릿 바이너리를 찾아(`find_export_template`) 복사하고, ② 프로젝트 리소스를 PCK 로 패킹(`save_pack`, 필요하면 암호화·셰이더 베이킹)하고, ③ PCK 를 옆에 두거나 내장합니다. 그래서 C++ 모듈, `disable_3d`, `precision=double` 처럼 바이너리가 달라져야 하는 변경은 `scons` 로 직접 템플릿을 만들어 `custom_template/debug|release` 에 지정해야 합니다.

```bash
godot --headless --export-release "Linux" build/linux/platform_lab.x86_64   # 프리셋 이름 = export_presets.cfg 의 name
godot --headless --export-debug   "Web"   build/web/index.html
godot --headless --export-pack    "Linux" build/only_data.pck               # 바이너리 없이 PCK/ZIP 만
godot --headless --export-patch   "Linux" build/patch1.pck --patches base.pck
```

- 템플릿 설치 위치: `EditorPaths.get_data_dir()/export_templates/<major.minor.status>/` (`editor/file_system/editor_paths.cpp get_export_templates_dir()`), Linux 에서는 `~/.local/share/godot/export_templates/4.8.dev/`. 템플릿 파일 이름은 `linux_release.x86_64`, `windows_release_x86_64.exe`, `android_release.apk`, `macos.zip`, `ios.zip`, `web_release.zip` 식입니다.
- `export_presets.cfg` 구조 (`editor/export/editor_export.cpp save_presets`): `[runnable_presets]` (플랫폼별 기본 프리셋), `[preset.N]` 공통 필드(`name`, `platform`, `custom_features`, `export_filter`, `include_filter`/`exclude_filter`, `export_path`, `patches`, 암호화 필드, `script_export_mode`), `[preset.N.options]` 플랫폼 옵션.
- **플랫폼 이름** 은 각 익스포트 플러그인의 `get_name()` 값 그대로: `Linux`, `Windows Desktop`, `macOS`, `Android`, `iOS`, `Web` (`platform/linuxbsd/export/export.cpp:45`, `platform/windows/export/export.cpp:55`, `platform/macos/export/export_plugin.h:135`, `platform/android/export/export_plugin.cpp:2290`, `platform/ios/export/export_plugin.h:57`, `platform/web/export/export_plugin.cpp:413`).
- **옵션 키** 는 `get_export_options()` 의 `PropertyInfo` 이름 그대로 복사했습니다: 공통 `custom_template/*`, `debug/export_console_wrapper`, `binary_format/embed_pck`, `texture_format/s3tc_bptc|etc2_astc`, `shader_baker/enabled` (`editor/export/editor_export_platform_pc.cpp`), Linux `binary_format/architecture`, `ssh_remote_deploy/*` (`platform/linuxbsd/export/export_plugin.cpp`), Windows `codesign/*`, `application/*` (`platform/windows/export/export_plugin.cpp`), macOS `export/distribution_type`, `codesign/entitlements/*`, `notarization/*`, `privacy/*` (`platform/macos/export/export_plugin.cpp`), Android `gradle_build/*`, `architectures/<abi>`, `package/*`, `screen/*` (`platform/android/export/export_plugin.cpp`), iOS `application/*`, `storyboard/*`, `capabilities/*`, `icons/*` (`platform/ios/export/export_plugin.cpp`, `editor/export/editor_export_platform_apple_embedded.cpp`), Web `variant/*`, `vram_texture_compression/*`, `html/*`, `progressive_web_app/*`, `threads/*` (`platform/web/export/export_plugin.cpp`).
- Android 와 iOS 는 프리셋에 텍스처 포맷 옵션이 없고 프로젝트 설정 `rendering/textures/vram_compression/import_etc2_astc` 를 따릅니다 (7장 7.6 모바일: ASTC).
- `custom_features="lowend"` (Android/Web 프리셋) 는 데모 2 의 `demo/quality.lowend="low"` 를 살리는 임의 태그입니다.

## 헤드리스 CI 예시

```yaml
# .github/workflows/platform-lab.yml (발췌)
- name: Selftest
  run: godot --headless --path learning/projects/06-platform-lab -s res://selftest.gd
- name: Platform report
  run: |
    godot --headless --path learning/projects/06-platform-lab -s res://tools/headless_task.gd -- --job=${{ github.run_id }}
    cat "$HOME/.local/share/godot/app_userdata/06 Platform Lab/report.json"
- name: Build DLC pack
  run: godot --headless --path learning/projects/06-platform-lab -s res://tools/make_pack.gd -- user://dlc.pck
- name: Export
  run: godot --headless --export-release "Linux" build/linux/platform_lab.x86_64
```

`-s` 스크립트가 `SceneTree` 를 상속하면 `main/main.cpp Main::start()` 가 메인 씬 대신 그 MainLoop 를 띄우고, `--headless` 는 DisplayServer 를 `headless` 로, 렌더링을 dummy 래스터라이저로 고정합니다. `--` 뒤의 인자는 엔진이 건드리지 않고 `OS.get_cmdline_user_args()` 로 전달됩니다.

## 함께 읽을 엔진 소스

| 주제 | 파일 | 학습 가이드 |
|---|---|---|
| OS 추상 계약과 기능 태그 | `core/os/os.h`, `core/os/os.cpp` (`has_feature`), `platform/linuxbsd/os_linuxbsd.cpp` (`_check_internal_feature_support`), `platform/web/os_web.cpp`, `platform/android/os_android.cpp` | 5장 5.1-5.2 |
| DisplayServer 등록/선택, 헤드리스 | `servers/display/display_server.h`, `servers/display/display_server.cpp:67` (`server_create_functions`), `servers/display/display_server_headless.h`, `main/main.cpp` (`--headless`, `display/display_server/driver.*`) | 5장 5.4 |
| 렌더링 드라이버 선택 | `main/main.cpp:2363-2389, 2634-2636` (`rendering_device/driver.*`, `gl_compatibility/driver.*`, `rendering_method.*`) | 5장 5.2, 6장, 7장 7.6 |
| 프로젝트 설정 오버라이드 | `core/config/project_settings.cpp` (`_set` 의 feature_overrides, `get_setting_with_override`, `_setup` 의 `override.cfg`, `has_custom_feature`) | 5장 5.7 |
| 입력 | `core/input/input.h`, `core/input/input_map.cpp`, `drivers/sdl/joypad_sdl.cpp`, `core/input/gamecontrollerdb.txt` | 5장 5.5 |
| PCK | `core/io/file_access_pack.h` (매직/플래그), `core/io/file_access_pack.cpp` (`try_open_pack`), `core/io/pck_packer.cpp`, `core/config/project_settings.cpp` (`_load_resource_pack`, `_setup`) | 5장 5.7 |
| 창 ↔ DisplayServer ↔ RenderingServer | `scene/main/window.cpp` (`_make_window`:748-778, `_update_window_size`:1303-1484, `get_window_id`), `scene/main/viewport.cpp` (`set_embedding_subwindows`:4310) | 3장, 5장 5.4 |
| 익스포트 | `editor/export/editor_export.cpp` (프리셋 저장/로드), `editor/export/editor_export_platform.cpp` (`save_pack`, custom features), `editor/export/editor_export_platform_pc.cpp`, `platform/*/export/export_plugin.cpp`, `editor/file_system/editor_paths.cpp` (`get_export_templates_dir`), `platform/linuxbsd/godot_linuxbsd.cpp:60-68` (`pck` 섹션) | 5장 5.7 |
| 헤드리스 스크립트 | `main/main.cpp` (`-s`, `--export-*`, `--` 사용자 인자), `core/os/main_loop.h` (`_initialize`, `_process`) | 1장 1.4, 5장 5.6 |

## 연습 과제

1. **모바일 렌더러 오버라이드**: `project.godot` 에 `rendering/scaling_3d/scale.mobile=0.75`, `rendering/textures/vram_compression/import_etc2_astc=true` 를 추가하고, 데모 2 의 시뮬레이션 버튼과 같은 방식(`get_setting_with_override_and_custom_features`)으로 `["mobile"]` 일 때의 값을 셀프테스트에 추가하세요. 7장 7.6 의 "모바일" 항목을 근거로 값을 고르세요.
2. **패치 PCK**: `tools/make_pack.gd` 를 확장해 `PCKPacker.add_file_removal("res://dlc/greeting.txt")` 로 파일 삭제 항목을 담은 `user://patch.pck` 를 만들고, 데모 4 에서 두 팩을 순서대로 로드한 뒤 `FileAccess.file_exists` 결과가 어떻게 바뀌는지 확인하세요 (`core/io/file_access_pack.h` 의 `PACK_FILE_REMOVAL`).
3. **재매핑 영구 저장**: 데모 3 의 런타임 재매핑을 `ProjectSettings.set_setting("input/jump", {...})` + `ProjectSettings.save_custom("user://override.cfg")` 로 저장하고, 다음 실행에서 `override.cfg` 가 어떻게 읽히는지 (`project_settings.cpp _setup`) 추적하세요.
4. **커스텀 템플릿**: 5장 실습 5 처럼 `scons platform=linuxbsd target=template_release disable_3d=yes optimize=size` 로 최소 템플릿을 만들고, `export_presets.cfg` 의 Linux 프리셋 `custom_template/release` 에 지정해 `--export-release` 하세요. `strings 결과물 | grep GDPC` 로 내장 PCK 를 찾고, 데모 1 의 기능 태그 표에서 `template`/`release` 가 참이 되는지 보세요.
5. **DisplayServer 비교**: 같은 데모 5 를 `--display-driver x11` 과 `--display-driver wayland` (또는 `--headless`) 로 실행해 `has_feature` 표와 `screen_get_scale`, `window_set_vsync_mode` 결과 차이를 표로 정리하세요.

## 흔한 함정

- `get_setting()` 은 오버라이드를 **무시** 합니다. 플랫폼별 값을 읽으려면 `get_setting_with_override()` 를 써야 합니다. 에디터 빌드는 `editor` 태그가 참이므로 `키.editor` 가 있으면 그 값이 나옵니다 (데모 2 에서 `greeting.editor` 가 이깁니다).
- 오버라이드는 **선언 순서** 로 첫 번째 참인 태그를 고릅니다. `키.mobile` 과 `키.android` 를 둘 다 두면 위에 쓴 것이 이깁니다.
- `override.cfg` 도 기능 태그를 탑니다. 모든 플랫폼에서 바꾸려면 `.태그` 키도 함께 덮어써야 합니다.
- 프리셋 Custom Features 는 **익스포트 결과물** 에서만 참입니다. 에디터/`--path` 실행에서 `OS.has_feature("lowend")` 는 항상 false 입니다.
- `"headless"` 는 OS 기능 태그가 아닙니다. `DisplayServer.get_name()` 을 보세요. 헤드리스에서 `get_screen_count()` 는 0, `window_get_mode()` 는 `MINIMIZED`, 모든 `has_feature` 는 false 입니다.
- `ResourceLoader.exists()` 는 `.txt` 같은 비-리소스에 false 를 돌려줍니다. `FileAccess.file_exists()` 를 쓰세요.
- `load_resource_pack(replace_files=true)` 는 같은 경로의 기존 파일을 팩 쪽으로 **덮어씁니다**. DLC 가 본편 파일을 가리지 않게 하려면 `false` 를 주거나 경로를 분리하세요. 팩 안의 스크립트는 넣지 마세요 (보안·캐시 문제).
- `PCKPacker.add_file(target, source)` 의 `target` 은 팩 안 경로(`res://` 접두사는 떼어짐), `source` 는 실제 파일입니다. 순서를 바꾸면 조용히 실패합니다.
- `gui_embed_subwindows` 는 자식 창이 떠 있는 동안 못 바꿉니다 (경고만 찍고 무시). 먼저 창을 닫으세요.
- `DisplayServer.window_set_vsync_mode` 는 Compatibility 렌더러에서 `ENABLED` 외 값이 `ENABLED` 처럼 동작하고, 지원하지 않는 DisplayServer 는 경고만 찍습니다.
- `--export-*` 는 **에디터 바이너리** 에서만 동작하며 프리셋 이름은 `export_presets.cfg` 의 `name` 과 정확히 같아야 합니다. 템플릿이 없으면 "No export template found" 로 실패합니다.
- `push_error()` 는 stdout 에 `ERROR:` 를 찍어 헤드리스 검증을 실패시킵니다. 헤드리스에서 예상되는 제약(조이패드 없음, 화면 없음 등)은 `Log.warn` 으로 알리세요.
