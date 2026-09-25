# 01 · 첫 게임 "Dodge (닷지)" — Stage 1: 사용자로서 Godot 익히기

학습 로드맵 [9장 Stage 1](../../09-learning-roadmap.md) 의 실습 프로젝트입니다. 공식 튜토리얼 "Your first 2D game (Dodge the Creeps)" 의 구조를
**바이너리 에셋 없이**(폴리곤·라벨만) 다시 만들고, 그 안에 쓰인 개념 하나하나를 별도 데모로 풀어 놓았습니다.
목표는 [8장 8.2](../../08-comparison-other-engines.md) 가 말하는 "**모든 것이 노드**, 씬은 노드 트리의 직렬화, 기능은 자식 노드로 붙인다"
를 손으로 확인하는 것입니다.

## 목적

- 노드 트리 / 씬 인스턴스 / 시그널 / 그룹 / 리소스 / 입력 액션 — 여섯 개념이 **실제 게임 파일의 어느 줄**에 있는지 안다.
- `.tscn` 텍스트가 에디터의 씬 독·인스펙터·시그널 탭과 어떻게 1:1 로 대응하는지 읽을 수 있다.
- 창 없이도(`--headless`) 게임 로직을 검증하는 습관을 들인다 (`selftest.gd`).
- 체크포인트(9장): "시그널은 왜 필요한가?", "`_ready` 와 `_enter_tree` 의 차이는?", "`_process` 와 `_physics_process` 는 언제 각각 불리나?" 에 이 프로젝트의 코드로 답할 수 있으면 통과.

## 실행 방법

```bash
# 1) 에디터에서 열기: 프로젝트 매니저 → Import → 이 폴더의 project.godot
#    F5 = 허브(main.tscn) 실행, F6 = 현재 열린 씬만 실행 (예: demos/game/game.tscn 단독 실행)

# 2) 명령행 (저장소 루트에서)
bin/godot.linuxbsd.editor.x86_64 --path learning/projects/01-first-game

# 3) 헤드리스 셀프테스트 (창 없음, 종료 코드 0 = 통과)
bin/godot.linuxbsd.editor.x86_64 --headless --path learning/projects/01-first-game -s res://selftest.gd

# 4) 전체 검증 (셀프테스트 + 허브 5프레임 + 모든 .gd 컴파일 + 모든 데모 씬 6프레임)
learning/projects/tools/verify.sh learning/projects/01-first-game
```

허브 창의 왼쪽 버튼으로 데모를 열고, 아래 로그 패널(오토로드 `Log` 의 `message` 시그널을 받아 씀)에서 각 데모의 설명을 읽으세요.
같은 내용이 stdout 에도 찍히므로 명령행에서도 볼 수 있습니다.

### 왜 `rendering_method = "gl_compatibility"` 인가

`project.godot:55`. 2D 만 쓰고, 초보자용이며, 최대 호환이 목표이기 때문입니다.
Compatibility 렌더러는 OpenGL 3.3 / ES 3.0 / WebGL 2 만 요구해 오래된 노트북·웹·저사양 안드로이드에서도 돌고, Vulkan 드라이버 문제를 피합니다.
Forward+ 가 주는 것(클러스터 라이팅, SDFGI, 볼류메트릭 포그…)은 전부 3D 기능입니다.
자세한 비교는 [6장](../../06-graphics-backends.md), 튜닝 항목은 [7장](../../07-graphics-tuning.md) 을 보세요.

## 데모 목록

| 버튼 | 씬 | 보여 주는 개념 |
|---|---|---|
| 게임 실행 (Dodge) | `demos/game/game.tscn` | 완성된 작은 게임. 아래 "개념 → 파일:줄" 표가 이 씬을 해부합니다 |
| 시그널 101 | `demos/signals_101/` | 시그널 연결 3가지(.tscn `[connection]` / `connect()` / `Callable.bind`), `CONNECT_ONE_SHOT`, 인자 있는 커스텀 시그널, `await` |
| 씬 인스턴스화 | `demos/scene_instancing/` | `preload` + `instantiate()` N번, `owner`/`get_path()`/`get_parent()`, `add_child` 전에 `@export` 설정, `queue_free` vs `free`, `reparent` |
| .tscn 해부 | `demos/tscn_anatomy/` | `mob.tscn` 을 `FileAccess` 로 텍스트로 읽어 `[gd_scene]` `[ext_resource]` `[sub_resource]` `[node]` `[connection]` 설명 + `PackedScene.get_state()` 대조 |

