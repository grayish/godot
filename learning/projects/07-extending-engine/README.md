# 07. 엔진 확장과 기여 — 에디터 플러그인, 커스텀 C++ 모듈, GDExtension

학습 가이드 `learning/09-learning-roadmap.md` Stage 7, `learning/04-modules-and-scripting.md` 4.1·4.6,
`learning/02-core-layer.md` 2.7 에 대응하는 실습 프로젝트입니다.

## 목적

"엔진을 확장한다"는 말이 실제로 어느 코드 경로를 뜻하는지 네 가지 층위에서 직접 만져 봅니다.

| 층위 | 이 프로젝트의 산출물 | 엔진에서 일어나는 일 |
|---|---|---|
| A. 에디터 플러그인 | `addons/learning_tools/` | 에디터(= `EditorNode` 를 얹은 Godot 앱)의 씬 트리에 컨트롤과 콜백을 추가 |
| B. 커스텀 C++ 모듈 | `custom_modules/summator/` | 엔진에 정적 링크되어 `ClassDB::register_class<T>()` 로 등록 |
| C. GDExtension | `gdextension/` (godot-cpp) | 공유 라이브러리가 `entry_symbol` 로 초기화되고 `ClassDB::register_extension_class()` 로 등록 |
| D. 기여 워크플로우 | 데모 3 체크리스트 | `CONTRIBUTING.md`, `.pre-commit-config.yaml`, `doc/classes`, `tests/` |

B 와 C 는 같은 기능(`add / reset / get_total` 을 가진 Summator)을 두 방식으로 만들어, 스크립트에서
`ClassDB.class_exists("Summator")` / `("SummatorExt")` 로 결과를 비교합니다 (4장 실습 4).

## 실행 방법

이 프로젝트는 엔진 저장소 안(`learning/projects/07-extending-engine/`)에 있고, 저장소 루트 기준 명령을 씁니다.
`godot` 는 편의상 `bin/godot.linuxbsd.editor.x86_64` 를 뜻합니다.

- 에디터에서 열기: 프로젝트 매니저에서 이 디렉터리를 가져오기(Import). `project.godot` 의 `[editor_plugins] enabled` 에
  플러그인이 이미 적혀 있어 열자마자 **Learning Tools** 플러그인이 켜집니다
  (끄고 켜기: Project > Project Settings > Plugins).
- 명령행 실행: `godot --path learning/projects/07-extending-engine`
- 헤드리스 셀프테스트: `godot --headless --path learning/projects/07-extending-engine -s res://selftest.gd`
  → 마지막 줄 `SELFTEST PASS 07-extending-engine`
- 전체 검증(셀프테스트 + 허브 5프레임 + 모든 데모 인스턴스화):
  `learning/projects/tools/verify.sh learning/projects/07-extending-engine`

## A. 에디터 플러그인 `addons/learning_tools/`

플러그인은 별도 프로세스가 아니라 **에디터 씬 트리 안의 노드**입니다. `EditorNode::set_addon_plugin_enabled()`
(`editor/editor_node.cpp`) 가 `plugin.cfg` 의 `script` 를 로드해 `EditorPlugin` 인스턴스를 만들고 `add_child` 하므로
`_enter_tree` 가 불립니다. `plugin.gd` 가 등록하는 다섯 가지:

