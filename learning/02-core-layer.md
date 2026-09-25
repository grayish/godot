# 2장. 코어 계층 (`core/`)

`core/`는 Godot의 "표준 라이브러리"입니다. 씬도, 렌더러도 모르지만, 그 둘이 공유하는 모든 기반(객체 모델, 동적 타입, 리플렉션, 리소스, OS 추상화, 컨테이너, 확장 ABI)이 여기 있습니다.

```
core/
├── object/      Object, ClassDB, GDType, RefCounted, ObjectDB, MessageQueue, Callable 바인딩(method_bind)
├── variant/     Variant, Array, Dictionary, Callable, Signal, 연산자/변환 테이블
├── string/      String(UTF-32), StringName(인터닝), ustring, translation
├── math/        Vector2/3/4, Basis, Transform, AABB, Projection, Color, 난수, 기하
├── os/          OS, MainLoop, Thread, Mutex, Semaphore, 메모리 할당, 시간
├── io/          Resource, ResourceLoader/Saver, FileAccess/DirAccess, PCK, 압축/암호화, JSON, HTTP, 네트워크 소켓
├── input/       Input, InputMap, InputEvent*
├── config/      ProjectSettings, Engine
├── templates/   Vector, LocalVector, HashMap, List, RID, RID_Owner, PagedAllocator, CommandQueueMT, SafeRefCount...
├── extension/   GDExtension (C ABI), gdextension_interface.json → .gen.h
├── error/       Error enum, ERR_FAIL_* 매크로
├── debugger/    EngineDebugger, 원격 디버거 프로토콜
├── crypto/      mbedTLS 래핑
└── register_core_types.cpp  등록 순서의 진실
```

## 2.1 Object와 GDCLASS: 객체 모델의 심장

📌 `core/object/object.h`

Godot의 모든 노드, 리소스, 서버 래퍼는 `Object`에서 파생합니다. `Object`는 다음을 제공합니다.

- **동적 프로퍼티 접근**: `set("name", value)`, `get("name")`, `get_property_list()` — 에디터 인스펙터, 직렬화, 애니메이션 트랙이 모두 이 경로를 씁니다.
- **메서드 호출**: `call("method", args...)`, `callv()`, `call_deferred()` — 스크립트와 C++ 사이의 공통 호출 규약.
- **시그널**: `connect`, `emit_signal`, `disconnect` (`object.h:770-794`). 저장소는 `HashMap<StringName, SignalData>`(`:426`)이며 각 슬롯은 `Callable`입니다.
- **알림(notification)**: `notification(int p_what)` — 가상 함수 대신 정수 코드를 계층 전체에 전파 (`:724-733`).
- **ObjectID**: `_instance_id` — 댕글링 포인터 대신 검증 가능한 64비트 ID (2.1.3).
- **스크립트 인스턴스**: `script_instance` (`:452`) — GDScript/C#/GDExtension이 이 객체에 "붙는" 지점.

### 2.1.1 `GDCLASS` 매크로가 하는 일

`object.h:245-333`의 `GDCLASS(m_class, m_inherits)`는 헤더 주석대로 "이 매크로 하나가 사실상 객체 모델을 정의"합니다. 펼치면:

1. `GDSOFTCLASS` (`:158-241`): `self_type`/`super_type` 별칭, `get_class_ptr_static()` (함수 로컬 static 변수의 주소를 타입 ID로 사용), `is_class_ptr()`, 그리고 `_getv/_setv/_get_property_listv/_validate_propertyv/_notification_forwardv…` 체인. **서브클래스가 실제로 오버라이드했을 때만** 호출하기 위해 멤버 함수 포인터를 비교합니다:
   ```cpp
   if (m_class::_get_get() != m_inherits::_get_get()) { if (_get(p_name, r_ret)) return true; }
   ```