각 데모는 `_ready` 에서 자동 시연을 한 번 돌리므로 헤드리스 검증에서도 로그가 남습니다. 버튼은 같은 일을 다시 합니다.

## 게임 파일 안내: 개념 → 파일:줄

게임의 트리 (허브에서 "게임 실행" 을 누르면 로그에 `get_tree_string_pretty()` 결과가 찍힙니다):

```
Game (Node2D)                      demos/game/game.tscn:8   + game.gd
├─ Player (CharacterBody2D)        game.tscn:11  ← player.tscn 을 instance= 로 인스턴스화
│  ├─ CollisionShape2D (CircleShape2D sub_resource)   player.tscn:13
│  └─ Polygon2D (삼각형)                               player.tscn:16
├─ MobSpawner (Node) + mob_spawner.gd                game.tscn:14
│  └─ SpawnTimer (Timer)                             game.tscn:17
├─ ScoreTimer (Timer)                                game.tscn:20
├─ StartTimer (Timer, one_shot)                      game.tscn:22
├─ HUD (CanvasLayer) + hud.gd                        game.tscn:26
│  ├─ ScoreLabel / MessageLabel / RestartButton      game.tscn:29,37,45
├─ Background (ColorRect)        ← 코드로 생성        game.gd:118 _build_arena()
└─ WallTop/Bottom/Left/Right (StaticBody2D)          game.gd:135 _add_wall()
   └─ Mob (Area2D) ×N  ← 실행 중 스포너가 추가      mob.tscn:8, mob_spawner.gd:57
```

| 개념 | 어디에 있나 | 설명 |
|---|---|---|
| **노드 트리** | `game.tscn:8-50` `[node ... parent=...]` | `parent="."` 은 루트의 자식, `parent="HUD"` 는 HUD 의 자식. 에디터 씬 독의 들여쓰기가 이 `parent` 값이다 |
| | `game.gd:118-153` | 같은 트리를 코드로 만든다: `StaticBody2D.new()` → `add_child()`. `.tscn` 과 코드는 결과가 같은 노드 |
| | `player.gd:20-21` `@onready` | 자식은 부모보다 먼저 `_ready` 되므로(`node.cpp:323 _propagate_ready`, 자식→부모) `_ready` 직전에 `$자식` 을 잡아도 안전 |
| **씬 인스턴스** | `game.tscn:4` + `:11` | `[ext_resource type="PackedScene"]` 을 `instance=ExtResource("2_player")` 로 붙임 = 에디터의 "자식 씬 인스턴스화" 버튼 |
| | `mob_spawner.gd:6,39` | `preload("mob.tscn")` 한 `PackedScene` 을 `instantiate()` — 같은 씬에서 N개의 독립 노드 |
| | `game.gd:97-114` | 재시작 = 같은 `.tscn` 을 다시 `instantiate()` 해 형제로 넣고 자신은 `queue_free`. 단독 실행이면 `reload_current_scene()` |
| **시그널** | `player.gd:9` `signal hit` / `:54` `hit.emit()` | 플레이어는 "맞았다"만 알린다. 누가 듣는지 모른다 |
| | `game.tscn:53-57` `[connection ...]` | 에디터 Node 독 → Signals 탭이 만드는 줄. 인스턴스화 때 `connect()` 로 바뀐다 (`packed_scene.cpp:222 SceneState::instantiate`) |
| | `game.gd:74` `_on_player_hit` | 위 `[connection]` 의 수신 쪽. 여기서 게임 오버를 결정 |
| | `mob.tscn:19` + `mob.gd:45` | Mob 은 시그널을 **정의하지 않고** `Area2D` 가 이미 가진 `body_entered` 만 쓴다 |
| | `main.gd:77` `pressed.connect(_open_demo.bind(i))` | 코드 연결 + `bind` 로 인덱스 전달 |
| | `log.gd:7,28` | 오토로드가 시그널을 방출하고 허브가 받는다 (`main.gd:43`) — 전역 이벤트 버스의 최소형 |
| **그룹** | `mob.tscn:8` `groups=["mobs"]` | 에디터 Node 독 → Groups 탭. 인스턴스화 시 `add_to_group` |
| | `game.gd:49,84` `call_group("mobs", "queue_free")` | 스포너가 몇 마리를 만들었는지 몰라도 한 줄로 정리 (`scene_tree.cpp:362 call_group_flagsp`) |
| | `mob_spawner.gd:62` `get_nodes_in_group` | 그룹 크기 조회 (`scene_tree.cpp:1621`) |
| **리소스** | `mob_stats.gd:1-17` | `class_name MobStats extends Resource` + `@export` 4개 = 데이터 컨테이너 |
| | `mob_stats_fast.tres`, `mob_stats_slow.tres` | 같은 스크립트, 다른 값. 헤더 `script_class="MobStats"` 가 그 `class_name` |
| | `mob.gd:13` `@export var stats` | 씬은 하나, 꽂는 리소스에 따라 다른 몹. 인스펙터에서 `.tres` 를 끌어다 놓는 것이 이 변수 |
| | `mob_spawner.gd:9-12,41` | `STATS_POOL` 에서 임의로 골라 `add_child` 전에 넣는다 |
| **입력 액션** | `project.godot:28-51` `[input]` | 프로젝트 설정 → Input Map 이 저장하는 형식. 한 액션에 이벤트 2개(WASD + 방향키). `physical_keycode` 는 `@GlobalScope` `Key` 열거값 |
| | `player.gd:28` `Input.get_vector(...)` | 네 액션 → 정규화된 벡터 (`core/input/input.cpp:586`). 액션 목록은 시작 시 `input_map.cpp:325 load_from_project_settings` 가 읽는다 |
| **물리 몸체** | `player.tscn:8-10`, `mob.tscn:8-10` | 레이어/마스크: 플레이어(1)는 벽(2)에 막히고, 몹(4)은 플레이어(1)만 감지. `player.gd:30 move_and_slide()` (`character_body_2d.cpp:45`) |
| **타이머** | `game.tscn:17-24`, `game.gd:59-71` | `Timer.timeout` 시그널로 점수(1초마다 +1)·스폰·시작 지연. `timer.cpp:67` 이 `timeout` 을 방출 |
| **CanvasLayer** | `game.tscn:26`, `game.gd:40-41` | HUD 는 부모 트랜스폼을 무시한다. 허브 컨테이너 안에 있을 때 `offset` 으로 아레나 원점에 맞춘다 |

