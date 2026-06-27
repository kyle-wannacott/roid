shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

uniform bool overlay = true;

// ── Pixelation ─────────────────────────────────────────────────────────────────
uniform bool     pixelate   = true;
uniform vec2     resolution = vec2(640.0, 480.0);

// ── Brightness / vignette ──────────────────────────────────────────────────────
uniform float brightness = 1.4;
uniform float vignette_intensity = 0.4;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.5;

// ── Palette quantisation ───────────────────────────────────────────────────────
uniform bool  quantize_enabled = false;
uniform int   palette_size     : hint_range(1, 256) = 32;
uniform vec4  palette[256];
uniform bool  dither_enabled   = false;
uniform float dither_strength  : hint_range(0.0, 1.0) = 0.25;

// ─────────────────────────────────────────────────────────────────────────────

float vignette(vec2 uv) {
	uv *= 1.0 - uv.xy;
	float vig = uv.x * uv.y * 15.0;
	return pow(vig, vignette_intensity * vignette_opacity);
}

float bayer4x4(ivec2 pixel_pos) {
	int x = pixel_pos.x & 3;
	int y = pixel_pos.y & 3;
	int idx = y * 4 + x;
	float m[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	);
	return m[idx] / 16.0 - 0.5;
}

vec4 nearest_palette_color(vec4 color) {
	float best = 1e9;
	vec4 result = color;
	for (int i = 0; i < palette_size; i++) {
		vec3 diff = color.rgb - palette[i].rgb;
		float d = dot(diff, diff);
		if (d < best) {
			best = d;
			result = vec4(palette[i].rgb, color.a);
		}
	}
	return result;
}

void fragment() {
	vec2 uv = overlay ? SCREEN_UV : UV;
	vec2 text_uv = pixelate ? (ceil(uv * resolution) / resolution) : uv;

	vec4 text = texture(SCREEN_TEXTURE, text_uv);
	text.a = 1.0;
	text.rgb = clamp(text.rgb * brightness, 0.0, 1.0);
	text.rgb *= vignette(uv);

	if (quantize_enabled && palette_size > 0) {
		if (dither_enabled && dither_strength > 0.0) {
			ivec2 pixel_pos = ivec2(uv * resolution);
			float offset = bayer4x4(pixel_pos) * dither_strength / float(palette_size);
			text.rgb = clamp(text.rgb + vec3(offset), 0.0, 1.0);
		}
		text = nearest_palette_color(text);
	}

	COLOR = text;
}
