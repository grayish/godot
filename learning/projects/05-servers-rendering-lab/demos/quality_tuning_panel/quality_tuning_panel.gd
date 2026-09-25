extends Control

## 데모 5: 품질 튜닝 패널 — 뷰포트/렌더링 서버의 품질 파라미터를 실시간으로 바꿔 본다.
## 각 컨트롤의 툴팁이 대응하는 프로젝트 설정 키(7장)를 알려 준다. 프로젝트 설정은 "루트 뷰포트의 기본값" 이고,
## 여기서는 SubViewport 에 같은 속성을 직접 준다 (scene/main/viewport.cpp set_scaling_3d_mode 등 → RS.viewport_set_*).
## 뷰포트와 무관한 전역 항목은 RenderingServer 에 직접: directional_shadow_atlas_set_size,
## environment_set_ssao_quality, directional_soft_shadow_filter_set_quality
## (기본값 출처: servers/rendering/rendering_server.cpp RenderingServer::init() GLOBAL_DEF, :3750 근처).
## 헤드리스/gl_compatibility 에서 지원되지 않는 값은 엔진이 조용히 무시하므로 호출 자체는 안전하다.
## 프레임 시간: RS.viewport_set_measure_render_time → servers/rendering/renderer_viewport.cpp:1576, :1583.

const SETTING_KEYS: Dictionary = {
	"scaling_3d_mode": "rendering/scaling_3d/mode",
	"scaling_3d_scale": "rendering/scaling_3d/scale",
	"msaa_3d": "rendering/anti_aliasing/quality/msaa_3d",
	"screen_space_aa": "rendering/anti_aliasing/quality/screen_space_aa",
	"use_taa": "rendering/anti_aliasing/quality/use_taa",
	"use_debanding": "rendering/anti_aliasing/quality/use_debanding",
	"use_occlusion_culling": "rendering/occlusion_culling/use_occlusion_culling",
	"positional_shadow_atlas_size": "rendering/lights_and_shadows/positional_shadow/atlas_size",
	"directional_shadow_size": "rendering/lights_and_shadows/directional_shadow/size",
	"directional_shadow_16_bits": "rendering/lights_and_shadows/directional_shadow/16_bits",
	"directional_soft_shadow_quality": "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",
	"ssao_quality": "rendering/environment/ssao/quality",
	"ssao_half_size": "rendering/environment/ssao/half_size",
	"mesh_lod_threshold": "rendering/mesh_lod/lod_change/threshold_pixels",
	"env_ssao": "rendering/environment/ssao/* (Environment.ssao_enabled 는 리소스 속성)",
	"env_ssil": "rendering/environment/ssil/* (Environment.ssil_enabled)",
	"env_ssr": "rendering/environment/screen_space_reflection/* (Environment.ssr_enabled)",
	"env_glow": "rendering/environment/glow/* (Environment.glow_enabled)",
	"env_fog": "rendering/environment/volumetric_fog/* (Environment.volumetric_fog_enabled)",
	"env_sdfgi": "rendering/global_illumination/sdfgi/* (Environment.sdfgi_enabled)",
	"debug_draw": "rendering/ 키 없음 — Viewport.debug_draw (에디터 뷰포트 디버그 드로우와 동일)",
}
const OBJECT_COUNT: int = 40
const ORBIT_RADIUS: float = 14.0

@onready var sub_viewport: SubViewport = $Layout/ViewportContainer/SubViewport
@onready var camera: Camera3D = $Layout/ViewportContainer/SubViewport/Camera3D
@onready var panel: VBoxContainer = $Layout/Panel/VBox

var environment: Environment
var header_label: Label
var orbit_angle: float = 0.0
var header_timer: float = 0.0
var directional_shadow_size: int = 4096
var shadow_16_bits: bool = true
var ssao_quality: int = RenderingServer.ENV_SSAO_QUALITY_MEDIUM
var ssao_half_size: bool = true


func _ready() -> void:
	_build_scene()
	RenderingServer.viewport_set_measure_render_time(sub_viewport.get_viewport_rid(), true)
	_build_panel()
	_update_header()
	Log.info("각 컨트롤 위에 마우스를 올리면 대응하는 프로젝트 설정 키가 보입니다 (7장 표).")
	Log.info("SSAO/SSIL/SSR/볼류메트릭 안개/SDFGI/FSR2/TAA 는 Forward+ 전용이라 mobile·gl_compatibility 에선 무시됩니다.")
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		Log.warn("현재 렌더링 메서드는 %s 입니다. Forward+ 전용 항목은 효과가 없습니다." % RenderingServer.get_current_rendering_method())


