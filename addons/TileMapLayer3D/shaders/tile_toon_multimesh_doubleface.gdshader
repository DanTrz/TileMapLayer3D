shader_type spatial;
// cull_disabled allows rendering both sides of the mesh, essential for thin tile meshes
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// ==========================================
// 1. TILEMAP & ATLAS SETTINGS
// ==========================================
group_uniforms Tile_MultiMesh;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;
// Inset prevents the sampler from picking up pixels from adjacent atlas tiles
uniform float inset_value : hint_range(0.0, 2.0) = 0.5; 

// ==========================================
// 2. PAINTERLY STYLE
// ==========================================
group_uniforms Painterly_Style;
uniform bool use_painterly = false;
uniform sampler2D brush_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float painterly_strength : hint_range(0.0, 2.0) = 0.5; 
uniform float painterly_tiling = 5.0; 
// Stretch transforms circular noise into brush stroke lines
uniform float painterly_stretch : hint_range(0.01, 1.0) = 0.2; 
// Sharpness defines how "hard" the brush stroke edges appear
uniform float painterly_sharpness : hint_range(0.001, 0.5) = 0.05; 
// Frames per second for the stop-motion "boiling" effect
uniform float painterly_frames_per_second : hint_range(0.0, 24.0) = 0.0;
uniform vec2 painterly_dir = vec2(1.0, 0.5); 

// ==========================================
// 3. INNER EROSION
// ==========================================
group_uniforms Inner_Erosion; 
uniform bool use_erosion = false;
// Intensity of the scratchy shadows eating into the lit areas
uniform float erosion_scale : hint_range(0.0, 5.0) = 1.0; 
// Distance threshold for how far the erosion reaches
uniform float erosion_threshold : hint_range(0.0, 1.0) = 0.5; 

// ==========================================
// 4. TOON LIGHTING BASE
// ==========================================
group_uniforms Lighting_Base;
uniform int cuts : hint_range(1, 256) = 3;
uniform float step_smoothness : hint_range(0.0, 1.0) = 0.1;
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness : hint_range(1.0, 8.0) = 1.0;
uniform bool use_attenuation = true;
uniform bool clamp_diffuse_to_max = false;

// ==========================================
// 5. SHADOW STYLIZATION
// ==========================================
group_uniforms Shadow_Stylization;
uniform bool use_ramp = false;
uniform sampler2D ramp_texture : source_color;
uniform vec4 shadow_tint : source_color = vec4(0.2, 0.2, 0.3, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0) = 0.3;
uniform bool use_borders = false;
uniform float border_width : hint_range(0.0, 0.5, 0.001) = 0.01; 

// ==========================================
// 6. SPECULAR & NORMAL MAP
// ==========================================
group_uniforms Specular;
uniform bool use_specular = true;
uniform float specular_strength : hint_range(0.0, 1.0) = 1.0;
uniform float specular_shininess : hint_range(0.0, 32.0) = 16.0;
// Edge softness for the stylized specular highlight
uniform float specular_softness : hint_range(0.0, 1.0) = 0.1; 
uniform sampler2D specular_map : source_color; 

group_uniforms Normal_Map;
uniform sampler2D normal_texture : hint_normal;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

// ==========================================
// 7. RIM LIGHT
// ==========================================
group_uniforms Rim_Light;
uniform bool use_rim = true;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount : hint_range(0.0, 16.0) = 2.0;
uniform float rim_smoothness : hint_range(0.0, 1.0) = 0.2;
uniform float rim_mask_shadow : hint_range(0.0, 1.0) = 1.0;
uniform float rim_blend : hint_range(0.0, 1.0) = 1.0;

// ==========================================
// 8. PATTERNS & DITHER3D
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
varying vec4 node_position;
varying float proj_00;
varying float proj_11;
varying vec2 v_uv_min;
varying vec2 v_uv_max;
varying float v_anim_total;
varying vec2 v_tile_uv; // Shared UV for textures