### `.tscn` 텍스트 ↔ 에디터

`demos/game/mob.tscn` (".tscn 해부" 데모가 화면에 띄우는 파일):

```
[gd_scene load_steps=3 format=3]                          ← 헤더. format=3 = Godot 4. load_steps = ext 1 + sub 1 + 1
[ext_resource type="Script" path="res://demos/game/mob.gd" id="1_mob"]   ← 파일시스템 독의 다른 파일 참조
[sub_resource type="CircleShape2D" id="CircleShape2D_mob"]  ← 인스펙터에서 "새 CircleShape2D" 한 것. 이 파일 안에만 존재
radius = 16.0                                              ← 기본값(10.0)과 다른 속성만 저장된다
[node name="Mob" type="Area2D" groups=["mobs"]]            ← 씬 독의 루트. groups= 는 Groups 탭
collision_layer = 4                                        ← 인스펙터 Collision 섹션
script = ExtResource("1_mob")                              ← 인스펙터 Script 칸
[node name="CollisionShape2D" type="CollisionShape2D" parent="."]   ← 루트의 자식 (들여쓰기 1단)
shape = SubResource("CircleShape2D_mob")
[connection signal="body_entered" from="." to="." method="_on_body_entered"]   ← Signals 탭의 연결
```

- 파서: `scene/resources/resource_format_text.cpp:443 ResourceLoaderText::load` — `[gd_scene]` 이면 `SceneState` 를 채운다 (`:1152`, `connection` 은 `:309`).
- `SceneState` (`scene/resources/packed_scene.h`) 는 노드/속성/연결을 **평평한 배열**로 들고 있고, `instantiate()` (`packed_scene.cpp:222`) 가 순서대로
  `ClassDB::instantiate(type)` → 속성 `set` → 그룹 → `add_child` → 마지막에 `[connection]` 을 `connect` 한다.
  ".tscn 해부" 데모가 `get_state()` 로 이 배열을 그대로 보여 준다 (`tscn_anatomy.gd:91-109`).
