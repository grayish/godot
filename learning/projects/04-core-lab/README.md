# 04 코어 계층 실험실 (core/)

`learning/02-core-layer.md` (2장. 코어 계층) 을 손으로 만져 보는 Godot 4 학습 프로젝트입니다.
씬도 렌더러도 모르는 `core/` — Object/ClassDB/Variant/ObjectDB/RefCounted/Resource/IO/스레드 — 가
실제로 어떻게 움직이는지, 데모 7개와 헤드리스 셀프테스트로 확인합니다. 바이너리 에셋은 하나도 없습니다
(텍스트 `.tscn`/`.tres`/`.gd` 뿐).

## 목적

- `Object.set/get/call`, `notification`, 시그널 플래그, `ObjectDB` validator 같은 **객체 모델의 기본 계약**을 관찰한다.
- `RefCounted` 카운트가 언제 오르내리는지, 순환 참조가 왜 새는지, `Node` 는 왜 참조 카운트가 아닌 **부모 소유**인지 본다.
- `Variant`/`Packed*Array`/`Array`/`Dictionary` 의 **COW 와 참조 공유**를 시간 측정으로 구별한다.
- `ResourceLoader`/`ResourceSaver` 의 캐시와 **포맷 로더 플러그인**(커스텀 `.kv`)을 GDScript 로 직접 구현한다.
- `FileAccess`/`DirAccess`/`ConfigFile`/`JSON`/`StreamPeerBuffer` 로 I/O 계층을, `Thread`/`Mutex`/`Semaphore`/`WorkerThreadPool` 로 OS 계층을 만진다.

## 실행 방법

```bash
# 1) 에디터에서 열기: 프로젝트 관리자 → 가져오기 → learning/projects/04-core-lab/project.godot
#    (처음 열면 .godot/ 캐시가 생성됩니다. .gitignore 에 포함되어 있습니다.)

# 2) 명령행에서 허브 실행 (창 필요)
godot --path learning/projects/04-core-lab

# 3) 헤드리스 셀프테스트 (창 없이, 코어 로직만 검사 → "SELFTEST PASS 04-core-lab" 출력)
godot --headless --path learning/projects/04-core-lab -s res://selftest.gd

# 4) 저장소의 헤드리스 빌드로 전체 검증 (셀프테스트 + 허브 5프레임 + 모든 데모 인스턴스화)
learning/projects/tools/verify.sh learning/projects/04-core-lab
```

허브(`main.tscn`)는 왼쪽에 데모 버튼, 오른쪽 위에 선택한 데모, 오른쪽 아래에 로그 패널을 둡니다.
모든 데모는 `Log` 오토로드(`log.gd`)로 설명을 찍고, 허브가 `Log.message` 시그널을 받아 패널에 비춥니다.
같은 내용이 stdout 에도 나오므로 헤드리스로 돌려도 읽을 수 있습니다.

## 데모 목록

