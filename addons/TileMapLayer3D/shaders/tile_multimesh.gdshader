shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
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
	
	// Manual nearest-neighbor: snap to texel center for pixel-perfect filtering
	// At exact texel center, bilinear filter returns the exact texel value
	vec2 final_uv = remapped_uv;
	if (use_nearest_texture) {
		vec2 tex_size = vec2(textureSize(albedo_texture, 0));
		final_uv = (floor(remapped_uv * tex_size) + 0.5) / tex_size;
	}
	vec4 tex_color = texture(albedo_texture, final_uv);
	
	//   discard must happen BEFORE any other assignments
	if (tex_color.a < alpha_threshold) {
		discard;  // ← This is what makes shadows work!
	}
	
	if (debug_show_backfaces && !FRONT_FACING) {
		ALBEDO = vec3(1.0, 0.0, 0.0); //vec3(0.5, 0.5, 0.5);

	} else {
		ALBEDO = albedo_color.rgb * tex_color.rgb;
	}
	
}