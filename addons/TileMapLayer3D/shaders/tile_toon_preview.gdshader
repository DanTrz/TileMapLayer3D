shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// ==========================================
// TILE PREVIEW SETTINGS
// ==========================================
group_uniforms Tile_Preview;
uniform sampler2D atlas_texture : source_color, filter_linear, repeat_disable;
uniform vec2 uv_region_min = vec2(0.0, 0.0);
uniform vec2 uv_region_max = vec2(1.0, 1.0);
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;

// ==========================================
// PAINTERLY STYLE
// ==========================================
group_uniforms Painterly_Style;
uniform bool use_painterly = false;
uniform sampler2D brush_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float painterly_strength : hint_range(0.0, 2.0) = 0.5; // Strength of brush edge breakup
uniform float painterly_tiling = 5.0; // Scale of the brush texture
uniform float painterly_fps : hint_range(0.0, 24.0) = 0.0; // Stop-motion animation speed (0 = static)
uniform vec2 painterly_dir = vec2(1.0, 0.5); // Animation scroll direction

// ==========================================
// TOON LIGHTING BASE
// ==========================================
group_uniforms Lighting_Base;
uniform int cuts : hint_range(1, 8) = 3;
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
uniform float border_width : hint_range(0.0, 0.5, 0.001) = 0.01; 

// ==========================================
// SPECULAR & NORMAL MAP
// ==========================================
group_uniforms Specular;
uniform bool use_specular = true;
uniform float specular_strength : hint_range(0.0, 1.0) = 1.0;
uniform float specular_shininess : hint_range(0.0, 32.0) = 16.0;
uniform sampler2D specular_map : source_color; // Must be part of the atlas

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
// PAINTERLY STYLE
// ==========================================
group_uniforms Painterly_Style;
uniform bool use_painterly = false;
uniform sampler2D brush_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float painterly_strength : hint_range(0.0, 2.0) = 0.5;
uniform float painterly_tiling = 5.0;
uniform float painterly_fps : hint_range(0.0, 24.0) = 0.0;
uniform vec2 painterly_dir = vec2(1.0, 0.5);

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

group_uniforms Pattern_Dither3D_Core;
uniform sampler3D dither_tex_3d : filter_linear;
uniform sampler2D dither_ramp_tex : filter_linear;
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

// ==========================================
// VARYINGS
// ==========================================
varying vec4 node_position;
varying float proj_00;
varying float proj_11;

void vertex() {
	// Store node position and projection parameters for Local Screen and Radial Compensation
	node_position = (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	proj_00 = PROJECTION_MATRIX[0][0];
	proj_11 = PROJECTION_MATRIX[1][1];
}

void fragment() {
	// 1. RECALCULATE UV FOR ATLAS REGION
	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(uv_region_min, uv_region_max, flipped_uv);

	// 2. PAINTERLY UV DISTORTION (Applies before clamping)
	vec2 p_uv = remapped_uv;
	if (use_painterly) {
		// Stop-motion time logic. If FPS <= 0.0, animation completely stops
		float choppy_time = (painterly_fps > 0.0) ? (floor(TIME * painterly_fps) / painterly_fps) : 0.0;
		vec2 brush_uv = (UV * painterly_tiling) + (choppy_time * painterly_dir);
		float noise = texture(brush_texture, brush_uv).r;
		p_uv += (noise - 0.5) * 0.05 * painterly_strength;
	}

	// 3. PREVENT TEXTURE BLEEDING (Atlas Bleed)
	vec2 tex_size = vec2(textureSize(atlas_texture, 0));
	vec2 half_texel = 0.5 / tex_size;
	vec2 clamped_uv = clamp(p_uv, uv_region_min + half_texel, uv_region_max - half_texel);

	vec2 tile_uv = clamped_uv;
	if (use_nearest_texture) {
		// Pixel snap for nearest filter
		tile_uv = (floor(clamped_uv * tex_size) + 0.5) / tex_size;
	}

	// 4. COLOR AND TRANSPARENCY
	vec4 tex_color = texture(atlas_texture, tile_uv);

	if (tex_color.a < alpha_threshold) {
		discard;
	}

	ALBEDO = albedo_color.rgb * tex_color.rgb;

	// NORMALS (Sampled from atlas)
	vec3 n_map = texture(normal_texture, tile_uv).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n_map, normal_strength);
}

