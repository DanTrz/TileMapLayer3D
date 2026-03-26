shader_type spatial;
// cull_disabled is kept as per original to allow viewing thin tile meshes from both sides
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// ==========================================
// TILEMAP & ATLAS SETTINGS (Original Core)
// ==========================================
group_uniforms Tile_MultiMesh;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;
uniform bool debug_show_backfaces = true;
// Inset prevents bilinear filtering from sampling pixels of neighboring tiles in the atlas
uniform float inset_value : hint_range(0.0, 2.0) = 0.5; 

// ==========================================
// PAINTERLY STYLE
// ==========================================
group_uniforms Painterly_Style;
uniform bool use_painterly = false;
uniform sampler2D brush_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Global intensity of the brush distortion effect
uniform float painterly_strength : hint_range(0.0, 2.0) = 0.5; 
// Tiling scale for the brush texture
uniform float painterly_tiling = 5.0; 
// Stretch factor to transform the noise into elongated brush strokes
uniform float painterly_stretch : hint_range(0.01, 1.0) = 0.2; 
// High-contrast sharpness for the brush stroke edges
uniform float painterly_sharpness : hint_range(0.001, 0.5) = 0.05; 
// Stop-motion frame rate (0.0 stops the animation)
uniform float painterly_frames_per_second : hint_range(0.0, 24.0) = 0.0; 
// Direction and speed of the boiling texture animation
uniform vec2 painterly_direction = vec2(1.0, 0.5); 

// ==========================================
// INNER EROSION
// ==========================================
group_uniforms Inner_Erosion; 
uniform bool use_erosion = false;
// Intensity of the scratchy artifacts eating into the shadow edges
uniform float erosion_scale : hint_range(0.0, 5.0) = 1.0; 
// Controls the depth of the erosion into the shadow area
uniform float erosion_threshold : hint_range(0.0, 1.0) = 0.5; 

// ==========================================
// TOON LIGHTING BASE
// ==========================================
group_uniforms Lighting_Base;
// Number of discrete color steps in the shading
uniform int cuts : hint_range(1, 256) = 3;
// Softness of the transition between toon steps
uniform float step_smoothness : hint_range(0.0, 1.0) = 0.1;
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness : hint_range(1.0, 8.0) = 1.0;
uniform bool use_attenuation = true;
uniform bool clamp_diffuse_to_max = false;

// ==========================================
// SHADOW STYLIZATION
// ==========================================
group_uniforms Shadow_Stylization;
uniform bool use_ramp = false;
uniform sampler2D ramp_texture : source_color;
uniform vec4 shadow_tint : source_color = vec4(0.2, 0.2, 0.3, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0) = 0.3;
uniform bool use_borders = false;
// Width of the dark line between toon lighting steps
uniform float border_width : hint_range(0.0, 0.5, 0.001) = 0.01; 

// ==========================================
// SPECULAR & NORMAL MAP
// ==========================================
group_uniforms Specular;
uniform bool use_specular = true;
uniform float specular_strength : hint_range(0.0, 1.0) = 1.0;
uniform float specular_shininess : hint_range(0.0, 32.0) = 16.0;
// Edge softness for the stylized specular spot
uniform float specular_softness : hint_range(0.0, 1.0) = 0.1; 
uniform sampler2D specular_map : source_color; 

group_uniforms Normal_Map;
uniform sampler2D normal_texture : hint_normal;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

// ==========================================
// RIM LIGHT
// ==========================================
group_uniforms Rim_Light;
uniform bool use_rim = true;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount : hint_range(0.0, 16.0) = 2.0;
uniform float rim_smoothness : hint_range(0.0, 1.0) = 0.2;
uniform float rim_mask_shadow : hint_range(0.0, 1.0) = 1.0;
uniform float rim_blend : hint_range(0.0, 1.0) = 1.0;

// ==========================================
// PATTERNS & DITHER3D
// ==========================================
group_uniforms Pattern_General;
uniform bool use_pattern = false;
uniform int pattern_type : hint_enum("Standard_Texture", "Dither3D") = 1;
uniform float pattern_blend : hint_range(0.0, 1.0) = 1.0;

