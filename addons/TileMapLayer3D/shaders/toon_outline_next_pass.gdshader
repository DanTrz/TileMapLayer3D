shader_type spatial;
// cull_front is essential for the inverted hull method to only show the "back" of the expanded mesh
render_mode cull_front, unshaded; 

// --- PARAMETER GROUPS ---

group_uniforms Outline_Settings;
// The base color of the outline strokes
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// The base thickness of the outline shell
uniform float outline_thickness : hint_range(0.0, 0.5) = 0.02; 
// Intensity of the thickness variations based on the brush noise
uniform float outline_wobble_intensity : hint_range(0.0, 1.0) = 0.5;

group_uniforms Painterly_Outline;
// Toggle for the sketchy painterly effects
uniform bool use_painterly = true;
// Noise texture representing brush strokes, used for both shape and transparency
uniform sampler2D brush_texture : hint_default_white, repeat_enable;
// Scale factor for the brush texture
uniform float painterly_tiling = 5.0;
// Frame rate for the stop-motion "boiling" effect
uniform float painterly_frames_per_second : hint_range(0.0, 24.0) = 12.0;
// Direction and speed of the texture offset over time
uniform vec2 painterly_direction = vec2(1.0, 0.5);
// Cutoff point for transparency; higher values make the outline more fragmented
uniform float outline_threshold : hint_range(0.0, 1.0) = 0.5; 

void vertex() {
	// Calculate the stepped time to achieve a traditional animation/stop-motion feel
	float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
	
	// Synchronize UV coordinates with the main body shader using the same tiling and 0.2 horizontal stretch
	vec2 brush_uv_coordinates = (UV * vec2(painterly_tiling, painterly_tiling * 0.2)) + (choppy_time * painterly_direction);
	
	// Sample the noise to determine local thickness displacement
	float noise_sample_value = texture(brush_texture, brush_uv_coordinates).r;
	float final_thickness_value = outline_thickness;
	
	if (use_painterly) {
		// Video Part 4 Logic: Dynamically vary the thickness to create a "Scribble" effect.
		// This simulates the look of a hand-drawn line where pressure or multiple strokes vary.
		float wobble_factor = mix(1.0, noise_sample_value * 2.0, outline_wobble_intensity);
		final_thickness_value *= wobble_factor;
	}
	
	// Displace the vertices along the vertex normals to create the outline hull
	VERTEX += NORMAL * final_thickness_value;
}

void fragment() {
	// Set the basic color of the outline
	ALBEDO = outline_color.rgb;
	
	if (use_painterly) {
		// Calculate choppy time again for fragment-based transparency synchronization
		float choppy_time = (painterly_frames_per_second > 0.001) ? (floor(TIME * painterly_frames_per_second) / painterly_frames_per_second) : 0.0;
		
		// Use the same coordinate logic to ensure transparency gaps match the stroke movement
		vec2 brush_uv_coordinates = (UV * vec2(painterly_tiling, painterly_tiling * 0.2)) + (choppy_time * painterly_direction);
		float noise_sample_value = texture(brush_texture, brush_uv_coordinates).r;
		
		// Sketchy/Smudgy effect: discard pixels where the noise is below the threshold.
		// This creates a broken line effect similar to a dry brush or pencil sketch.
		if (noise_sample_value < outline_threshold) {
			discard;
		}
	}
}