2. 지연 생성되는 `GDType` (`:251-267`, `core/object/gdtype.h`): 클래스별 메서드/프로퍼티/시그널/상수 테이블. 4.x 후반에 도입된 새 구조로, `ADD_SIGNAL`/`BIND_ENUM_CONSTANT`가 `ClassDB` 대신 여기에 씁니다.
3. `initialize_class()` (`:289-310`):
   ```cpp
   m_inherits::initialize_class();                                 // 부모 먼저
   _add_class_to_classdb(get_gdtype_static_mutable(), &super_type::get_gdtype_static());
   get_gdtype_static_mutable().initialize();
   if (m_class::_get_bind_methods() != m_inherits::_get_bind_methods()) { _bind_methods(); }
   ```
   즉 **`_bind_methods()`는 클래스당 한 번, 처음 `initialize_class()`가 불릴 때 지연 실행**됩니다. `GDREGISTER_CLASS(Foo)`가 그 트리거입니다.

### 2.1.2 `_bind_methods()` 관례

```cpp
void Sprite2D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_texture", "texture"), &Sprite2D::set_texture);
    ClassDB::bind_method(D_METHOD("get_texture"), &Sprite2D::get_texture);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "texture", PROPERTY_HINT_RESOURCE_TYPE, "Texture2D"), "set_texture", "get_texture");
    ADD_SIGNAL(MethodInfo("texture_changed"));
    BIND_ENUM_CONSTANT(...);
}
```

- `D_METHOD` (`class_db.h:76-93`): 디버그 빌드에서는 인자 이름을 보존한 `MethodDefinition`, 릴리스에서는 그냥 문자열.
- `ClassDB::bind_method` (`:352-364`) → `create_method_bind()`가 템플릿으로 `MethodBind` 객체를 생성 (`core/object/method_bind.h`). 이 객체가 `Variant` 인자 배열을 실제 C++ 시그니처로 변환합니다. **스크립트 ↔ C++ 호출의 모든 오버헤드는 이 변환에 있습니다.**
- `ADD_PROPERTY` = "이 이름의 프로퍼티는 setter/getter 이 메서드 쌍으로 접근한다" — 인스펙터·`.tscn` 직렬화·애니메이션이 이 정보를 사용.
- `GDVIRTUAL*` 매크로 (`:138-147`, `gdvirtual.gen.h`는 `make_virtuals.py`가 생성): `_process`, `_ready` 같은 스크립트 오버라이드 가능 가상 함수 선언. `GDVIRTUAL_CALL(_process, delta)`가 스크립트 인스턴스 → GDExtension → 미구현 순으로 찾습니다.

### 2.1.3 ObjectDB와 ObjectID (`object.h:880-946`)

64비트 `ObjectID` = 24비트 슬롯 인덱스 + 39비트 validator + 1비트 "RefCounted 여부". `ObjectDB::get_instance(id)`는 슬롯의 validator가 일치할 때만 포인터를 돌려주므로, **해제된 객체의 ID로 접근해도 크래시 대신 nullptr**을 얻습니다. GDScript의 `is_instance_valid()`, `Variant`가 Object를 담을 때 ID를 같이 저장하는 이유(`variant.h:174-190 ObjData { ObjectID id; Object *obj; }`)가 이것입니다.

### 2.1.4 생명주기와 메모리

- `memnew(T)` (`core/os/memory.h:148`) → `operator new(DefaultAllocator)` → `postinitialize_handler()` → `_initialize()`, `_postinitialize()` → `NOTIFICATION_POSTINITIALIZE`.
- `memdelete(p)` (`:157-170`) → `predelete_handler()` → `_predelete()` (여기서 삭제를 거부할 수 있음) → `NOTIFICATION_PREDELETE` → 소멸자 → `free_static`.
- `Memory::alloc_static`는 블록 앞에 크기·원소 수 헤더를 숨겨 둡니다 (`:54-63`).
- `RefCounted` (`core/object/ref_counted.h`) + `Ref<T>` 스마트 포인터: `unreference()`가 0을 반환하면 `memdelete`. **Resource는 RefCounted, Node는 아님** — 노드는 부모가 소유(`queue_free`), 리소스는 참조 카운트로 소유. 이 차이가 Godot 메모리 관리의 핵심 규칙입니다.
- `Object::cast_to<T>()` (`:637-658`): `dynamic_cast`보다 빠른 다운캐스트. `AncestralClass` 비트 필드(`:368-386`, `NODE`, `RESOURCE`, `CONTROL`… 15비트)로 자주 쓰는 계층은 비트 검사 한 번으로 끝냅니다.

