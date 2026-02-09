shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_toon, specular_toon;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
uniform bool use_nearest_texture = true;
uniform sampler2D albedo_texture_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_linear : source_color, filter_linear, repeat_disable;
uniform bool debug_show_backfaces = true;

varying vec4 v_uv_bounds;

void vertex() {
	vec4 base_uvs = INSTANCE_CUSTOM;
	vec4 anim_params = COLOR;

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
	// Инверсия Y для плоскостей (стандарт Godot 3D)
	vec2 mesh_uv = vec2(UV.x, 1.0 - UV.y);
	mesh_uv = clamp(mesh_uv, 0.001, 0.999);
	
	vec2 final_uv = mix(v_uv_bounds.rg, v_uv_bounds.ba, mesh_uv);
	
	vec4 tex = use_nearest_texture 
		? texture(albedo_texture_nearest, final_uv) 
		: texture(albedo_texture_linear, final_uv);
	
	if (tex.a < alpha_threshold) {
		discard;
	}

	if (debug_show_backfaces && !FRONT_FACING) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
	} else {
		ALBEDO = albedo_color.rgb * tex.rgb;
	}
	ALPHA = tex.a * albedo_color.a;
}