void vertex() {
	// Store projection matrix components for dither screen-space calculations
	node_position = (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	proj_00 = PROJECTION_MATRIX[0][0];
	proj_11 = PROJECTION_MATRIX[1][1];
	
	// Handle Tile Atlas coordinates and Animation data from MultiMesh
	vec4 uv_rect = INSTANCE_CUSTOM;
	vec4 anim = COLOR;
	vec2 min_u = uv_rect.rg;
	vec2 max_u = uv_rect.ba;

	float anim_total = anim.b;
	if (anim_total > 1.0) {
		float total = round(anim_total);
		float cols = max(floor(anim.a), 1.0);
		float speed = fract(anim.a) * 256.0;
		float frame_index = floor(mod(TIME * speed, total) + 0.001);
		// Calculate the frame offset in the atlas
		vec2 offset = vec2(mod(frame_index, cols) * anim.r, floor(frame_index / cols) * anim.g);
		min_u += offset;
		max_u += offset;
	}
	
	v_uv_min = min_u;
	v_uv_max = max_u;
	v_anim_total = anim_total;
}

void fragment() {
	// 1. ATLAS RECONSTRUCTION
	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(v_uv_min, v_uv_max, flipped_uv);
	
	vec2 painterly_uv = remapped_uv;

	// 2. PAINTERLY UV DISTORTION
	if (use_painterly) {
		float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		// Use UV for global noise continuity, incorporating stretch for stroke look
		vec2 brush_uv = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_dir);
		float noise_sample = texture(brush_texture, brush_uv).r;
		painterly_uv += (noise_sample - 0.5) * 0.05 * painterly_strength;
	}

	// 3. TEXTURE BLEED PROTECTION (INSET)
	vec2 atlas_texture_size = vec2(textureSize(albedo_texture_linear, 0));
	vec2 texel_inset_clamping = inset_value / atlas_texture_size;
	v_tile_uv = clamp(painterly_uv, v_uv_min + texel_inset_clamping, v_uv_max - texel_inset_clamping);

	// 4. ALBEDO SAMPLING & ALPHA DISCARD
	vec4 albedo_tex_sample;
	if (v_anim_total > 1.0) {
		albedo_tex_sample = use_nearest_texture
			? textureLod(albedo_texture_nearest, v_tile_uv, 0.0)
			: textureLod(albedo_texture_linear, v_tile_uv, 0.0);
	} else {
		albedo_tex_sample = use_nearest_texture
			? texture(albedo_texture_nearest, v_tile_uv)
			: texture(albedo_texture_linear, v_tile_uv);
	}

	// Discard transparent pixels to allow shadows and correct double-face sorting
	if (albedo_tex_sample.a < alpha_threshold) {
		discard;
	}

	ALBEDO = albedo_color.rgb * albedo_tex_sample.rgb;
	
	// NORMAL MAP APPLICATION
	// Sampled from the atlas using the same clamped UV
	vec3 normal_map_sample = texture(normal_texture, v_tile_uv).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), normal_map_sample, normal_strength);
}

