// Gem material shader.
//  • Per‑instance colour via the MultiMesh's INSTANCE_CUSTOM
//    (set via set_instance_color).  The COLOR built-in only reads
//    from per‑vertex mesh colors, which we don't bake.
//  • Round‑cut diamond shape has a vertical brightness gradient
//    (model‑space Y so the gradient is fixed to the gem, not the world).
//  • Facet "fire" — each face catches light differently based on its
//    normal direction (fixed pattern, doesn't swim as the gem tumbles).
//  • Fresnel edge glow for the glassy crystal look.
//  • Fake refraction by sampling the screen texture with normal‑offset UVs.
//  • Twinkle — each gem pulses on its own phase derived from INSTANCE_CUSTOM.a.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert;

uniform float fresnel_power       : hint_range(0.0, 6.0)   = 2.5;
uniform float refraction_strength : hint_range(0.0, 0.15) = 0.05;
uniform float emission_strength   : hint_range(0.0, 4.0)  = 1.4;
uniform float gradient_top        : hint_range(0.0, 2.0)  = 1.3;
uniform float gradient_bottom     : hint_range(0.0, 2.0)  = 0.5;
uniform float facet_fire          : hint_range(0.0, 0.6)  = 0.35;
uniform float twinkle_amount      : hint_range(0.0, 0.5)  = 0.15;
uniform float alpha_val           : hint_range(0.0, 1.0)  = 0.82;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

varying float v_local_y;
varying vec3  v_normal;

void vertex() {
	// Local Y runs from culet (‑0.55) up to the table (0.45) on the
	// round‑cut gem, so we use it for the gradient.
	v_local_y = VERTEX.y;
	v_normal  = NORMAL;
}

void fragment() {
	// Per‑instance base hue (MultiMesh per‑instance color, set via
	// set_instance_color on the MultiMesh).
	vec3 base = INSTANCE_CUSTOM.rgb;

	// Vertical gradient — brighter at the table, darker at the culet.
	float t = clamp((v_local_y + 0.55) / 1.0, 0.0, 1.0);
	vec3 graded = base * mix(gradient_bottom, gradient_top, t);

	// Fixed "fire" pattern across the facets.  The exact direction is
	// arbitrary but it doesn't change as the gem rotates, so the
	// pattern is locked to the gem itself.
	vec3 fire_dir = normalize(vec3(0.5, 1.0, 0.3));
	float facet = dot(normalize(v_normal), fire_dir) * 0.5 + 0.5;
	graded *= (1.0 - facet_fire + facet_fire * facet);

	// Fresnel — edges glow brighter, like real glass.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// Fake refraction — sample the screen behind the gem, offset by
	// the surface normal so it looks like light is bending through.
	vec2 distorted_uv = SCREEN_UV + NORMAL.xy * refraction_strength;
	vec3 refractive = texture(screen_tex, distorted_uv).rgb;

	// Mix: at the centre, show the refracted scene; at the edges, show
	// the gem's own colour (with gradient + facet).
	vec3 col = mix(refractive, graded, fresnel);

	// Per‑instance twinkle — phase from INSTANCE_CUSTOM.a.
	float twinkle = 0.5 + 0.5 * sin(TIME * 4.0 + INSTANCE_CUSTOM.a * 6.28);
	col *= (1.0 + twinkle_amount * twinkle);

	// Strong emission so the gem glows in the dark.
	col += base * emission_strength * 0.4;

	ALBEDO   = col;
	EMISSION = base * emission_strength;
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	ALPHA    = alpha_val;
}
