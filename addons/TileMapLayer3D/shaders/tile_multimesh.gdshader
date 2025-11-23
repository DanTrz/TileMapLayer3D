shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;
uniform bool debug_show_backfaces = true;

varying vec4 uv_rect_data;

void vertex() {
	uv_rect_data = INSTANCE_CUSTOM + COLOR;
}

void fragment() {
	vec2 uv_min = uv_rect_data.rg;
	vec2 uv_max = uv_rect_data.ba;
	
	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(uv_min, uv_max, flipped_uv);
	
	vec4 tex_color = use_nearest_texture
			? texture(albedo_texture_nearest, remapped_uv)
			: texture(albedo_texture_linear, remapped_uv);
	
	// CRITICAL: discard must happen BEFORE any other assignments
	if (tex_color.a < alpha_threshold) {
		discard;  // ← This is what makes shadows work!
	}
	
	if (debug_show_backfaces && !FRONT_FACING) {
		ALBEDO = vec3(1.0, 0.0, 0.0);

	} else {
		ALBEDO = albedo_color.rgb * tex_color.rgb;
	}
}