shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// Main color — deep purple (136/255 = 0.533)
uniform vec4 main_color : source_color = vec4(0.6, 0.0, 0.533, 1.0);

// Tweak these in the inspector
uniform float pixel_amount : hint_range(10.0, 120.0) = 60.0;
uniform float color_steps : hint_range(2.0, 20.0) = 10.0;
uniform float resolution_ratio : hint_range(0.5, 3.0) = 1.77;

float sawtooth(float a, float freq) {
	if (mod(a, freq) < freq * 0.5) return mod(a, freq * 0.5);
	return freq * 0.5 - mod(a, freq * 0.5);
}

void fragment() {
	vec2 uv = UV;

	// --- Pixelate ---
	uv.x = floor(uv.x * pixel_amount) / pixel_amount;
	uv.y = floor(uv.y * pixel_amount) / pixel_amount;

	// --- Interlacing ---
	float pix_amt = 2.0;
	if (mod(FRAGCOORD.y, pix_amt) < pix_amt * 0.5) {
		uv += 0.1 + sin(TIME * 0.2 + uv.y * 8.0) * 0.05;
	} else {
		uv -= 0.1 + sin(TIME * 0.2 + uv.y * 8.0 + 0.5) * 0.05;
	}

	vec2 uv2 = uv;

	// --- Background sawtooth pattern ---
	vec3 color = vec3(mod(abs(sawtooth(uv.x, 0.6) * resolution_ratio + sawtooth(uv.y, 0.6) + TIME * 0.3), 0.4)) * main_color.rgb;

	// --- Stripe overlay ---
	if (uv2.x < 0.5) {
		uv2.x = 1.0 - uv2.x;
	}
	if (uv2.y > 0.5) {
		uv2.y = 1.0 - uv2.y;
	}
	uv2.x += sin(uv2.y * 4.0 + TIME) * 0.1;

	if (mod(abs(uv2.x * resolution_ratio + uv2.y + TIME * 0.2), 0.2) < 0.1) {
		vec3 lines = vec3(cos(uv.x * 2.0 + TIME + uv.y * 3.0)) * main_color.rgb * 0.7;
		color = mix(color, lines, 0.3);
	}

	// --- SNES-style color quantization ---
	color = ceil(color * color_steps) / color_steps;

	ALBEDO = color;
}
