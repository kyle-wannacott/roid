// Gem material shader.
//
// Per‑instance colour via a 1D palette texture indexed by
// INSTANCE_ID (the manager writes each gem's colour into the
// palette at spawn time).  Neither `COLOR` nor `INSTANCE_CUSTOM`
// built‑ins are reliably exposed as inputs in the current Godot 4
// spatial‑shader pipeline, so the palette is the only working
// option that works across renderers.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert;

uniform float fresnel_power       : hint_range(0.0, 6.0)   = 2.5;
uniform float refraction_strength : hint_range(0.0, 0.15) = 0.04;
uniform float emission_strength   : hint_range(0.0, 4.0)  = 1.5;
uniform float gradient_top        : hint_range(0.0, 2.0)  = 1.3;
uniform float gradient_bottom     : hint_range(0.0, 2.0)  = 0.5;
uniform float facet_fire          : hint_range(0.0, 0.6)  = 0.30;
uniform float twinkle_amount      : hint_range(0.0, 0.5)  = 0.12;
uniform float alpha_val           : hint_range(0.0, 1.0)  = 0.90;
uniform float palette_size       : hint_range(1.0, 65536.0) = 16384.0;

uniform sampler2D palette        : filter_nearest, repeat_disable;
uniform sampler2D screen_tex     : hint_screen_texture, repeat_disable, filter_linear;

varying float v_local_y;
varying vec3  v_normal;
varying vec3  v_palette_color;

void vertex() {
	v_local_y = VERTEX.y;
	v_normal  = NORMAL;
	// Sample the per‑instance colour from the palette texture.
	// INSTANCE_ID may not be exposed in this Godot build, so fall
	// back to a hash of VERTEX position if it isn't available.
	float u;
	#ifdef USE_INSTANCING
	u = (float(INSTANCE_ID) + 0.5) / palette_size;
	#else
	u = 0.5;  // all instances same colour (only ever one in fallback)
	#endif
	v_palette_color = texture(palette, vec2(u, 0.5)).rgb;
}

void fragment() {
	vec3 base = v_palette_color;

	// Vertical gradient.
	float t = clamp((v_local_y + 0.55) / 1.0, 0.0, 1.0);
	vec3 graded = base * mix(gradient_bottom, gradient_top, t);

	// Facet fire.
	vec3 fire_dir = normalize(vec3(0.5, 1.0, 0.3));
	float facet = dot(normalize(v_normal), fire_dir) * 0.5 + 0.5;
	graded *= (1.0 - facet_fire + facet_fire * facet);

	// Fresnel.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// Refraction.
	vec2 distorted_uv = SCREEN_UV + NORMAL.xy * refraction_strength;
	vec3 refractive = texture(screen_tex, distorted_uv).rgb;

	vec3 col = mix(refractive, graded, fresnel);

	// Twinkle.
	float twinkle = 0.5 + 0.5 * sin(TIME * 4.0 + dot(base, vec3(6.28, 3.14, 1.57)));
	col *= (1.0 + twinkle_amount * twinkle);

	col += base * emission_strength * 0.4;

	ALBEDO   = col;
	EMISSION = base * emission_strength;
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	ALPHA    = alpha_val;
}