void light() {
	// Reconstruct the atlas-clamped UVs for lighting features (Specular, etc)
	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(v_uv_min, v_uv_max, flipped_uv);
	
	vec2 distorted_uv_coordinates = remapped_uv;
	float stroke_mask_value = 0.5;
	float raw_brush_noise = 0.5;

	// Calculate stop-motion animation and distorted coordinates for lighting
	if (use_painterly) {
		float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		vec2 brush_uv_coordinates = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_dir);
		raw_brush_noise = texture(brush_texture, brush_uv_coordinates).r;
		stroke_mask_value = smoothstep(0.5 - painterly_sharpness, 0.5 + painterly_sharpness, raw_brush_noise);
		distorted_uv_coordinates += (stroke_mask_value - 0.5) * 0.05 * painterly_strength;
	}
	
	// Final tile-clamped UV used specifically for sampling maps in the light pass
	vec2 atlas_texture_size = vec2(textureSize(albedo_texture_linear, 0));
	vec2 texel_inset_clamping = inset_value / atlas_texture_size;
	vec2 tile_light_uv = clamp(distorted_uv_coordinates, v_uv_min + texel_inset_clamping, v_uv_max - texel_inset_clamping);

	// --- BASE LIGHTING CALCULATION ---
	float attenuation_factor = use_attenuation ? ATTENUATION : 1.0;
	float normal_dot_light = dot(NORMAL, LIGHT);
	float normal_dot_view = dot(NORMAL, VIEW);
	
	float diffuse_raw_intensity = normal_dot_light + (attenuation_factor - 1.0) + wrap;

	// Break up shadow edges with the painterly brush texture
	if (use_painterly) {
		diffuse_raw_intensity += (stroke_mask_value - 0.5) * painterly_strength;
	}
	
	// Apply inner rim erosion (the "scratchy" hand-painted shadow effect)
	if (use_painterly && use_erosion) {
		float fresnel_factor = 1.0 - clamp(normal_dot_view, 0.0, 1.0);
		float erosion_mask = smoothstep(erosion_threshold - 0.1, erosion_threshold + 0.1, raw_brush_noise * fresnel_factor);
		diffuse_raw_intensity -= erosion_mask * erosion_scale * (1.0 - clamp(normal_dot_light, 0.0, 1.0));
	}

	diffuse_raw_intensity = clamp(diffuse_raw_intensity, 0.0, 1.0);
	float diffuse_steep_intensity = clamp(diffuse_raw_intensity * steepness, 0.0, 1.0);

	// Toon Shading Stepping Logic
	float cuts_float = float(cuts);
	float light_multiplier = diffuse_steep_intensity * cuts_float;
	float step_fraction = fract(light_multiplier);
	float light_factor_smooth = smoothstep(0.5 - step_smoothness, 0.5 + step_smoothness, step_fraction);
	float diffuse_stepped_intensity = clamp((floor(light_multiplier) + light_factor_smooth) / cuts_float, 0.0, 1.0);

	// --- PATTERN & DITHER3D LOGIC ---
	float pattern_mask_value = 1.0;
	if (use_pattern) {
		if (pattern_type == 0) { // Standard Texture pattern
			vec2 pattern_coords = (pattern_uv_mode == 1) ? SCREEN_UV : (pattern_uv_mode == 2 ? (SCREEN_UV * 2.0 - 1.0) * node_position.w - node_position.xy : distorted_uv_coordinates);
			vec2 tuned_pattern_uv = pattern_coords * pattern_tiling * vec2(1.0, VIEWPORT_SIZE.y / VIEWPORT_SIZE.x);
			float pattern_tex_sample = texture(pattern_texture, tuned_pattern_uv).r;
			pattern_mask_value = clamp(smoothstep(pattern_tex_sample - pattern_smoothness, pattern_tex_sample + pattern_smoothness, diffuse_stepped_intensity + pattern_amount), 0.0, 1.0);
		} 
		else { // Dither3D pattern
			float brightness_input = clamp(diffuse_stepped_intensity * dither_input_exposure + dither_input_offset, 0.0, 1.0);
			if (dither_inverse_dots) brightness_input = 1.0 - brightness_input;

			ivec3 dither_tex_size = textureSize(dither_tex_3d, 0);
			float dither_x_res = float(dither_tex_size.x);
			float dots_per_side = dither_x_res / 16.0;
			float brightness_curve_val = texture(dither_ramp_tex, vec2((0.5 / dither_x_res + (1.0 - 1.0/dither_x_res) * brightness_input), 0.5)).r;
			
			vec2 derivative_x = dFdx(distorted_uv_coordinates); 
			vec2 derivative_y = dFdy(distorted_uv_coordinates);

			if (dither_radial_compensation) {
				vec2 screen_pos = (SCREEN_UV - 0.5) * 2.0;
				vec2 view_dir_proj = vec2(screen_pos.x / proj_00, screen_pos.y / proj_11);
				float radial_comp = dot(view_dir_proj, view_dir_proj) + 1.0;
				derivative_x *= radial_comp; derivative_y *= radial_comp;
			}

			// Frequency vector calculation for anti-aliased dither points
			float Q_math = dot(derivative_x, derivative_x) + dot(derivative_y, derivative_y);
			float R_math = derivative_x.x * derivative_y.y - derivative_y.x * derivative_x.y;
			float dither_disc = sqrt(max(0.0, Q_math * Q_math - 4.0 * R_math * R_math));
			vec2 freq_vec = sqrt(vec2(Q_math + dither_disc, Q_math - dither_disc) / 2.0);

			float d_spacing = freq_vec.y * exp2(dither_dot_scale) * dots_per_side * 0.125;
			d_spacing *= pow(brightness_curve_val * 2.0 + 0.001, -(1.0 - dither_size_variability));
			
			float log_spacing = log2(d_spacing);
			int scale_level = int(floor(log_spacing));
			float blend_f = log_spacing - float(scale_level);
			
			vec2 dither_uv_final = distorted_uv_coordinates / exp2(float(scale_level));
			float sublayer_coord = mix(0.25 * pow(dots_per_side, 2.0), pow(dots_per_side, 2.0), 1.0 - blend_f);
			
			float dither_threshold = 1.0 - brightness_curve_val;
			
			if (dither_quantize_layers) {
				float orig_sub = sublayer_coord;
				sublayer_coord = floor(sublayer_coord + 0.5);
				dither_threshold *= sqrt(sublayer_coord / (orig_sub + 0.00001));
			}
			
			float final_pattern_val = texture(dither_tex_3d, vec3(dither_uv_final, (sublayer_coord - 0.5) / pow(dots_per_side, 2.0))).r;
			float d_soft = dither_softness * 0.8; 
			float d_bw = smoothstep(dither_threshold - d_soft, dither_threshold + d_soft, final_pattern_val);
			
			if (dither_softness <= 0.01) {
				float c_multiplier = dither_contrast * exp2(dither_dot_scale) * 0.1 * pow(freq_vec.y / (freq_vec.x + 0.00001), dither_stretch_smoothness);
				d_bw = clamp((final_pattern_val - dither_threshold) * c_multiplier + 0.5, 0.0, 1.0);
			}
			pattern_mask_value = dither_inverse_dots ? 1.0 - d_bw : d_bw;
		}
	}
	
	// Borders logic centered on the toon color step transitions
	float border_mask = 0.0;
	if (use_borders) {
		float b_half = border_width * 0.5;
		border_mask = step(0.5 - b_half, step_fraction) * step(step_fraction, 0.5 + b_half);
		border_mask *= step(light_multiplier, cuts_float - 0.4) * step(0.4, light_multiplier);
	}

	// Final Light Index Assembly
	float final_light_idx = mix(diffuse_stepped_intensity, diffuse_stepped_intensity * pattern_mask_value, pattern_blend);
	float final_light_map = clamp(final_light_idx * (1.0 - border_mask), 0.0, 1.0);
	
	vec3 base_diff_color = ALBEDO * LIGHT_COLOR / PI;
	vec3 light_output;

	if (use_ramp) {
		light_output = base_diff_color * texture(ramp_texture, vec2(final_light_map, 0.0)).rgb;
	} else {
		light_output = mix(base_diff_color * shadow_tint.rgb * shadow_tint_amount, base_diff_color, final_light_map);
	}

	if (clamp_diffuse_to_max) {
		DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, light_output);
	} else {
		DIFFUSE_LIGHT += light_output;
	}

	// Stylized Specular using half-vector and atlas-clamped Specular Map
	if (use_specular) {
		vec3 h_vector = normalize(LIGHT + VIEW);
		float n_dot_h = dot(NORMAL, h_vector);
		float s_base = clamp(n_dot_h, 0.0, 1.0);
		float s_mask = smoothstep(0.5 - specular_softness, 0.5 + specular_softness, pow(s_base, specular_shininess));
		float s_painterly = use_painterly ? stroke_mask_value : 1.0;
		// Crucial: Sample specular map from the correct atlas region
		float s_map_val = texture(specular_map, tile_light_uv).r;
		
		SPECULAR_LIGHT += s_mask * specular_strength * s_painterly * s_map_val * LIGHT_COLOR;
	}

	// Rim Lighting calculation
	if (use_rim) {
		float f_rim = pow(1.0 - clamp(normal_dot_view, 0.0, 1.0), rim_amount);
		float r_intensity = smoothstep(0.5 - rim_smoothness/2.0, 0.5 + rim_smoothness/2.0, f_rim);
		SPECULAR_LIGHT += rim_color.rgb * mix(r_intensity, r_intensity * clamp(normal_dot_light * attenuation_factor, 0.0, 1.0), rim_mask_shadow) * rim_blend * LIGHT_COLOR / PI;
	}
}