// Energy shield material — applied to the ship's hull meshes via
// a second material pass.  A fresnel‑weighted hexagonal pattern
// pulses in the shield colour, and cracks appear when the shield
// is low on charge.  Reads a global `shield_strength` uniform
// updated each frame from Ship.gd.

shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_back, diffuse_lambert;

uniform vec4 shield_color   : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 crack_color    : source_color = vec4(0.6, 0.9, 1.0, 1.0);
uniform float shield_strength : hint_range(0.0, 1.0) = 1.0;
uniform float fresnel_power   : hint_range(0.0, 6.0)   = 2.0;
uniform float hex_scale        : hint_range(1.0, 20.0)  = 6.0;
uniform float pulse_speed      : hint_range(0.0, 6.0)   = 2.0;

varying vec3 v_normal;
varying vec3 v_world_pos;

void vertex() {
	v_normal = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hex(vec2 p) {
	p = abs(p);
	return max(p.x * 0.866025 + p.y * 0.5, p.y);
}

void fragment() {
	// Fresnel: strongest at the silhouette.
	float fresnel = pow(1.0 - clamp(dot(normalize(v_normal), VIEW), 0.0, 1.0), fresnel_power);

	// Hexagonal pattern in tangent‑ish space, using world position.
	vec2 p = v_world_pos.xz * hex_scale;
	float h = hex(fract(p) - 0.5);
	// Animated pulse along the hex grid.
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed - h * 6.2831);

	// Cracks appear when the shield is low — they flash brighter
	// as strength drops (the structure fails).
	float crack = 0.0;
	if (shield_strength < 0.6) {
		float crack_noise = fract(sin(dot(floor(v_world_pos * 8.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		crack = (1.0 - smoothstep(0.0, 0.6, shield_strength)) * step(0.7, crack_noise);
	}

	// Final emission: fresnel rim + hex pattern + cracks, scaled by
	// shield strength.  No albedo override — the hull's own colour
	// shows through where the shield is weak or absent.
	vec3 col = shield_color.rgb * fresnel * (0.6 + 0.4 * pulse);
	col += crack_color.rgb * crack * 1.5;
	EMISSION = col * shield_strength;
	ALBEDO = ALBEDO;  // pass through the hull's existing albedo
	ALPHA = 1.0;
}