| # | 데모 | 보여주는 개념 |
|---|------|----------------|
| 1 | `demos/classdb_browser/` | `ClassDB.get_class_list` 필터/목록, 상속 사슬(`get_parent_class` 루프), `can_instantiate`/`is_class_enabled`/API 종류, 메서드·프로퍼티·시그널·정수 상수·enum 목록, `ClassDB.instantiate` 로 인스턴스 생성(Node 면 트리에 추가), `Engine.get_singleton_list`. `_bind_methods()` 가 채우는 테이블을 밖에서 읽는 것. |
| 2 | `demos/object_model/` | `set/get/call/callv` (StringName), `has_method/has_signal`, 커스텀 `notification()`/`_notification()` 과 `NOTIFICATION_PREDELETE`, `CONNECT_ONE_SHOT`/`CONNECT_DEFERRED`/`CONNECT_REFERENCE_COUNTED`, `get_instance_id`/`instance_from_id`/`is_instance_valid` (ObjectDB validator), `WeakRef`, `free()` vs `queue_free()`, `get_class/is_class`, `set_meta/get_meta_list`, `tr`. |
| 3 | `demos/refcount_and_ownership/` | `get_reference_count()` 가 Ref 복사/Array 삽입/해제에 따라 변하는 모습, 두 RefCounted 의 순환 참조 누수와 `WeakRef` 로 끊기, `Node` 소유권 트리(부모 free → 자식 free, `remove_child` 한 노드는 남음), `Resource` 공유 vs `duplicate()` vs `duplicate(true)`(배열 공유·내장 서브리소스·`@export` 만 복사), `resource_local_to_scene`. |
| 4 | `demos/variant_internals/` | `PackedInt32Array`/`Array` 대입 공유 vs `duplicate()`, COW 실측(duplicate 는 버퍼 공유, 첫 쓰기에서 복사), Dictionary 참조/깊은 복제/값 비교, `String ==` vs `StringName ==` 마이크로 벤치마크, `NodePath` 파싱, `RenderingServer.instance_create` 의 RID 와 `Resource.get_rid`, Color/Vector 패킹과 `var_to_bytes` 크기, `var_to_str`/`var_to_bytes` 왕복. |
| 5 | `demos/resources_and_loaders/` | 커스텀 Resource(`KeyValueStore`, `@export var data`), `ResourceSaver.save` → `user://`, `CACHE_MODE_REUSE` vs `CACHE_MODE_IGNORE` 의 인스턴스 id 비교, `exists`/`get_resource_type`/`has_cached`, GDScript `ResourceFormatLoader`+`ResourceFormatSaver` 로 만든 `.kv` 텍스트 포맷(데모 시작 시 등록, 종료 시 해제), `load_threaded_request`/`get_status`/진행률 → 번들된 `sample_store.tres`. |
| 6 | `demos/file_and_os/` | `OS.get_user_data_dir`, `ProjectSettings.globalize_path/localize_path`, `FileAccess` 쓰기/읽기와 `get_open_error`, `DirAccess` 로 `res://`/`user://` 열거와 폴더 생성(PCK 안에서도 동일), `ConfigFile` 왕복(타입 유지), `JSON.stringify/parse_string`(숫자는 전부 float), `StreamPeerBuffer` put/get(u8/float/utf8 string/u32), `FileAccess.get_md5/get_sha256`. |
| 7 | `demos/threads_and_workers/` | `Thread.start`+`wait_to_finish`(반환값), `Mutex` 로 보호한 카운터(버튼으로 경합 관찰), `Semaphore` 생산자/소비자, `WorkerThreadPool.add_group_task` 청크 합산 + `wait_for_group_task_completion`, `add_task`, 스레드에서 `call_deferred`/`set_deferred` 로 UI 갱신, `OS.get_processor_count`, 스레드 안전 API 요약. |

## 셀프테스트가 검사하는 것 (`selftest.gd`)

`extends SceneTree` 러너가 프레임마다 테스트 하나를 실행합니다 (UI 없음).

1. `instance_from_id` 가 `free()` 뒤에 null / `is_instance_valid`·`is_instance_id_valid` 가 false
2. `PackedInt32Array` 대입 공유 + `duplicate()` 후 쓰기 분리(COW), `Array` 대입 공유 + `duplicate()` 독립
3. 커스텀 `.kv` 로더/세이버 등록 → `ResourceSaver.save` → `ResourceLoader.load(CACHE_MODE_IGNORE)` 왕복 → 등록 해제
4. `WorkerThreadPool.add_group_task` 청크 합 == 직렬 합 (Mutex 로 합산)
5. `ConfigFile` 저장/로드 왕복 (섹션 순서, bool/float/Vector2/UTF-8 문자열, default)
6. `var_to_bytes`/`bytes_to_var`, `var_to_str`/`str_to_var` 왕복 (Dictionary 값 비교), Object 는 `EncodedObjectAsID` 로만 복원

## 함께 읽을 엔진 소스

