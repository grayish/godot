# 02 — 씬 트리 실험실 (Scene Tree Lab)

> 학습 자료 `learning/01-architecture-overview.md` 1.4 (프레임 루프 `Main::iteration()`) 와
> `learning/03-servers-and-scene.md` 3.2–3.4 (SceneTree, Node 생명주기, Viewport/Window) 를 손으로 확인하는 Godot 4 프로젝트입니다.
> 엔진 소스는 이 저장소(4.8 dev, master) 기준입니다.

## 목적

- `Node` 의 생명주기 콜백/알림이 **어떤 순서로, 왜 그 순서로** 오는지 (`_propagate_enter_tree` 는 위→아래, `_propagate_ready` 는 아래→위).
- 한 프레임 안에서 물리 틱과 `_process` 가 몇 번 도는지, `Engine.physics_ticks_per_second / max_fps / time_scale` 이 각각 무엇을 바꾸는지.
- `call_deferred`, `set_deferred`, `CONNECT_DEFERRED`, `await process_frame / physics_frame`, `create_timer(0)` 이 `MessageQueue` flush 지점과 어떻게 얽히는지.
- 그룹(`group_map`)과 서브트리 전파(`propagate_call / propagate_notification`)의 차이, `node_added / node_removed`.
- 입력 이벤트가 `_input → GUI → _shortcut_input → _unhandled_key_input → _unhandled_input` 으로 흐르는 경로와 `mouse_filter`.
- `PackedScene` 이 들고 있는 `SceneState`(노드/속성/연결 표)와 `owner` 의 의미.

모든 시각 요소는 코드로 만든 `Control` / `Label` / `ColorRect` / `_draw()` 뿐이며 바이너리 에셋이 없습니다.

## 실행 방법

| 방법 | 명령 |
|---|---|
| 에디터에서 열기 | Godot 4.x 프로젝트 관리자에서 `learning/projects/02-scene-tree-lab/project.godot` 을 가져와 실행 (F5) |
| 명령행 실행 | `bin/godot.linuxbsd.editor.x86_64 --path learning/projects/02-scene-tree-lab` |
| 헤드리스 셀프테스트 | `bin/godot.linuxbsd.editor.x86_64 --headless --path learning/projects/02-scene-tree-lab -s res://selftest.gd` → 마지막 줄 `SELFTEST PASS 02-scene-tree-lab` |
| 전체 검증 | `learning/projects/tools/verify.sh learning/projects/02-scene-tree-lab` → `VERIFY PASS` (셀프테스트 + 허브 5프레임 + 모든 데모 인스턴스화) |

허브(`main.tscn`)는 왼쪽에 데모 버튼, 오른쪽 위에 선택한 데모, 아래에 `Log` 오토로드(`log.gd`)의 `message` 시그널을 비추는 로그 패널이 있습니다.
데모가 무엇을 하는지는 모두 로그 패널(그리고 stdout)에 한국어로 찍힙니다.

## 데모 목록