func _exit_tree() -> void:
	# 전역(RS) 설정은 다른 데모에도 영향을 주므로 프로젝트 설정값(= RenderingServer::init 의 GLOBAL_DEF)으로 되돌린다.
	var shadow_key: String = "rendering/lights_and_shadows/directional_shadow/"
	_set_directional_shadow(int(ProjectSettings.get_setting(shadow_key + "size", 4096)), bool(ProjectSettings.get_setting(shadow_key + "16_bits", true)))
	RenderingServer.directional_soft_shadow_filter_set_quality(int(ProjectSettings.get_setting(shadow_key + "soft_shadow_filter_quality", 2)) as RenderingServer.ShadowQuality)
	_set_ssao(int(ProjectSettings.get_setting("rendering/environment/ssao/quality", 2)), bool(ProjectSettings.get_setting("rendering/environment/ssao/half_size", true)))


func _build_scene() -> void:
	$Layout/ViewportContainer/SubViewport/DirectionalLight3D.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.45, 0.47, 0.5)
	plane.material = ground_mat
	ground.mesh = plane
	sub_viewport.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in OBJECT_COUNT:
		var mi := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(float(i) / OBJECT_COUNT, 0.6, 0.9)
		if i % 3 == 0:
			mat.metallic = 0.9
			mat.roughness = 0.15
		else:
			mat.roughness = 0.75
		var height: float = rng.randf_range(0.6, 2.5)
		var primitive: PrimitiveMesh
		if i % 2 == 0:
			var box := BoxMesh.new()
			box.size = Vector3(rng.randf_range(0.6, 1.6), height, rng.randf_range(0.6, 1.6))
			primitive = box
		else:
			var sphere := SphereMesh.new()
			sphere.radius = height * 0.4
			sphere.height = height * 0.8
			primitive = sphere
		primitive.material = mat
		mi.mesh = primitive
		mi.position = Vector3(rng.randf_range(-10.0, 10.0), height * 0.45, rng.randf_range(-10.0, 10.0))
		sub_viewport.add_child(mi)
	for i: int in 3:
		var omni := OmniLight3D.new()
		omni.light_color = Color.from_hsv(i / 3.0, 0.5, 1.0)
		omni.light_energy = 4.0
		omni.omni_range = 12.0
		omni.shadow_enabled = true
		omni.position = Vector3(cos(i * TAU / 3.0) * 6.0, 3.0, sin(i * TAU / 3.0) * 6.0)
		sub_viewport.add_child(omni)
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssr_enabled = true
	environment.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	sub_viewport.add_child(world_env)


