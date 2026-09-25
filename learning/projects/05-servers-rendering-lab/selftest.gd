extends SceneTree

## 헤드리스 셀프테스트: godot --headless --path <dir> -s res://selftest.gd
## 프레임이 필요한 테스트(물리 step, call_deferred 된 _draw)를 위해 테스트를 코루틴으로 한 번에 하나씩 실행한다.
## 엔진: 헤드리스 = DisplayServerHeadless + RasterizerDummy (servers/rendering/dummy/). RID 는 발급되지만
##       그리지 않고, RenderingDevice 는 없다. 물리(GodotPhysics2D)와 오디오(AudioDriverDummy)는 실제로 돈다.

const PROJECT_DIR: String = "05-servers-rendering-lab"
const CANVAS_DEMO: String = "res://demos/rs_canvas_2d/rs_canvas_2d.tscn"
const PHYSICS_DEMO: String = "res://demos/physics_server_direct/physics_server_direct.tscn"
const COMPUTE_SCRIPT: String = "res://demos/rendering_device_compute/rendering_device_compute.gd"
const COMPUTE_GLSL: String = "res://demos/rendering_device_compute/double.glsl"
const QUALITY_SCRIPT: String = "res://demos/quality_tuning_panel/quality_tuning_panel.gd"
const RS3D_SCRIPT: String = "res://demos/rs_no_nodes_3d/rs_no_nodes_3d.gd"
const SHADER_FILES: Array[String] = ["res://demos/shader_pipeline/wave.gdshader", "res://demos/shader_pipeline/pulse.gdshader"]

var tests: Array[Callable] = []
var failures: Array[String] = []
var index: int = 0
var busy: bool = false
var log_received: int = 0


func _initialize() -> void:
	tests = [
		_test_log_autoload,
		_test_rs_instance_rids,
		_test_rs_canvas_item,
		_test_physics_body_falls,
		_test_rendering_device_null,
		_test_compute_helpers,
		_test_rendering_method,
		_test_audio_server,
		_test_shader_files,
		_test_quality_helpers,
		_test_rs3d_transform_helper,
		_test_canvas_demo_draw_count,
		_test_physics_demo_scene,
	]
	print("SELFTEST start: %d tests" % tests.size())


func _process(_delta: float) -> bool:
	if busy:
		return false
	if index >= tests.size():
		_finish()
		return true
	busy = true
	_run(tests[index])
	index += 1
	return false


## 코루틴이든 아니든 await 로 끝날 때까지 기다린 뒤 다음 테스트로 넘어간다.
func _run(test: Callable) -> void:
	print("-- " + test.get_method())
	await test.call()
	busy = false


func _check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   " + what)
	else:
		failures.append(what)
		print("  FAIL " + what)


func _finish() -> void:
	if failures.is_empty():
		print("SELFTEST PASS " + PROJECT_DIR)
		quit(0)
	else:
		print("SELFTEST FAIL " + PROJECT_DIR + ": " + str(failures))
		quit(1)


func _test_log_autoload() -> void:
	# -s 로 실행되는 이 스크립트는 오토로드 전역 상수가 등록되기 전에 컴파일되므로 `Log` 식별자를 직접 쓸 수 없다.
	# 대신 root 아래의 노드를 찾아 동적으로 부른다 (main/main.cpp Main::start() "Load Autoloads").
	var log_node: Node = get_root().get_node_or_null("Log")
	_check(log_node != null, "Log 오토로드가 root 아래에 있음")
	if log_node == null:
		return
	log_node.connect("message", func(_text: String, _level: int) -> void: log_received += 1)
	log_node.call("info", "selftest info")
	log_node.call("warn", "selftest warn")
	log_node.call("section", "selftest section")
	_check(log_received == 3, "Log.info/warn/section 이 message 시그널을 3회 발생")


func _test_rs_instance_rids() -> void:
	var inst: RID = RenderingServer.instance_create()
	_check(inst.is_valid(), "RS.instance_create() RID 유효 (더미 래스터라이저도 RID 발급)")
	var mesh := BoxMesh.new()
	RenderingServer.instance_set_scenario(inst, get_root().find_world_3d().scenario)
	RenderingServer.instance_set_base(inst, mesh.get_rid())
	RenderingServer.instance_set_transform(inst, Transform3D(Basis(), Vector3(1, 2, 3)))
	RenderingServer.free_rid(inst)
	_check(true, "instance_set_scenario/base/transform + free_rid 오류 없음")