| 주제 | 파일 | 학습 가이드 |
|------|------|-------------|
| Object, GDCLASS, notification, 시그널 emit | `core/object/object.h`, `core/object/object.cpp` (`emit_signalp`) | 2장 2.1, 2.1.1, 2.1.5 |
| ObjectDB / ObjectID validator | `core/object/object.h` (`ObjectDB::get_instance`, 880행~) | 2장 2.1.3 |
| memnew/memdelete, PREDELETE | `core/os/memory.h` | 2장 2.1.4 |
| RefCounted, Ref<T>, WeakRef | `core/object/ref_counted.h`, `core/object/ref_counted.cpp` | 2장 2.1.4 |
| Node 소유권(자식 memdelete), queue_free | `scene/main/node.cpp` (`Node::~Node`), `scene/main/scene_tree.cpp` (`queue_delete`, `_flush_delete_queue`, `process` 의 flush 순서) | 2장 2.1.4, 1장 1.4 |
| ClassDB, _bind_methods, GDREGISTER_* | `core/object/class_db.h`, `core/object/class_db.cpp`, `core/object/gdtype.h`, `core/core_bind.h` (`CoreBind::ClassDB`) | 2장 2.1.2, 2.2 |
| Variant 레이아웃, PackedArrayRef, 연산자 테이블 | `core/variant/variant.h`, `core/variant/variant_op.cpp`, `core/variant/variant_call.cpp` | 2장 2.3 |
| COW 컨테이너 | `core/templates/cowdata.h` (`_copy_on_write`), `core/templates/vector.h`, `core/variant/array.cpp` (`recursive_duplicate`) | 2장 2.6 |
| StringName 인터닝, NodePath | `core/string/string_name.h`, `core/string/node_path.h` | 2장 2.3 |
| RID / RID_Owner | `core/templates/rid.h`, `core/templates/rid_owner.h` | 2장 2.6, 3장 |
| 직렬화 | `core/variant/variant_parser.cpp` (`var_to_str`), `core/io/marshalls.cpp` (`encode_variant`/`decode_variant`) | 2장 2.5 |
| Resource, ResourceCache, local_to_scene | `core/io/resource.h`, `core/io/resource.cpp`, `scene/resources/packed_scene.cpp` (`duplicate_for_local_scene`) | 2장 2.5 |
| ResourceLoader/Saver, 포맷 플러그인, 스레드 로딩 | `core/io/resource_loader.cpp` (`_load`, `MAX_LOADERS`, `_run_load_task`), `core/io/resource_saver.cpp` | 2장 2.5 |
| FileAccess/DirAccess, PCK | `core/io/file_access.h`, `core/io/dir_access.cpp`, `core/io/file_access_pack.cpp`, `core/config/project_settings.cpp` (`globalize_path`) | 2장 2.4, 2.5, 5장 |
| ConfigFile, JSON, StreamPeer | `core/io/config_file.cpp`, `core/io/json.cpp`, `core/io/stream_peer.cpp` | 2장 2.5 |
| OS, Thread, Mutex, Semaphore | `core/os/os.h`, `core/os/thread.h`, `core/os/mutex.h`, `core/os/semaphore.h` | 2장 2.4 |
| WorkerThreadPool, MessageQueue | `core/object/worker_thread_pool.cpp`, `core/object/message_queue.cpp` | 2장 2.4, 1장 1.4 |
| 등록 순서의 진실 | `core/register_core_types.cpp` | 2장 2.9 |
| 전역 클래스 캐시 (class_name) | `core/object/script_language.cpp` (`init_languages`), `core/config/project_settings.cpp` (`get_global_class_list`) | 4장 |

## 연습 과제

1. **notification 전파 관찰**: `object_model` 의 `Probe` 를 `Node` 상속으로 바꾸고 `_notification` 에서 `NOTIFICATION_ENTER_TREE`/`READY`/`EXIT_TREE` 를 로그로 찍어 `add_child`/`queue_free` 순서와 대조하세요. `scene/main/node.cpp` 의 `_propagate_ready()` 를 같이 읽으면 좋습니다.
2. **로더 우선순위**: `KVFormatLoader` 를 `add_resource_format_loader(loader, true)` (at_front) 로 등록하고 `.tres` 확장자도 인식하도록 바꿔 보세요. `ResourceLoader::_load` 가 "처음 인식한 로더" 에 맡기므로 내장 텍스트 로더보다 먼저 호출됩니다. 무엇이 깨지는지 확인한 뒤 되돌리세요.
3. **COW 를 깨뜨리기**: `variant_internals` 에서 `PackedInt32Array` 를 함수 인자로 넘겨 안에서 `append` 하면 호출자에게 보이는지, `Dictionary` 값으로 넣은 뒤 `d["k"].append()` 는 어떤지 실험하고 `PackedInt32Array.xml` 의 "passed by reference" 주석과 비교하세요.
4. **경합 재현**: `threads_and_workers` 의 "Mutex 없이" 버튼을 여러 번 눌러 결과가 40000 보다 작아지는 빈도를 보고, `INCREMENTS_PER_THREAD` 를 키우면 어떻게 변하는지 기록하세요. 그다음 `Mutex` 대신 `Semaphore(1)` 로 같은 보호를 구현해 보세요.
5. **셀프테스트 확장**: `selftest.gd` 에 "순환 참조 두 개를 만들고 WeakRef 로 바꾸면 둘 다 해제된다" 테스트를 추가하세요 (`is_instance_id_valid` 로 판정).
6. **ObjectDB 덤프**: `OS.get_static_memory_usage()` 와 `Performance.get_monitor(Performance.OBJECT_COUNT)` 를 각 데모 전후에 찍어 누수가 없는지 확인하는 코드를 허브에 넣어 보세요.

