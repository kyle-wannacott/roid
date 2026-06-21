// Sun material — spatial 3D shader, ported from a 2D canvas_item sun.
// The sphere is treated as a 2D disc in screen space by using the
// normalised view direction as the sampling plane.  This means the
// sun always looks the same from the camera regardless of the sphere's
// orientation in the world (it's a billboarded‑ish effect inside a
// sphere mesh).
//
// All the knobs from the original are preserved: core/hot/corona/spot
// colours, surface detail, granulation, flares, rotation, bloom.

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

group_uniforms appearance;
uniform vec4 core_color   : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform vec4 hot_color    : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform vec4 corona_color : source_color = vec4(1.0, 0.42, 0.06, 1.0);
uniform vec4 spot_color   : source_color = vec4(0.45, 0.18, 0.02, 1.0);

group_uniforms shape;
uniform float sun_radius     : hint_range(0.05, 0.95) = 0.30;
uniform float corona_size    : hint_range(0.0, 0.45)  = 0.18;
uniform float bloom_strength : hint_range(0.0, 3.0)   = 1.1;

group_uniforms surface;
uniform float surface_detail : hint_range(1.0, 12.0) = 5.0;
uniform float granulation    : hint_range(0.0, 1.0)  = 0.55;
uniform float spot_amount    : hint_range(0.0, 1.0)  = 0.35;
uniform float rotation_speed : hint_range(-1.0, 1.0) = 0.03;

group_uniforms flares;
uniform float flare_detail   : hint_range(1.0, 12.0) = 4.0;
uniform float flare_intensity: hint_range(0.0, 4.0)  = 1.6;
uniform float flare_speed     : hint_range(0.0, 2.0)  = 0.45;

uniform float time_offset    : hint_range(0.0, 100.0) = 0.0;

const int MAX_OCTAVES = 6;
const mat2 ROT = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);

	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	return mix(nxy0, nxy1, u.z);
}

float fbm3(vec3 p, int octaves) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < MAX_OCTAVES; i++) {
		if (i >= octaves) break;
		value += amp * value_noise3(p);
		p.xy = ROT * p.xy;
		p.yz = ROT * p.yz;
		p *= 2.02;
		amp *= 0.5;
	}
	return value;
}

// Compute a 2D disc coordinate for the current fragment, using the
// view direction so the sun looks the same from any camera angle.
// `view_sun` is the unit vector from camera to sun centre.
// `frag_dir` is the unit vector from camera to the current fragment.
// Returns vec2(uv.x, uv.y) in [-1, 1] and a bool is_disc (1 if the
// fragment is inside the sun disc, 0 for the corona/halo).
vec3 sun_coords(vec3 view_sun, vec3 frag_dir) {
	// Project the fragment ray onto the sun's "screen plane" (the
	// plane through the sun centre perpendicular to view_sun).  The
	// projected point's offset from the sun centre is the 2D disc
	// coordinate.
	float cos_a = dot(frag_dir, view_sun);
	// The screen offset is frag_dir scaled so its component along
	// view_sun equals 1, minus view_sun.
	vec3 screen_pt = frag_dir / max(cos_a, 0.0001) - view_sun;
	// Build an orthonormal basis around view_sun so the 2D coords
	// are stable regardless of view_sun's direction.
	vec3 up = abs(view_sun.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 right = normalize(cross(view_sun, up));
	up = cross(right, view_sun);
	float u = dot(screen_pt, right);
	float v = dot(screen_pt, up);
	float dist = length(vec2(u, v));
	return vec3(u, v, dist);
}

void fragment() {
	// World‑space vectors for the sun projection.
	vec3 sun_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 frag_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_sun = normalize(sun_world - CAMERA_POSITION_WORLD);
	vec3 frag_dir = normalize(frag_world - CAMERA_POSITION_WORLD);
	vec3 sc = sun_coords(view_sun, frag_dir);
	float u = sc.x;
	float v = sc.y;
	float dist = sc.z;

	float t = TIME + time_offset;
	vec3 col = vec3(0.0);

	if (dist <= sun_radius) {
		// ---- Sun surface -------------------------------------------
		vec2 nxy = vec2(u, v) / sun_radius;
		float nz = sqrt(max(0.0, 1.0 - dot(nxy, nxy)));

		float spin = t * rotation_speed * TAU;
		float cs = cos(spin);
		float sn = sin(spin);

		vec3 sp = vec3(cs * nxy.x + sn * nz, nxy.y, -sn * nxy.x + cs * nz);
		sp *= (3.0 + surface_detail);
		int oct = int(surface_detail);

		float cells = fbm3(sp + vec3(0.0, t * 0.05, t * 0.03), oct);
		float fine = fbm3(sp * 2.7 - vec3(t * 0.08, 0.0, 0.0), min(oct, 3));
		float plasma = mix(cells, fine, 0.4);

		vec3 base = mix(hot_color.rgb, core_color.rgb, smoothstep(0.2, 0.9, plasma));
		base += core_color.rgb * granulation * pow(plasma, 3.0);

		float spots = fbm3(sp * 0.6 + vec3(t * 0.02, 0.0, -t * 0.015), 4);
		float spot_mask = smoothstep(0.62, 0.42, spots) * spot_amount;
		base = mix(base, spot_color.rgb, spot_mask);

		float limb = clamp(pow(nz, 0.55), 0.12, 1.0);
		base *= limb;

		float rim = smoothstep(sun_radius, sun_radius * 0.82, dist);
		base += hot_color.rgb * (1.0 - rim) * 0.6;

		col = base;
	} else {
		// ---- Corona, flares and bloom -------------------------------
		float d_out = dist - sun_radius;
		float d_norm = d_out / corona_size;

		float ringscale = 4.0 + flare_detail;
		vec2 dir2d = vec2(u, v) / max(dist, 0.0001) * ringscale;

		vec3 acc = vec3(0.0);

		if (d_norm < 1.0) {
			vec3 fuv1 = vec3(dir2d, d_norm * 3.0 - t * flare_speed);
			vec3 fuv2 = vec3(dir2d * 1.7, d_norm * 4.5 - t * flare_speed * 1.4);
			float f1 = fbm3(fuv1, int(flare_detail));
			float f2 = fbm3(fuv2, int(flare_detail));
			float flare = pow(f1 * f2, 1.5) * flare_intensity;

			float edge_fade = 1.0 - d_norm;
			float corona_a = clamp(pow(edge_fade * (0.4 + flare), 1.8), 0.0, 1.0);

			acc += mix(corona_color.rgb, hot_color.rgb, flare) * corona_a;
		}

		float halo = exp(-d_out / (corona_size * (0.45 + bloom_strength)));
		halo = pow(halo, 1.5) * bloom_strength;
		acc += corona_color.rgb * halo;

		col = acc;
	}

	ALBEDO   = col;
	EMISSION = col;
}