func _build_panel() -> void:
	header_label = Label.new()
	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(header_label)
	var method: String = RenderingServer.get_current_rendering_method()
	var scaling_entries: Array = []
	for opt: Dictionary in scaling_mode_options(method, OS.get_name()):
		scaling_entries.append([opt["label"], opt["id"], opt["enabled"]])
	_add_option("3D 스케일링 모드", "scaling_3d_mode", scaling_entries, sub_viewport.scaling_3d_mode, _on_scaling_mode)
	_add_slider("3D 해상도 스케일", "scaling_3d_scale", 0.25, 1.0, 0.05, sub_viewport.scaling_3d_scale,
		func(v: float) -> void: sub_viewport.scaling_3d_scale = v)
	_add_option("MSAA 3D", "msaa_3d", [["Disabled", Viewport.MSAA_DISABLED], ["2x", Viewport.MSAA_2X], ["4x", Viewport.MSAA_4X], ["8x", Viewport.MSAA_8X]],
		sub_viewport.msaa_3d, func(i: int, o: OptionButton) -> void: sub_viewport.msaa_3d = o.get_item_id(i) as Viewport.MSAA)
	_add_option("스크린 스페이스 AA", "screen_space_aa",
		[["Disabled", Viewport.SCREEN_SPACE_AA_DISABLED], ["FXAA", Viewport.SCREEN_SPACE_AA_FXAA], ["SMAA (RD 전용)", Viewport.SCREEN_SPACE_AA_SMAA, method != "gl_compatibility"]],
		sub_viewport.screen_space_aa, func(i: int, o: OptionButton) -> void: sub_viewport.screen_space_aa = o.get_item_id(i) as Viewport.ScreenSpaceAA)
	_add_check("TAA (Forward+ 전용)", "use_taa", sub_viewport.use_taa, func(v: bool) -> void: sub_viewport.use_taa = v)
	_add_check("디밴딩", "use_debanding", sub_viewport.use_debanding, func(v: bool) -> void: sub_viewport.use_debanding = v)
	_add_check("오클루전 컬링", "use_occlusion_culling", sub_viewport.use_occlusion_culling, func(v: bool) -> void: sub_viewport.use_occlusion_culling = v)
	_add_option("포지셔널 그림자 아틀라스", "positional_shadow_atlas_size", [["1024", 1024], ["2048", 2048], ["4096", 4096], ["8192", 8192]],
		sub_viewport.positional_shadow_atlas_size, func(i: int, o: OptionButton) -> void: sub_viewport.positional_shadow_atlas_size = o.get_item_id(i))
	_add_option("방향광 그림자 크기 (RS 전역)", "directional_shadow_size", [["1024", 1024], ["2048", 2048], ["4096", 4096], ["8192", 8192]],
		directional_shadow_size, func(i: int, o: OptionButton) -> void: _set_directional_shadow(o.get_item_id(i), shadow_16_bits))
	_add_check("방향광 그림자 16비트 (RS 전역)", "directional_shadow_16_bits", shadow_16_bits, func(v: bool) -> void: _set_directional_shadow(directional_shadow_size, v))
	_add_option("방향광 소프트 섀도 품질 (RS 전역)", "directional_soft_shadow_quality",
		[["Hard", RenderingServer.SHADOW_QUALITY_HARD], ["Soft Very Low", RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW], ["Soft Low", RenderingServer.SHADOW_QUALITY_SOFT_LOW],
		["Soft Medium", RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM], ["Soft High", RenderingServer.SHADOW_QUALITY_SOFT_HIGH], ["Soft Ultra", RenderingServer.SHADOW_QUALITY_SOFT_ULTRA]],
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, func(i: int, o: OptionButton) -> void: RenderingServer.directional_soft_shadow_filter_set_quality(o.get_item_id(i) as RenderingServer.ShadowQuality))
	_add_option("SSAO 품질 (RS 전역)", "ssao_quality",
		[["Very Low", RenderingServer.ENV_SSAO_QUALITY_VERY_LOW], ["Low", RenderingServer.ENV_SSAO_QUALITY_LOW], ["Medium", RenderingServer.ENV_SSAO_QUALITY_MEDIUM],
		["High", RenderingServer.ENV_SSAO_QUALITY_HIGH], ["Ultra", RenderingServer.ENV_SSAO_QUALITY_ULTRA]],
		ssao_quality, func(i: int, o: OptionButton) -> void: _set_ssao(o.get_item_id(i), ssao_half_size))
	_add_check("SSAO 절반 해상도 (RS 전역)", "ssao_half_size", ssao_half_size, func(v: bool) -> void: _set_ssao(ssao_quality, v))
	_add_check("SSAO", "env_ssao", environment.ssao_enabled, func(v: bool) -> void: environment.ssao_enabled = v)
	_add_check("SSIL", "env_ssil", environment.ssil_enabled, func(v: bool) -> void: environment.ssil_enabled = v)
	_add_check("SSR", "env_ssr", environment.ssr_enabled, func(v: bool) -> void: environment.ssr_enabled = v)
	_add_check("Glow", "env_glow", environment.glow_enabled, func(v: bool) -> void: environment.glow_enabled = v)
	_add_check("볼류메트릭 안개", "env_fog", environment.volumetric_fog_enabled, func(v: bool) -> void: environment.volumetric_fog_enabled = v)
	_add_check("SDFGI", "env_sdfgi", environment.sdfgi_enabled, func(v: bool) -> void: environment.sdfgi_enabled = v)
	_add_slider("메시 LOD 임계값 (px)", "mesh_lod_threshold", 0.0, 8.0, 0.25, sub_viewport.mesh_lod_threshold,
		func(v: float) -> void: sub_viewport.mesh_lod_threshold = v)
	_add_option("디버그 드로우", "debug_draw",
		[["Disabled", Viewport.DEBUG_DRAW_DISABLED], ["Overdraw", Viewport.DEBUG_DRAW_OVERDRAW], ["Wireframe", Viewport.DEBUG_DRAW_WIREFRAME],
		["Shadow Atlas", Viewport.DEBUG_DRAW_SHADOW_ATLAS], ["Directional Shadow Atlas", Viewport.DEBUG_DRAW_DIRECTIONAL_SHADOW_ATLAS],
		["SSAO", Viewport.DEBUG_DRAW_SSAO], ["SSIL", Viewport.DEBUG_DRAW_SSIL], ["Occluders", Viewport.DEBUG_DRAW_OCCLUDERS],
		["Motion Vectors", Viewport.DEBUG_DRAW_MOTION_VECTORS], ["Internal Buffer", Viewport.DEBUG_DRAW_INTERNAL_BUFFER], ["Normal Buffer", Viewport.DEBUG_DRAW_NORMAL_BUFFER]],
		sub_viewport.debug_draw, func(i: int, o: OptionButton) -> void: sub_viewport.debug_draw = o.get_item_id(i) as Viewport.DebugDraw)