| # | 등록 | API (`doc/classes/EditorPlugin.xml`) | 엔진 구현 |
|---|---|---|---|
| 1 | "Engine Source Hint" 독 — 선택한 노드의 클래스·상속 사슬·엔진 소스 경로 추정·`doc/classes/<Class>.xml` | `add_control_to_dock(DOCK_SLOT_RIGHT_UL, control)` + `EditorInterface.get_selection().selection_changed` | `editor/plugins/editor_plugin.cpp:95` (내부적으로 `EditorDock` 생성), `editor/editor_interface.cpp` |
| 2 | 인스펙터 맨 위 "엔진 소스: …" 라벨 (`inspector_plugin.gd`) | `add_inspector_plugin`, `EditorInspectorPlugin._can_handle/_parse_begin/add_custom_control` | `editor/inspector/editor_inspector.cpp EditorInspector::update_tree()` |
| 3 | 커스텀 노드 `SourceHintLabel2D` (`source_hint_label_2d.gd`, `@tool Node2D`, `draw_string` 으로 자기 힌트를 그림) | `add_custom_type("SourceHintLabel2D", "Node2D", script, null)` | `editor/editor_data.cpp EditorData::add_custom_type` — "진짜 클래스"가 아니라 Node2D + 스크립트 |
| 4 | 익스포트 로그 + 생성 파일 추가 (`export_plugin.gd`) | `add_export_plugin`, `EditorExportPlugin._export_begin/_export_file/_export_end`, `add_file` | `editor/export/editor_export_plugin.cpp`, `editor_export_platform.cpp export_project_files()` |
| 5 | Project > Tools > "Learning: Print ClassDB stats" | `add_tool_menu_item(name, callable)` | `editor/plugins/editor_plugin.cpp:242` → `EditorNode::add_tool_menu_item` |

`_exit_tree` 는 등록의 역순으로 전부 해제합니다. 소스 경로 추정 규칙은 `source_hint.gd` 에 있습니다
(Control→`scene/gui/`, Node2D→`scene/2d/`, Node3D→`scene/3d/`, Resource→`scene/resources/`, 그 외→`scene/main/`,
파일명 = 클래스명 snake_case + `.h`). 이 프로젝트가 저장소 안에 있으므로 추정 경로가 실제로 존재하는지도 표시합니다.

> 참고: `add_control_to_dock` 은 4.8 문서에서 deprecated 이며 `add_dock(EditorDock)` 이 대체 API 입니다.
> 이 프로젝트는 스펙대로 레거시 API 를 쓰고 있으니, 연습 과제에서 `EditorDock` 으로 바꿔 보세요.

## B. 커스텀 C++ 모듈 `custom_modules/summator/`

`methods.py is_module()` 이 요구하는 세 파일(`config.py`, `SCsub`, `register_types.cpp`)에 클래스 본체와 문서를 더한
최소 구성입니다. 스타일은 엔진과 동일합니다: `core/object/ref_counted.h` 의 라이선스 박스 주석, `#pragma once`, 탭, `.clang-format`.

| 파일 | 역할 |
|---|---|
| `config.py` | `can_build(env, platform)` → True, `configure(env)`, `get_doc_classes()` → `["Summator"]`, `get_doc_path()` → `"doc_classes"` |
| `SCsub` | `env_modules.Clone()` 후 `add_source_files(env.modules_sources, "*.cpp")` (`modules/jsonrpc/SCsub` 와 같은 패턴) |
| `register_types.h/.cpp` | `initialize_summator_module(ModuleInitializationLevel)` 가 `MODULE_INITIALIZATION_LEVEL_SCENE` 에서 `GDREGISTER_CLASS(Summator)` |
| `summator.h/.cpp` | `class Summator : public RefCounted { GDCLASS(Summator, RefCounted); … }`, `_bind_methods()` 에서 `ClassDB::bind_method(D_METHOD("add", "value"), &Summator::add)` 등 |
| `doc_classes/Summator.xml` | `doc/class.xsd` 로 검증되는 클래스 문서. `--doctool` 과 `doc/tools/make_rst.py` 가 `config.py` 의 목록을 보고 찾는다 |

빌드 (저장소 루트에서, 수 분~수십 분):

```
scons platform=linuxbsd target=editor custom_modules=learning/projects/07-extending-engine/custom_modules
```

`SConstruct` 는 `custom_modules` 경로를 `methods.detect_modules()` 로 훑고, 그 경로를 `CPPPATH` 에 넣어
`modules/modules_builders.py` 가 생성하는 `register_module_types.gen.cpp` 에서 `summator/register_types.h` 를 포함하게 합니다.
빌드 후 `bin/godot...` 로 이 프로젝트를 열면 데모 1 이 `Summator: 있음 — API_CORE` 를 출력합니다.

빌드 없이 문법만 확인하려면:

