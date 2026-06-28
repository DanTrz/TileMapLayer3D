shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// Single sampler, no filter_* hint — filtering is emulated on UVs in sample_filtered() so the
// vertex tile honors the filter mode in every renderer including Compatibility.
uniform sampler2D albedo_texture : source_color, repeat_disable;
uniform float alpha_threshold = 0.5;
uniform bool debug_show_backfaces = true;
uniform bool use_nearest_texture = true;

// Renderer-agnostic filter — must match the multimesh tile shaders.
// Nearest = snap to texel center; Linear = manual 4-tap bilinear.
vec4 sample_filtered(sampler2D tex, vec2 uv, bool use_nearest) {
	vec2 ts = vec2(textureSize(tex, 0));
	if (use_nearest) {
		vec2 snapped = (floor(uv * ts) + 0.5) / ts;
		return texture(tex, snapped);
	}
	vec2 px = uv * ts - 0.5;
	vec2 f = fract(px);
	vec2 base = (floor(px) + 0.5) / ts;
	vec4 c00 = texture(tex, base);
	vec4 c10 = texture(tex, base + vec2(1.0 / ts.x, 0.0));
	vec4 c01 = texture(tex, base + vec2(0.0, 1.0 / ts.y));
	vec4 c11 = texture(tex, base + vec2(1.0 / ts.x, 1.0 / ts.y));
	return mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
}

void fragment() {
	// Flip normal for back faces so lighting is correct with cull_disabled
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	vec4 tex_color = sample_filtered(albedo_texture, UV, use_nearest_texture);
	if (tex_color.a < alpha_threshold) {
		discard;
	}

	// Show backfaces as RED to indicate face direction (matches MultiMesh shader)
	// Helps users identify which side will be visible after baking (which uses backface culling)
	if (debug_show_backfaces && !FRONT_FACING) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
	} else {
		ALBEDO = tex_color.rgb;
	}
}