func _on_scaling_mode(index: int, option: OptionButton) -> void:
	sub_viewport.scaling_3d_mode = option.get_item_id(index) as Viewport.Scaling3DMode
	Log.info("scaling_3d_mode = %s (FSR2/MetalFX Temporal 은 TAA 와 배타적, 모션 벡터 필요)" % option.get_item_text(index))


func _set_directional_shadow(size: int, bits16: bool) -> void:
	directional_shadow_size = size
	shadow_16_bits = bits16
	RenderingServer.directional_shadow_atlas_set_size(size, bits16)


func _set_ssao(quality: int, half: bool) -> void:
	ssao_quality = quality
	ssao_half_size = half
	# 나머지 인자는 프로젝트 설정 기본값: adaptive_target 0.5, blur_passes 2, fadeout 50..300
	RenderingServer.environment_set_ssao_quality(quality as RenderingServer.EnvironmentSSAOQuality, half, 0.5, 2, 50.0, 300.0)


func _add_row(label_text: String, key: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190, 0)
	var tip: String = "프로젝트 설정: " + String(SETTING_KEYS.get(key, "(없음)"))
	label.tooltip_text = tip
	control.tooltip_text = tip
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	panel.add_child(row)


## entries: [[label, id, enabled?], ...]. 콜백은 (index, option) 을 받는다.
func _add_option(label_text: String, key: String, entries: Array, selected_id: int, callback: Callable) -> void:
	var option := OptionButton.new()
	for i: int in entries.size():
		var e: Array = entries[i]
		option.add_item(String(e[0]), int(e[1]))
		if e.size() > 2 and not bool(e[2]):
			option.set_item_disabled(i, true)
	option.select(option.get_item_index(selected_id))
	option.item_selected.connect(callback.bind(option))
	_add_row(label_text, key, option)


func _add_check(label_text: String, key: String, initial: bool, callback: Callable) -> void:
	var check := CheckBox.new()
	check.button_pressed = initial
	check.toggled.connect(callback)
	_add_row(label_text, key, check)


func _add_slider(label_text: String, key: String, min_v: float, max_v: float, step: float, initial: float, callback: Callable) -> void:
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.value_changed.connect(callback)
	_add_row(label_text, key, slider)


func _process(delta: float) -> void:
	orbit_angle += delta * 0.25
	camera.look_at_from_position(Vector3(cos(orbit_angle) * ORBIT_RADIUS, 7.0, sin(orbit_angle) * ORBIT_RADIUS), Vector3(0.0, 0.5, 0.0))
	header_timer += delta
	if header_timer >= 0.5:
		header_timer = 0.0
		_update_header()


func _update_header() -> void:
	var vp: RID = sub_viewport.get_viewport_rid()
	header_label.text = "method=%s driver=%s\nGPU: %s (%s) API %s\nFPS %d | 렌더 CPU %.2f ms | GPU %.2f ms (viewport_get_measured_render_time_*)" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version(),
		Engine.get_frames_per_second(),
		RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
	]


## 렌더링 메서드/OS 에 따라 고를 수 있는 Viewport.Scaling3DMode 목록 (순수 함수: 셀프테스트가 검사).
static func scaling_mode_options(method: String, os_name: String) -> Array[Dictionary]:
	var apple: bool = os_name == "macOS" or os_name == "iOS"
	var rd: bool = method == "forward_plus" or method == "mobile"
	return [
		{"id": Viewport.SCALING_3D_MODE_BILINEAR, "label": "Bilinear", "enabled": true},
		{"id": Viewport.SCALING_3D_MODE_FSR, "label": "FSR 1.0", "enabled": rd},
		{"id": Viewport.SCALING_3D_MODE_FSR2, "label": "FSR 2.2", "enabled": method == "forward_plus"},
		{"id": Viewport.SCALING_3D_MODE_METALFX_SPATIAL, "label": "MetalFX Spatial", "enabled": rd and apple},
		{"id": Viewport.SCALING_3D_MODE_METALFX_TEMPORAL, "label": "MetalFX Temporal", "enabled": method == "forward_plus" and apple},
		{"id": Viewport.SCALING_3D_MODE_NEAREST, "label": "Nearest", "enabled": true},
	]
