extends CanvasLayer
## HUD. CanvasLayer 는 부모 Node2D 의 트랜스폼을 무시하고 뷰포트 좌표에 그린다
## (엔진: scene/main/canvas_layer.cpp — 자기만의 캔버스 RID 를 RenderingServer 에 만든다).
## 그래서 카메라가 움직여도 점수는 제자리에 있다. 허브 안에서는 game.gd 가 offset 으로 아레나 위치에 맞춘다.

@onready var score_label: Label = $ScoreLabel
@onready var message_label: Label = $MessageLabel
@onready var restart_button: Button = $RestartButton


func update_score(score: int) -> void:
	score_label.text = str(score)


func show_message(text: String) -> void:
	message_label.text = text
	message_label.show()


func hide_message() -> void:
	message_label.hide()


func show_game_over(score: int) -> void:
	show_message("게임 오버! 점수 %d" % score)
	restart_button.show()


func hide_restart() -> void:
	restart_button.hide()
