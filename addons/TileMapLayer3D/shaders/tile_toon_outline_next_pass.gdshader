shader_type spatial;
// cull_front is essential for the inverted hull method
// depth_draw_always ensures it sorts correctly with the main pass
render_mode cull_front, unshaded, depth_draw_always; 

// ==========================================
// TILEMAP DATA (Crucial for Atlas support)
// ==========================================
group_uniforms Tile_Data;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;

// ==========================================
// OUTLINE SETTINGS
// ==========================================
group_uniforms Outline_Settings;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.5) = 0.02; 
uniform float outline_wobble_intensity : hint_range(0.0, 1.0) = 0.5;

// ==========================================
// PAINTERLY STYLE
// ==========================================
group_uniforms Painterly_Outline;
uniform bool use_painterly = true;
uniform sampler2D brush_texture : hint_default_white, repeat_enable;
uniform float painterly_tiling = 5.0;
uniform float painterly_stretch : hint_range(0.01, 1.0) = 0.2;
uniform float painterly_frames_per_second : hint_range(0.0, 24.0) = 12.0;
uniform vec2 painterly_direction = vec2(1.0, 0.5);
uniform float outline_threshold : hint_range(0.0, 1.0) = 0.5; 

// VARYINGS to pass tile data from vertex to fragment
varying flat vec4 vary_uv_rect;
varying flat vec4 vary_anim_data;

void vertex() {
	// Capture the same instance data as the main shader
	vary_uv_rect = INSTANCE_CUSTOM;
	vary_anim_data = COLOR;

	float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
	
	// Synchronize noise with the main pass
	vec2 brush_uv_coordinates = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_direction);
	float noise_sample_value = texture(brush_texture, brush_uv_coordinates).r;
	
	float final_thickness_value = outline_thickness;
	if (use_painterly) {
		// Randomize thickness to give it a hand-drawn "jittery" feel
		float wobble_factor = mix(1.0, noise_sample_value * 2.0, outline_wobble_intensity);
		final_thickness_value *= wobble_factor;
	}
	
	// Expand the mesh to create the silhouette shell
	VERTEX += NORMAL * final_thickness_value;
}

void fragment() {
	// --- 1. RECONSTRUCT TILE UV (Same logic as main shader) ---
	vec2 uv_min = vary_uv_rect.rg;
	vec2 uv_max = vary_uv_rect.ba;

	float frame_step_x = vary_anim_data.r;
	float frame_step_y = vary_anim_data.g;
	float anim_total = vary_anim_data.b;
	float cols_and_speed = vary_anim_data.a;

	if (anim_total > 1.0) {
		float total = round(anim_total);
		float cols = max(floor(cols_and_speed), 1.0);
		float speed = fract(cols_and_speed) * 256.0;
		float frame_index = floor(mod(TIME * speed, total) + 0.001);
		vec2 offset = vec2(mod(frame_index, cols) * frame_step_x, floor(frame_index / cols) * frame_step_y);
		uv_min += offset;
		uv_max += offset;
	}

	vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);
	vec2 tile_uv = mix(uv_min, uv_max, flipped_uv);

	// --- 2. MASK OUTLINE BY TILE ALPHA ---
	// This ensures the outline only appears around the actual image on the tile
	vec4 atlas_sample = texture(albedo_texture, tile_uv);
	if (atlas_sample.a < alpha_threshold) {
		discard; 
	}

	// Set outline base color
	ALBEDO = outline_color.rgb;
	
	// --- 3. PAINTERLY SKETCHY DISCARD ---
	if (use_painterly) {
		float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		
		// Ensure brush coordinates are identical to the vertex pass
		vec2 brush_uv_coordinates = (UV * vec2(painterly_tiling, painterly_tiling * painterly_stretch)) + (choppy_time * painterly_direction);
		float noise_sample_value = texture(brush_texture, brush_uv_coordinates).r;
		
		// If noise is low, discard the pixel to create gaps in the outline
		if (noise_sample_value < outline_threshold) {
			discard;
		}
	}
}