// Outfit material with a "dye": recolours the pale linen in an outfit texture
// (T_Peasant_BaseColor: the shirt, blouse and sleeves) to any colour, leaving
// leather, wool, metal and skin alone. One texture, as many villager colours
// as we like.
//
// How: for each pixel, convert its colour to HSV (hue, saturation, value).
// Pale, unsaturated pixels count as linen. Those get the dye's hue and
// saturation but keep their own relative brightness, so folds, seams and
// shading survive.
//
// Otherwise it does what Godot's StandardMaterial3D does with a glTF material:
// base colour, normal map, and ORM (occlusion, roughness, metallic packed
// into the R, G, B channels of one texture).
shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec3 dye_color : source_color = vec3(0.3, 0.45, 0.2);
uniform float dye_strength : hint_range(0.0, 1.0) = 1.0;
// What counts as linen: brighter than this value (0..1)...
uniform float linen_min_value = 0.45;
// ...and less saturated than this.
uniform float linen_max_saturation = 0.4;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb;
	// source_color textures arrive in linear space (good for lighting maths),
	// but "pale" and "saturated" are judged in the sRGB colours an artist sees,
	// so convert for the comparison and back for the result.
	vec3 hsv = rgb2hsv(pow(base, vec3(1.0 / 2.2)));
	// Soft thresholds, so the dye fades in rather than leaving speckles at
	// the borders between linen and leather.
	float mask = smoothstep(linen_min_value - 0.1, linen_min_value + 0.05, hsv.z)
		* (1.0 - smoothstep(linen_max_saturation - 0.1, linen_max_saturation + 0.05, hsv.y))
		* dye_strength;
	vec3 dye = rgb2hsv(pow(dye_color, vec3(1.0 / 2.2)));
	dye.y *= 0.85;  // plant dyes on linen are never fully saturated
	// Keep the cloth's relative brightness: typical linen (value ~0.75) comes
	// out at the dye's own brightness, folds darker, highlights lighter.
	vec3 dyed = pow(hsv2rgb(vec3(dye.x, dye.y, clamp(hsv.z / 0.75 * dye.z, 0.0, 1.0))), vec3(2.2));
	ALBEDO = mix(base, dyed, mask);

	vec3 orm = texture(orm_texture, UV).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
}