### 2.1.5 시그널 방출의 실제 (`object.cpp:1256 emit_signalp`)

1. 시그널이 블록되어 있으면 종료.
2. 슬롯 `Callable`을 최대 5개까지 스택에 복사(`MAX_SLOTS_ON_STACK`), 초과분은 힙에 — **방출 중 disconnect가 일어나도 안전**하게 하기 위함.
3. `CONNECT_ONE_SHOT` 연결은 호출 전에 먼저 끊음.
4. 각 Callable 호출. `CONNECT_DEFERRED`면 `MessageQueue`에 넣음 (다음 `flush()`에서 실행, 1장 1.4).

## 2.2 ClassDB: 런타임 리플렉션 (`core/object/class_db.h`)

- `static HashMap<StringName, ClassInfo> classes` (`:176`) — 이름 → 클래스 정보. `ClassInfo`(`:111-139`)는 부모 포인터, `creation_func`, `gdextension` 포인터, `exposed`, `is_virtual`, `api`(CORE/EDITOR/EXTENSION) 등을 가짐.
- `ClassDB::instantiate("Sprite2D")` → `creation_func` 호출. 이것이 `.tscn` 로딩과 `ClassDB.instantiate()`의 실체.
- `register_class<T>` (`:225-238`), `register_abstract_class`, `register_internal_class`, `register_runtime_class`(에디터에선 인스턴스화 불가), `register_extension_class` (GDExtension 용).
- `GDREGISTER_*` 매크로(`:553-574`)는 `if constexpr (GD_IS_CLASS_ENABLED(m_class))`로 감싸져 있어, 빌드 프로파일(`build_profile=`)로 뺀 클래스는 컴파일 자체에서 사라집니다(`disabled_classes.gen.h`).
- `ClassDB::set_current_api(API_EDITOR)` — 등록 시점에 따라 API 범주가 태깅되어 `extension_api.json` 덤프(GDExtension 바인딩 생성용)에 반영됩니다.

⚠️ `ClassDB`는 **정적 클래스**이지 싱글턴 Object가 아닙니다. 스크립트에서 보이는 `ClassDB` 싱글턴은 `CoreBind::ClassDB` 래퍼입니다(`core/core_bind.h`).

## 2.3 Variant: 동적 타입의 공용 화폐 (`core/variant/variant.h`)

`Variant::Type` (`:97-147`)에는 NIL/BOOL/INT/FLOAT/STRING, 수학 타입 15종(VECTOR2 … PROJECTION), COLOR/STRING_NAME/NODE_PATH/RID/OBJECT/CALLABLE/SIGNAL/DICTIONARY/ARRAY, Packed*Array 10종 — 총 39개 타입이 있습니다.