group_uniforms Pattern_Standard_Texture;
uniform sampler2D pattern_texture : hint_default_black;
uniform int pattern_uv_mode : hint_enum("UV", "Screen", "Local Screen") = 2;
uniform float pattern_tiling = 32.0;
uniform float pattern_amount : hint_range(0.0, 1.0) = 0.5;
uniform float pattern_smoothness : hint_range(0.0, 1.0) = 0.5;

group_uniforms Pattern_Dither3D_Advanced;
uniform sampler3D dither_tex_3d : filter_linear;
uniform sampler2D dither_ramp_tex : filter_linear;
uniform float dither_dot_scale : hint_range(2, 10) = 5.0;
uniform float dither_contrast : hint_range(0, 2) = 1.0;
uniform float dither_input_exposure : hint_range(0, 5) = 1.0;
uniform float dither_input_offset : hint_range(-1, 1) = 0.0;
uniform float dither_softness : hint_range(0.0, 2.0, 0.01) = 0.1; 
uniform float dither_size_variability : hint_range(0, 1) = 0.0;
uniform float dither_stretch_smoothness : hint_range(0, 2) = 1.0;
uniform bool dither_inverse_dots = false;
uniform bool dither_radial_compensation = false;
uniform bool dither_quantize_layers = false;

// ==========================================
// VARYINGS
// ==========================================
varying flat vec4 vary_uv_rect_data;
varying flat vec4 vary_anim_data;
varying vec4 vary_node_position;
varying float vary_projection_00;
varying float vary_projection_11;

void vertex() {
	// Original logic: Capture instance data for atlas mapping and vertex color for animation
	vary_uv_rect_data = INSTANCE_CUSTOM;
	vary_anim_data = COLOR;
	
	// Advanced logic: Capture projection data for screen-space effects
	vary_node_position = (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	vary_projection_00 = PROJECTION_MATRIX[0][0];
	vary_projection_11 = PROJECTION_MATRIX[1][1];
}

void fragment() {
	// 1. TILE FRAME SELECTION (Original logic preserved)
	vec2 uv_min = vary_uv_rect_data.rg;
	vec2 uv_max = vary_uv_rect_data.ba;

	float frame_step_x = vary_anim_data.r;
	float frame_step_y = vary_anim_data.g;
	float anim_total = vary_anim_data.b;
	float cols_and_speed = vary_anim_data.a;

	if (anim_total > 1.0) {
		float total_frames = round(anim_total);
		float columns = max(floor(cols_and_speed), 1.0);
		float animation_speed = fract(cols_and_speed) * 256.0;
		float current_frame = floor(mod(TIME * animation_speed, total_frames) + 0.001);
		
		vec2 frame_offset = vec2(mod(current_frame, columns) * frame_step_x, floor(current_frame / columns) * frame_step_y);
		uv_min += frame_offset;
		uv_max += frame_offset;
	}

	// 2. UV REMAPPING
	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(uv_min, uv_max, flipped_uv);

	// 3. PAINTERLY UV DISTORTION (Applied before clamping to prevent bleeding)
	vec2 distorted_painterly_uv = remapped_uv;
	if (use_painterly) {
		float choppy_time = (painterly_frames_per_second > 0.0) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		vec2 brush_uv_coords = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_direction);
		float brush_noise_sample = texture(brush_texture, brush_uv_coords).r;
		distorted_painterly_uv += (brush_noise_sample - 0.5) * 0.05 * painterly_strength;
	}

	// 4. PIXEL INSETS (Texture Bleeding Prevention logic from original)
	vec2 atlas_texture_size = vec2(textureSize(albedo_texture_linear, 0));
	vec2 texel_inset_clamping = inset_value / atlas_texture_size;
	vec2 final_clamped_uv = clamp(distorted_painterly_uv, uv_min + texel_inset_clamping, uv_max - texel_inset_clamping);

	// 5. COLOR SAMPLING (Original filter logic preserved)
	vec4 texture_albedo_sample;
	if (anim_total > 1.0) {
		texture_albedo_sample = use_nearest_texture
			? textureLod(albedo_texture_nearest, final_clamped_uv, 0.0)
			: textureLod(albedo_texture_linear, final_clamped_uv, 0.0);
	} else {
		texture_albedo_sample = use_nearest_texture
			? texture(albedo_texture_nearest, final_clamped_uv)
			: texture(albedo_texture_linear, final_clamped_uv);
	}

	// 6. ALPHA DISCARD
	if (texture_albedo_sample.a < alpha_threshold) {
		discard;
	}

	// 7. FINAL ALBEDO & DEBUG BACKFACES
	if (debug_show_backfaces && !FRONT_FACING) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
	} else {
		ALBEDO = albedo_color.rgb * texture_albedo_sample.rgb;
	}
	
	// 8. NORMAL MAP APPLICATION (Using the same clamped atlas UVs)
	vec3 normal_map_sample = texture(normal_texture, final_clamped_uv).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), normal_map_sample, normal_strength);
}

