shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;
uniform bool debug_show_backfaces = true;
uniform float inset_value = 0.5; // Inset in pixels to prevent texture bleeding, can be adjusted based on texture resolution

varying flat vec4 uv_rect_data;
varying flat vec4 anim_data;


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
    // Static tiles: default COLOR=(1,1,1,1), guard 1.0 > 1.0 = false - means it's skipped
    float frame_step_x = anim_data.r;
    float frame_step_y = anim_data.g;
    float anim_total = anim_data.b;
    float cols_and_speed = anim_data.a;

    if (anim_total > 1.0) {
        float total = round(anim_total);
        float cols = max(floor(cols_and_speed), 1.0);
        float speed = fract(cols_and_speed) * 256.0;
        float frame_index = floor(mod(TIME * speed, total) + 0.001);
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

    vec2 final_uv;
    if (use_nearest_texture) {
        // Nearest: no interpolation might not even need to apply a pixel inset
        // final_uv = remapped_uv;

        vec2 texel_inset = inset_value / vec2(textureSize(albedo_texture_linear, 0));
        final_uv = clamp(remapped_uv, uv_min + texel_inset, uv_max - texel_inset);
    } else {
        // final_uv = remapped_uv; //

        // Linear: half-texel inset to prevent bilinear bleed
        vec2 texel_inset = inset_value / vec2(textureSize(albedo_texture_linear, 0));
        final_uv = clamp(remapped_uv, uv_min + texel_inset, uv_max - texel_inset);
    }

    // Sample texture with correct filter mode (nearest or linear)
    // Animated tiles: force mip level 0 to prevent cross-frame mipmap bleeding
    vec4 tex_color;
    if (anim_total > 1.0) {
        tex_color = use_nearest_texture
            ? textureLod(albedo_texture_nearest, final_uv, 0.0)
            : textureLod(albedo_texture_linear, final_uv, 0.0);
    } else {
        tex_color = use_nearest_texture
            ? texture(albedo_texture_nearest, final_uv)
            : texture(albedo_texture_linear, final_uv);
    }

    if (tex_color.a < alpha_threshold) {
        discard;
    }

    if (debug_show_backfaces && !FRONT_FACING) {
        ALBEDO = vec3(1.0, 0.0, 0.0);
    } else {
        ALBEDO = albedo_color.rgb * tex_color.rgb;
    }
}