```
g++ -std=c++17 -fsyntax-only -I. -Iplatform/linuxbsd -DTOOLS_ENABLED -DDEBUG_ENABLED -DUNIX_ENABLED \
  learning/projects/07-extending-engine/custom_modules/summator/summator.cpp
clang-format --dry-run --Werror learning/projects/07-extending-engine/custom_modules/summator/*.{h,cpp}
xmllint --noout --schema doc/class.xsd learning/projects/07-extending-engine/custom_modules/summator/doc_classes/Summator.xml
```

**단위 테스트는 의도적으로 뺐습니다.** 모듈 테스트는 `modules/<m>/tests/*.h` 에 doctest 케이스를 두고
`SCsub` 에서 `if env["tests"]: env_x.add_source_files(env.modules_sources, "./tests/*.cpp")` 로 묶으며
(`modules/jsonrpc/SCsub`, `modules/jsonrpc/tests/test_jsonrpc.h`), `modules/SCsub` 가 모든 `tests/*.h` 를 모아
`modules_tests.gen.h` 를 만들어 `tests/test_main.cpp` 가 포함합니다. GDScript 는 한 단계 더 나아가
`modules/gdscript/tests/gdscript_test_runner.cpp` 가 `tests/scripts/**/*.gd` 를 실행하고 `.out` 파일과 비교합니다.
실행은 `scons tests=yes` 후 `bin/godot --test`.

## C. GDExtension `gdextension/`

같은 Summator 를 godot-cpp 로 만든 소스입니다. **이 C++ 소스는 공식 godot-cpp 예제 구조를 따르며, 이 저장소 안에서는
컴파일하지 않았습니다** (godot-cpp 가 없고 네트워크 빌드가 필요). 빌드 절차:

```
cd learning/projects/07-extending-engine/gdextension
git clone -b 4.4 https://github.com/godotengine/godot-cpp
scons platform=linuxbsd target=template_debug      # bin/libsummator_ext.linux.template_debug.x86_64.so
mv summator_ext.gdextension.example summator_ext.gdextension
```

그리고 프로젝트를 다시 엽니다. `.gdextension` 파일이 있는데 라이브러리가 없으면 프로젝트를 열 때 오류가 나기 때문에
`.example` 로 두었습니다 (Godot 는 `res://` 전체에서 `.gdextension` 을 찾아 `.godot/extension_list.cfg` 에 적어 둡니다).

| 파일 | 역할 |
|---|---|
| `SConstruct` | `env = SConscript("godot-cpp/SConstruct")`, `Glob("src/*.cpp")`, `env.SharedLibrary("bin/libsummator_ext{suffix}{SHLIBSUFFIX}")` |
| `src/summator_ext.h/.cpp` | `godot::RefCounted` 파생, `GDCLASS(SummatorExt, RefCounted)`, `_bind_methods` |
| `src/register_types.h/.cpp` | `initialize_summator_ext_module` + `extern "C" GDExtensionBool GDE_EXPORT summator_ext_init(GDExtensionInterfaceGetProcAddress, GDExtensionClassLibraryPtr, GDExtensionInitialization *)` |
| `summator_ext.gdextension.example` | `[configuration] entry_symbol="summator_ext_init" compatibility_minimum="4.4"`, `[libraries]` 플랫폼별 경로 |

로딩 경로(2장 2.7): `register_core_extensions()` → `GDExtensionManager::load_extensions()` → `OS::open_dynamic_library`
→ `entry_symbol` 호출 → 확장이 `get_proc_address("classdb_register_extension_class…")` 로 엔진 함수를 **이름으로** 얻어
`ObjectGDExtension` 콜백 묶음을 넘김 → `ClassDB::register_extension_class()`. 그 뒤로는 C++ 모듈 클래스와 구별되지 않지만
`ClassInfo.gdextension` 이 non-null 이어서 스크립트의 `ClassDB.class_get_api_type()` 이 `API_EXTENSION` 을 돌려줍니다.

### 모듈 vs GDExtension (4장 4.6)

