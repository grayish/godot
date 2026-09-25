// 공용 셰이더 함수. #include 는 ShaderPreprocessor 가 처리한다.
// 엔진: servers/rendering/shader_preprocessor.cpp:1368 preprocess() — ShaderInclude 리소스는
//       scene/resources/shader_include.cpp 가 로드하고, 포함된 파일이 바뀌면 셰이더가 재컴파일된다.

float lab_pulse(float t) {
	return 0.5 + 0.5 * sin(t * 2.0);
}

vec3 lab_palette(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (vec3(1.0, 1.0, 1.0) * t + vec3(0.0, 0.33, 0.67)));
}
