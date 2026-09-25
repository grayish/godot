class_name MobStats
extends Resource
## 몹 스탯 리소스. 같은 mob.tscn 에 다른 .tres 를 꽂으면 다른 몹이 된다 ("데이터는 리소스, 행동은 씬").
## Resource 는 RefCounted 라 참조가 0 이 되면 사라지고, 같은 경로는 ResourceCache 로 한 번만 로드된다
## (엔진: core/io/resource.h, core/io/resource_loader.cpp). Node 는 그렇지 않다 — 부모가 소유한다.
## .tres 는 텍스트 리소스 포맷(scene/resources/resource_format_text.cpp)으로 저장되며, 헤더의
## script_class="MobStats" 가 이 class_name 이다.
##
## 주의: class_name 으로 만든 전역 이름은 에디터가 .godot/global_script_class_cache.cfg 를 만들어야
## 다른 스크립트에서 타입으로 보인다 (엔진: core/config/project_settings.cpp get_global_class_list()).
## 헤드리스/명령행만으로 돌릴 때도 동작하도록 다른 스크립트는 preload 상수(MobStatsScript)로 이 타입을 가리킨다.

@export var display_name: String = "mob"
## 몹이 발사될 때 [speed_min, speed_max] 사이에서 임의 속도를 고른다 (픽셀/초).
@export var speed_min: float = 150.0
@export var speed_max: float = 250.0
@export var color: Color = Color(1, 1, 1, 1)
