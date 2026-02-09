shader_type spatial;
// depth_draw_always предотвращает мерцание. cull_back — для корректных теней куба.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_toon, specular_toon;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;

varying vec4 v_uv_bounds;
varying float v_side_shadow; // Для визуального отделения граней

void vertex() {
	vec4 base_uvs = INSTANCE_CUSTOM;
	vec4 anim_params = COLOR;
	
	// Базовое затенение сторон в зависимости от нормали, чтобы куб не выглядел плоским
	// (Даже если в сцене плохой свет, грани будет видно)
	v_side_shadow = mix(1.0, 0.7, abs(NORMAL.x)); 
	v_side_shadow = mix(v_side_shadow, 0.8, abs(NORMAL.z));

	if (anim_params.r > 1.0) {
		float frames = anim_params.r;
		float speed = anim_params.g;
		float cols = max(anim_params.b, 1.0);
		float step_x = anim_params.a;
		
		float curr_f = floor(mod(TIME * speed, frames));
		float f_col = mod(curr_f, cols);
		float f_row = floor(curr_f / cols);
		
		float uv_w = base_uvs.b - base_uvs.r;
		float uv_h = base_uvs.a - base_uvs.g;
		float step_y = uv_h * (step_x / uv_w);
		
		vec2 shift = vec2(f_col * step_x, f_row * step_y);
		base_uvs.rg += shift;
		base_uvs.ba += shift;
	}
	v_uv_bounds = base_uvs;
}

void fragment() {
	// Ограничиваем UV, чтобы не захватывать соседние пиксели атласа
	vec2 mesh_uv = clamp(UV, 0.001, 0.999);
	
	// Вычисляем размер текущего кадра
	vec2 uv_size = v_uv_bounds.ba - v_uv_bounds.rg;
	// Накладываем UV меша на область кадра
	vec2 final_uv = v_uv_bounds.rg + mesh_uv * uv_size;
	
	vec4 tex;
	if (use_nearest_texture) {
		tex = texture(albedo_texture_nearest, final_uv);
	} else {
		tex = texture(albedo_texture_linear, final_uv);
	}
	
	if (tex.a < alpha_threshold) {
		discard;
	}

	// Умножаем на v_side_shadow, чтобы бока были чуть темнее и был виден объем
	ALBEDO = albedo_color.rgb * tex.rgb * v_side_shadow;
	ALPHA = tex.a * albedo_color.a;
}