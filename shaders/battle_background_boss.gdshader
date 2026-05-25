shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// --- Colors ---
uniform vec4 color_base : source_color = vec4(0.25, 0.02, 0.04, 1.0);      // deep crimson base
uniform vec4 color_primary : source_color = vec4(0.55, 0.08, 0.12, 1.0);   // primary diamond
uniform vec4 color_ghost : source_color = vec4(0.65, 0.12, 0.18, 1.0);     // ghost diamond

// --- Controls ---
uniform float diamond_scale : hint_range(0.5, 6.0) = 1.8;      // how large the diamonds are
uniform float scroll_speed : hint_range(0.0, 2.0) = 0.4;       // primary scroll speed
uniform float ghost_opacity : hint_range(0.0, 1.0) = 0.35;     // how visible the ghost layer is
uniform float wave_strength : hint_range(0.0, 0.3) = 0.06;     // ripple/wave distortion
uniform float wave_speed : hint_range(0.0, 3.0) = 1.1;         // ripple speed
uniform float wave_frequency : hint_range(1.0, 12.0) = 4.5;    // ripple frequency
uniform float brightness_pulse : hint_range(0.0, 0.3) = 0.08;  // slow brightness breathe

// returns 0-1 diamond shape value for a given uv
// 1 = inside diamond highlight, 0 = base
float diamond_pattern(vec2 uv) {
	// rotate 45 degrees to get diamonds from a square grid
	vec2 rotated = vec2(
		uv.x + uv.y,
		uv.x - uv.y
	) * 0.707;
	vec2 local = fract(rotated) - 0.5;
	float dist = abs(local.x) + abs(local.y);
	// soft edge diamond
	return smoothstep(0.48, 0.28, dist);
}

void fragment() {
	vec2 uv = UV;

	// --- Wave / ripple distortion ---
	float wave_x = sin(uv.y * wave_frequency + TIME * wave_speed) * wave_strength;
	float wave_y = cos(uv.x * wave_frequency * 0.7 + TIME * wave_speed * 0.8) * wave_strength * 0.6;
	uv.x += wave_x;
	uv.y += wave_y;

	// --- Primary layer — scrolls left to right ---
	vec2 uv_primary = uv * diamond_scale;
	uv_primary.x += TIME * scroll_speed * 0.08;
	uv_primary.y += TIME * scroll_speed * 0.01; // slight vertical drift
	float primary = diamond_pattern(uv_primary);

	// --- Ghost layer — scrolls right to left, offset position ---
	vec2 uv_ghost = uv * diamond_scale;
	uv_ghost.x -= TIME * scroll_speed * 0.06; // opposite direction, slightly slower
	uv_ghost.x += 0.5; // offset so ghost diamonds sit between primary ones
	uv_ghost.y += 0.5;
	uv_ghost.y -= TIME * scroll_speed * 0.008;
	float ghost = diamond_pattern(uv_ghost);

	// --- Slow brightness pulse ---
	float pulse = 1.0 + sin(TIME * 0.7) * brightness_pulse;

	// --- Composite ---
	// start with base, add primary diamonds, then ghost on top at reduced opacity
	vec3 col = color_base.rgb;
	col = mix(col, color_primary.rgb * pulse, primary * 0.85);
	col = mix(col, color_ghost.rgb * pulse, ghost * ghost_opacity);

	ALBEDO = col;
}
