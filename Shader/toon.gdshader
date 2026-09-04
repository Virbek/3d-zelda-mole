shader_type spatial;
render_mode blend_mix, cull_back, diffuse_toon, specular_toon;

uniform vec4 albedo_color : source_color = vec4(0.8, 0.5, 0.3, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform bool use_texture = false;

uniform int shade_steps : hint_range(2, 6) = 3;
uniform float shade_softness : hint_range(0.0, 0.5) = 0.05;

uniform vec4 shadow_color : source_color = vec4(0.3, 0.2, 0.2, 1.0);

void fragment() {
	vec4 base_color = albedo_color;
	if (use_texture) {
		base_color = texture(albedo_texture, UV) * albedo_color;
	}
	ALBEDO = base_color.rgb;
}

void light() {
	// Intensité de lumière brute
	float ndotl = dot(NORMAL, LIGHT);

	// Quantification en paliers (cel shading)
	float steps = float(shade_steps);
	float banded = floor(ndotl * steps) / steps;
	banded = smoothstep(0.0, shade_softness, ndotl - banded * (1.0 - shade_softness));
	banded = clamp(banded + floor(ndotl * steps) / steps, 0.0, 1.0);

	vec3 lit_color = mix(shadow_color.rgb * ALBEDO, ALBEDO, banded);

	DIFFUSE_LIGHT += lit_color * ATTENUATION * LIGHT_COLOR;
}