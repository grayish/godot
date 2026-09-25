class_name GuiProbe
extends Control
## Control 에 붙여 _gui_input 호출을 보고하는 탐침. 스크립트의 base 가 Control 이라 Button, Panel 등 어떤 Control 서브클래스에도
## set_script() 로 붙일 수 있다.
## 엔진: scene/main/viewport.cpp Viewport::_gui_call_input() → scene/gui/control.cpp Control::_call_gui_input():
##   gui_input 시그널 → (handled 아니면) GDVIRTUAL _gui_input → (handled 아니면) C++ gui_input() (BaseButton 의 클릭 처리 등).
## 다른 파일에서는 class_name 대신 preload() 로 참조한다.

## (who: String, event: InputEvent) 로 보고한다.
var sink: Callable = Callable()


func _gui_input(event: InputEvent) -> void:
	if sink.is_valid():
		sink.call(String(name), event)
