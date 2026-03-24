shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform float alpha_threshold = 0.5;

void fragment() {
	// Flip normal for back faces so lighting is correct with cull_disabled
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	vec4 tex_color = texture(albedo_texture, UV);
	if (tex_color.a < alpha_threshold) {
		discard;
	}
	ALBEDO = tex_color.rgb;
}