func _test_rs_canvas_item() -> void:
	var holder := Control.new()
	get_root().add_child(holder)
	var item: RID = RenderingServer.canvas_item_create()
	_check(item.is_valid(), "RS.canvas_item_create() RID 유효")
	RenderingServer.canvas_item_set_parent(item, holder.get_canvas_item())
	RenderingServer.canvas_item_add_rect(item, Rect2(0, 0, 10, 10), Color.RED)
	RenderingServer.canvas_item_add_circle(item, Vector2(5, 5), 4.0, Color.BLUE)
	RenderingServer.canvas_item_add_line(item, Vector2.ZERO, Vector2(10, 10), Color.WHITE, 2.0)
	RenderingServer.canvas_item_add_polygon(item, PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(5, 10)]), PackedColorArray([Color.GREEN]))
	RenderingServer.canvas_item_set_transform(item, Transform2D(0.5, Vector2(3, 3)))
	RenderingServer.canvas_item_clear(item)
	RenderingServer.free_rid(item)
	holder.free()
	_check(true, "canvas_item_add_rect/circle/line/polygon + set_transform + clear + free_rid 오류 없음")


func _test_physics_body_falls() -> void:
	var space: RID = get_root().find_world_2d().space
	var shape: RID = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 8.0)
	var body: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_space(body, space)
	var start := Vector2(100, 100)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, start))
	var ground: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(ground, PhysicsServer2D.BODY_MODE_STATIC)
	var rect: RID = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(rect, Vector2(200, 10))
	PhysicsServer2D.body_add_shape(ground, rect)
	PhysicsServer2D.body_set_space(ground, space)
	PhysicsServer2D.body_set_state(ground, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(100, 400)))
	# Main::iteration 이 매 물리 틱 PhysicsServer2D::step() 을 돌린다 (헤드리스에서도).
	for i: int in 6:
		await physics_frame
	var xf: Transform2D = PhysicsServer2D.body_get_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM)
	_check(xf.origin.y > start.y, "중력으로 y 증가: %.2f → %.2f" % [start.y, xf.origin.y])
	var query := PhysicsRayQueryParameters2D.create(Vector2(300, 100), Vector2(300, 600))
	var hit: Dictionary = get_root().find_world_2d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit["rid"] == ground, "direct_space_state.intersect_ray 가 정적 바닥 RID 에 맞음")
	PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(ground)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(rect)


func _test_rendering_device_null() -> void:
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	_check(rd == null, "헤드리스: create_local_rendering_device() == null")
	_check(RenderingServer.get_rendering_device() == null, "헤드리스: get_rendering_device() == null")
	var script: GDScript = load(COMPUTE_SCRIPT)
	var demo: Object = script.new()
	var output: PackedFloat32Array = demo.call("run_local_compute", PackedFloat32Array([1.0, 2.0]))
	_check(output.is_empty(), "데모 코드가 RD null 을 경고만 하고 빈 결과를 반환")
	_check(demo.call("run_main_device_compute") == false, "메인 RD null → 렌더 스레드 실행을 건너뜀(false)")
	demo.free()


func _test_compute_helpers() -> void:
	var script: GDScript = load(COMPUTE_SCRIPT)
	var demo: Object = script.new()
	var text: String = FileAccess.get_file_as_string(COMPUTE_GLSL)
	var source: String = demo.call("extract_stage_source", text, "compute")
	_check(source.begins_with("#version 450"), "GLSL compute 섹션 추출: #version 450 로 시작")
	_check(source.contains("local_size_x = 64"), "compute 섹션에 local_size_x = 64")
	var has_header: bool = false
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#["):
			has_header = true
	_check(not has_header, "섹션 헤더 줄은 제거됨")
	_check(demo.call("extract_stage_source", text, "vertex") == "", "없는 섹션은 빈 문자열")
	var input: PackedFloat32Array = demo.call("make_input", 5)
	var doubled: PackedFloat32Array = demo.call("cpu_double", input)
	_check(doubled.size() == 5 and is_equal_approx(doubled[4], input[4] * 2.0), "CPU 참조 구현이 2배")
	demo.free()


func _test_rendering_method() -> void:
	var method: String = RenderingServer.get_current_rendering_method()
	print("  rendering_method=%s driver=%s adapter='%s' vendor='%s' api='%s' display=%s" % [
		method, RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(), DisplayServer.get_name()])
	_check(not method.is_empty(), "get_current_rendering_method() 가 비어 있지 않음")
	_check(DisplayServer.get_name() == "headless", "DisplayServer 는 headless")


func _test_audio_server() -> void:
	_check(AudioServer.get_bus_count() >= 1, "AudioServer.get_bus_count() >= 1 (Master)")
	print("  audio driver=%s mix_rate=%.0f latency=%.4f" % [AudioServer.get_driver_name(), AudioServer.get_mix_rate(), AudioServer.get_output_latency()])
	var before: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(before, "SelfTestBus")
	AudioServer.add_bus_effect(before, AudioEffectReverb.new())
	AudioServer.set_bus_volume_db(before, -3.0)
	_check(AudioServer.get_bus_index("SelfTestBus") == before, "add_bus + set_bus_name → get_bus_index")
	_check(AudioServer.get_bus_effect_count(before) == 1, "add_bus_effect(AudioEffectReverb) 1개")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(before), -3.0), "set_bus_volume_db 반영")
	var player := AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.1
	player.stream = generator
	player.bus = "SelfTestBus"
	get_root().add_child(player)
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	_check(playback != null, "AudioStreamGeneratorPlayback 획득 (더미 드라이버에서도 동작)")
	if playback != null:
		var pushed: bool = playback.push_frame(Vector2(0.1, 0.1))
		_check(pushed and playback.get_frames_available() >= 0, "push_frame / get_frames_available")
	player.stop()
	player.free()
	AudioServer.remove_bus(before)
	_check(AudioServer.bus_count == before, "remove_bus 로 원상 복구")