- 저장 시에는 `owner` 가 씬 루트인 노드만 기록된다 (`packed_scene.cpp:861 _parse_node`). 그래서 코드로 `add_child` 만 한 노드는 `.tscn` 에 남지 않는다 — "씬 인스턴스화" 데모가 `owner` 를 찍어 보여 준다 (`card.gd:15-19`).

## 함께 읽을 엔진 소스

| 주제 | 파일 | 학습 자료 |
|---|---|---|
| 노드 생명주기: `add_child` → `_propagate_enter_tree`(부모→자식) → `_propagate_ready`(자식→부모) | `scene/main/node.cpp:1711, :341, :323` | [3장 3.3](../../03-servers-and-scene.md) |
| `queue_free` 는 프레임 끝에: `queue_free` → `SceneTree::_flush_delete_queue` | `scene/main/node.cpp:3503`, `scene/main/scene_tree.cpp:1637` | 3장 3.2/3.3 |
| `_process` 분배, `process_frame`, 타이머 | `scene/main/scene_tree.cpp:689 SceneTree::process` | 3장 3.2 |
| 그룹: `call_group`, `get_nodes_in_group`, `group_map` | `scene/main/scene_tree.cpp:362, :1621`, `scene_tree.h` | 3장 3.2 |
| 시그널 저장·방출: `connect`, `emit_signalp` | `core/object/object.cpp:1585, :1256`, `core/object/object.h` | [2장 2.1](../../02-core-layer.md) |
| `.tscn` 파싱과 인스턴스화 | `scene/resources/resource_format_text.cpp:443`, `scene/resources/packed_scene.cpp:222, :861, :2570` | 3장, 9장 Stage 1 실습 |
| 리소스와 캐시 (`Resource` 는 RefCounted, `Node` 는 아님) | `core/io/resource.h`, `core/io/resource_loader.cpp` | 2장 2.1.4 / 2.3 |
| 입력 액션 로드, `get_vector` | `core/input/input_map.cpp:325`, `core/input/input.cpp:586` | 2장 (core/input) |
| 물리 몸체와 영역 | `scene/2d/physics/character_body_2d.cpp:45`, `scene/2d/physics/area_2d.cpp:168 _body_inout` | 3장 3.1.5 |
| CanvasLayer 가 별도 캔버스인 이유 | `scene/main/canvas_layer.cpp` | 3장 3.3 "노드 계층과 서버 RID" |
| 오토로드 등록 순서 (메인 씬보다 먼저, `-s` 스크립트 컴파일보다 **뒤**) | `main/main.cpp:4495` | [1장](../../01-architecture-overview.md) 부팅 순서 |
| `class_name` 전역 캐시 | `core/config/project_settings.cpp get_global_class_list`, `editor/file_system/editor_file_system.cpp:330` | [4장](../../04-modules-and-scripting.md) GDScript |
| `await` 코루틴과 "instance is gone" 오류 | `modules/gdscript/gdscript_function.cpp:283` | 4장 |
| 클래스 레퍼런스 원본 (에디터 F1 도움말) | `doc/classes/Node.xml`, `Node2D.xml`, `Area2D.xml`, `CharacterBody2D.xml`, `SceneTree.xml`, `PackedScene.xml`, `SceneState.xml` | 9장 Stage 1 |

## 연습 과제

1. **몹 종류 추가**: `mob_stats_zigzag.tres` 를 만들고(`MobStats` 에 `@export var wobble: float` 추가), `mob.gd:36 _process` 에서 `wobble` 만큼 좌우로 흔들리게 하세요.
   스포너의 `STATS_POOL` 에 넣기만 하면 나머지는 그대로입니다 — "씬은 하나, 데이터로 변주" 를 체감하는 과제.
2. **최고 점수**: 게임 오버 때 `score` 를 `user://highscore.cfg` 에 `ConfigFile` 로 저장하고 HUD 에 "최고 N" 을 보여 주세요.
   재시작이 **씬 재인스턴스**이므로 값을 어디에 둬야 살아남는지(오토로드? 파일?) 생각해 보세요.
3. **시그널로 결합 풀기**: 지금 `mob.gd:47` 은 `body.call("take_hit")` 로 플레이어 메서드를 직접 부릅니다. 대신 Mob 에 `signal touched(body)` 를 만들고
   스포너가 스폰 직후 `mob.touched.connect(...)` 하도록 바꾼 뒤, `selftest.gd` 에 `has_signal("touched")` 검사를 추가하세요.