- 크기: **24바이트**(`real_t`=float) / 40바이트(double) (`:163-166` 주석). `Type` + `union _data`(`:255-267`). 작은 값은 인라인, `Transform3D`/`Projection` 등 큰 값만 힙 포인터.
- 연산자 테이블: `variant_op.cpp`가 (타입 A, 타입 B, 연산자) 3차원 함수 포인터 테이블을 가집니다. GDScript의 `a + b`는 결국 `Variant::evaluate()` → 이 테이블 조회입니다. 타입이 정적으로 알려지면 GDScript 컴파일러는 "validated operator"를 미리 골라 테이블 조회를 건너뜁니다 (4장).
- 메서드 호출: `Variant::call()`, `Variant::get_builtin_method()` — `variant_call.cpp`에 `String.substr` 같은 내장 타입 메서드가 등록됨.
- `Callable` (`core/variant/callable.h`): 16바이트로 고정(`register_core_types.cpp:139`의 `static_assert`). (ObjectID + StringName) 또는 `CallableCustom*` (람다, `callable_mp`, 바인딩된 인자).
- `StringName` (`core/string/string_name.h`): 인터닝된 문자열. 비교가 포인터 비교라서 `NodePath`·프로퍼티 조회가 빠릅니다. 전역 테이블 `TABLE_BITS = 16`(65,536 버킷) + `PagedAllocator`. `SNAME("x")` 매크로는 함수 로컬 static 캐시.

## 2.4 OS 추상화 (`core/os/`)

- `OS` (`os.h`): 순수 가상 함수로 플랫폼 계약을 정의합니다 — `initialize/finalize`, `execute/create_process/kill`, 환경 변수, `get_name/get_version`, `get_ticks_usec/delay_usec`, `get_main_loop`, 동적 라이브러리 로딩(`open_dynamic_library`, GDExtension이 사용), 경로(`get_user_data_dir`, `get_executable_path`). 각 플랫폼이 `OS_Windows`, `OS_LinuxBSD : OS_Unix` 등으로 구현 (5장).
- `MainLoop` (`main_loop.h`): `initialize / iteration_prepare / physics_process / iteration_end / process / finalize`. `SceneTree`가 기본 구현. 스크립트로도 `_process`를 오버라이드한 MainLoop를 만들 수 있습니다.
- 스레드: `Thread`(`thread.h`, `THREADS_ENABLED` 없으면 no-op 스텁), `Mutex`(재귀)·`BinaryMutex`(비재귀), `SpinLock`, `RWLock`, `Semaphore`, `ConditionVariable`. `WorkerThreadPool`(`core/object/worker_thread_pool.h`)이 엔진 전역 작업 풀이며 렌더 스레드·물리 스레드·셰이더 컴파일이 모두 이 풀의 태스크입니다.
- 메모리: `memnew/memdelete/memalloc/memfree`, `memnew_arr`. `new`를 직접 쓰면 `postinitialize_handler`가 빠져 Object가 깨집니다.

## 2.5 I/O와 리소스 (`core/io/`)

### Resource
`Resource : RefCounted` (`resource.h:52`). `path_cache`(리소스 경로), `local_to_scene`, `emit_changed()`, 그리고 `virtual RID get_rid()` (`:184`) — 서버에 대응 객체가 있는 리소스(Texture, Mesh, Material, Shader)는 이 함수로 RID를 노출합니다 (3장 3.6). `ResourceCache`(`:197`)는 경로 → 리소스 포인터 맵으로 같은 파일을 두 번 로드하지 않게 합니다.

### 로더 플러그인 패턴
- `ResourceFormatLoader` (`resource_loader.h:48`)를 상속해 `_recognize_path`, `_get_recognized_extensions`, `_load`를 구현하고 `ResourceLoader::add_resource_format_loader()`(`:263`)로 등록. 최대 64개(`MAX_LOADERS`).
- `ResourceLoader::_load` (`resource_loader.cpp:275`)는 등록된 로더를 순회하며 **처음으로 `recognize_path()`가 true인 로더**에 맡깁니다.
- 빌트인: 바이너리(`.res/.scn`), 텍스트(`.tres/.tscn`, `scene/resources/resource_format_text.cpp`), 임포터(`.import` 메타로 임포트된 에셋), 이미지, 번역, GDExtension. 모듈이 추가: gltf, gdscript, mono 등.
- `load_threaded_request/get` (`:249-251`) — 백그라운드 로딩.
- `ResourceSaver` / `ResourceFormatSaver`는 대칭 구조.

