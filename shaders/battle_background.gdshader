shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// --- Palette ---
// Darker, more saturated EarthBound-style colors
uniform vec4 color_dark0 : source_color = vec4(0.0, 0.18, 0.22, 1.0);   // dark teal
uniform vec4 color_dark1 : source_color = vec4(0.08, 0.04, 0.18, 1.0);  // dark purple
uniform vec4 color_dark2 : source_color = vec4(0.18, 0.08, 0.0, 1.0);   // dark amber
uniform vec4 color_bright0 : source_color = vec4(0.0, 0.85, 0.6, 1.0);  // teal
uniform vec4 color_bright1 : source_color = vec4(0.9, 0.75, 0.0, 1.0);  // golden yellow
uniform vec4 color_bright2 : source_color = vec4(0.55, 0.2, 0.75, 1.0); // purple

// --- Controls ---
uniform float pattern_scale : hint_range(2.0, 24.0) = 7.0;
uniform float warp_strength : hint_range(0.0, 0.3) = 0.07;
uniform float warp_speed : hint_range(0.0, 3.0) = 0.9;
uniform float scroll_speed : hint_range(0.0, 1.0) = 0.15;
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.6;
uniform float color_cycle_speed : hint_range(0.0, 1.0) = 0.18;
uniform float shape_softness : hint_range(0.0, 1.0) = 0.18; // soft edge on diamonds

vec4 get_dark_color(float t) {
	t = mod(t, 3.0);
	if (t < 1.0) return mix(color_dark0, color_dark1, t);
	if (t < 2.0) return mix(color_dark1, color_dark2, t - 1.0);
	return mix(color_dark2, color_dark0, t - 2.0);
}

vec4 get_bright_color(float t) {
	t = mod(t, 3.0);
	if (t < 1.0) return mix(color_bright0, color_bright1, t);
	if (t < 2.0) return mix(color_bright1, color_bright2, t - 1.0);
	return mix(color_bright2, color_bright0, t - 2.0);
}

void fragment() {
	vec2 uv = UV;

	// --- Pulse / breathe ---
	float pulse = sin(TIME * pulse_speed) * 0.02;
	uv = (uv - 0.5) * (1.0 + pulse) + 0.5;

	// --- Warp — slow and hypnotic ---
	float warp_x = sin(uv.y * 4.0 + TIME * warp_speed) * warp_strength;
	float warp_y = cos(uv.x * 4.0 + TIME * warp_speed * 0.75) * warp_strength;
	uv.x += warp_x;
	uv.y += warp_y;

	// --- Slow diagonal scroll ---
	uv.x += TIME * scroll_speed * 0.04;
	uv.y += TIME * scroll_speed * 0.025;

	// --- Diamond / rotated square pattern ---
	// rotate UV 45 degrees to get diamonds from a grid
	vec2 pattern_uv = uv * pattern_scale;
	vec2 rotated = vec2(
		pattern_uv.x + pattern_uv.y,
		pattern_uv.x - pattern_uv.y
	) * 0.707; // normalize after 45deg rotation

	vec2 cell = floor(rotated);
	vec2 local = fract(rotated) - 0.5; // -0.5 to 0.5 within cell

	// diamond shape: |x| + |y| < threshold
	float diamond_size = 0.38 + sin(TIME * pulse_speed * 0.7) * 0.03;
	float dist = abs(local.x) + abs(local.y);
	float shape = smoothstep(diamond_size + shape_softness, diamond_size - shape_softness, dist);

	// --- Per-cell color phase offset ---
	float phase = (cell.x * 1.618 + cell.y * 2.414); // golden ratio offset for variety
	float time_dark = TIME * color_cycle_speed + phase * 0.4;
	float time_bright = TIME * color_cycle_speed + phase * 0.4 + 1.5;

	vec4 dark_col = get_dark_color(time_dark);
	vec4 bright_col = get_bright_color(time_bright);

	// shape = 1 inside diamond (bright), 0 outside (dark)
	vec4 final_color = mix(dark_col, bright_col, shape);

	ALBEDO = final_color.rgb;
}
