shader_type spatial;
render_mode diffuse_toon;

uniform sampler2D _Pattern : source_color;
uniform float _Offset : hint_range(0.0, 1.0, 0.01);
uniform float _PinAmount : hint_range(0.0, 1.0, 0.01);

uniform vec3 _BaseColor : source_color;
uniform vec3 _MidColor : source_color;
uniform vec3 _HighColor : source_color;

void vertex() {
	// Called for every vertex the material is visible on.
}

vec3 pin_light(vec3 base, vec3 blend, float opacity)
{
	vec3 check = step(0.5, blend);
	vec3 result_1 = check * max(2.0 * (base - 0.5), blend);
	vec3 result_2 = result_1 + (1.0 - check) * min(2.0 * base, blend);
	return mix(base, result_2, opacity);
}

void fragment() 
{
	float view_tangent = dot(-TANGENT, VIEW);
	float view_binormal = dot(BINORMAL, VIEW);
	float view_normal = dot(NORMAL, VIEW);
	
	vec3 view_TS = vec3(view_tangent, view_binormal, view_normal);
	view_TS = normalize(view_TS);
	
	vec2 uv_tangent_offset =  view_TS.xy * _Offset;
	vec2 uv_pin_offset = view_TS.xy * _Offset * 0.5;
	
	float t = texture(_Pattern, UV + uv_tangent_offset).r;
	vec2 uv_distorted = t - uv_tangent_offset;
	vec4 albedo = texture(_Pattern, uv_distorted);
	
	float t_AB = clamp(t, 0.0, 0.5) * 2.0;
	float t_BC = (clamp(t, 0.5, 1.0) - 0.5) * 2.0;
	
	vec3 color_AB = mix(_BaseColor, _MidColor, t_AB);
	vec3 color_BC = mix(color_AB, _HighColor, t_BC);
	albedo.rgb *= color_BC;
	
	vec3 pin_pattern = texture(_Pattern, UV + uv_pin_offset).rgb;
	vec3 pin_color = 1.0 - abs((fract(pin_pattern + view_TS) * 2.0) - 1.0);
	pin_color *= _PinAmount;
	
	vec3 blend = pin_light(albedo.rgb, pin_color, 1.0);
	
	ALBEDO = blend;
	SPECULAR = 1.0;
	ROUGHNESS = 0.5;
	RIM = 50.0;
	RIM_TINT = 0.01;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}