extends Control

## 데모 4: RenderingDevice(RD) 로 컴퓨트 셰이더 실행 — float 배열의 각 원소를 2배로 만든다.
## 1) 로컬 디바이스: RenderingServer.create_local_rendering_device() — 화면과 무관한 보조 RD.
##    우리가 submit()/sync() 를 직접 부른다. gl_compatibility / headless 에서는 null 이다.
## 2) 메인 디바이스: RenderingServer.get_rendering_device() — 렌더 스레드가 소유한다.
##    RenderingServer.call_on_render_thread() 로 콜러블을 렌더 스레드에 넘겨 실행하고,
##    submit/sync 는 부르지 않는다(프레임 끝에 엔진이 한다).
## 엔진: servers/rendering/rendering_device.cpp storage_buffer_create(:1513) uniform_set_create(:4471)
##       compute_pipeline_create(:5152) compute_list_begin(:6783) compute_list_dispatch(:6935)
##       submit(:8135) sync(:8145) buffer_get_data(:1356) create_local_device(:9286)
##       servers/rendering/rendering_server.cpp:1891 create_local_rendering_device — RD 싱글톤이 없으면 nullptr
##       servers/rendering/rendering_device_binds.h — RDShaderFile / RDShaderSource / RDUniform 스크립트 바인딩
##       servers/rendering/rendering_server_default.h:1230 call_on_render_thread → command_queue.push
##       servers/rendering/rendering_device_graph.h — 배리어는 렌더 그래프가 자동 삽입한다 (6.3 절)

const SHADER_PATH: String = "res://demos/rendering_device_compute/double.glsl"
const LOCAL_SIZE_X: int = 64
const ELEMENT_COUNT: int = 200 # 64 의 배수가 아니어도 셰이더의 length() 가드가 처리한다

var input_data: PackedFloat32Array
var local_result: PackedFloat32Array
var main_result: PackedFloat32Array
var last_elapsed_usec: int = 0
var main_elapsed_usec: int = 0
var output_label: RichTextLabel


func _ready() -> void:
	input_data = make_input(ELEMENT_COUNT)
	_build_ui()
	Log.info("입력 %d개: %s ..." % [input_data.size(), str(input_data.slice(0, 6))])
	Log.info("파이프라인: 셰이더(SPIR-V) → 스토리지 버퍼 → RDUniform/uniform set → compute pipeline → compute list → dispatch")
	_on_local_pressed()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var local_button := Button.new()
	local_button.text = "로컬 RD 로 실행 (create_local_rendering_device)"
	local_button.pressed.connect(_on_local_pressed)
	row.add_child(local_button)
	var main_button := Button.new()
	main_button.text = "메인 RD 로 실행 (call_on_render_thread)"
	main_button.pressed.connect(_on_main_pressed)
	row.add_child(main_button)
	output_label = RichTextLabel.new()
	output_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(output_label)
	_refresh_output()


func _on_local_pressed() -> void:
	local_result = run_local_compute(input_data)
	if local_result.is_empty():
		Log.info("로컬 RD 경로를 건너뛰었습니다. CPU 참조 결과: %s ..." % str(cpu_double(input_data).slice(0, 6)))
	else:
		Log.info("로컬 RD 출력: %s ... (%d us, CPU 참조와 일치: %s)" % [str(local_result.slice(0, 6)), last_elapsed_usec, str(local_result == cpu_double(input_data))])
	_refresh_output()


func _on_main_pressed() -> void:
	if run_main_device_compute():
		Log.info("메인 RD: 콜러블을 렌더 스레드 큐에 넣었습니다. 결과는 call_deferred 로 돌아옵니다.")
	_refresh_output()


## 로컬 디바이스에서 실행. RD 가 없으면 빈 배열을 돌려준다 (헤드리스 셀프테스트가 이 경로를 검사한다).
func run_local_compute(input: PackedFloat32Array) -> PackedFloat32Array:
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	if rd == null:
		Log.warn("RenderingDevice 사용 불가 (gl_compatibility 또는 headless)")
		return PackedFloat32Array()
	Log.info("로컬 RD 생성: %s / %s" % [rd.get_device_name(), rd.get_device_vendor_name()])
	var result: PackedFloat32Array = _dispatch_double(rd, input, true)
	# 로컬 디바이스는 우리가 memnew 한 Object 다. RID 를 모두 반납한 뒤 free() 로 정리한다.
	rd.free()
	return result


## 메인 디바이스에서 실행. 렌더 스레드 소유이므로 call_on_render_thread 로 넘긴다. RD 가 없으면 false.
func run_main_device_compute() -> bool:
	if RenderingServer.get_rendering_device() == null:
		Log.warn("메인 RenderingDevice 없음 (gl_compatibility 또는 headless) — 렌더 스레드 실행을 건너뜁니다")
		return false
	# thread_model=Safe(기본) 이면 서버 스레드 == 메인 스레드라 즉시 실행되고,
	# Separate 이면 CommandQueueMT 에 들어가 렌더 스레드에서 실행된다. 어느 쪽이든 RD 접근은 안전하다.
	RenderingServer.call_on_render_thread(_on_render_thread)
	return true