func _test_shader_files() -> void:
	for path: String in SHADER_FILES:
		var shader: Shader = load(path)
		_check(shader is Shader, path.get_file() + " 은 Shader 리소스")
		var params: Array[Dictionary] = RenderingServer.get_shader_parameter_list(shader.get_rid())
		_check(params.size() >= 2, path.get_file() + " get_shader_parameter_list 에 uniform %d개" % params.size())
	var wave: Shader = load(SHADER_FILES[0])
	var pulse: Shader = load(SHADER_FILES[1])
	_check(wave.get_mode() == Shader.MODE_SPATIAL and pulse.get_mode() == Shader.MODE_CANVAS_ITEM, "get_mode(): spatial / canvas_item")
	var include: Resource = load("res://demos/shader_pipeline/common.gdshaderinc")
	_check(include is ShaderInclude, "common.gdshaderinc 는 ShaderInclude")
	_check(RenderingServer.global_shader_parameter_get_list().has(&"lab_time"), "project.godot [shader_globals] lab_time 이 등록됨")


func _test_quality_helpers() -> void:
	var script: GDScript = load(QUALITY_SCRIPT)
	var demo: Object = script.new()
	var keys: Dictionary = demo.get("SETTING_KEYS")
	var all_ok: bool = true
	for key: String in keys:
		if not String(keys[key]).begins_with("rendering/"):
			all_ok = false
	_check(keys.size() >= 12 and all_ok, "툴팁 설정 키 %d개가 모두 rendering/ 로 시작" % keys.size())
	var gl: Array = demo.call("scaling_mode_options", "gl_compatibility", "Linux")
	var fp_mac: Array = demo.call("scaling_mode_options", "forward_plus", "macOS")
	var fp_linux: Array = demo.call("scaling_mode_options", "forward_plus", "Linux")
	_check(not gl[1]["enabled"] and not gl[2]["enabled"], "gl_compatibility: FSR/FSR2 비활성")
	_check(fp_linux[2]["enabled"] and not fp_linux[4]["enabled"], "forward_plus/Linux: FSR2 활성, MetalFX Temporal 비활성")
	_check(fp_mac[4]["enabled"], "forward_plus/macOS: MetalFX Temporal 활성")
	demo.free()


func _test_rs3d_transform_helper() -> void:
	var script: GDScript = load(RS3D_SCRIPT)
	var demo: Object = script.new()
	var a: Transform3D = demo.call("compute_transform", 0, 100, 0.0)
	var b: Transform3D = demo.call("compute_transform", 1, 100, 0.0)
	var c: Transform3D = demo.call("compute_transform", 0, 100, 1.0)
	_check(a.origin != b.origin, "인덱스가 다르면 위치가 다름")
	_check(a.basis != c.basis, "시간이 다르면 회전이 다름")
	_check(is_equal_approx(a.basis.determinant(), 1.0), "basis 는 순수 회전 (det = 1)")
	demo.free()


func _test_canvas_demo_draw_count() -> void:
	var packed: PackedScene = load(CANVAS_DEMO)
	var demo: Node = packed.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame
	var first: int = demo.call("get_draw_count")
	_check(first >= 1, "_draw 최초 호출 %d회 (트리 진입 시 queue_redraw)" % first)
	await process_frame
	await process_frame
	_check(demo.call("get_draw_count") == first, "queue_redraw 없이는 _draw 가 다시 불리지 않음")
	demo.call("request_redraw")
	await process_frame
	await process_frame
	_check(demo.call("get_draw_count") == first + 1, "queue_redraw() 후 _draw 정확히 1회 추가")
	demo.queue_free()
	await process_frame


func _test_physics_demo_scene() -> void:
	var packed: PackedScene = load(PHYSICS_DEMO)
	var demo: Node = packed.instantiate()
	get_root().add_child(demo)
	for i: int in 12:
		await physics_frame
	var positions: PackedVector2Array = demo.call("get_server_ball_local_positions")
	var spawns: PackedVector2Array = demo.call("get_server_ball_spawn_positions")
	_check(positions.size() >= 6 and spawns.size() == positions.size(), "서버 공 %d개 생성" % positions.size())
	if not positions.is_empty():
		_check(positions[0].y > spawns[0].y, "서버 공 #0 이 중력으로 낙하: %.1f → %.1f" % [spawns[0].y, positions[0].y])
	var hit: String = demo.call("get_last_hit")
	_check(hit != "-" and hit != "없음", "레이캐스트 명중: " + hit)
	demo.queue_free()
	await process_frame
