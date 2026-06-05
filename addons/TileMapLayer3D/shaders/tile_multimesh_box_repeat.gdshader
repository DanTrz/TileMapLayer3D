shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// Dedicated shader for BOX_MESH / PRISM_MESH chunks in REPEAT texture mode ONLY.
// Identical to tile_multimesh_doubleface.gdshader (atlas remap + inset + alpha discard,
// double-sided via cull_disabled) EXCEPT it depth-corrects the side faces:
//
//   The box/prism mesh is baked once at depth_scale = 1.0 and the real depth is applied as a
//   per-instance local-Y scale (build_tile_transform -> get_scale_for_orientation). In REPEAT
//   mode the side faces bake a full 0->1 texture down their depth, so a thin (depth < 1) box
//   squashes the whole texture into the short side. Here we recover the per-instance Y scale
//   from MODEL_MATRIX and shrink the side-face V span to match, so the side shows only a
//   depth_scale slice of the texture at the same texel density as the top face.
//
//   Top / bottom / prism-cap faces are left untouched (they are depth-independent). Side faces
//   are detected by their horizontal model-space normal (|n.y| below the threshold uniform).
//   This shader never renders flat / animated / arch tiles, so it needs no self-gating and no
//   animation / freeze-UV handling.

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;
uniform float inset_value = 0.5; // Inset in pixels to prevent texture bleeding
// Side faces have a horizontal local normal (|n.y| < this); top/bottom/caps have |n.y| ~= 1.
// Mirrors GlobalConstants.BOX_SIDE_NORMAL_Y_THRESHOLD.
uniform float side_normal_y_threshold = 0.5;

varying flat vec4 uv_rect_data;
varying vec3 model_normal;          // local-space normal (pre-orientation) — side detection
varying flat float inst_y_scale;    // recovered per-instance local-Y scale == depth_scale

void vertex() {
	uv_rect_data = INSTANCE_CUSTOM;
	model_normal = NORMAL;
	// Local Y axis of the instance carries depth_scale (applied before orientation rotation).
	inst_y_scale = length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	vec2 uv_min = uv_rect_data.rg;
	vec2 uv_max = uv_rect_data.ba;

	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);

	// Depth-correct side faces only: shrink the V span by depth_scale, anchored at the
	// front-face edge (flipped_uv.y == 1.0 — the seam where the side meets the main face),
	// so the side samples a depth_scale slice of the texture at top-face texel density.
	// depth == 1.0 is a no-op. Top/bottom/cap faces (|n.y| >= threshold) are untouched.
	if (abs(model_normal.y) < side_normal_y_threshold) {
		flipped_uv.y = 1.0 - (1.0 - flipped_uv.y) * inst_y_scale;
	}

	vec2 remapped_uv = mix(uv_min, uv_max, flipped_uv);

	// Half-texel inset to prevent bleed/bilinear bleed at the atlas-cell edges.
	vec2 texel_inset = inset_value / vec2(textureSize(albedo_texture_linear, 0));
	vec2 final_uv = clamp(remapped_uv, uv_min + texel_inset, uv_max - texel_inset);

	vec4 tex_color = use_nearest_texture
		? texture(albedo_texture_nearest, final_uv)
		: texture(albedo_texture_linear, final_uv);

	// discard must happen BEFORE any other assignments (keeps shadows correct).
	if (tex_color.a < alpha_threshold) {
		discard;
	}

	ALBEDO = albedo_color.rgb * tex_color.rgb;
}
