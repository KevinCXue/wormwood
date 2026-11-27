// The forest spirit's skin: near-black bark with a sickly green glow round
// its edges, a slow writhing in the twigs, and a noise "dissolve" used for
// the smoky tail and for crumbling away when it dies. See forest_spirit.gd.
//
// A shader is a small program the GPU runs for every vertex (vertex()) and
// every pixel (fragment()) of the mesh. Uniforms are its parameters, set
// from code or the Inspector, like arguments to a function.
shader_type spatial;

uniform vec3 bark_color : source_color = vec3(0.022, 0.02, 0.018);
uniform vec3 glow_color : source_color = vec3(0.45, 0.95, 0.55);
uniform float rim_strength = 0.35;  // how bright the edge glow is
uniform float rim_power = 4.0;      // higher = a thinner edge
uniform float vein_strength = 0.9;  // glowing cracks running through the bark
uniform float writhe = 0.03;        // metres the surface sways
uniform float dissolve = 0.0;       // 0 = whole, 1 = gone (death)
// Fade the mesh out towards UV.y = 1 (the tail's tip): 0 = off.
uniform float tail_fade = 0.0;
uniform float flicker = 0.0;        // 0..1 extra glow (pulses, being hit)

varying vec3 world_pos;

// Cheap value noise, so the shader needs no texture.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Each part sways a little out of step with its neighbours.
	VERTEX += NORMAL * writhe * sin(TIME * 3.1 + w.x * 4.0 + w.y * 5.0 + w.z * 3.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Vertical streaks of bark: stretch the noise along Y.
	float grain = noise(world_pos * vec3(9.0, 1.5, 9.0));
	float speck = noise(world_pos * 22.0);
	ALBEDO = bark_color * (0.6 + 0.9 * grain) + vec3(0.02, 0.03, 0.02) * speck;
	ROUGHNESS = 0.95;

	// Holes: the tail thins into smoke, and death eats it away.
	float n = noise(world_pos * 6.0 + vec3(0.0, TIME * 0.8, 0.0));
	float gone = max(dissolve, tail_fade * UV.y);
	if (n < gone) {
		discard;
	}

	// Edge glow (fresnel: bright where the surface turns away from the
	// camera), flickering, plus a burning edge around dissolving holes.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float pulse = 0.75 + 0.25 * sin(TIME * 2.3 + world_pos.y * 3.0);
	float burn = smoothstep(gone + 0.08, gone, n) * step(0.001, gone);
	// Veins: thin lines where stretched noise crosses one value, like light
	// leaking through cracks in the bark.
	float v = noise(world_pos * vec3(7.0, 1.6, 7.0) + vec3(0.0, TIME * 0.15, 0.0));
	float vein = smoothstep(0.025, 0.0, abs(v - 0.5));
	// `flicker` (winding up, being hit) makes the cracks and edges flare,
	// not the whole body.
	float flare = pulse + flicker * 3.0;
	EMISSION = glow_color * (fresnel * rim_strength * flare + vein * vein_strength * flare
		+ burn * 2.0);
}