| # | 디렉터리 | 보여주는 개념 |
|---|---|---|
| 1 | `demos/lifecycle_order/` | `lifecycle_probe.gd` 를 공유하는 `Root > A > (A1, A2), Root > B > B1` 트리를 코드로 만들어 `_init`, `NOTIFICATION_PARENTED`, `_enter_tree`, `NOTIFICATION_POST_ENTER_TREE`, `_ready`, `_exit_tree`, `NOTIFICATION_UNPARENTED`, `NOTIFICATION_PREDELETE` 를 깊이별 들여쓰기로 기록. 버튼: 서브트리 추가 / `queue_free` / `reparent` / `request_ready()` 후 재추가 / 재추가(없이). |
| 2 | `demos/process_vs_physics/` | 초당 `_process` / `_physics_process` 횟수, `Engine.physics_ticks_per_second`(30/60/120), `max_fps`(0/30/60), `time_scale`(0.5/1/2), `get_physics_frames() / get_process_frames() / get_frames_drawn() / get_physics_interpolation_fraction()`, 물리 틱으로 움직이는 `Node2D` + 물리 보간 토글, `process_priority` 순서(3개 탐침), `process_mode` ALWAYS/PAUSABLE/WHEN_PAUSED + `get_tree().paused`. |
| 3 | `demos/deferred_queue/` | 여섯 가지 "나중에 실행"의 요청 시점과 실행 시점을 `Engine.get_process_frames() / get_physics_frames() / is_in_physics_frame()` 으로 비교. 입력 콜백 / `_process` 안 / `_physics_process` 안에서 요청해 보며 `Main::iteration()` 의 flush 지점을 확인. |
| 4 | `demos/groups_and_notifications/` | `add_to_group / is_in_group / get_nodes_in_group / call_group / call_group_flags(REVERSE, DEFERRED) / propagate_call(parent_first) / propagate_notification(NOTIFICATION_CUSTOM_PING=10001)`, `SceneTree.node_added / node_removed`. |
| 5 | `demos/input_propagation/` | 키/마우스 이벤트가 `_input`, `Control._gui_input`(Button, Panel, 루트), `_shortcut_input`, `_unhandled_key_input`, `_unhandled_input` 을 거치는 순서. 단계별 `set_input_as_handled()` 체크박스, 루트/Panel 의 `mouse_filter` STOP/PASS/IGNORE 선택. |
| 6 | `demos/packed_scene_inspect/` | `sample.tscn`(노드 4개, `[connection]` 1개)의 `PackedScene.get_state()` 로 `get_node_count / get_node_name·type·path / get_node_property_*` / `get_connection_*` 를 덤프, `instantiate()` 후 각 노드의 `owner` 와 `get_tree_string_pretty()`, `pack()` 으로 재포장. |

## 함께 읽을 엔진 소스

| 주제 | 파일 (이 저장소) | 학습 자료 |
|---|---|---|
| 프레임 루프, flush 지점 | `main/main.cpp` `Main::iteration()` — 물리 틱 루프 안의 `message_queue->flush()` 2회, `process()` 뒤 1회, `_process_frames++` 는 끝에서 | 1장 1.4 |
| 물리 틱 수 계산 | `main/main_timer_sync.cpp` `advance_core()` | 1장 1.4 |
| 지연 호출 큐 | `core/object/message_queue.h` `CallQueue::push_callp / push_set / push_callablep / flush` | 1장 1.4 |
| SceneTree 한 프레임 | `scene/main/scene_tree.cpp` `physics_process()` / `process()` — `physics_frame`/`process_frame` emit → `_process()` → flush → `process_timers()` → `_flush_delete_queue()` | 3장 3.2 |
| 우선순위 정렬 | `scene/main/scene_tree.cpp` `_process_group()` (`ComparatorWithPriority`) | 3장 3.2 |
| 그룹 호출 | `scene/main/scene_tree.cpp` `call_group_flagsp()` — `GROUP_CALL_REVERSE` 역순 루프, `GROUP_CALL_DEFERRED` → `MessageQueue::push_callp` | 3장 3.2 |
| 노드 생명주기 | `scene/main/node.cpp` `_propagate_enter_tree()` / `_propagate_ready()` / `_propagate_exit_tree()` / `request_ready()` / `reparent()` / `propagate_call()` / `propagate_notification()` / `NOTIFICATION_PREDELETE` 처리 | 3장 3.3 |
| queue_free | `scene/main/node.cpp` `queue_free()` → `scene_tree.cpp` `queue_delete()` / `_flush_delete_queue()` | 3장 3.3 |
| 입력 전파 | `scene/main/viewport.cpp` `push_input()` / `_gui_input_event()` / `_gui_call_input()` / `_push_unhandled_input_internal()`, `scene/gui/control.cpp` `_call_gui_input()` | 3장 3.4 |
| 창 → 뷰포트 | `scene/main/window.cpp` `_window_input()` | 3장 3.4 |
| PackedScene | `scene/resources/packed_scene.cpp` `SceneState::instantiate()` / `PackedScene::pack()`, `scene/resources/resource_format_text.cpp` | 3장 3.6 |
| 오토로드/-s 스크립트 | `main/main.cpp` `Main::start()` — 스크립트 로드 후 오토로드 등록 순서 | 1장 1.3 |

