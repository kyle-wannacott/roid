// Gem material shader.  Uses the COLOR built-in (which receives
// the MultiMesh's per-instance color when use_colors is enabled).
// A subtle time-based "twinkle" is layered on top for life.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform float twinkle_speed = 4.0;
uniform float twinkle_amount = 0.15;

void fragment() {
	vec3 base = COLOR.rgb;
	float twinkle = 0.5 + 0.5 * sin(TIME * twinkle_speed + COLOR.a * 6.28);
	vec3 c = base * (1.0 + twinkle_amount * twinkle);
	ALBEDO = c;
	EMISSION = c * 1.4;
	METALLIC = 0.0;
	ROUGHNESS = 0.15;
}
