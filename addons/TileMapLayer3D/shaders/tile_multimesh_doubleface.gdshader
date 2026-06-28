shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold = 0.5;
uniform bool use_nearest_texture = true;
// Single sampler — filtering is emulated on UVs below so it works identically in the
// Compatibility renderer (which ignores per-sampler filter_* qualifiers). No filter_* hint here.
uniform sampler2D albedo_texture : source_color, repeat_disable;
uniform float inset_value = 0.5; // Inset in pixels to prevent texture bleeding, can be adjusted based on texture resolution

varying flat vec4 uv_rect_data;
varying flat vec4 anim_data;

// Renderer-agnostic filter on already-final atlas UV (works in Compatibility too, where
// per-sampler filter_* qualifiers are ignored). Nearest = snap to texel center (bit-identical
// to hardware point sampling). Linear = manual 4-tap bilinear (same weighted average as a
// hardware bilinear sampler, minus mipmaps/anisotropy — undesired for pixel-art anyway).
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
	anim_data = COLOR;
}

void fragment() {
	vec2 uv_min = uv_rect_data.rg;
	vec2 uv_max = uv_rect_data.ba;

	// Decode freeze-UV rotation from packed custom_data.a
	// Values < 2.0 = no freeze (backward compatible), >= 2.0 = freeze with encoded rotation
	int freeze_rot = int(floor(uv_rect_data.a / 2.0));
	if (freeze_rot > 0) {
		uv_max.y = uv_rect_data.a - float(freeze_rot) * 2.0;
	}

	// Animation data packed as (frame_step_x, frame_step_y, total_frames, cols + speed/256)
	// Static tiles: default COLOR=(1,1,1,1), guard 1.0 > 1.0 = false → skipped
	float frame_step_x = anim_data.r;
	float frame_step_y = anim_data.g;
	float anim_total = anim_data.b;
	float cols_and_speed = anim_data.a;

	if (anim_total > 1.0) {
		float total = round(anim_total);
		float cols = max(floor(cols_and_speed), 1.0);
		float speed = fract(cols_and_speed) * 256.0;
		// ORIGINAL: +0.001 biases up to prevent float imprecision from rounding down
		// at frame boundaries (e.g., floor(1.9999) -> 1 instead of 2).
		// BUG: When mod() returns a value in [total - 0.001, total), adding 0.001
		// pushes it to >= total, making floor() produce `total` — an out-of-bounds
		// frame index. This samples past the animation strip (blank/ghost frame).
		// More frequent on AMD GPUs due to different mod() precision characteristics.
		// float frame_index = floor(mod(TIME * speed, total) + 0.001);

		// FIX: min() clamps frame_index to [0, total-1], preventing OOB access.
		// Keeps the +0.001 bias (still needed to avoid rounding-down stutter).
		// Uses min() instead of a second mod() because mod() would wrap to frame 0
		// causing a visible flash, while clamping to last frame is imperceptible.
		float frame_index = min(floor(mod(TIME * speed, total) + 0.001), total - 1.0);
		float col = mod(frame_index, cols);
		float row = floor(frame_index / cols);
		// Offset tile's base UV to the current animation frame
		vec2 offset = vec2(col * frame_step_x, row * frame_step_y);
		uv_min += offset;
		uv_max += offset;
	}

	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);

	// Counter-rotate UV to cancel mesh rotation when freeze-UV is active
	if (freeze_rot > 0) {
		int rot_steps = freeze_rot - 1;
		if (rot_steps == 1) flipped_uv = vec2(flipped_uv.y, 1.0 - flipped_uv.x);
		else if (rot_steps == 2) flipped_uv = vec2(1.0 - flipped_uv.x, 1.0 - flipped_uv.y);
		else if (rot_steps == 3) flipped_uv = vec2(1.0 - flipped_uv.y, flipped_uv.x);
	}

	vec2 remapped_uv = mix(uv_min, uv_max, flipped_uv);

	// Half-texel inset (in both modes) to prevent atlas-cell bleed / bilinear bleed.
	vec2 texel_inset = inset_value / vec2(textureSize(albedo_texture, 0));
	vec2 final_uv = clamp(remapped_uv, uv_min + texel_inset, uv_max - texel_inset);

	// Filter is emulated on UVs (single sampler, non-mipmapped) so it is correct in every
	// renderer including Compatibility. The animated branch no longer needs textureLod —
	// a non-mipmapped sampler already reads mip 0, so cross-frame mipmap bleed can't occur.
	vec4 tex_color = sample_filtered(albedo_texture, final_uv, use_nearest_texture);

	// discard must happen BEFORE any other assignments
	if (tex_color.a < alpha_threshold) {
		discard;  // ← This is what makes shadows work!
	}

	// Always renders both faces without backface debug (cull_disabled)
	ALBEDO = albedo_color.rgb * tex_color.rgb;
}
