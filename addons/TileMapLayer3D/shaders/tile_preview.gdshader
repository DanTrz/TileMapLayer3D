shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// Preview shader — UV region passed via uniforms (no INSTANCE_CUSTOM/COLOR tricks)
// Single sampler, no filter_* hint — filtering is emulated on UVs in sample_filtered() so the
// preview matches placed tiles exactly in every renderer including Compatibility.
uniform sampler2D atlas_texture : source_color, repeat_disable;
uniform vec2 uv_region_min = vec2(0.0, 0.0);
uniform vec2 uv_region_max = vec2(1.0, 1.0);
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;

// Renderer-agnostic filter on already-final atlas UV — must match the multimesh tile shaders.
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
    vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
    vec2 remapped_uv = mix(uv_region_min, uv_region_max, flipped_uv);

    // Atlas-bleed prevention (same as multimesh shader)
    vec2 tex_size = vec2(textureSize(atlas_texture, 0));
    vec2 half_texel = 0.5 / tex_size;
    vec2 final_uv = clamp(remapped_uv, uv_region_min + half_texel, uv_region_max - half_texel);

    vec4 tex_color = sample_filtered(atlas_texture, final_uv, use_nearest_texture);

    if (tex_color.a < alpha_threshold) {
        discard;
    }

    ALBEDO = albedo_color.rgb * tex_color.rgb;
}