func _on_render_thread() -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		return
	var t0: int = Time.get_ticks_usec()
	main_result = _dispatch_double(rd, input_data, false)
	main_elapsed_usec = Time.get_ticks_usec() - t0
	# UI 갱신은 메인 스레드에서: Callable.call_deferred 는 MessageQueue 를 거치므로 스레드 안전하다.
	_show_main_result.call_deferred()


func _show_main_result() -> void:
	if not is_inside_tree():
		return
	Log.info("메인 RD 출력: %s ... (%d us, 일치: %s)" % [str(main_result.slice(0, 6)), main_elapsed_usec, str(main_result == cpu_double(input_data))])
	_refresh_output()


## 셰이더 RID 를 만든다. 에디터가 임포트해 둔 RDShaderFile 이 있으면 그것을, 없으면 GLSL 원문을 런타임 컴파일한다.
func _create_shader(rd: RenderingDevice) -> RID:
	var spirv: RDShaderSPIRV = null
	if ResourceLoader.exists(SHADER_PATH, "RDShaderFile"):
		var shader_file: RDShaderFile = load(SHADER_PATH)
		if shader_file != null:
			spirv = shader_file.get_spirv()
	if spirv == null:
		var source := RDShaderSource.new()
		source.source_compute = extract_stage_source(FileAccess.get_file_as_string(SHADER_PATH), "compute")
		spirv = rd.shader_compile_spirv_from_source(source) # glslang → SPIR-V (modules/glslang)
	if spirv == null:
		Log.warn("SPIR-V 를 얻지 못했습니다")
		return RID()
	if not spirv.compile_error_compute.is_empty():
		Log.warn("컴퓨트 셰이더 컴파일 오류: " + spirv.compile_error_compute)
		return RID()
	return rd.shader_create_from_spirv(spirv)


func _dispatch_double(rd: RenderingDevice, input: PackedFloat32Array, own_submit: bool) -> PackedFloat32Array:
	var shader: RID = _create_shader(rd)
	if not shader.is_valid():
		return PackedFloat32Array()
	var bytes: PackedByteArray = input.to_byte_array()
	var buffer: RID = rd.storage_buffer_create(bytes.size(), bytes)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0 # GLSL: layout(set = 0, binding = 0)
	uniform.add_id(buffer)
	var uniforms: Array[RDUniform] = [uniform]
	var uniform_set: RID = rd.uniform_set_create(uniforms, shader, 0) # set = 0
	var pipeline: RID = rd.compute_pipeline_create(shader)
	var t0: int = Time.get_ticks_usec()
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, ceili(float(input.size()) / LOCAL_SIZE_X), 1, 1)
	rd.compute_list_end()
	if own_submit:
		rd.submit() # 로컬 디바이스: 명령 버퍼 제출
		rd.sync() # GPU 완료 대기. 메인 디바이스에서는 절대 부르지 않는다(엔진이 프레임마다 한다).
	# buffer_get_data 는 스테이징 버퍼로 GPU→CPU 복사 후 반환 (메인 디바이스에서는 내부적으로 플러시/대기).
	var output: PackedFloat32Array = rd.buffer_get_data(buffer).to_float32_array()
	last_elapsed_usec = Time.get_ticks_usec() - t0
	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)
	rd.free_rid(buffer)
	rd.free_rid(shader)
	return output


func _refresh_output() -> void:
	if output_label == null:
		return
	var text: String = "[b]입력[/b] (%d개): %s ...\n" % [input_data.size(), str(input_data.slice(0, 8))]
	text += "[b]CPU 참조[/b]: %s ...\n" % str(cpu_double(input_data).slice(0, 8))
	text += "[b]로컬 RD[/b]: %s\n" % ("(사용 불가)" if local_result.is_empty() else "%s ... %d us" % [str(local_result.slice(0, 8)), last_elapsed_usec])
	text += "[b]메인 RD[/b]: %s\n" % ("(아직 없음 / 사용 불가)" if main_result.is_empty() else "%s ... %d us" % [str(main_result.slice(0, 8)), main_elapsed_usec])
	text += "\nget_rendering_device() = %s\n" % ("null" if RenderingServer.get_rendering_device() == null else "있음 (렌더 스레드 소유)")
	text += "rendering_method = %s, driver = %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()]
	output_label.text = text


static func make_input(n: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(n)
	for i: int in n:
		data[i] = i * 0.5
	return data


static func cpu_double(input: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(input.size())
	for i: int in input.size():
		out[i] = input[i] * 2.0
	return out


## RD 셰이더 파일에서 "#[stage]" 섹션의 본문만 잘라 낸다 (RDShaderFile::parse_versions_from_text 의 축소판).
static func extract_stage_source(text: String, stage: String) -> String:
	var collecting: bool = false
	var out := PackedStringArray()
	for line: String in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#[") and stripped.ends_with("]"):
			collecting = stripped.substr(2, stripped.length() - 3).strip_edges() == stage
			continue
		if collecting:
			out.append(line)
	return "\n".join(out).strip_edges()