void light() {
	// --- RECONSTRUCT TILE UV FOR LIGHT PASS ---
	// Godot 4 doesn't allow passing varyings from fragment to light, so we rebuild it here
	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(uv_region_min, uv_region_max, flipped_uv);
	vec2 p_uv = remapped_uv;
	
	if (use_painterly) {
		float choppy_time = (painterly_fps > 0.0) ? (floor(TIME * painterly_fps) / painterly_fps) : 0.0;
		vec2 brush_uv = (UV * painterly_tiling) + (choppy_time * painterly_dir);
		float noise = texture(brush_texture, brush_uv).r;
		p_uv += (noise - 0.5) * 0.05 * painterly_strength;
	}
	
	vec2 tex_size = vec2(textureSize(atlas_texture, 0));
	vec2 half_texel = 0.5 / tex_size;
	vec2 tile_uv = clamp(p_uv, uv_region_min + half_texel, uv_region_max - half_texel);
	if (use_nearest_texture) tile_uv = (floor(tile_uv * tex_size) + 0.5) / tex_size;

	// --- BASE LIGHTING ---
	float atten = use_attenuation ? ATTENUATION : 1.0;
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_raw = clamp(NdotL + (atten - 1.0) + wrap, 0.0, 1.0);

	// --- PAINTERLY SHADOW BREAKUP ---
	if (use_painterly) {
		float choppy_time = (painterly_fps > 0.0) ? (floor(TIME * painterly_fps) / painterly_fps) : 0.0;
		vec2 brush_uv = (UV * painterly_tiling) + (choppy_time * painterly_dir);
		float brush_noise = texture(brush_texture, brush_uv).r;
		
		// Shift the shadow edge using the brush texture
		diffuse_raw += (brush_noise - 0.5) * painterly_strength;
		diffuse_raw = clamp(diffuse_raw, 0.0, 1.0);
	}

	// --- TOON STEPPING ---
	float diffuse_steep = clamp(diffuse_raw * steepness, 0.0, 1.0);
	float cuts_f = float(cuts);
	float light_mult = diffuse_steep * cuts_f;
	float step_fract = fract(light_mult);
	float light_factor = smoothstep(0.5 - step_smoothness, 0.5 + step_smoothness, step_fract);
	float diffuse_stepped = clamp((floor(light_mult) + light_factor) / cuts_f, 0.0, 1.0);

	// --- PATTERN LOGIC ---
	float pattern_mask = 1.0;
	if (use_pattern) {
		if (pattern_type == 0) { // Standard Texture
			vec2 pat_uv = (pattern_uv_mode == 1) ? SCREEN_UV : (pattern_uv_mode == 2 ? (SCREEN_UV * 2.0 - 1.0) * node_position.w - node_position.xy : UV);
			vec2 tuned_uv = pat_uv * pattern_tiling * vec2(1.0, VIEWPORT_SIZE.y / VIEWPORT_SIZE.x);
			float pat_tex = texture(pattern_texture, tuned_uv).r;
			pattern_mask = clamp(smoothstep(pat_tex - pattern_smoothness, pat_tex + pattern_smoothness, diffuse_stepped + pattern_amount), 0.0, 1.0);
		} 
		else { // Dither3D
			float b = clamp(diffuse_stepped * dither_input_exposure + dither_input_offset, 0.0, 1.0);
			if (dither_inverse_dots) b = 1.0 - b;

			ivec3 tex_size_i = textureSize(dither_tex_3d, 0);
			float xRes = float(tex_size_i.x);
			float invXres = 1.0 / xRes;
			float dotsPerSide = xRes / 16.0;
			float invZres = 1.0 / pow(dotsPerSide, 2.0);

			float b_curve = texture(dither_ramp_tex, vec2((0.5 * invXres + (1.0 - invXres) * b), 0.5)).r;
			vec2 dx = dFdx(UV); vec2 dy = dFdy(UV);

			if (dither_radial_compensation) {
				vec2 screenP = (SCREEN_UV - 0.5) * 2.0;
				vec2 viewDirProj = vec2(screenP.x / proj_00, screenP.y / proj_11);
				float radialComp = dot(viewDirProj, viewDirProj) + 1.0;
				dx *= radialComp; dy *= radialComp;
			}

			float Q = dot(dx, dx) + dot(dy, dy);
			float R = dx.x * dy.y - dx.y * dx.x;
			float discriminant = sqrt(max(0.0, Q*Q - 4.0*R*R));
			vec2 freq = sqrt(vec2(Q + discriminant, Q - discriminant) / 2.0);
			
			float spacing = freq.y * exp2(dither_dot_scale) * dotsPerSide * 0.125;
			spacing *= pow(b_curve * 2.0 + 0.001, -(1.0 - dither_size_variability));
			
			float spacingLog = log2(spacing);
			int pScaleLevel = int(floor(spacingLog));
			float f = spacingLog - float(pScaleLevel);
			
			vec2 d_uv = UV / exp2(float(pScaleLevel));
			float subLayer = mix(0.25 * pow(dotsPerSide, 2.0), pow(dotsPerSide, 2.0), 1.0 - f);
			
			float thresholdTweak = 1.0;
			if (dither_quantize_layers) {
				float origSub = subLayer; subLayer = floor(subLayer + 0.5);
				thresholdTweak = sqrt(subLayer / origSub);
			}
			subLayer = (subLayer - 0.5) * invZres;
			
			float pattern_val = texture(dither_tex_3d, vec3(d_uv, subLayer)).r;
			float threshold = 1.0 - (dither_quantize_layers ? b_curve * thresholdTweak : b_curve);
			float soft = dither_softness * 0.8; 
			float bw = smoothstep(threshold - soft, threshold + soft, pattern_val);
			
			if (dither_softness <= 0.005) {
				float c_val = dither_contrast * exp2(dither_dot_scale) * 0.1 * pow(freq.y / freq.x, dither_stretch_smoothness);
				float baseVal = mix(0.5, b, clamp(1.05 / (1.0 + c_val), 0.0, 1.0));
				bw = clamp((pattern_val - threshold) * c_val + baseVal, 0.0, 1.0);
			}
			pattern_mask = dither_inverse_dots ? 1.0 - bw : bw;
		}
	}
	
	// --- BORDERS ---
	float border = 0.0;
	if (use_borders) {
		border = step(1.0 - border_width, step_fract) * step(light_mult, cuts_f - 0.1) * step(0.1, light_mult);
	}

	// --- FINAL COLOR ASSEMBLY ---
	float final_light_idx = mix(diffuse_stepped, diffuse_stepped * pattern_mask, pattern_blend);
	float light_map = clamp(final_light_idx * (1.0 - border), 0.0, 1.0);
	
	vec3 base_diff = ALBEDO * LIGHT_COLOR / PI;
	vec3 diff_out;

	if (use_ramp) {
		diff_out = base_diff * texture(ramp_texture, vec2(light_map, 0.0)).rgb;
	} else {
		diff_out = mix(base_diff * shadow_tint.rgb * shadow_tint_amount, base_diff, light_map);
	}

	if (clamp_diffuse_to_max) {
		DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diff_out);
	} else {
		DIFFUSE_LIGHT += diff_out;
	}

	// --- SPECULAR & RIM ---
	if (use_specular) {
		float spec = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), specular_shininess * specular_shininess) * texture(specular_map, tile_uv).r * atten;
		SPECULAR_LIGHT += step(0.5, spec) * specular_strength * LIGHT_COLOR;
	}
	if (use_rim) {
		float NdotV = dot(NORMAL, VIEW);
		float fresnel_v = pow(1.0 - clamp(NdotV, 0.0, 1.0), rim_amount);
		float rim_v = smoothstep(0.5 - rim_smoothness/2.0, 0.5 + rim_smoothness/2.0, fresnel_v);
		SPECULAR_LIGHT += rim_color.rgb * mix(rim_v, rim_v * clamp(NdotL * atten, 0.0, 1.0), rim_mask_shadow) * rim_blend * LIGHT_COLOR / PI;
	}
}