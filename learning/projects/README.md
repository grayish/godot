# 학습 단계별 실습 프로젝트

`learning/09-learning-roadmap.md`의 Stage 1~7에 하나씩 대응하는 **실행 가능한 Godot 프로젝트**입니다.
각 프로젝트는 그 단계에서 배우는 개념을 "눌러 보고, 로그로 확인하고, 소스 경로를 따라갈 수 있게" 만든 데모 모음입니다.

| 단계 | 디렉터리 | 다루는 개념 | 데모 | 함께 읽을 장 |
|---|---|---|---|---|
| 1 | [`01-first-game`](01-first-game/README.md) | 노드 트리 · 씬 인스턴스 · 시그널 · 그룹 · 리소스(.tres) · 입력 액션 · .tscn 텍스트 형식. 완성된 2D 닷지 게임 포함 | 4 (+게임) | 9장 Stage 1, 8장 8.2 |
| 2 | [`02-scene-tree-lab`](02-scene-tree-lab/README.md) | `_enter_tree`/`_ready` 순서, process vs physics, `call_deferred`와 MessageQueue, 그룹·알림, 입력 전파, `PackedScene`/`SceneState` | 6 | 1장 1.4, 3장 3.2~3.4 |
| 3 | [`03-gdscript-lab`](03-gdscript-lab/README.md) | 정적 타이핑 벤치마크(validated opcode), Variant/Callable/Signal 값, 코루틴(await), 클래스 시스템, `Expression`·리플렉션, 에러 처리 | 6 | 4장 4.2, 2장 2.3 |
| 4 | [`04-core-lab`](04-core-lab/README.md) | ClassDB 브라우저, Object 모델·ObjectDB, RefCounted/소유권, Variant 내부(COW), 리소스 로더/세이버 플러그인, 파일/OS, 스레드·WorkerThreadPool | 7 | 2장 |
| 5 | [`05-servers-rendering-lab`](05-servers-rendering-lab/README.md) | 노드 없이 RenderingServer로 그리기, 캔버스 아이템, PhysicsServer2D 직접 사용, RenderingDevice 컴퓨트 셰이더, 품질 튜닝 패널, 셰이더 파이프라인, AudioServer | 7 | 3장 3.1/3.6/3.7, 6장, 7장 |
| 6 | [`06-platform-lab`](06-platform-lab/README.md) | OS/DisplayServer 정보와 기능 태그, 설정 오버라이드, 입력 장치·리매핑, PCK 패킹/로딩, 창·디스플레이, 익스포트 프리셋, 헤드리스 스크립트 | 6 (+도구 2) | 5장, 7장 7.6 |
| 7 | [`07-extending-engine`](07-extending-engine/README.md) | 에디터 플러그인(dock/inspector/custom type/export plugin), 커스텀 C++ 모듈 골격, godot-cpp GDExtension 소스, `@tool` 스크립트, 기여 체크리스트 | 3 (+addon, module, gdextension) | 4장 4.1/4.6, 2장 2.7, 9장 Stage 7 |

## 공통 구조

```
NN-<slug>/
├── project.godot      # config_version=5, 메인 씬 main.tscn, 오토로드 Log, 1280x720
├── README.md          # 목적 · 실행법 · 데모 설명 · 함께 읽을 엔진 소스 · 연습 과제 · 흔한 함정
├── main.tscn/main.gd  # 데모 허브: 왼쪽 버튼 목록, 오른쪽 데모 영역, 아래 로그 패널
├── log.gd             # 오토로드 "Log": Log.info/warn/section → 콘솔 출력 + message 시그널
├── demos/<name>/      # 데모별 <name>.tscn + <name>.gd (독립적, 각 ~250줄 이하)
└── selftest.gd        # 헤드리스 셀프테스트 (SceneTree 스크립트): SELFTEST PASS/FAIL 출력 후 종료
```

- 모든 에셋은 텍스트(.tscn/.tres/.gdshader)입니다. 바이너리 파일이 없어 diff 로 읽을 수 있습니다.
- 스크립트는 정적 타이핑과 탭 들여쓰기를 쓰고, 주석에 관련 엔진 소스 경로를 적어 두었습니다 (예: `# 엔진: scene/main/node.cpp _propagate_ready()`).
- Godot **4.4+ API** 기준으로 작성했고, 이 저장소의 4.8 dev 빌드로 검증했습니다.

## 실행 방법

**에디터에서**: Project Manager → Import → 해당 디렉터리의 `project.godot` → Edit → F5.

**명령행에서** (저장소 루트 기준, `godot`은 4.4 이상 바이너리):

```bash
godot --path learning/projects/02-scene-tree-lab                      # 허브 실행
godot --headless --path learning/projects/02-scene-tree-lab -s res://selftest.gd   # 셀프테스트
godot --path learning/projects/05-servers-rendering-lab --rendering-method mobile  # 렌더러 바꿔 보기
```

**전체 검증** (헤드리스 빌드로도 동작합니다. 0장 참고: `scons platform=linuxbsd target=editor`):

```bash
for d in learning/projects/0*/; do
	learning/projects/tools/verify.sh "$d" bin/godot.linuxbsd.editor.x86_64 | tail -1
done
```

`tools/verify.sh`는 (1) `selftest.gd`, (2) 허브 씬 5프레임, (3) 모든 `.gd` 컴파일 검사 + 모든 데모 씬 인스턴스화(`tools/demo_runner.gd`)를 순서대로 실행하고, `SCRIPT ERROR`/`ERROR:` 가 한 줄이라도 나오면 실패로 처리합니다.

## 프로젝트를 만들며 확인한 흔한 함정

- **`class_name`은 에디터가 만든 캐시가 있어야 전역 이름으로 보입니다.** `.godot/global_script_class_cache.cfg` 가 없는 상태(에디터를 한 번도 열지 않고 `--headless -s` 로 실행)에서는 `Identifier not found`가 납니다. 그래서 프로젝트들은 파일 간 참조에 `preload()` 상수를 씁니다. 에디터에서 열면 `class_name`도 정상 동작합니다.
- **`-s` 로 실행하는 SceneTree 스크립트는 오토로드보다 먼저 컴파일됩니다.** `selftest.gd` 안에서 `Log` 같은 오토로드 이름을 직접 쓰면 컴파일 오류가 나므로 `get_root().get_node("Log")` 또는 런타임 `load()` 를 씁니다 (`main/main.cpp` `Main::start` 의 오토로드 등록 시점 참고).
- **헤드리스 빌드에는 RenderingDevice가 없습니다.** `RenderingServer.get_rendering_device()` / `create_local_rendering_device()` 가 `null` 을 돌려주므로 컴퓨트 데모는 이를 확인하고 안내만 출력합니다. 더미 래스터라이저도 RID 는 정상적으로 발급합니다.
- **`await` 뒤에 노드가 이미 해제되었을 수 있습니다.** 데모가 닫힌 뒤 코루틴이 재개되면 오류가 나므로 `await` 다음에는 `is_inside_tree()` 를 확인합니다.
- **`push_error()`는 진짜 오류에만.** 헤드리스에서 예상되는 제약(창 없음, 조이패드 없음)은 `Log.warn` 으로 처리해야 검증 스크립트가 통과합니다.
