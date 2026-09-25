#[compute]
#version 450

// Godot RD 셰이더 파일: 첫 줄의 스테이지 섹션 헤더(#[ 스테이지 이름 ]) 뒤에 일반 GLSL 450 이 온다.
// 에디터는 editor/import/resource_importer_shader_file.cpp 가 RDShaderFile 로 임포트(glslang → SPIR-V)하고,
// 임포트가 없으면 데모 코드가 이 섹션을 잘라 RDShaderSource 로 런타임 컴파일한다.
// 파서: servers/rendering/rendering_device_binds.cpp RDShaderFile::parse_versions_from_text(:40)

// 워크그룹 64 스레드. GDScript 에서 compute_list_dispatch(ceil(n / 64), 1, 1).
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

// std430 스토리지 버퍼: set 0, binding 0 → RDUniform.binding = 0, uniform_set_create(..., shader, 0).
layout(set = 0, binding = 0, std430) restrict buffer DataBuffer {
	float data[];
}
data_buffer;

void main() {
	uint idx = gl_GlobalInvocationID.x;
	// n 이 64 의 배수가 아닐 때 마지막 워크그룹의 남는 스레드를 걸러 낸다.
	if (idx >= data_buffer.data.length()) {
		return;
	}
	data_buffer.data[idx] *= 2.0;
}
