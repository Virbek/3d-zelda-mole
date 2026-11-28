shader_type spatial;
render_mode blend_mix, cull_back, diffuse_toon, specular_toon;

uniform vec4 albedo_color : source_color = vec4(0.8, 0.5, 0.3, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform bool use_texture = false;

uniform int shade_steps : hint_range(2, 6) = 3;
uniform float shade_softness : hint_range(0.0, 0.5) = 0.05;

uniform vec4 shadow_color : source_color = vec4(0.3, 0.2, 0.2, 1.0);
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.2;

// --- Stylisation ---
// Ombres froides / lumières chaudes : la partie à l'ombre glisse de
// shadow_color vers shadow_tint, la partie éclairée prend light_tint.
uniform vec4 shadow_tint : source_color = vec4(0.3, 0.26, 0.6, 1.0);
uniform vec4 light_tint : source_color = vec4(1.08, 1.0, 0.88, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 1.0;
// Liseré clair sur les bords côté lumière. Désactivé par défaut : sur un
// grand sol vu en rasant, il éclaircirait tout. Les personnages l'activent
// (ToonBuilder.toon_material(..., rim = true)).
uniform vec4 rim_color : source_color = vec4(1.0, 0.86, 0.6, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rim_width : hint_range(0.0, 1.0) = 0.5;

// Salissures du décor : pied des volumes plus sombre, grandes taches de
// rouille en aplats et grain fin, calculés en coordonnées monde (pas de
// texture). Réservé aux objets fixes : sur un objet qui bouge, le motif
// glisserait. Activé par ToonBuilder.toon_material(..., grime = true).
uniform float grime : hint_range(0.0, 1.0) = 0.0;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13) * 0.3 + vnoise(p * 4.7) * 0.15;
}

void fragment() {
	vec4 base_color = albedo_color;
	if (use_texture) {
		base_color = texture(albedo_texture, UV) * albedo_color;
	}
	vec3 col = base_color.rgb;
	if (grime > 0.0) {
		// Pied des volumes plus sombre (sable tassé), haut plus clair
		float h = smoothstep(0.0, 2.5, v_world.y);
		col *= mix(1.0, mix(0.68, 1.08, h), grime);
		// Grandes taches de rouille, en aplats (toon : pas de dégradé doux)
		float n = fbm(v_world * vec3(0.9, 0.55, 0.9));
		float stain = step(0.58, n) * 0.55 + step(0.68, n) * 0.45;
		col = mix(col, col * vec3(0.82, 0.55, 0.38), stain * 0.6 * grime);
		// Grain fin, quantifié en trois niveaux
		float grain = floor(vnoise(v_world * 7.0) * 3.0) / 2.0;
		col *= mix(1.0, 0.9 + 0.14 * grain, grime);
	}
	ALBEDO = col;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);

	float steps = float(shade_steps);
	float banded = floor(ndotl * steps) / steps;
	banded = smoothstep(0.0, shade_softness, ndotl - banded * (1.0 - shade_softness));
	banded = clamp(banded + floor(ndotl * steps) / steps, 0.0, 1.0);

	vec3 shade = mix(shadow_color.rgb, shadow_tint.rgb, tint_amount) * ALBEDO;
	vec3 lit_col = ALBEDO * mix(vec3(1.0), light_tint.rgb, tint_amount);

	// Liseré : bord de la silhouette, côté éclairé ou rasant
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = step(rim_width, fres) * smoothstep(-0.3, 0.2, ndotl) * rim_amount * 0.9;

	if (LIGHT_IS_DIRECTIONAL) {
		// Soleil : ATTENUATION ne contient que l'ombre portée. On la traite
		// comme une bande de plus du dégradé toon : une zone à l'ombre prend
		// la teinte d'ombre au lieu de tomber au noir complet.
		float lit = max(banded * ATTENUATION, ambient_floor);
		vec3 col = mix(mix(shade, lit_col, lit), rim_color.rgb, rim);
		DIFFUSE_LIGHT += col * LIGHT_COLOR;
	} else {
		// Lampes locales : ATTENUATION porte aussi la portée, on la garde
		vec3 col = mix(mix(shade, lit_col, max(banded, ambient_floor)), rim_color.rgb, rim);
		DIFFUSE_LIGHT += col * ATTENUATION * LIGHT_COLOR;
	}
}
