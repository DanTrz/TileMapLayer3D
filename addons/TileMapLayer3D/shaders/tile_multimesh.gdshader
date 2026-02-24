shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform bool debug_show_backfaces = true;

varying vec4 uv_rect_data;
varying vec4 anim_data;

void vertex() {
	uv_rect_data = INSTANCE_CUSTOM;
	anim_data = COLOR;
}

void fragment() {
	vec2 uv_min = uv_rect_data.rg;
	vec2 uv_max = uv_rect_data.ba;

	// Animation: subdivide spritesheet region into current frame
	// Static tiles: default COLOR=(1,1,1,1), guard 1.0 > 1.0 = false → skipped
	float anim_cols = anim_data.r;
	float anim_rows = anim_data.g;
	float anim_total = anim_data.b;
	float anim_speed = anim_data.a;

	if (anim_speed > 0.0 && anim_total > 1.0) {
		float frame_index = floor(mod(TIME * anim_speed, anim_total));
		float col = mod(frame_index, anim_cols);
		float row = floor(frame_index / anim_cols);
		vec2 full_size = uv_max - uv_min;
		vec2 frame_size = vec2(full_size.x / anim_cols, full_size.y / anim_rows);
		uv_min = uv_min + vec2(col * frame_size.x, row * frame_size.y);
		uv_max = uv_min + frame_size;
	}

	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(uv_min, uv_max, flipped_uv);
	
	// Manual nearest-neighbor: snap to texel center for pixel-perfect filtering
	// // At exact texel center, bilinear filter returns the exact texel value
	// vec2 final_uv = remapped_uv;
	// if (use_nearest_texture) {
	// 	vec2 tex_size = vec2(textureSize(albedo_texture, 0));
	// 	final_uv = (floor(remapped_uv * tex_size) + 0.5) / tex_size;
	// }
	// // if (use_nearest_texture) {
	// // 	vec2 tex_size = vec2(textureSize(albedo_texture, 0));
	// // 	vec2 half_texel = 0.5 / tex_size;
	// // 	// Clamp to tile's valid texel range to prevent sampling neighboring atlas tiles
	// // 	vec2 clamped_uv = clamp(remapped_uv, uv_min + half_texel, uv_max - half_texel);
	// // 	final_uv = (floor(clamped_uv * tex_size) + 0.5) / tex_size;
	// // }

	// Compute texel dimensions for atlas-bleed prevention
	vec2 tex_size = vec2(textureSize(albedo_texture, 0));
	vec2 half_texel = 0.5 / tex_size;

	// Clamp to tile's valid texel range (prevents atlas bleed in BOTH filter modes)
	// Applied AFTER mix() so only edge pixels are affected — interior pixels untouched
	vec2 clamped_uv = clamp(remapped_uv, uv_min + half_texel, uv_max - half_texel);

	vec2 final_uv = clamped_uv;
	if (use_nearest_texture) {
		// Manual nearest-neighbor: snap to texel center
		final_uv = (floor(clamped_uv * tex_size) + 0.5) / tex_size;
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