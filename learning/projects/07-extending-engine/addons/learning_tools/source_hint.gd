extends RefCounted

## 클래스 이름 → 엔진 소스 경로 추정 (휴리스틱). 플러그인 독, 인스펙터 플러그인, SourceHintLabel2D,
## selftest 가 공유한다. class_name 을 쓰지 않는 이유: 명령행(--headless)에서 .godot/ 캐시가 없으면
## 전역 클래스 이름이 해석되지 않으므로 preload() 로 참조한다.
##
## 규칙 (엔진 소스 트리의 배치 관례):
##   Control 계열 → scene/gui/,  Node2D 계열 → scene/2d/,  Node3D 계열 → scene/3d/,
##   Resource 계열 → scene/resources/,  그 외(Node, Object 등) → scene/main/
## 파일 이름은 클래스 이름의 snake_case + ".h" (예: CharacterBody2D → character_body_2d.h).
## 예외는 많다(물리 노드는 scene/2d/physics/, Resource 는 core/io/resource.h 등) — 그래서 "힌트"다.
## 상속 사슬은 core/object/class_db.cpp ClassDB::get_parent_class() 로 ClassInfo.inherits 를 따라간다.

const ROOT_MAP: Array[Array] = [
	["Control", "scene/gui/"],
	["Node2D", "scene/2d/"],
	["Node3D", "scene/3d/"],
	["Resource", "scene/resources/"],
]
const DEFAULT_DIR: String = "scene/main/"


## 클래스에서 Object 까지의 상속 사슬. 알 수 없는 클래스면 [cls] 만 돌려준다
## (ClassDB.get_parent_class 는 모르는 클래스에 ERR_FAIL 을 찍으므로 먼저 존재를 확인한다).
static func inheritance_chain(cls: String) -> Array[String]:
	var chain: Array[String] = []
	var current: String = cls
	while not current.is_empty():
		chain.append(current)
		if not ClassDB.class_exists(current):
			break
		current = String(ClassDB.get_parent_class(current))
	return chain


static func engine_dir_for(cls: String) -> String:
	if not ClassDB.class_exists(cls):
		return DEFAULT_DIR
	for pair: Array in ROOT_MAP:
		var root: String = pair[0]
		# is_parent_class(class, inherits): inherits 가 class 의 조상인가.
		if cls == root or ClassDB.is_parent_class(cls, root):
			return pair[1]
	return DEFAULT_DIR


static func engine_source_path(cls: String) -> String:
	return engine_dir_for(cls) + cls.to_snake_case() + ".h"


static func doc_xml_path(cls: String) -> String:
	return "doc/classes/" + cls + ".xml"


## 이 프로젝트는 엔진 저장소 안(learning/projects/<dir>/)에 있으므로 세 단계 위가 저장소 루트다.
static func repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../..").simplify_path()


## 추정 경로가 저장소에 실제로 존재하는지. 저장소 밖에서 쓰면 항상 false.
static func exists_in_repo(relative_path: String) -> bool:
	return FileAccess.file_exists(repo_root().path_join(relative_path))


static func describe(cls: String) -> Dictionary:
	var source: String = engine_source_path(cls)
	var doc: String = doc_xml_path(cls)
	return {
		"class": cls,
		"chain": inheritance_chain(cls),
		"source": source,
		"source_exists": exists_in_repo(source),
		"doc": doc,
		"doc_exists": exists_in_repo(doc),
	}


## 독/인스펙터에 쓰는 여러 줄 요약.
static func describe_text(cls: String) -> String:
	var d: Dictionary = describe(cls)
	var chain: Array[String] = d["chain"]
	var lines: PackedStringArray = PackedStringArray()
	lines.append("클래스: " + String(d["class"]))
	lines.append("상속: " + " > ".join(chain))
	lines.append("엔진 소스(추정): " + String(d["source"]) + (" [있음]" if bool(d["source_exists"]) else " [추정]"))
	lines.append("문서 XML: " + String(d["doc"]) + (" [있음]" if bool(d["doc_exists"]) else " [추정]"))
	return "\n".join(lines)
