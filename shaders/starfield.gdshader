// Procedural starfield sky shader.
// Generates multi-layered stars and a faint nebula gradient using
// hashed grid cells in spherical coordinates. No textures required.
shader_type sky;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 hsv2rgb(vec3 c) {
	vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), rgb, c.y);
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	float lon = atan(dir.x, dir.z);
	float lat = asin(clamp(dir.y, -1.0, 1.0));
	vec2 uv = vec2(lon, lat) * 200.0;

	// ---- Layer 1: dim small stars ----
	vec2 g1 = floor(uv);
	vec2 f1 = fract(uv) - 0.5;
	float h1 = hash21(g1);
	float star1 = 0.0;
	if (h1 > 0.94) {
		vec2 off = vec2(hash21(g1 + 1.7), hash21(g1 + 3.1)) - 0.5;
		float d = length(f1 - off * 0.7);
		star1 = (1.0 - smoothstep(0.0, 0.04, d)) * (0.3 + h1 * 0.4);
	}

	// ---- Layer 2: bright stars ----
	vec2 uv2 = uv * 0.4;
	vec2 g2 = floor(uv2);
	vec2 f2 = fract(uv2) - 0.5;
	float h2 = hash21(g2 + 5.0);
	float star2 = 0.0;
	vec3 star2_color = vec3(1.0);
	if (h2 > 0.985) {
		vec2 off = vec2(hash21(g2 + 7.7), hash21(g2 + 11.3)) - 0.5;
		float d = length(f2 - off * 0.6);
		float intensity = 1.0 - smoothstep(0.0, 0.06, d);
		float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + h2 * 3.0) + h2 * 6.28);
		star2 = intensity * twinkle;
		float hue = hash21(g2 + 9.1);
		star2_color = hsv2rgb(vec3(hue, 0.4, 1.0));
	}

	// ---- Layer 3: large soft glowing stars ----
	vec2 uv3 = uv * 0.12;
	vec2 g3 = floor(uv3);
	vec2 f3 = fract(uv3) - 0.5;
	float h3 = hash21(g3 + 13.0);
	float star3 = 0.0;
	if (h3 > 0.992) {
		vec2 off = vec2(hash21(g3 + 17.0), hash21(g3 + 19.0)) - 0.5;
		float d = length(f3 - off * 0.5);
		star3 = (1.0 - smoothstep(0.0, 0.15, d)) * 0.6;
	}

	// ---- Nebula clouds ----
	float n1 = hash21(floor(uv * 0.25));
	float n2 = hash21(floor(uv * 0.25) + 31.0);
	vec3 nebula = vec3(0.0);
	if (n1 > 0.6) {
		vec3 col1 = hsv2rgb(vec3(0.6 + n2 * 0.2, 0.6, 1.0));
		vec3 col2 = hsv2rgb(vec3(0.7 + n2 * 0.1, 0.5, 1.0));
		nebula = mix(col1, col2, n2) * (n1 - 0.6) * 0.15;
	}

	// ---- Distant galactic core glow ----
	float core = 1.0 - smoothstep(0.0, 0.4, abs(dir.y));
	core *= 1.0 - smoothstep(0.0, 0.5, abs(dir.x));
	vec3 galaxy_glow = vec3(0.03, 0.02, 0.05) * core;

	vec3 starfield = galaxy_glow + nebula + vec3(star1) + star2_color * star2 + vec3(star3);
	COLOR = starfield;
}
