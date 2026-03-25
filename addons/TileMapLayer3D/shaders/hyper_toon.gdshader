shader_type spatial;

// --- PARAMETER GROUPS ---

group_uniforms Albedo;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color;

group_uniforms Lighting_Base;
uniform int cuts : hint_range(1, 8) = 3;
uniform float step_smoothness : hint_range(0.0, 1.0) = 0.1;
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness : hint_range(1.0, 8.0) = 1.0;
uniform bool use_attenuation = true;
uniform bool clamp_diffuse_to_max = false;

group_uniforms Shadow_Stylization;
uniform bool use_ramp = false;
uniform sampler2D ramp_texture : source_color;
uniform vec4 shadow_tint : source_color = vec4(0.2, 0.2, 0.3, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0) = 0.3;
uniform bool use_borders = false;
uniform float border_width : hint_range(0.0, 0.5, 0.001) = 0.01; 

group_uniforms Specular;
uniform bool use_specular = true;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.8;
uniform float specular_shininess : hint_range(0.0, 32.0) = 16.0;
uniform float specular_softness : hint_range(0.0, 1.0) = 0.1; 
uniform sampler2D specular_map : source_color; 

group_uniforms Normal_Map;
uniform sampler2D normal_texture : hint_normal;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms Rim_Light;
uniform bool use_rim = true;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount : hint_range(0.0, 16.0) = 2.0;
uniform float rim_smoothness : hint_range(0.0, 1.0) = 0.2;
uniform float rim_mask_shadow : hint_range(0.0, 1.0) = 1.0;
uniform float rim_blend : hint_range(0.0, 1.0) = 1.0;

group_uniforms Painterly_Style;
uniform bool use_painterly = false;
uniform sampler2D brush_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float painterly_strength : hint_range(0.0, 2.0) = 0.5;
uniform float painterly_tiling = 5.0;
uniform float painterly_stretch : hint_range(0.01, 1.0) = 0.2; 
uniform float painterly_sharpness : hint_range(0.001, 0.5) = 0.05; 
uniform float painterly_frames_per_second : hint_range(0.0, 24.0) = 12.0; 
uniform vec2 painterly_direction = vec2(1.0, 0.5);

group_uniforms Inner_Erosion;
uniform bool use_erosion = false;
uniform float erosion_scale : hint_range(0.0, 5.0) = 1.0; 
uniform float erosion_threshold : hint_range(0.0, 1.0) = 0.5; 

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

group_uniforms Pattern_Dither3D_Core;
uniform sampler3D dither_texture_3d : filter_linear;
uniform sampler2D dither_ramp_texture : filter_linear;
uniform float dither_dot_scale : hint_range(2, 10) = 5.0;
uniform float dither_contrast : hint_range(0, 2) = 1.0; 
uniform float dither_input_exposure : hint_range(0, 5) = 1.0;
uniform float dither_input_offset : hint_range(-1, 1) = 0.0;

group_uniforms Pattern_Dither3D_Advanced;
uniform float dither_softness : hint_range(0.0, 2.0, 0.01) = 0.1; 
uniform float dither_size_variability : hint_range(0, 1) = 0.0;
uniform float dither_stretch_smoothness : hint_range(0, 2) = 1.0; 
uniform bool dither_inverse_dots = false;
uniform bool dither_radial_compensation = false;
uniform bool dither_quantize_layers = false;

varying vec4 vary_node_position;
varying float vary_projection_00;
varying float vary_projection_11;

void vertex() {
	// Project node position for screen-space calculations
	vary_node_position = (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	vary_projection_00 = PROJECTION_MATRIX[0][0];
	vary_projection_11 = PROJECTION_MATRIX[1][1];
}

void fragment() {
	// Sample base texture with clean UVs
	vec4 albedo_texture_sample = texture(albedo_texture, UV);
	ALBEDO = albedo_color.rgb * albedo_texture_sample.rgb;
	
	vec2 normal_uv_coordinates = UV;
	if (use_painterly) {
		float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		vec2 brush_uv = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_direction);
		float noise_sample = texture(brush_texture, brush_uv).r;
		// Apply painterly distortion to normal map UVs
		normal_uv_coordinates += (noise_sample - 0.5) * 0.05 * painterly_strength;
	}

	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_texture, normal_uv_coordinates).rgb, normal_strength);
}