## 로그 읽는 법 (핵심 결론)

- **enter_tree 는 위→아래, ready 는 아래→위.** `add_child()` 가 `_propagate_enter_tree()`(자신 → 자식 재귀) 다음 `_propagate_ready()`(자식 재귀 → 자신) 를 부르기 때문. 부모 `_ready` 에서 자식의 `@onready` 를 안전하게 쓸 수 있는 이유.
- **`_ready` 는 한 번만.** `data.ready_first` 가 첫 번째에 `false` 가 되고, `request_ready()` 만 다시 `true` 로 만든다 — 그 노드 하나만. `NOTIFICATION_POST_ENTER_TREE` 는 매번 온다.
- **`queue_free()` 는 즉시 지우지 않는다.** 그 프레임 `SceneTree::process()` 끝의 `_flush_delete_queue()` 에서 `memdelete` → `PREDELETE`(스크립트가 C++ 보다 먼저) → `remove_child` → `_exit_tree`(자식 먼저, 역순) → `UNPARENTED` → 자식들 삭제.
- **`max_fps` 는 물리 틱 수를 바꾸지 않는다.** 프레임 끝 `OS::add_frame_delay()` 에서 잠들 뿐. `physics_ticks_per_second` 가 시뮬레이션 해상도, `time_scale` 은 두 delta 에 곱해진다.
- **deferred 가 "같은 프레임" 에 실행되는 이유.** `Main::iteration()` 이 물리 틱마다, 그리고 `process()` 뒤에 `message_queue->flush()` 를 부른다. `process_frames` 는 iteration 끝에서 증가하므로 요청/실행의 `pf` 가 같으면 같은 iteration 이다. `await process_frame` 은 다음 `SceneTree::process()` 첫머리(노드 `_process` 전), `await physics_frame` 은 다음 물리 틱 첫머리, `create_timer(0)` 은 그 프레임 `process_timers()`(노드 `_process` 뒤) 에서 재개된다.
- **그룹 호출은 트리 순서, `propagate_*` 는 서브트리.** `get_nodes_in_group` 은 `_update_group_order()` 로 트리 순서 정렬. `propagate_notification` 은 항상 부모 먼저, `propagate_call` 은 `parent_first` 로 선택.
- **마우스 클릭은 Control 위에서는 항상 GUI 단계가 소비한다.** `_unhandled_input` 까지 가려면 그 지점의 모든 Control 이 `MOUSE_FILTER_IGNORE` 여야 한다 (허브의 레이아웃 컨테이너는 그래서 IGNORE 다). `STOP` 은 포인터 이벤트만 막고, 키 이벤트는 포커스 소유자에서 조상으로 계속 올라간다. `_shortcut_input` 에는 마우스가 절대 오지 않는다.

## 연습 과제

