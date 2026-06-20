// Asteroid material shader.
// Colour varies per-vertex from local vertex position so every
// asteroid looks slightly different (different scale/rotation makes
// the pattern unique per instance).  Hit feedback is done via a
// per-instance scale pop (set by the manager), not a material uniform.
shader_type spatial;
render_mode cull_disabled;

varying vec3 vert_color;

void vertex() {
	float r = 0.50 + 0.30 * sin(VERTEX.x * 3.7 + VERTEX.z * 2.3);
	float g = 0.45 + 0.25 * cos(VERTEX.y * 2.1 + VERTEX.x * 4.1);
	float b = 0.35 + 0.20 * sin(VERTEX.z * 5.3 + VERTEX.y * 3.7);
	vert_color = vec3(r, g, b);
}

void fragment() {
	ALBEDO = vert_color;
	ROUGHNESS = 0.95;
	METALLIC = 0.05;
}
