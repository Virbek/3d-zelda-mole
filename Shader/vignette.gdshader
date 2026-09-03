shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float softness : hint_range(0.0, 1.0) = 0.55;
uniform vec4 tint : source_color = vec4(0.5, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv) * 1.414;
	float v = smoothstep(1.0 - softness, 1.0, d);
	COLOR = vec4(tint.rgb, v * intensity);
}