// 공간(spatial) 셰이더: 정점을 파도처럼 움직이고 인스턴스별 색을 칠한다.
// 컴파일 사슬 (6.5 절): 이 파일 → ShaderPreprocessor(#include) → ShaderLanguage(AST, shader_language.cpp:11534)
//   → ShaderCompiler(GLSL 조각, shader_compiler.cpp:1558) → ShaderRD 템플릿 삽입(renderer_rd/shader_rd.cpp)
//   → glslang(SPIR-V) → 드라이버 컨테이너 → 파이프라인. GL 은 drivers/gles3/shader_gles3.cpp 가 직접 컴파일.
shader_type spatial;

#include "res://demos/shader_pipeline/common.gdshaderinc"

// 전역 유니폼: project.godot [shader_globals] 에 선언, RenderingServer.global_shader_parameter_set 으로 갱신.
global uniform float lab_time;
// 일반 유니폼: ShaderMaterial.set_shader_parameter → RS.material_set_param (scene/resources/material.cpp:420)
uniform float wave_height = 0.15;
uniform float wave_speed = 2.0;
// 인스턴스 유니폼: 같은 머티리얼을 공유하면서 GeometryInstance3D 마다 다른 값.
// scene/3d/visual_instance_3d.cpp:421 set_instance_shader_parameter → RS.instance_geometry_set_shader_parameter
instance uniform vec4 inst_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	VERTEX.y += wave_height * sin(lab_time * wave_speed + VERTEX.x * 4.0 + VERTEX.z * 2.0);
}

void fragment() {
	ALBEDO = inst_color.rgb * mix(0.6, 1.0, lab_pulse(lab_time));
	ROUGHNESS = 0.35;
	METALLIC = 0.1;
}