| | 모듈 (`modules/`, `custom_modules=`) | GDExtension |
|---|---|---|
| 엔진 재빌드 | 필요 | 불필요 |
| 접근 범위 | 엔진 내부 전부 (private 헤더 포함) | 공개 API(`extension_api.json`)만 |
| 언어 | C++ | C, C++, Rust, Swift, … |
| 배포 | 커스텀 익스포트 템플릿 필요 | `.gdextension` + 공유 라이브러리 |
| 적합 | 서버 백엔드 교체, 렌더러 수정, 코어 타입 추가 | 게임 로직, 서드파티 라이브러리 래핑, 플러그인 |
| 이 프로젝트 | `custom_modules/summator/` → `Summator`, `API_CORE` | `gdextension/` → `SummatorExt`, `API_EXTENSION` |

## D. 데모 목록 (허브 `main.tscn`)

| 데모 | 보여주는 개념 |
|---|---|
| `demos/extension_check/` | `ClassDB.class_exists / can_instantiate / instantiate / class_get_api_type / class_get_method_list`. `Summator`, `SummatorExt` 가 있으면 `add(5)+add(7)=12` 를 호출하고, 없으면 정확한 빌드 명령을 로그로 남긴다. 내장 모듈 클래스 `JSONRPC`(`modules/jsonrpc`) 로 "모듈 등록"의 살아 있는 예를 보여준다. |
| `demos/tool_scripts/` | 에디터는 Godot 앱이다(`main/main.cpp Main::start()` → `editor/editor_node.cpp`). `@tool` 루트의 `Engine.is_editor_hint()` 분기, `ToolWidget` 의 `_get_configuration_warnings()`, `update_configuration_warnings()`, `@export_tool_button` (Callable 프로퍼티), 에디터/런타임에서 따로 증가하는 틱 카운터. |
| `demos/contributing_guide/` | `CONTRIBUTING.md` 요약 체크리스트(이슈 → 제안 → 브랜치 → clang-format/pre-commit → doc XML(`--doctool`) → `tests/` → PR) 와 관련 문서 링크. `OS.shell_open` 은 헤드리스에서 건너뛴다. |

## 셀프테스트가 검사하는 것 (`selftest.gd`)

- `plugin.cfg` 가 `ConfigFile` 로 파싱되고 `plugin/name·description·author·version·script` 가 있으며 `script` 파일이 존재
- `project.godot` 의 `editor_plugins/enabled` 에 플러그인이 등록됨
- `ClassDB.class_exists("EditorPlugin")` 이면 애드온 스크립트 5개를 `load()` 해 컴파일·`can_instantiate` 확인,
  `plugin.gd` 가 `@tool` 이고 베이스가 `EditorPlugin` (에디터 빌드가 아니면 건너뜀)
- 소스 경로 휴리스틱: `Button→scene/gui/button.h`, `CharacterBody2D→scene/2d/character_body_2d.h`, `Node3D→scene/3d/node_3d.h`,
  `Node→scene/main/node.h`, `BoxMesh→scene/resources/box_mesh.h`, 모르는 클래스는 오류 없이 처리; 상속 사슬 `Button > … > Object`;
  저장소 안에서 실행되면 추정 파일의 실제 존재 여부
- 모듈 파일 7개 존재, `summator.h` 에 `GDCLASS(Summator, RefCounted)`·`#pragma once`·라이선스 박스, `register_types.cpp` 에
  `GDREGISTER_CLASS(Summator)`·SCENE 레벨, `config.py` 네 함수, `SCsub` 의 `add_source_files`; `Summator.xml` 을 `XMLParser` 로
  읽어 클래스/상속/메서드 3개 확인
- `summator_ext.gdextension.example` 이 `ConfigFile` 로 파싱되고 `[configuration] entry_symbol == "summator_ext_init"`,
  `compatibility_minimum`, `[libraries]` 6개 경로 규칙; 확장 소스 5개 존재, `GDCLASS(SummatorExt, RefCounted)`,
  `extern "C"` 함수 이름이 `entry_symbol` 과 일치
- `ClassDB.class_exists("Summator") / ("SummatorExt")` 결과 출력(단언하지 않음; 있으면 `get_total()==12` 는 단언),
  `JSONRPC` 가 `API_CORE`
