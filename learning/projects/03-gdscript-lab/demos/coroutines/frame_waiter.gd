class_name FrameWaiter
extends RefCounted
## 데모 3 과 selftest 가 함께 쓰는 정적 코루틴 모음. UI 도, Log 오토로드도 쓰지 않는다.
## (selftest 는 -s 로 실행되어 preload 가 오토로드 등록보다 먼저 컴파일되므로, 여기서 Log 를 쓰면 컴파일이 실패한다.)
## 엔진: scene/main/scene_tree.cpp SceneTree::process() 가 매 프레임 process_frame 을 emit 하고,
##       gdscript_vm.cpp OPCODE_AWAIT 가 그 시그널에 GDScriptFunctionState 를 ONE_SHOT 으로 연결한다.


## n 프레임을 기다린 뒤 실제로 기다린 프레임 수를 돌려준다. static 이라 인스턴스 없이도 코루틴이 된다.
static func wait_frames(tree: SceneTree, n: int) -> int:
	var waited: int = 0
	for _i: int in n:
		await tree.process_frame
		waited += 1
	return waited


## seconds 만큼 SceneTreeTimer 로 기다리고 실제 경과 밀리초를 돌려준다.
static func wait_seconds(tree: SceneTree, seconds: float) -> int:
	var t0: int = Time.get_ticks_msec()
	await tree.create_timer(seconds).timeout
	return Time.get_ticks_msec() - t0
