// 캔버스(canvas_item) 셰이더: 같은 include 와 같은 전역 유니폼을 2D 에서 쓴다.
shader_type canvas_item;

#include "res://demos/shader_pipeline/common.gdshaderinc"

global uniform float lab_time;
uniform vec4 tint : source_color = vec4(0.9, 0.4, 0.2, 1.0);
uniform float stripes = 8.0;

void fragment() {
	float band = step(0.5, fract(UV.y * stripes + lab_time));
	vec3 rainbow = lab_palette(UV.x + lab_time * 0.1);
	COLOR = vec4(mix(tint.rgb, rainbow, band), 1.0);
}