1. **자식까지 다시 `_ready`**: 데모 1 에 "`propagate_call("request_ready")` 후 재추가" 버튼을 추가해 모든 노드의 `_ready` 가 다시 오는지, 순서는 여전히 아래→위인지 확인하세요.
2. **`_exit_tree` 순서 검증**: `selftest.gd` 에 "형제 A, B 중 B 가 먼저 나간다" 를 넘어 `A2 → A1 → A` 전체 역순을 검사하는 체크를 추가하고, `node.cpp _propagate_exit_tree()` 의 `data.children.last()` 역순 루프와 대조하세요.
3. **물리 틱 스파이럴**: 데모 2 에서 `Engine.max_physics_steps_per_frame` 을 1 로 낮추고 tps 를 120 으로 올린 뒤 `_physics_process` 횟수가 왜 120 에 못 미치는지 `main.cpp` 의 클램프 코드로 설명하세요.
4. **deferred 순서 예측**: 데모 3 의 "다음 `_physics_process` 안" 버튼을 누르기 전에 여섯 줄의 `pf / phf / in_physics` 값을 종이에 예측하고 로그와 비교하세요. 틀린 항목은 `Main::iteration()` 의 어느 flush 지점 때문인지 찾으세요.
5. **`GROUP_CALL_UNIQUE`**: 데모 4 에 `GROUP_CALL_DEFERRED | GROUP_CALL_UNIQUE` 버튼을 추가해 한 프레임에 여러 번 눌러도 `ping` 이 한 번만 오는지 확인하고, `scene_tree.cpp` 의 `unique_group_calls` / `_flush_ugc()` 를 읽으세요.
6. **마우스를 `_unhandled_input` 까지**: 데모 5 에서 루트와 Panel 을 IGNORE 로 바꾸고 Panel 영역을 클릭해 `_unhandled_input` 이 찍히는지 확인한 뒤, `viewport.cpp gui_find_control_at_pos()` 가 IGNORE 컨트롤을 어떻게 건너뛰는지 찾으세요.
7. **pack() 에 코드 노드 포함**: 데모 6 에서 인스턴스에 `Label` 을 코드로 추가하고 `owner = 인스턴스` 를 설정한 뒤 `pack()` 의 노드 수가 5 가 되는지 확인하세요. 설정하지 않으면 왜 빠지는지 `PackedScene::pack()` → `SceneState::_parse_node()` 에서 찾으세요.

## 흔한 함정

- **`-s` 스크립트는 오토로드보다 먼저 컴파일된다.** `selftest.gd` 안에서 `Log` 를 쓰거나 `Log` 를 쓰는 스크립트를 `preload()` 하면 "Identifier not found: Log" 로 실패한다. 데모 스크립트는 `_initialize()` 에서 `load()` 로 읽어야 한다 (`main/main.cpp Main::start()` 의 순서).
- **`_initialize()` 시점엔 root 가 아직 트리 밖이다.** `SceneTree::initialize()` 가 `MainLoop::initialize()` 뒤에 `root->_set_tree()` 를 하므로, 노드 추가나 `push_input` 은 `_process` 첫 프레임부터 해야 한다 (`push_input` 은 `!is_inside_tree()` 로 ERROR 를 낸다).
- **`class_name` 은 `.godot/global_script_class_cache.cfg` 가 있어야 런타임에 풀린다.** 에디터로 한 번도 열지 않은 프로젝트를 헤드리스로 돌리면 다른 파일의 `class_name` 참조가 실패한다(이 환경에서는 컴파일이 멈추기까지 했다). 이 프로젝트는 그래서 모든 교차 파일 참조를 `preload()` 상수로 한다.
- **`Engine` 설정과 `paused` 는 프로세스 전역이다.** 데모 2 는 `_exit_tree` 에서 tps / max_fps / time_scale / physics_interpolation / paused 를 되돌린다. 되돌리지 않으면 다른 데모가 멈춘 채로 보인다.
- **허브가 `paused` 에도 살아 있어야 한다.** 허브 루트는 `PROCESS_MODE_ALWAYS` 다. 그 아래 데모 노드도 INHERIT 면 ALWAYS 가 되므로, 멈춰야 하는 노드에는 `PROCESS_MODE_PAUSABLE` 을 명시했다.
- **PREDELETE 안에서 다른 노드를 건드릴 때.** 종료 중에는 허브의 로그 패널이 먼저 해제될 수 있어 `main.gd` 는 `_exit_tree` 에서 `Log.message` 연결을 끊고 `is_instance_valid` 로 한 번 더 막는다.
- **`push_error()` 는 헤드리스 검증을 실패시킨다.** 헤드리스에서 없는 기능은 `Log.warn` 으로 알리고 계속 진행한다.
- **`await` 뒤에는 `is_inside_tree()` 를 확인한다.** 데모가 해제된 뒤 코루틴이 깨어나 해제된 노드를 건드리지 않게.
- **`.tscn` 의 `load_steps`** = 1 + ext_resource + sub_resource 수. `parent=` 는 먼저 선언된 노드만 가리킬 수 있다.