## 흔한 함정

- **`class_name` 은 에디터 캐시에 의존**: 전역 클래스 이름은 `.godot/global_script_class_cache.cfg` 에서 읽힙니다 (`ScriptServer::init_languages`). 에디터를 한 번도 열지 않은 체크아웃을 `--headless` 로 돌리면 `Identifier not declared` 가 납니다. 이 프로젝트는 그래서 `class_name` 을 선언하되 참조는 `preload()` 로 합니다.
- **`-s` 스크립트는 오토로드보다 먼저 컴파일**: `selftest.gd` 같은 `-s` MainLoop 스크립트 안에서 `Log.info()` 를 직접 쓰면 `Identifier not found: Log` 입니다 (`Main::start` 순서). 데모 씬은 오토로드 등록 뒤에 로드되므로 괜찮습니다.
- **`process_frame` 은 flush 앞에 온다**: `await get_tree().process_frame` 한 번은 `MessageQueue::flush()` 나 `_flush_delete_queue()` 를 지났다는 보장이 아닙니다 (`scene_tree.cpp` `SceneTree::process`). 데모 2 는 그래서 두 번 기다립니다.
- **Packed 배열도 대입은 공유**: Godot 4 GDScript 에서 `var b := a` 는 Packed 배열/Array/Dictionary 모두 같은 데이터를 가리킵니다. 독립 사본은 `duplicate()`. COW 는 "복사 비용을 첫 쓰기까지 미룬다" 는 뜻이지 "대입이 복사" 라는 뜻이 아닙니다.
- **`duplicate()` 는 `@export`(STORAGE) 프로퍼티만 복사**하고, 얕은 복제는 Array/Dictionary/서브리소스를 공유합니다.
- **RefCounted 순환 참조는 자동으로 풀리지 않습니다** (GC 없음). 부모→자식은 강한 참조, 자식→부모는 `WeakRef` 또는 ObjectID.
- **스레드에서 노드를 만지면 오류**: `Node` 계열은 스레드 가드가 있어 다른 스레드에서 프로퍼티/메서드를 부르면 오류가 납니다. `call_deferred`/`set_deferred` 로 메인 스레드에 맡기고, 시작한 `Thread` 는 반드시 `wait_to_finish()`.
- **`WorkerThreadPool` 그룹 상태 조회는 wait 전에만**: `wait_for_group_task_completion` 뒤에 `is_group_task_completed` 를 부르면 `Invalid Group ID`.
- **`StreamPeer.put_string` 은 ASCII 전용**: 한글은 `put_utf8_string`. 텍스트 파일에 `store_32` 를 섞으면 `get_as_text` 가 UTF-8 로 읽다 깨집니다.
- **JSON 숫자는 전부 float**, Vector2 같은 Variant 타입은 문자열이 됩니다. 타입을 지키려면 `ConfigFile`/`var_to_str`/`.tres`.
- **`error_string(ERR_PARSE_ERROR)` 는 "Parse error"** 를 출력합니다. 오류 문구를 grep 하는 검증 스크립트가 있다면 코드 값으로 찍으세요.
- **헤드리스 한계**: `RenderingServer.get_rendering_device()` 는 null, `DisplayServer.get_name()` 은 "headless". 데모는 `Log.warn` 으로 알리고 계속 진행합니다 (`push_error` 는 검증을 실패시킵니다).