### FileAccess / DirAccess
- `FileAccess::create(ACCESS_RESOURCES | ACCESS_USERDATA | ACCESS_FILESYSTEM | ACCESS_PIPE)` — 접근 유형별로 `create_func[]` 테이블(`file_access.h:149`)에 플랫폼 구현이 꽂힘. `OS_Unix::initialize_core()`가 `FileAccess::make_default<FileAccessUnix>(...)`로 설정 (5장).
- `res://`가 PCK로 로드되면 `ProjectSettings`가 `DirAccessPack`/`FileAccessPack`으로 교체 (`project_settings.cpp:604,623`). 래핑 계층: `file_access_encrypted`, `file_access_compressed`, `file_access_memory`, `file_access_zip`.

## 2.6 컨테이너 (`core/templates/`)

STL을 쓰지 않는 이유는 헤더 주석과 공식 문서("Core types → Containers")에 나옵니다: 이진 크기, 컴파일 시간, ABI 안정성, 그리고 COW(copy-on-write) 의미론이 스크립트 값 타입에 필요하기 때문입니다.

| 컨테이너 | 특징 | 언제 쓰나 |
|---|---|---|
| `Vector<T>` (`vector.h`) | **COW**. `CowData` 헤더(refcount, size), 1.5배 성장 | 스크립트에 노출되는 배열(Packed*Array), 복사가 잦은 값 |
| `LocalVector<T>` | 단일 소유, COW 없음, `tight` 옵션 | 서버 내부, 성능 민감 코드 |
| `FixedVector<T, N>` | 힙 할당 없음 | 작은 고정 크기 목록 |
| `HashMap<K,V>` | Robin-hood 해싱, **포인터 안정**, 삽입 순서 유지 | 일반 용도 |
| `AHashMap` | 배열 기반, 포인터 불안정, 더 빠름 | `GDType` 멤버 테이블 등 |
| `List<T>`, `SelfList<T>` | 이중 연결 리스트 / 침습형 리스트 | 삭제가 잦은 목록, 시그널 연결 목록 |
| `RBMap`, `RBSet` | 레드블랙 트리 | 정렬된 순회 필요 시 |
| `RID` / `RID_Owner<T>` / `RID_PtrOwner<T>` (`rid_owner.h`) | 64비트 핸들 = 인덱스 + validator, 청크 할당, 프리 리스트, 옵션 mutex | **서버가 내부 객체를 노출하는 유일한 방법** (3장) |
| `PagedAllocator<T>` | 페이지 단위 풀 | StringName 데이터, 물리 객체 |
| `PagedArray` | 멀티스레드로 큰 배열 채우기 | 렌더러 컬링 결과 |
| `CommandQueueMT` (`command_queue_mt.h`) | 명령을 튜플로 직렬화해 다른 스레드에서 실행. `push / push_and_ret / push_and_sync / flush_all` | 렌더 스레드, 물리 스레드 (3장 3.1) |
| `SafeNumeric`, `SafeFlag`, `SafeRefCount` | 원자 연산 래퍼 (암묵 변환 금지로 원자성이 코드에 드러나게) | 참조 카운트, 스레드 플래그 |
| `Span<T>` | 비소유 뷰 | 함수 인자 |

## 2.7 GDExtension: 재컴파일 없는 확장 (`core/extension/`)

- 인터페이스는 손으로 쓴 헤더가 아니라 **`gdextension_interface.json`에서 생성**됩니다 (`core/extension/SCsub` → `gdextension_interface.gen.h`). 바인딩 생성기(godot-cpp 등)도 같은 JSON을 읽습니다.
- 진입점: `.gdextension` 파일의 `entry_symbol`이 가리키는 함수
  ```c
  GDExtensionBool entry(GDExtensionInterfaceGetProcAddress get_proc_address,
                        GDExtensionClassLibraryPtr library, GDExtensionInitialization *init);
  ```
  확장은 `get_proc_address("classdb_register_extension_class6")` 등 **이름으로 함수 포인터를 가져와** 사용합니다. 이것이 엔진 버전이 바뀌어도 ABI가 유지되는 이유입니다.