void light() {
	vec2 distorted_uv_coordinates = UV;
	float stroke_mask_value = 0.5;
	float raw_brush_noise = 0.5;

	// Calculate stop-motion animation and distorted UVs
	if (use_painterly) {
		float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		vec2 brush_uv = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_direction);
		raw_brush_noise = texture(brush_texture, brush_uv).r;
		stroke_mask_value = smoothstep(0.5 - painterly_sharpness, 0.5 + painterly_sharpness, raw_brush_noise);
		distorted_uv_coordinates += (stroke_mask_value - 0.5) * 0.05 * painterly_strength;
	}

	float attenuation_value = use_attenuation ? ATTENUATION : 1.0;
	float normal_dot_light = dot(NORMAL, LIGHT);
	float normal_dot_view = dot(NORMAL, VIEW);
	
	float diffuse_raw_intensity = normal_dot_light + (attenuation_value - 1.0) + wrap;

	// Distort shadow edges with painterly mask
	if (use_painterly) {
		diffuse_raw_intensity += (stroke_mask_value - 0.5) * painterly_strength;
	}
	
	// Apply inner rim erosion (scratchy shadows)
	if (use_painterly && use_erosion) {
		float fresnel_factor = 1.0 - clamp(normal_dot_view, 0.0, 1.0);
		float erosion_pattern_value = smoothstep(erosion_threshold - 0.1, erosion_threshold + 0.1, raw_brush_noise * fresnel_factor);
		diffuse_raw_intensity -= erosion_pattern_value * erosion_scale * (1.0 - clamp(normal_dot_light, 0.0, 1.0));
	}

	diffuse_raw_intensity = clamp(diffuse_raw_intensity, 0.0, 1.0);
	float diffuse_steep_intensity = clamp(diffuse_raw_intensity * steepness, 0.0, 1.0);

	// Toon Shading Stepping
	float cuts_float = float(cuts);
	float light_multiplier = diffuse_steep_intensity * cuts_float;
	float step_fraction = fract(light_multiplier);
	float light_factor_smooth = smoothstep(0.5 - step_smoothness, 0.5 + step_smoothness, step_fraction);
	float diffuse_stepped_intensity = clamp((floor(light_multiplier) + light_factor_smooth) / cuts_float, 0.0, 1.0);

	// Pattern and Dither3D Logic
	float pattern_mask_value = 1.0;
	if (use_pattern) {
		if (pattern_type == 0) {
			vec2 screen_uv_mode_coordinates = (pattern_uv_mode == 1) ? SCREEN_UV : (pattern_uv_mode == 2 ? (SCREEN_UV * 2.0 - 1.0) * vary_node_position.w - vary_node_position.xy : distorted_uv_coordinates);
			vec2 tuned_pattern_uv = screen_uv_mode_coordinates * pattern_tiling * vec2(1.0, VIEWPORT_SIZE.y / VIEWPORT_SIZE.x);
			float pattern_texture_sample = texture(pattern_texture, tuned_pattern_uv).r;
			pattern_mask_value = clamp(smoothstep(pattern_texture_sample - pattern_smoothness, pattern_texture_sample + pattern_smoothness, diffuse_stepped_intensity + pattern_amount), 0.0, 1.0);
		} else {
			float brightness_input = clamp(diffuse_stepped_intensity * dither_input_exposure + dither_input_offset, 0.0, 1.0);
			if (dither_inverse_dots) brightness_input = 1.0 - brightness_input;
			
			ivec3 texture_size_integers = textureSize(dither_texture_3d, 0);
			float x_resolution = float(texture_size_integers.x);
			float inverse_x_resolution = 1.0 / x_resolution;
			float dots_per_side = x_resolution / 16.0;
			float inverse_z_resolution = 1.0 / pow(dots_per_side, 2.0);
			float brightness_curve_value = texture(dither_ramp_texture, vec2((0.5 * inverse_x_resolution + (1.0 - inverse_x_resolution) * brightness_input), 0.5)).r;
			
			vec2 derivative_x = dFdx(distorted_uv_coordinates); 
			vec2 derivative_y = dFdy(distorted_uv_coordinates);
			
			if (dither_radial_compensation) {
				vec2 screen_position = (SCREEN_UV - 0.5) * 2.0;
				vec2 view_direction_projection = vec2(screen_position.x / vary_projection_00, screen_position.y / vary_projection_11);
				float radial_compensation_factor = dot(view_direction_projection, view_direction_projection) + 1.0;
				derivative_x *= radial_compensation_factor; derivative_y *= radial_compensation_factor;
			}
			
			float dot_product_x = dot(derivative_x, derivative_x);
			float dot_product_y = dot(derivative_y, derivative_y);
			float dither_discriminant = sqrt(max(0.0, dot_product_x + dot_product_y));
			float dither_spacing = dither_discriminant * exp2(dither_dot_scale) * dots_per_side * 0.125;
			dither_spacing *= pow(brightness_curve_value * 2.0 + 0.001, -(1.0 - dither_size_variability));
			
			float spacing_logarithm = log2(dither_spacing);
			int scale_level_index = int(floor(spacing_logarithm));
			float blending_factor = spacing_logarithm - float(scale_level_index);
			vec2 level_uv_coordinates = distorted_uv_coordinates / exp2(float(scale_level_index));
			float sub_layer_coordinate = mix(0.25 * pow(dots_per_side, 2.0), pow(dots_per_side, 2.0), 1.0 - blending_factor);
			
			float dither_final_threshold = 1.0 - brightness_curve_value;
			
			// Use original sublayer value for threshold adjustment during quantization
			if (dither_quantize_layers) {
				float original_sub_layer = sub_layer_coordinate;
				sub_layer_coordinate = floor(sub_layer_coordinate + 0.5);
				float quantization_tweak = sqrt(sub_layer_coordinate / (original_sub_layer + 0.00001));
				dither_final_threshold *= quantization_tweak;
			}
			
			sub_layer_coordinate = (sub_layer_coordinate - 0.5) * inverse_z_resolution;
			float pattern_value_sample = texture(dither_texture_3d, vec3(level_uv_coordinates, sub_layer_coordinate)).r;
			float dither_soft_range = dither_softness * 0.8;
			float dither_black_white_mask = smoothstep(dither_final_threshold - dither_soft_range, dither_final_threshold + dither_soft_range, pattern_value_sample);
			
			// Sharp dither calculation using contrast and stretch smoothness parameters
			if (dither_softness <= 0.01) {
				float contrast_multiplier = dither_contrast * exp2(dither_dot_scale) * 0.1 * pow(1.0, dither_stretch_smoothness);
				dither_black_white_mask = clamp((pattern_value_sample - dither_final_threshold) * contrast_multiplier + 0.5, 0.0, 1.0);
			}
			pattern_mask_value = dither_inverse_dots ? 1.0 - dither_black_white_mask : dither_black_white_mask;
		}
	}
	
	// Borders logic centered on the toon step transitions
	float border_mask_value = 0.0;
	if (use_borders) {
		float border_half_width = border_width * 0.5;
		border_mask_value = step(0.5 - border_half_width, step_fraction) * step(step_fraction, 0.5 + border_half_width);
		border_mask_value *= step(light_multiplier, cuts_float - 0.4) * step(0.4, light_multiplier);
	}

	// Final Light Index Assembly
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

	// Stylized Specular logic using half-vector and specular map
	if (use_specular) {
		vec3 half_vector = normalize(LIGHT + VIEW);
		float normal_dot_half = dot(NORMAL, half_vector);
		float specular_base_value = clamp(normal_dot_half, 0.0, 1.0);
		float specular_mask_smooth = smoothstep(0.5 - specular_softness, 0.5 + specular_softness, pow(specular_base_value, specular_shininess));
		float specular_painterly_factor = use_painterly ? stroke_mask_value : 1.0;
		float specular_map_intensity = texture(specular_map, distorted_uv_coordinates).r;
		
		SPECULAR_LIGHT += specular_mask_smooth * specular_strength * specular_painterly_factor * specular_map_intensity * LIGHT_COLOR;
	}

	// Rim Lighting calculation
	if (use_rim) {
		float fresnel_rim = pow(1.0 - clamp(normal_dot_view, 0.0, 1.0), rim_amount);
		float rim_intensity = smoothstep(0.5 - rim_smoothness/2.0, 0.5 + rim_smoothness/2.0, fresnel_rim);
		SPECULAR_LIGHT += rim_color.rgb * mix(rim_intensity, rim_intensity * clamp(normal_dot_light * attenuation_value, 0.0, 1.0), rim_mask_shadow) * rim_blend * LIGHT_COLOR / PI;
	}
}