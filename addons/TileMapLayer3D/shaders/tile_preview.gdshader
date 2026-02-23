shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// Preview shader — UV region passed via uniforms (no INSTANCE_CUSTOM/COLOR tricks)
uniform sampler2D atlas_texture : source_color, filter_linear, repeat_disable;
uniform vec2 uv_region_min = vec2(0.0, 0.0);
uniform vec2 uv_region_max = vec2(1.0, 1.0);
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;

void fragment() {
    vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
    vec2 remapped_uv = mix(uv_region_min, uv_region_max, flipped_uv);

    // Atlas-bleed prevention (same as multimesh shader)
    vec2 tex_size = vec2(textureSize(atlas_texture, 0));
    vec2 half_texel = 0.5 / tex_size;
    vec2 clamped_uv = clamp(remapped_uv, uv_region_min + half_texel, uv_region_max - half_texel);

    vec2 final_uv = clamped_uv;
    if (use_nearest_texture) {
        final_uv = (floor(clamped_uv * tex_size) + 0.5) / tex_size;
    }

    vec4 tex_color = texture(atlas_texture, final_uv);

    if (tex_color.a < alpha_threshold) {
        discard;
    }

    ALBEDO = albedo_color.rgb * tex_color.rgb;
}