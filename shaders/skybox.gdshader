shader_type spatial;
render_mode unshaded, cull_front;
uniform sampler2D sky_texture : source_color;
uniform bool lock_aspect = false;
uniform float aspect_ratio = 1.3333333;
uniform vec2 fov = vec2(180.0, 90.0);
uniform ivec2 tiling = ivec2(1, 1);
uniform vec2 offset = vec2(0.0, 0.0);
// XY offset, ZW tiling
varying vec4 bg_coords;
void vertex() {
	// Camera YX rotation per Basis.get_euler source code
	float y = atan(VIEW_MATRIX[0][2], VIEW_MATRIX[2][2]);
	float x = asin(VIEW_MATRIX[1][2]);
	
	// Map rotation to screen space
	bg_coords.xy = vec2(y * -0.5, x) / PI;
	bg_coords.y += 0.5;
	
	bg_coords.w = fov.y / 180.0;
	bg_coords.z = !lock_aspect ? fov.x / 360.0 : VIEWPORT_SIZE.x / (VIEWPORT_SIZE.y * aspect_ratio) * bg_coords.w;
	
	// Keep background centered vertically when FOV changes
	bg_coords.y *= bg_coords.w > 1.0 ? 0.0 : 1.0 - bg_coords.w;
}
void fragment() {
	vec2 uv_offset = vec2(-offset.x, offset.y);
	vec2 uv = (SCREEN_UV + uv_offset) * bg_coords.zw + bg_coords.xy;
	uv *= vec2(tiling);
	ALBEDO = texture(sky_texture, uv).rgb;
}