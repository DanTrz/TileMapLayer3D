shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;


uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture : source_color, repeat_disable;
uniform float inset_value = 0.5;
uniform float side_normal_y_threshold = 0.5;

uniform sampler2D normal_texture : hint_normal, repeat_disable;
uniform bool has_normal_texture = false;

varying flat vec4 uv_rect_data;
varying vec3 model_normal;
varying flat float inst_y_scale;

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

void vertex() {
	uv_rect_data = INSTANCE_CUSTOM;
	model_normal = NORMAL;
	inst_y_scale = length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	vec2 uv_min = uv_rect_data.rg;
	vec2 uv_max = uv_rect_data.ba;

	// Decode freeze-UV rotation from packed custom_data.a (must match the shared tile shader):
	// values < 2.0 = no freeze; >= 2.0 = freeze with encoded rotation, where the real uv_max.y
	// is recovered by removing the rotation multiples of 2.0. Without this, freeze-UV box/prism
	// tiles carry uv_max.y >= 2.0 and sample garbage (noise) outside the atlas cell.
	int freeze_rot = int(floor(uv_rect_data.a / 2.0));
	if (freeze_rot > 0) {
		uv_max.y = uv_rect_data.a - float(freeze_rot) * 2.0;
	}

	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);

	if (freeze_rot > 0) {
		int rot_steps = freeze_rot - 1;
		if (rot_steps == 1) flipped_uv = vec2(flipped_uv.y, 1.0 - flipped_uv.x);
		else if (rot_steps == 2) flipped_uv = vec2(1.0 - flipped_uv.x, 1.0 - flipped_uv.y);
		else if (rot_steps == 3) flipped_uv = vec2(1.0 - flipped_uv.y, flipped_uv.x);
	}

	if (abs(model_normal.y) < side_normal_y_threshold) {
		flipped_uv.y = 1.0 - (1.0 - flipped_uv.y) * inst_y_scale;
	}

	vec2 remapped_uv = mix(uv_min, uv_max, flipped_uv);

	vec2 texel_inset = inset_value / vec2(textureSize(albedo_texture, 0));
	vec2 final_uv = clamp(remapped_uv, uv_min + texel_inset, uv_max - texel_inset);

	vec4 tex_color = sample_filtered(albedo_texture, final_uv, use_nearest_texture);

	// discard must happen BEFORE any other assignments (keeps shadows correct).
	if (tex_color.a < alpha_threshold) {
		discard;
	}

	if (has_normal_texture) {
		NORMAL_MAP = sample_filtered(normal_texture, final_uv, use_nearest_texture).rgb;
	}

	ALBEDO = albedo_color.rgb * tex_color.rgb;
}
