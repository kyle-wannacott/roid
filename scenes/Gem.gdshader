// Gem material shader — iridescent faceted gem.
//
// Combines the per‑instance COLOR (from MultiMesh use_colors) with
// an iridescent rainbow highlight that shifts with the view angle,
// creating the "fire" and sparkle of a real gemstone.
//
// Uses specular_schlick_ggx with high metallic and low roughness
// so each facet acts like a tiny mirror.

shader_type spatial;
render_mode specular_schlick_ggx, blend_mix, depth_draw_opaque, cull_disabled;

// ── Tuning uniforms ─────────────────────────────────────────────

uniform float roughness         : hint_range(0.0, 1.0) = 0.08;
uniform float metallic          : hint_range(0.0, 1.0) = 1.0;

// Iridescence — the rainbow "fire" effect
uniform float iridescence_scale     : hint_range(0.0, 12.0) = 4.0;
uniform float iridescence_intensity : hint_range(0.0, 1.0)  = 0.45;

// How much of the gem's own colour shows through vs the iridescence
uniform float color_strength     : hint_range(0.0, 1.0) = 0.55;

// Overall brightness
uniform float brightness         : hint_range(0.0, 2.0) = 1.1;

// Faint glow in shadow
uniform float emission_glow      : hint_range(0.0, 0.5) = 0.08;

// Alpha
uniform float alpha_val          : hint_range(0.0, 1.0) = 0.85;

// Optional editor preview colour — overrides COLOR when non‑black.
uniform vec3  _PreviewColor      : source_color = vec3(0.3, 0.85, 1.0);

// ── Varyings ────────────────────────────────────────────────────

varying vec3 v_gem_color;

// ── HSV helpers ─────────────────────────────────────────────────

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// ── Vertex ──────────────────────────────────────────────────────

void vertex() {
    v_gem_color = COLOR.rgb;
}

// ── Fragment ────────────────────────────────────────────────────

void fragment() {
    // Base gem colour from per‑instance COLOR (or preview override).
    vec3 base_color = (length(_PreviewColor) > 0.001) ? _PreviewColor : v_gem_color;

    // Iridescent rainbow based on view angle.
    // Using dot(NORMAL, VIEW) gives a smooth colour shift as the
    // viewing angle changes — facets at different angles catch
    // different rainbow hues.
    float angle = dot(NORMAL, VIEW);
    float hue = fract(angle * iridescence_scale);

    // Optional: sharpen the iridescence so it's not a smooth gradient
    // but has brighter bands like real gem fire.
    float banded = sin(angle * iridescence_scale * 6.28) * 0.5 + 0.5;
    banded = pow(banded, 1.5); // sharpen the bands

    vec3 iridescent = hsv2rgb(vec3(hue, 1.0, 1.0));

    // Mix iridescence with the gem's own colour.
    vec3 mixed = mix(base_color, iridescent, iridescence_intensity);

    // Keep some of the gem's colour so it's identifiable.
    vec3 final = mix(mixed, base_color, color_strength);

    // Add a bright sparkle kick from the banded iridescence.
    final += iridescent * banded * 0.3;

    // Brightness.
    final *= brightness;

    ALBEDO   = final;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    EMISSION = base_color * emission_glow;
    ALPHA    = alpha_val;
}
