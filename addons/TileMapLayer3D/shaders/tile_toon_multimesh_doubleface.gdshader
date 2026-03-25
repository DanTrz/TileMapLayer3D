shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon;

// --- ГРУППЫ ПАРАМЕТРОВ TILEMAP (DoubleFace) ---
group_uniforms Tile_MultiMesh;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;
uniform float inset_value : hint_range(0.0, 2.0) = 0.5;

// --- ГРУППЫ ПАРАМЕТРОВ TOON LIGHTING ---
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
uniform float specular_strength : hint_range(0.0, 1.0) = 1.0;
uniform float specular_shininess : hint_range(0.0, 32.0) = 16.0;
uniform sampler2D specular_map : source_color; // Соответствует атласу

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

varying flat vec4 uv_rect_data;
varying flat vec4 anim_data;
varying vec4 node_position;
varying float proj_00;
varying float proj_11;
varying vec2 tile_final_uv; // Рассчитанный UV кадра для фрагмента и света

void vertex() {
	uv_rect_data = INSTANCE_CUSTOM;
	anim_data = COLOR;
	
	node_position = (PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
	proj_00 = PROJECTION_MATRIX[0][0];
	proj_11 = PROJECTION_MATRIX[1][1];
}

void fragment() {
	// 1. ЛОГИКА АНИМАЦИИ ТАЙЛА
	vec2 uv_min = uv_rect_data.rg;
	vec2 uv_max = uv_rect_data.ba;

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
		vec2 offset = vec2(col * frame_step_x, row * frame_step_y);
		uv_min += offset;
		uv_max += offset;
	}

	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 remapped_uv = mix(uv_min, uv_max, flipped_uv);

	// 2. ИНСЕТЫ И ФИНАЛЬНЫЙ UV ТАЙЛА
	vec2 t_size = vec2(textureSize(albedo_texture_linear, 0));
	vec2 texel_inset = inset_value / t_size;
	tile_final_uv = clamp(remapped_uv, uv_min + texel_inset, uv_max - texel_inset);

	// 3. СЭМПЛИРОВАНИЕ ТЕКСТУРЫ
	vec4 tex_color;
	if (anim_total > 1.0) {
		tex_color = use_nearest_texture
			? textureLod(albedo_texture_nearest, tile_final_uv, 0.0)
			: textureLod(albedo_texture_linear, tile_final_uv, 0.0);
	} else {
		tex_color = use_nearest_texture
			? texture(albedo_texture_nearest, tile_final_uv)
			: texture(albedo_texture_linear, tile_final_uv);
	}

	// Discard прозрачных пикселей (важно для теней)
	if (tex_color.a < alpha_threshold) {
		discard;
	}

	ALBEDO = albedo_color.rgb * tex_color.rgb;
	
	// Карты нормалей (привязаны к UV тайла)
	vec3 n_map = texture(normal_texture, tile_final_uv).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n_map, normal_strength);
}

void light() {
	float atten = use_attenuation ? ATTENUATION : 1.0;
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_raw = clamp(NdotL + (atten - 1.0) + wrap, 0.0, 1.0);
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
			vec2 p_uv = (pattern_uv_mode == 1) ? SCREEN_UV : (pattern_uv_mode == 2 ? (SCREEN_UV * 2.0 - 1.0) * node_position.w - node_position.xy : UV);
			vec2 tuned_uv = p_uv * pattern_tiling * vec2(1.0, VIEWPORT_SIZE.y / VIEWPORT_SIZE.x);
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
			
			subLayer = (subLayer - 0.5) * invZres;
			float pattern_val = texture(dither_tex_3d, vec3(d_uv, subLayer)).r;
			
			float threshold = 1.0 - (dither_quantize_layers ? b_curve * sqrt(floor(mix(0.25 * pow(dotsPerSide, 2.0), pow(dotsPerSide, 2.0), 1.0 - f) + 0.5) / mix(0.25 * pow(dotsPerSide, 2.0), pow(dotsPerSide, 2.0), 1.0 - f)) : b_curve);
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
		// Спекуляр берется из соответствующего региона атласа
		float spec_map_val = texture(specular_map, tile_final_uv).r;
		float spec = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), specular_shininess * specular_shininess) * spec_map_val * atten;
		SPECULAR_LIGHT += step(0.5, spec) * specular_strength * LIGHT_COLOR;
	}
	if (use_rim) {
		float NdotV = dot(NORMAL, VIEW);
		float fresnel_v = pow(1.0 - clamp(NdotV, 0.0, 1.0), rim_amount);
		float rim_v = smoothstep(0.5 - rim_smoothness/2.0, 0.5 + rim_smoothness/2.0, fresnel_v);
		SPECULAR_LIGHT += rim_color.rgb * mix(rim_v, rim_v * clamp(NdotL * atten, 0.0, 1.0), rim_mask_shadow) * rim_blend * LIGHT_COLOR / PI;
	}
}