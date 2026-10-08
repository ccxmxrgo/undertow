shader_type canvas_item;
// Alpha-only cyberpunk visor overlay (D-03): vignette, rounded corners, faint scanlines.
// No screen texture / back buffer. Uses UV (not FRAGCOORD) so scanlines survive stretch.

uniform float vignette : hint_range(0.0, 1.0) = 0.55;
uniform float bottom_cap : hint_range(0.0, 1.0) = 0.35;
uniform float scan : hint_range(0.0, 0.2) = 0.06;
uniform float corner_radius_px = 64.0;

void fragment() {
	vec2 px = UV * vec2(1920.0, 1080.0);
	// (a) vignette: zero across the central region, rising to `vignette` at the corners.
	vec2 c = UV * 2.0 - 1.0;
	float edge_x = smoothstep(0.60, 1.0, abs(c.x));
	float edge_y = smoothstep(0.60, 1.0, abs(c.y));
	float v = vignette * edge_x * (0.7 + 0.3 * edge_y);  // exactly 0 where |x| < 0.60
	if (c.y > 0.0) {
		v = min(v, bottom_cap * vignette);
	}
	// (b) rounded-corner mask: fade to black near the corners.
	vec2 d = min(px, vec2(1920.0, 1080.0) - px);
	vec2 q = max(vec2(corner_radius_px) - d, vec2(0.0));
	float corner = smoothstep(0.0, corner_radius_px, length(q));
	// (c) static scanlines: 540 lines over the canvas height.
	float line = step(0.5, fract(UV.y * 540.0));
	float a = v + corner * (1.0 - v) + scan * line;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 1.0));
}
