shader_type canvas_item;
// Sonar CRT pass on the highway surface (02.2 UI-SPEC 7.4 row 2, section 11). It sits on the
// Highway's "Surface" Polygon2D (show_behind_parent), so it shades only the lane-strip fill;
// separators, beat lines, the hit line, sustains, receptors and the gems are drawn later by
// other canvas items and are never touched (S-12, T-02.2-17). The vertex colour carries the
// strip fill (HIGHWAY_BASE plus the tier tint and the bottom fade); this pass adds:
//   - lit-glass lane edges: each strip glows faintly in its own lane colour near its edges,
//   - phosphor: a small SONAR lift near the outer rails,
//   - a sonar sweep band once per bar from the hit line to the far end, with an afterglow trail,
//   - scanlines: 2 px darker every 4 px.
// Every colour arrives as a uniform set from Palette by Highway; this file holds no colour
// constants (VIS-01). Low effects removes the material (plain strips); Reduce motion keeps
// the scanlines and turns the sweep off.

uniform vec4 scan_color : source_color;
uniform vec4 sweep_color : source_color;
uniform vec4 lane_color_0 : source_color;
uniform vec4 lane_color_1 : source_color;
uniform vec4 lane_color_2 : source_color;
uniform vec4 lane_color_3 : source_color;
// Sweep position in depth units: 0 = hit line, 1 = far end (set per frame from the bar phase).
uniform float sweep_pos = 0.0;
uniform float sweep_gain = 0.05;
// Afterglow length in depth units (400 ms expressed as a fraction of one bar).
uniform float afterglow = 0.2;
uniform float band_px = 80.0;
uniform float phosphor = 0.015;
uniform float lane_edge_gain = 0.10;
uniform float lane_edge_px = 7.0;
uniform bool scanlines_on = true;
uniform bool sweep_on = true;
// Trench projection (Highway sets these from Trench so the shader and the board agree).
uniform float vp_x = 960.0;
uniform float vp_y = 396.0;
uniform float travel = 534.0;
uniform float perspective = 0.70;
uniform float lane_spread = 210.0;
uniform float far_spread = 0.35;
// Depth where the sweep and phosphor start fading toward the far end (Trench.LINE_FADE_START).
uniform float fade_start = 0.45;

varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX;
}

float smin() {
	return 1.0 / (1.0 + perspective);
}

// Normalised projection n (0 at the far end, 1 at the hit line) for a screen y.
float norm_at_y(float y) {
	return (y - vp_y) / travel;
}

// Linear depth d for a projection n (inverse of Trench.point).
float depth_at_n(float n) {
	float s = smin() + clamp(n, 0.0, 1.2) * (1.0 - smin());
	return (1.0 / s - 1.0) / perspective;
}

float y_at_depth(float d) {
	float s = 1.0 / (1.0 + perspective * d);
	return vp_y + travel * (s - smin()) / (1.0 - smin());
}

vec3 lane_rgb(float lane) {
	if (lane < 0.5) {
		return lane_color_0.rgb;
	} else if (lane < 1.5) {
		return lane_color_1.rgb;
	} else if (lane < 2.5) {
		return lane_color_2.rgb;
	}
	return lane_color_3.rgb;
}

void fragment() {
	vec4 c = COLOR;
	float n = norm_at_y(v_pos.y);
	float d = depth_at_n(n);
	float lane_w = lane_spread * (far_spread + (1.0 - far_spread) * clamp(n, 0.0, 1.2));
	float f = (v_pos.x - vp_x) / max(lane_w, 0.001);
	float u = clamp(f + 2.0, 0.0, 3.999);
	float lane = floor(u);
	float fr = u - lane;
	// Lit-glass lane edges, fading toward the far end so the vanishing point stays dark.
	float edge_dist = min(fr, 1.0 - fr) * lane_w;
	float glass = exp(-edge_dist / lane_edge_px) * lane_edge_gain * smoothstep(0.0, 0.5, n);
	c.rgb += lane_rgb(lane) * glass;
	// Phosphor lift near the outer rails.
	float rail = smoothstep(1.55, 2.0, abs(f));
	float far_fade = 1.0 - smoothstep(fade_start, 1.0, d);
	c.rgb += sweep_color.rgb * phosphor * rail * far_fade;
	if (sweep_on) {
		float ys = y_at_depth(sweep_pos);
		float below = v_pos.y - ys;
		float band = below >= 0.0 ? 1.0 - smoothstep(0.0, band_px, below) : 1.0 - smoothstep(0.0, 6.0, -below);
		float trail = d <= sweep_pos ? exp(-(sweep_pos - d) / max(afterglow, 0.001)) : 0.0;
		float g = max(band, 0.6 * trail);
		c.rgb += sweep_color.rgb * sweep_gain * sweep_color.a * g * far_fade;
	}
	if (scanlines_on && mod(floor(v_pos.y), 4.0) < 2.0) {
		c.rgb = mix(c.rgb, scan_color.rgb, scan_color.a);
	}
	COLOR = c;
}