void light() {
	// RECONSTRUCT REMAPPED ATLAS UVs FOR LIGHTING CALCULATIONS
	vec2 uv_min = vary_uv_rect_data.rg;
	vec2 uv_max = vary_uv_rect_data.ba;
	float anim_total = vary_anim_data.b;

	if (anim_total > 1.0) {
		float columns = max(floor(vary_anim_data.a), 1.0);
		float animation_speed = fract(vary_anim_data.a) * 256.0;
		float current_frame = floor(mod(TIME * animation_speed, round(anim_total)) + 0.001);
		vec2 frame_offset = vec2(mod(current_frame, columns) * vary_anim_data.r, floor(current_frame / columns) * vary_anim_data.g);
		uv_min += frame_offset;
		uv_max += frame_offset;
	}

	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 base_remapped_uv = mix(uv_min, uv_max, flipped_uv);
	
	vec2 distorted_lighting_uv = base_remapped_uv;
	float sharp_stroke_mask = 0.5;
	float raw_brush_noise = 0.5;

	// Calculate stop-motion animation and distorted coordinates for shadow breakup
	if (use_painterly) {
		float choppy_time = (painterly_frames_per_second > 0.0) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		vec2 brush_uv_coords = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_direction);
		raw_brush_noise = texture(brush_texture, brush_uv_coords).r;
		sharp_stroke_mask = smoothstep(0.5 - painterly_sharpness, 0.5 + painterly_sharpness, raw_brush_noise);
		distorted_lighting_uv += (sharp_stroke_mask - 0.5) * 0.05 * painterly_strength;
	}
	
	// Final atlas-safe UVs for specular and normal mapping in the light pass
	vec2 atlas_texture_size = vec2(textureSize(albedo_texture_linear, 0));
	vec2 texel_inset_clamping = inset_value / atlas_texture_size;
	vec2 tile_clamped_lighting_uv = clamp(distorted_lighting_uv, uv_min + texel_inset_clamping, uv_max - texel_inset_clamping);

	// --- BASE LIGHTING ---
	float attenuation_factor = use_attenuation ? ATTENUATION : 1.0;
	float normal_dot_light = dot(NORMAL, LIGHT);
	float normal_dot_view = dot(NORMAL, VIEW);
	
	float diffuse_raw_intensity = normal_dot_light + (attenuation_factor - 1.0) + wrap;

	// Break up shadow edges with the painterly brush texture
	if (use_painterly) {
		diffuse_raw_intensity += (sharp_stroke_mask - 0.5) * painterly_strength;
	}
	
	// Apply inner rim erosion (hand-painted "scratchy" shadow effect)
	if (use_painterly && use_erosion) {
		float fresnel_factor = 1.0 - clamp(normal_dot_view, 0.0, 1.0);
		float erosion_mask = smoothstep(erosion_threshold - 0.1, erosion_threshold + 0.1, raw_brush_noise * fresnel_factor);
		diffuse_raw_intensity -= erosion_mask * erosion_scale * (1.0 - clamp(normal_dot_light, 0.0, 1.0));
	}

	diffuse_raw_intensity = clamp(diffuse_raw_intensity, 0.0, 1.0);
	float diffuse_steep_intensity = clamp(diffuse_raw_intensity * steepness, 0.0, 1.0);

	// --- TOON STEPPING ---
	float cuts_float = float(cuts);
	float light_multiplier = diffuse_steep_intensity * cuts_float;
	float step_fraction = fract(light_multiplier);
	float light_factor_smooth = smoothstep(0.5 - step_smoothness, 0.5 + step_smoothness, step_fraction);
	float diffuse_stepped_intensity = clamp((floor(light_multiplier) + light_factor_smooth) / cuts_float, 0.0, 1.0);

	// --- PATTERN & DITHER3D LOGIC ---
	float pattern_mask_value = 1.0;
	if (use_pattern) {
		if (pattern_type == 0) { // Standard Texture
			vec2 screen_uv_coords = (pattern_uv_mode == 1) ? SCREEN_UV : (pattern_uv_mode == 2 ? (SCREEN_UV * 2.0 - 1.0) * vary_node_position.w - vary_node_position.xy : distorted_lighting_uv);
			vec2 tuned_pattern_uv = screen_uv_coords * pattern_tiling * vec2(1.0, VIEWPORT_SIZE.y / VIEWPORT_SIZE.x);
			float pattern_tex_sample = texture(pattern_texture, tuned_pattern_uv).r;
			pattern_mask_value = clamp(smoothstep(pattern_tex_sample - pattern_smoothness, pattern_tex_sample + pattern_smoothness, diffuse_stepped_intensity + pattern_amount), 0.0, 1.0);
		} else { // Dither3D
			float brightness_input = clamp(diffuse_stepped_intensity * dither_input_exposure + dither_input_offset, 0.0, 1.0);
			if (dither_inverse_dots) brightness_input = 1.0 - brightness_input;
			
			ivec3 dither_tex_size_ivec = textureSize(dither_tex_3d, 0);
			float dither_x_resolution = float(dither_tex_size_ivec.x);
			float dither_dots_per_side = dither_x_resolution / 16.0;
			float brightness_curve_val = texture(dither_ramp_tex, vec2((0.5 / dither_x_resolution + (1.0 - 1.0 / dither_x_resolution) * brightness_input), 0.5)).r;
			
			vec2 derivative_x = dFdx(distorted_lighting_uv); 
			vec2 derivative_y = dFdy(distorted_lighting_uv);
			
			if (dither_radial_compensation) {
				vec2 screen_position = (SCREEN_UV - 0.5) * 2.0;
				vec2 view_projection_dir = vec2(screen_position.x / vary_projection_00, screen_position.y / vary_projection_11);
				float radial_factor = dot(view_projection_dir, view_projection_dir) + 1.0;
				derivative_x *= radial_factor; derivative_y *= radial_factor;
			}
			
			// --- FIX: Calculating the freq_vector for sharp dither calculation ---
			float Q_math = dot(derivative_x, derivative_x) + dot(derivative_y, derivative_y);
			float R_math = derivative_x.x * derivative_y.y - derivative_y.x * derivative_x.y;
			float discriminant = sqrt(max(0.0, Q_math * Q_math - 4.0 * R_math * R_math));
			vec2 freq_vector = sqrt(vec2(Q_math + discriminant, Q_math - discriminant) / 2.0);
			
			float dither_spacing = freq_vector.y * exp2(dither_dot_scale) * dither_dots_per_side * 0.125;
			dither_spacing *= pow(brightness_curve_val * 2.0 + 0.001, -(1.0 - dither_size_variability));
			
			float spacing_log = log2(dither_spacing);
			int scale_level = int(floor(spacing_log));
			float blend_factor = spacing_log - float(scale_level);
			vec2 dither_final_uv = distorted_lighting_uv / exp2(float(scale_level));
			float sub_layer_coord = mix(0.25 * pow(dither_dots_per_side, 2.0), pow(dither_dots_per_side, 2.0), 1.0 - blend_factor);
			
			float dither_threshold = 1.0 - brightness_curve_val;
			if (dither_quantize_layers) {
				float original_sub_layer = sub_layer_coord;
				sub_layer_coord = floor(sub_layer_coord + 0.5);
				dither_threshold *= sqrt(sub_layer_coord / (original_sub_layer + 0.00001));
			}
			
			float pattern_value_sample = texture(dither_tex_3d, vec3(dither_final_uv, (sub_layer_coord - 0.5) / pow(dither_dots_per_side, 2.0))).r;
			float soft_range = dither_softness * 0.8;
			float black_white_mask = smoothstep(dither_threshold - soft_range, dither_threshold + soft_range, pattern_value_sample);
			
			if (dither_softness <= 0.01) {
				float contrast_multiplier = dither_contrast * exp2(dither_dot_scale) * 0.1 * pow(freq_vector.y / (freq_vector.x + 0.00001), dither_stretch_smoothness);
				black_white_mask = clamp((pattern_value_sample - dither_threshold) * contrast_multiplier + 0.5, 0.0, 1.0);
			}
			pattern_mask_value = dither_inverse_dots ? 1.0 - black_white_mask : black_white_mask;
		}
	}
	
	// --- BORDERS (Centered exactly on step transitions) ---
	float border_mask_value = 0.0;
	if (use_borders) {
		float border_half_width = border_width * 0.5;
		border_mask_value = step(0.5 - border_half_width, step_fraction) * step(step_fraction, 0.5 + border_half_width);
		border_mask_value *= step(light_multiplier, cuts_float - 0.4) * step(0.4, light_multiplier);
	}

	// --- FINAL COLOR ASSEMBLY ---
	float final_lighting_index = mix(diffuse_stepped_intensity, diffuse_stepped_intensity * pattern_mask_value, pattern_blend);
	float light_map_intensity = clamp(final_lighting_index * (1.0 - border_mask_value), 0.0, 1.0);
	
	vec3 base_diffuse_lighting = ALBEDO * LIGHT_COLOR / PI;
	vec3 diffuse_output_color;

	if (use_ramp) {
		diffuse_output_color = base_diffuse_lighting * texture(ramp_texture, vec2(light_map_intensity, 0.0)).rgb;
	} else {
		diffuse_output_color = mix(base_diffuse_lighting * shadow_tint.rgb * shadow_tint_amount, base_diffuse_lighting, light_map_intensity);
	}

	if (clamp_diffuse_to_max) {
		DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse_output_color);
	} else {
		DIFFUSE_LIGHT += diffuse_output_color;
	}

	// --- STYLIZED SPECULAR ---
	if (use_specular) {
		vec3 half_vector = normalize(LIGHT + VIEW);
		float normal_dot_half = dot(NORMAL, half_vector);
		float specular_base_value = clamp(normal_dot_half, 0.0, 1.0);
		float specular_mask_smooth = smoothstep(0.5 - specular_softness, 0.5 + specular_softness, pow(specular_base_value, specular_shininess));
		float specular_painterly_factor = use_painterly ? sharp_stroke_mask : 1.0;
		// Specular map respects the atlas region reconstruction
		float specular_map_intensity = texture(specular_map, tile_clamped_lighting_uv).r;
		
		SPECULAR_LIGHT += specular_mask_smooth * specular_strength * specular_painterly_factor * specular_map_intensity * LIGHT_COLOR;
	}

	// --- RIM LIGHT ---
	if (use_rim) {
		float fresnel_rim = pow(1.0 - clamp(normal_dot_view, 0.0, 1.0), rim_amount);
		float rim_intensity = smoothstep(0.5 - rim_smoothness/2.0, 0.5 + rim_smoothness/2.0, fresnel_rim);
		SPECULAR_LIGHT += rim_color.rgb * mix(rim_intensity, rim_intensity * clamp(normal_dot_light * attenuation_factor, 0.0, 1.0), rim_mask_shadow) * rim_blend * LIGHT_COLOR / PI;
	}
}