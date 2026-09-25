extends Control

## 데모 6: 셰이더 파이프라인 — 셰이더 파일, #include, 세 종류의 유니폼, 셰이더 RID 와 파라미터 목록.
## 엔진: scene/resources/shader.cpp _check_shader_rid(:52) — Shader 리소스는 처음 필요할 때
##       RS.shader_create_from_code 로 RID 를 만든다 (지연 생성, 3.6 절). set_code(:83) → shader_set_code.
##       scene/resources/material.cpp:420 ShaderMaterial::set_shader_parameter → RS.material_set_param
##       scene/3d/visual_instance_3d.cpp:421 GeometryInstance3D::set_instance_shader_parameter
##       servers/rendering/shader_preprocessor.cpp / shader_language.cpp / shader_compiler.cpp — 컴파일 사슬
##       servers/rendering/renderer_rd/shader_rd.cpp:610 — 셰이더 캐시 경로 (user://shader_cache), 변형 병렬 컴파일
##       drivers/gles3/shader_gles3.cpp — GL 은 glCompileShader + glGetProgramBinary 캐시

const WAVE_SHADER: String = "res://demos/shader_pipeline/wave.gdshader"
const PULSE_SHADER: String = "res://demos/shader_pipeline/pulse.gdshader"
const RUNTIME_GLOBAL: StringName = &"lab_runtime_tint"
const RUNTIME_SHADER_CODE: String = """shader_type canvas_item;
global uniform vec4 lab_runtime_tint : source_color;
void fragment() {
	COLOR = vec4(lab_runtime_tint.rgb * (0.4 + 0.6 * UV.x), 1.0);
}
"""

var wave_material: ShaderMaterial
var pulse_material: ShaderMaterial
var runtime_material: ShaderMaterial
var runtime_rect: ColorRect
var meshes: Array[MeshInstance3D] = []
var elapsed: float = 0.0
var info_timer: float = 0.0
var wave_height: float = 0.15
var added_runtime_global: bool = false
var info_label: RichTextLabel
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 11
	# 런타임 전역 유니폼. 셰이더가 참조하기 전에 등록해야 하므로 셰이더를 만들기 전에 추가한다.
	# 같은 이름이 이미 있으면(데모를 다시 열었을 때) global_shader_parameter_add 가 오류를 내므로 목록으로 확인.
	if not RenderingServer.global_shader_parameter_get_list().has(RUNTIME_GLOBAL):
		RenderingServer.global_shader_parameter_add(RUNTIME_GLOBAL, RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.2, 0.9, 0.6, 1.0))
		added_runtime_global = true
	_build_3d()
	_build_ui()
	_refresh_info()
	Log.info("lab_time 은 project.godot [shader_globals] 에 선언된 전역 유니폼이고 매 프레임 global_shader_parameter_set 으로 갱신합니다.")
	Log.info("%s 은 런타임에 global_shader_parameter_add 로 추가한 전역 유니폼입니다 (코드로 만든 Shader 가 참조)." % RUNTIME_GLOBAL)
	Log.info("셰이더 캐시: rendering/shader_compiler/shader_cache/enabled=%s, 경로 %s" % [
		str(ProjectSettings.get_setting("rendering/shader_compiler/shader_cache/enabled", true)),
		OS.get_user_data_dir().path_join("shader_cache")])


func _exit_tree() -> void:
	# 전역 유니폼을 참조하는 셰이더를 먼저 놓은 뒤 전역을 제거한다.
	runtime_rect.material = null
	runtime_material = null
	if added_runtime_global:
		RenderingServer.global_shader_parameter_remove(RUNTIME_GLOBAL)