- 로딩 흐름: `register_core_extensions()` (`register_core_types.cpp:399`) → `GDExtensionManager::load_extensions()` → `OS::open_dynamic_library` → `entry_symbol` 호출 → 확장이 CORE/SERVERS/SCENE/EDITOR 각 레벨에서 `initialize(userdata, level)` 콜백을 받음 (1장의 초기화 레벨과 동일).
- 클래스 등록: 확장이 넘긴 콜백 묶음 `ObjectGDExtension` (`object.h:74-136`: `create_instance`, `free_instance`, `set/get`, `get_virtual`…)이 `ClassDB::register_extension_class()` (`class_db.cpp:1953`)로 들어가면 엔진 입장에선 C++ 클래스와 구별되지 않습니다.
- 매 프레임 `GDExtensionManager::frame()` (`main.cpp:5104`)이 호출되어 핫 리로드 등을 처리합니다.

## 2.8 ProjectSettings와 Engine (`core/config/`)

- `ProjectSettings` (`project_settings.h`): `project.godot`/`project.binary`의 key→Variant 저장소. `GLOBAL_DEF("path/key", default)`로 기본값을 등록하면서 값을 읽고, `GLOBAL_GET`으로 읽습니다. `.feature` 접미사(`rendering/.../size.mobile`)는 **기능 태그 오버라이드** — 익스포트 타깃이 `mobile` 태그를 가지면 그 값이 우선 (`feature_overrides`, `:109`). `_setup()` (`project_settings.cpp:693`)의 검색 순서(명시 PCK → 실행 파일 내장 PCK → 옆의 .pck → `project.godot` → 상위 디렉터리 탐색)는 5장 5.6에서.
- `Engine` (`engine.h`): Object가 아닌 순수 싱글턴. 물리 틱 수(`ips`), `physics_jitter_fix`, `max_fps`, `time_scale`, 프레임 카운터, `editor_hint`, 그리고 스크립트 싱글턴 레지스트리(`add_singleton`).

## 2.9 `register_core_types()` 순서 (`core/register_core_types.cpp:135-358`)

읽어 두면 "무엇이 무엇에 의존하는가"가 보입니다.

1. `ObjectDB::setup()`, `StringName::setup()`, 전역 상수, `CoreStringNames`
2. `Object`, `RefCounted`, `WeakRef`, `Resource` 등록 → `ResourceLoader::initialize()`
3. `Variant::register_types()` — 연산자/메서드 테이블
4. 리소스 포맷 로더/세이버(바이너리, 임포터, 이미지, 번역…)
5. `Script`, `ScriptLanguage`, `Image`, `InputEvent*`
6. 네트워크(`StreamPeer*`, `PacketPeer*`, `HTTPClient`), 암호화, JSON
7. `MainLoop`, `Translation`, `UndoRedo`, `FileAccess`/`DirAccess`, `Thread`/`Mutex`, `XMLParser`, `ConfigFile`, `AStar*`…
8. `GDExtension`, `GDExtensionManager`, `ResourceUID`
9. `CoreBind::*` (스크립트용 `OS`, `Engine`, `ClassDB`, `ResourceLoader` 래퍼), `ProjectSettings`, `Input`(abstract), `InputMap`
10. `WorkerThreadPool`

`unregister_core_types()`는 역순이며 `StringName::cleanup()`이 마지막입니다 — 다른 모든 것이 StringName을 쓰기 때문.

🧪 **실습 2**: `Object` 서브클래스를 하나 만들어 `GDREGISTER_CLASS`로 등록하고, GDScript에서 `ClassDB.class_get_method_list("MyClass")`를 출력해 보세요. 그다음 `--dump-extension-api`로 `extension_api.json`을 만들어 내 클래스 항목을 확인하면 ClassDB → GDExtension 바인딩 파이프라인 전체가 연결됩니다.