4. **`_enter_tree` vs `_ready`**: `player.gd` 에 `_enter_tree()` 를 추가해 `get_node_or_null("CollisionShape2D")` 를 찍어 보세요. `_ready` 와 결과가 다른 이유를
   `node.cpp:341` 과 `:323` 의 순회 방향으로 설명하세요.
5. **F6 단독 실행**: 에디터에서 `game.tscn` 을 열고 F6 으로 실행해 재시작 버튼을 누르면 `reload_current_scene()` 경로(`game.gd:99-102`)가 쓰입니다.
   허브에서 실행했을 때와 로그를 비교하고, 왜 두 경로가 필요한지 적어 보세요.

## 흔한 함정

- **`class_name` 이 다른 스크립트에서 "Could not find type" 이 된다** — 전역 클래스 이름은 에디터가 `.godot/global_script_class_cache.cfg` 를 써 줘야
  보입니다 (`project_settings.cpp get_global_class_list`). 에디터를 한 번도 열지 않고 `--headless` 로만 돌리면 캐시가 없습니다.
  이 프로젝트가 `const MobStatsScript := preload("mob_stats.gd")` 로 타입을 잡는 이유입니다 (`mob.gd:8`, `game.gd:15`). 익스포트된 게임에는 캐시가 포함됩니다.
- **`-s` 스크립트에서 오토로드 이름을 못 쓴다** — `selftest.gd` 는 오토로드가 등록되기 **전에** 컴파일되므로 `Log` 를 직접 쓰면 "Identifier not found",
  `Log` 를 쓰는 스크립트를 `preload` 하면 같이 실패합니다. 트리에서 `get_root().get_node("Log")` 로 찾고, 데모 씬은 테스트 안에서 `load()` 하세요.
- **`await get_tree().create_timer(...)` 뒤에 노드가 사라지면 오류** — `SceneTreeTimer` 는 트리가 소유하므로 노드가 `free` 된 뒤에도 신호를 보내고,
  코루틴이 깨어나며 "Resumed function after await, but class instance is gone" (`gdscript_function.cpp:283`) 을 찍습니다.
  자식 `Timer` 노드를 기다리면(`signals_101.gd:146`) 노드와 함께 사라져 안전하고, 깨어난 뒤에는 `if not is_inside_tree(): return` 을 두세요.
- **`body_entered` 안에서 물리 상태를 바꾸면 오류** — 그 콜백은 물리 서버가 쿼리를 플러시하는 중에 불립니다. `collision_shape.disabled = true` 대신
  `set_deferred("disabled", true)` (`player.gd:53`), 노드 제거는 `queue_free` (`call_group("mobs", "queue_free")`).
- **`queue_free` 직후에도 노드는 살아 있다** — `is_instance_valid()` 가 true, `get_child_count()` 도 그대로. 프레임 끝 `_flush_delete_queue` 에서 지워집니다.
  "씬 인스턴스화" 데모의 `demo_free()` 와 `selftest.gd:184` 가 이 차이를 보여 줍니다. 즉시 지워야 하면 `free()`.
- **형제 이름이 겹치면 `@Node2D@12` 로 바뀐다** — 재시작 때 옛 `Game` 을 먼저 `remove_child` 하는 이유 (`game.gd:112`). 코드로 만든 노드는 `name` 을 주세요.
- **`CanvasLayer` 는 부모를 따라오지 않는다** — 허브 컨테이너 안에서 HUD 가 창 왼쪽 위에 붙는 현상. `offset` 으로 맞춥니다 (`game.gd:40`).
- **뷰포트 크기에 기대지 말 것** — 헤드리스에선 창이 100×100 이고, 허브 안에선 컨테이너가 화면이 아닙니다. 아레나는 상수 `ARENA` (`game.gd:8`).
- **`.tscn` 에 기본값은 저장되지 않는다** — `ScoreTimer` 에 `wait_time` 줄이 없는 것은 기본값 1.0 이기 때문. 파일에 없다고 속성이 없는 게 아닙니다.
- **Godot 3 문법 금지** — `yield`→`await`, `instance()`→`instantiate()`, `connect("sig", obj, "m")`→`sig.connect(obj.m)`, `export var`→`@export var`,
  `KinematicBody2D`→`CharacterBody2D`, `Vector2.zero`→`Vector2.ZERO`, `rand_range`→`randf_range`, `.empty()`→`.is_empty()`.