- `Log` autoload 의 `message(text, level)` 시그널, `tool_widget.gd` 의 경고/버튼 Callable/자식 세기, 데모 상수와 허브 `DEMOS` 의 씬 존재

## 함께 읽을 엔진 소스

| 주제 | 파일 | 가이드 |
|---|---|---|
| 플러그인 로딩 | `editor/editor_node.cpp` (`set_addon_plugin_enabled`), `editor/plugins/editor_plugin.cpp`, `editor/plugins/editor_plugin.h` | 9장 Stage 7 |
| 에디터 = Godot 앱 | `main/main.cpp` (`Main::start`), `editor/editor_node.cpp`, `core/config/engine.h` (`editor_hint`) | 1장, 9장 Stage 1·7 |
| 독/인스펙터/익스포트 | `editor/docks/editor_dock.cpp`, `editor/docks/editor_dock_manager.cpp`, `editor/inspector/editor_inspector.cpp`, `editor/export/editor_export_plugin.cpp` | — |
| 모듈 구조 | `modules/jsonrpc/{SCsub,config.py,register_types.cpp}`, `modules/register_module_types.h`, `modules/modules_builders.py`, `SConstruct` (`custom_modules`), `methods.py` (`detect_modules`, `convert_custom_modules_path`) | 4장 4.1 |
| ClassDB 등록 | `core/object/class_db.h` (`GDREGISTER_CLASS`, `register_class`, `register_extension_class`), `core/object/class_db.cpp`, `core/object/object.h` (`GDCLASS`, `ObjectGDExtension`) | 2장 2.1·2.2 |
| GDExtension 로딩 | `core/extension/gdextension_interface.json` (→ `gdextension_interface.gen.h`), `core/extension/gdextension.cpp`, `core/extension/gdextension_manager.cpp`, `core/register_core_types.cpp` (`register_core_extensions`) | 2장 2.7 |
| @tool 과 경고 | `modules/gdscript/gdscript.cpp` (`is_tool`), `scene/main/node.cpp` (`update_configuration_warnings`), `modules/gdscript/doc_classes/@GDScript.xml` (`@export_tool_button`) | 4장 4.2 |
| 기여 규칙 | `CONTRIBUTING.md`, `.pre-commit-config.yaml`, `.clang-format`, `misc/scripts/{file_format,header_guards,copyright_headers}.py`, `doc/class.xsd`, `doc/tools/make_rst.py`, `tests/test_main.cpp`, `modules/gdscript/tests/README.md` | 9장 Stage 7 |

## 연습 과제

1. **`add_dock` 로 이식**: `plugin.gd` 의 독을 deprecated 된 `add_control_to_dock` 대신 `EditorDock`(`doc/classes/EditorDock.xml`) +
   `add_dock/remove_dock` 으로 바꾸세요. `editor/plugins/editor_plugin.cpp:95` 가 레거시 호출을 어떻게 `EditorDock` 으로 감싸는지 먼저 읽습니다.
2. **모듈에 시그널과 프로퍼티 추가**: `Summator` 에 `total` 프로퍼티(`ADD_PROPERTY` + `PROPERTY_HINT_RANGE`)와 `total_changed` 시그널(`ADD_SIGNAL(MethodInfo(...))`)을
   추가하고 `doc_classes/Summator.xml` 에 `<members>`/`<signals>` 를 채운 뒤 `xmllint --schema doc/class.xsd` 로 검증하세요.
   `core/object/object.h` 의 `ADD_PROPERTY` 매크로와 `scene/main/timer.cpp` 의 `_bind_methods` 를 참고합니다.
3. **모듈 단위 테스트**: `custom_modules/summator/tests/test_summator.h` 에 doctest 케이스(`TEST_CASE("[Summator] add and reset")`)를 쓰고
   `SCsub` 에 `if env["tests"]:` 블록을 추가한 뒤 `scons tests=yes custom_modules=...` 와 `bin/godot --test --test-case="*Summator*"` 로 실행하세요.
