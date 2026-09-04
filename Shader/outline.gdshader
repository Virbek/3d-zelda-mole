shader_type spatial;
render_mode cull_front, unshaded, diffuse_lambert, depth_draw_always;

uniform float outline_width : hint_range(0.0, 0.05) = 0.01;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}