func _build_3d() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.offset_right = -360.0
	add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	container.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(0.0, 3.5, 6.0), Vector3(0.0, 0.3, 0.0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	viewport.add_child(light)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var wave_shader: Shader = load(WAVE_SHADER)
	wave_material = ShaderMaterial.new()
	wave_material.shader = wave_shader
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.6, 1.6)
	mesh.subdivide_width = 24
	mesh.subdivide_depth = 24
	var colors: Array[Color] = [Color(1.0, 0.4, 0.3), Color(0.3, 0.9, 0.5), Color(0.4, 0.5, 1.0)]
	for i: int in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = wave_material # 세 개가 같은 머티리얼(같은 material RID)을 공유한다
		mi.position = Vector3((i - 1) * 2.0, 0.0, 0.0)
		viewport.add_child(mi)
		mi.set_instance_shader_parameter("inst_color", colors[i]) # 그런데 색은 인스턴스마다 다르다
		meshes.append(mi)


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = -350.0
	box.anchor_left = 1.0
	add_child(box)
	var pulse_shader: Shader = load(PULSE_SHADER)
	pulse_material = ShaderMaterial.new()
	pulse_material.shader = pulse_shader
	var pulse_rect := ColorRect.new()
	pulse_rect.custom_minimum_size = Vector2(0, 110)
	pulse_rect.material = pulse_material
	box.add_child(pulse_rect)
	# 코드로 만든 셰이더: 런타임 전역 유니폼을 참조한다 (전역을 add 한 뒤에 만들었으므로 컴파일 가능).
	var runtime_shader := Shader.new()
	runtime_shader.code = RUNTIME_SHADER_CODE
	runtime_material = ShaderMaterial.new()
	runtime_material.shader = runtime_shader
	runtime_rect = ColorRect.new()
	runtime_rect.custom_minimum_size = Vector2(0, 60)
	runtime_rect.material = runtime_material
	box.add_child(runtime_rect)
	var row := HBoxContainer.new()
	box.add_child(row)
	var uniform_button := Button.new()
	uniform_button.text = "일반 유니폼"
	uniform_button.tooltip_text = "ShaderMaterial.set_shader_parameter"
	uniform_button.pressed.connect(_on_uniform_pressed)
	row.add_child(uniform_button)
	var instance_button := Button.new()
	instance_button.text = "인스턴스 유니폼"
	instance_button.tooltip_text = "GeometryInstance3D.set_instance_shader_parameter"
	instance_button.pressed.connect(_on_instance_pressed)
	row.add_child(instance_button)
	var global_button := Button.new()
	global_button.text = "전역 유니폼"
	global_button.tooltip_text = "RenderingServer.global_shader_parameter_set"
	global_button.pressed.connect(_on_global_pressed)
	row.add_child(global_button)
	info_label = RichTextLabel.new()
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(info_label)


func _on_uniform_pressed() -> void:
	wave_height = 0.05 if wave_height > 0.1 else 0.25
	wave_material.set_shader_parameter("wave_height", wave_height)
	pulse_material.set_shader_parameter("tint", Color.from_hsv(rng.randf(), 0.7, 0.9))
	Log.info("set_shader_parameter: wave_height=%.2f — 머티리얼 RID 하나의 파라미터라 세 메시가 함께 바뀝니다." % wave_height)
	_refresh_info()


func _on_instance_pressed() -> void:
	for mi: MeshInstance3D in meshes:
		mi.set_instance_shader_parameter("inst_color", Color.from_hsv(rng.randf(), 0.7, 0.95))
	Log.info("set_instance_shader_parameter: 머티리얼은 그대로, 인스턴스별 버퍼(instance uniform) 만 갱신됩니다.")
	_refresh_info()


func _on_global_pressed() -> void:
	RenderingServer.global_shader_parameter_set(RUNTIME_GLOBAL, Color.from_hsv(rng.randf(), 0.8, 0.95))
	Log.info("global_shader_parameter_set: 전역 버퍼 하나를 바꾸면 그것을 참조하는 모든 셰이더가 함께 바뀝니다.")
	_refresh_info()


func _process(delta: float) -> void:
	elapsed += delta
	RenderingServer.global_shader_parameter_set(&"lab_time", elapsed)
	info_timer += delta
	if info_timer >= 1.0:
		info_timer = 0.0
		_refresh_info()


func _refresh_info() -> void:
	if info_label == null:
		return
	var text: String = ""
	for shader: Shader in [wave_material.shader, pulse_material.shader, runtime_material.shader]:
		text += "[b]%s[/b] mode=%s rid=%s\n" % [shader.resource_path.get_file() if not shader.resource_path.is_empty() else "(코드로 생성)", _mode_name(shader.get_mode()), str(shader.get_rid())]
		for param: Dictionary in RenderingServer.get_shader_parameter_list(shader.get_rid()):
			text += "   uniform %s (Variant.Type %d)\n" % [param["name"], int(param["type"])]
	text += "\nShaderMaterial rid: %s\n" % str(wave_material.get_rid())
	for i: int in meshes.size():
		text += "메시 %d inst_color = %s\n" % [i, str(meshes[i].get_instance_shader_parameter("inst_color"))]
	text += "\n전역 유니폼 목록: %s\n" % str(RenderingServer.global_shader_parameter_get_list())
	text += "lab_time = %s\n" % str(RenderingServer.global_shader_parameter_get(&"lab_time"))
	text += "%s = %s" % [RUNTIME_GLOBAL, str(RenderingServer.global_shader_parameter_get(RUNTIME_GLOBAL))]
	info_label.text = text


func _mode_name(mode: Shader.Mode) -> String:
	match mode:
		Shader.MODE_SPATIAL:
			return "spatial"
		Shader.MODE_CANVAS_ITEM:
			return "canvas_item"
		Shader.MODE_PARTICLES:
			return "particles"
		Shader.MODE_SKY:
			return "sky"
		Shader.MODE_FOG:
			return "fog"
	return str(mode)