4. **GDExtension 실제 빌드**: C 절차대로 godot-cpp 를 받아 빌드하고, 데모 1 에서 `SummatorExt` 가 `API_EXTENSION` 으로 보이는지,
   `--verbose` 로 실행했을 때 `GDExtension` 로딩 로그가 어디서 찍히는지(`core/extension/gdextension.cpp`) 확인하세요.
5. **인스펙터 플러그인 확장**: `inspector_plugin.gd` 의 `_parse_property` 를 구현해 `Node.name` 속성 옆에 `doc/classes/<Class>.xml` 의
   해당 `<member>` 줄 번호를 보여 주세요 (`FileAccess.get_file_as_string` + `String.find`).

## 흔한 함정

- **`class_name` 은 명령행에서 해석되지 않을 수 있다.** 전역 클래스 목록은 에디터가 만드는 `.godot/global_script_class_cache.cfg` 에서
  읽습니다(`core/object/script_language.cpp ScriptServer::init_languages`). `.godot/` 이 없는 새 체크아웃에서 `--headless -s` 로 실행하면
  `Identifier "X" not declared` 파스 오류가 납니다. 그래서 이 프로젝트는 공유 스크립트를 `preload()` 상수로 참조합니다.
- **`-s` 스크립트에서 autoload 를 쓰는 스크립트를 `preload` 하지 말 것.** `godot -s res://selftest.gd` 의 메인 루프 스크립트는
  autoload 가 트리에 추가되기 *전에* 컴파일됩니다(`main/main.cpp Main::start()`). 그때 함께 컴파일되는 `preload` 대상이 `Log` 를 참조하면
  `Identifier not found: Log` 가 납니다. 반면 `_initialize`/`_process` 안의 `load()` 는 autoload 등록 뒤라 문제없습니다 —
  `tools/demo_runner.gd` 와 `selftest.gd` 의 `_load_script()` 가 그 방식입니다.
- **애드온 스크립트는 에디터 밖에서도 `load()` 될 수 있다.** 검증 러너가 모든 `.gd` 를 컴파일하므로 `EditorInterface` 같은 에디터 전용
  호출은 클래스 본문(상수/기본값)이 아니라 함수 안에 두어야 합니다. `EditorInterface` 싱글턴 자체는 에디터 빌드라면 항상 등록되어 있습니다
  (`editor/register_editor_types.cpp`).
- **`.gdextension` 이 있으면 라이브러리도 있어야 한다.** 라이브러리가 없으면 프로젝트를 열 때마다 오류가 납니다. 빌드 전에는 `.example` 로 두세요.
- **`entry_symbol` 과 `extern "C"` 함수 이름 불일치**는 "Unable to load GDExtension" 의 가장 흔한 원인입니다. 셀프테스트가 둘을 대조합니다.
- **`ClassDB.instantiate` 는 소유권을 넘긴다.** `RefCounted` 파생은 참조가 끊기면 사라지지만 순수 `Object`(예: `JSONRPC`)는 `free()` 하지 않으면
  종료 시 `ObjectDB instance leaked` 경고가 납니다.
- **`@tool` 루트 스크립트의 `_ready` 는 에디터에서도 돈다.** 에디터에는 autoload 가 없으므로 `Engine.is_editor_hint()` 로 먼저 갈라야 합니다.
- **`push_error` / `push_warning` 은 헤드리스 검증을 실패시킨다.** 기대된 제약(창 없음, 모듈 없음)은 `Log.warn` 으로 print 만 합니다.
- **모듈 `.cpp` 에서 `ClassDB::bind_method` 를 쓰려면 `core/object/class_db.h` 를 직접 포함**해야 합니다. `ref_counted.h` 만으로는
  `ClassDB` 가 전방 선언일 뿐이라 "incomplete type 'ClassDB'" 오류가 납니다 (`g++ -fsyntax-only` 로 바로 잡힙니다).
- **라이선스 박스 주석은 76열 고정폭**입니다. `misc/scripts/copyright_headers.py` 훅이 파일명 줄의 패딩까지 검사하므로 손으로 쓰지 말고
  기존 파일에서 복사하세요.
