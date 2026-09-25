extends Control

## 데모 3: 기여 워크플로우 체크리스트 (저장소 루트 CONTRIBUTING.md + 9장 Stage 7 요약).
## 버튼/링크는 OS.shell_open 으로 브라우저를 연다 — 헤드리스(DisplayServer "headless")에서는 열 수 없으므로 경고만 남긴다.
## 엔진: core/os/os.h OS::shell_open() → 플랫폼별 구현 (platform/linuxbsd/os_linuxbsd.cpp 는 xdg-open 실행).
##       .pre-commit-config.yaml — clang-format, ruff, file-format, header-guards, copyright-headers, doc-status, make-rst 훅.

const CHECKLIST: Array[String] = [
	"[b]1. 버그 리포트[/b] — 이슈 트래커에 최소 재현 프로젝트(MRP, .godot 제외)와 함께. 최신 stable/dev 스냅샷에서 재현되는지, 회귀(regression)면 어느 버전부터인지 적는다.",
	"[b]2. 기능 제안[/b] — 메인 이슈 트래커는 기능 제안을 받지 않는다. godot-proposals 저장소에 먼저 제안하고 합의를 얻는다.",
	"[b]3. 브랜치[/b] — master 에서 토픽 브랜치 하나 = 주제 하나. 리뷰 후 커밋은 squash. 다른 개발자와 구현 방향을 먼저 이야기한다 (Rocket.Chat).",
	"[b]4. 코드 스타일[/b] — .clang-format 을 따르고 prek/pre-commit 훅(.pre-commit-config.yaml)을 설치한다: clang-format, ruff, file_format.py, header_guards.py, copyright_headers.py.",
	"[b]5. 문서 XML[/b] — 새 클래스/메서드는 doc/classes/*.xml (모듈은 modules/<m>/doc_classes/). `bin/godot --doctool .` 로 골격을 생성/병합하고 설명을 채운다. doc-status 훅이 빈 설명을 잡는다.",
	"[b]6. 단위 테스트[/b] — tests/ 의 doctest 케이스 (`scons tests=yes` 후 `bin/godot --test`). 모듈은 modules/<m>/tests/*.h 를 SCsub 에서 env[\"tests\"] 로 묶는다 (modules/jsonrpc/SCsub). GDScript 통합 테스트는 modules/gdscript/tests/scripts/.",
	"[b]7. PR[/b] — 템플릿에 따라 무엇을/왜 바꿨는지, 닫는 이슈 번호를 적는다. CI(정적 검사·빌드·테스트)가 통과해야 리뷰가 시작된다. 문서 변경은 godot-docs 저장소로.",
]

const LINKS: Array[Dictionary] = [
	{"title": "Contributing docs (전체)", "url": "https://contributing.godotengine.org/en/latest/index.html"},
	{"title": "PR 워크플로우", "url": "https://contributing.godotengine.org/en/latest/development/workflows/creating_pull_requests.html"},
	{"title": "C++ 사용 지침 (코드 스타일)", "url": "https://contributing.godotengine.org/en/latest/development/engine/cpp_usage_guidelines.html"},
	{"title": "리뷰 프로세스", "url": "https://contributing.godotengine.org/en/latest/development/workflows/review_guidelines.html"},
	{"title": "엔진 개발 가이드 (docs)", "url": "https://docs.godotengine.org/en/latest/engine_details/development/index.html"},
	{"title": "단위 테스트 작성", "url": "https://docs.godotengine.org/en/latest/engine_details/architecture/unit_testing.html"},
	{"title": "godot-proposals", "url": "https://github.com/godotengine/godot-proposals"},
]

var _text: RichTextLabel


static func can_open_urls() -> bool:
	# 헤드리스 DisplayServer 에는 브라우저를 띄울 셸이 없다고 본다 (servers/display_server_headless.h).
	return DisplayServer.get_name() != "headless"


func _ready() -> void:
	_build_ui()
	Log.info("체크리스트 %d항목, 링크 %d개. 원본: 저장소 루트 CONTRIBUTING.md, learning/09-learning-roadmap.md Stage 7" % [CHECKLIST.size(), LINKS.size()])
	if not can_open_urls():
		Log.warn("헤드리스 모드: 버튼/링크는 URL 을 로그로만 출력합니다 (OS.shell_open 생략).")


func _build_ui() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.selection_enabled = true
	# [url] 태그 클릭 → meta_clicked(meta) — meta 는 url 문자열.
	_text.meta_clicked.connect(_on_meta_clicked)
	box.add_child(_text)
	_text.append_text("[b]Godot 기여 체크리스트[/b] (CONTRIBUTING.md 요약)\n\n")
	for item: String in CHECKLIST:
		_text.append_text(item + "\n\n")
	_text.append_text("[b]관련 문서[/b]\n")
	for link: Dictionary in LINKS:
		_text.append_text("• [url=%s]%s[/url]\n" % [String(link["url"]), String(link["title"])])

	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(260, 0)
	box.add_child(buttons)
	var header := Label.new()
	header.text = "문서 열기"
	buttons.add_child(header)
	for link: Dictionary in LINKS:
		var button := Button.new()
		button.text = String(link["title"])
		button.pressed.connect(_open_url.bind(String(link["url"])))
		buttons.add_child(button)


func _on_meta_clicked(meta: Variant) -> void:
	_open_url(String(meta))


func _open_url(url: String) -> void:
	if not can_open_urls():
		Log.warn("브라우저를 열 수 없는 환경입니다. URL: " + url)
		return
	# OS.shell_open 은 Error 를 돌려준다 (core/error/error_list.h). OK 가 아니면 원인을 로그로 남긴다.
	var err: Error = OS.shell_open(url)
	if err == OK:
		Log.info("브라우저로 열기: " + url)
	else:
		Log.warn("shell_open 실패 (%s): %s" % [error_string(err), url])
