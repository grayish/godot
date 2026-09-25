extends ColorRect
## 카드. scene_instancing 데모가 여러 번 인스턴스화하는 작은 씬 (Unity 프리팹에 해당, 8장 8.2).
## @export 변수는 add_child 전에 넣어 두면 _ready 에서 바로 쓸 수 있다.

@export var title: String = "카드"
@export var number: int = 0
@export var card_color: Color = Color(0.25, 0.3, 0.45, 1)

@onready var title_label: Label = $Title


func _ready() -> void:
	color = card_color
	title_label.text = "%s\n#%d" % [title, number]
	# owner: 이 노드가 "어느 씬 파일에 속하는가". 인스턴스화된 씬의 루트는 owner 가 없고(null),
	# 그 자식(Title)의 owner 는 루트(Card)다. PackedScene.pack() 은 owner 가 루트인 노드만 저장한다
	# (엔진: scene/resources/packed_scene.cpp SceneState::_parse_node).
	Log.info("Card._ready: %s | path=%s | owner=%s | Title.owner=%s" % [
		title, get_path(), str(owner), str(title_label.owner)])
