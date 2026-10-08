shader_type canvas_item;
// Diver-goggle recording visor (D-03; AV-01 visor portion pulled forward 2026-10-08;
// recording-frame art direction from the user, same day).
// Mask/alpha based only: no screen texture, no back buffer, so the highway is never warped.
// Layers: superellipse lens mask (opaque near-black outside), red-tinted rim with RGB split,
// glow and bevel, heavy inner vignette; with effects on: scanlines, fine grain, a slow sweep
// band and periodic horizontal slice jitter. `glitch` (0..1, driven by VisorFrame on miss or
// hull damage) boosts the split and slice offset for a 120 ms burst.
// Everything is forced to exactly 0 inside `clear_rect` (highway + 48px margin).
// Works in design pixels (UV * canvas) so it survives canvas stretch.

uniform vec2 canvas = vec2(1920.0, 1080.0);
uniform vec2 lens_center = vec2(960.0, 520.0);
uniform vec2 lens_half = vec2(845.0, 470.0);  // lens spans y 50..990, leaving a bottom frame band
uniform float lens_power = 4.0;  // superellipse exponent
uniform float mask_alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(0.55, 0.06, 0.16, 1.0);  // deep red
uniform vec4 rim_hot : source_color = vec4(1.0, 0.122, 0.294, 1.0);  // #FF1F4B
uniform float rim_width = 8.0;
uniform float rim_glow = 22.0;
uniform float bevel_gap = 12.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.8;
uniform float vignette_width = 260.0;
// Highway (x 672..1248) plus its 48px margin: x 624..1296, full height. Fades back in over 48px.
uniform vec4 clear_rect = vec4(624.0, 0.0, 672.0, 1080.0);  // x, y, w, h
uniform float clear_fade = 48.0;
// 1.0 = full visor, 0.0 = Low effects / reduce motion (no scanlines, grain, sweep, jitter).
uniform float effects : hint_range(0.0, 1.0) = 1.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float scan : hint_range(0.0, 0.2) = 0.08;
uniform float scan_lines = 540.0;
uniform float grain : hint_range(0.0, 0.2) = 0.07;
uniform float sweep_alpha : hint_range(0.0, 0.2) = 0.04;
uniform float sweep_period = 8.0;
uniform float chroma_px = 2.5;
uniform float sheen : hint_range(0.0, 0.2) = 0.05;  // static lavender glass tint inside the lens
uniform float jitter_period = 3.7;  // seconds between ambient slice glitches
uniform float jitter_px = 4.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Signed pixel distance to the lens edge (negative inside), via r / |grad r|.
float lens_sd(vec2 px) {
	vec2 d = abs(px - lens_center);
	vec2 u = max(d / lens_half, vec2(1e-4));
	float n = lens_power;
	float r = pow(pow(u.x, n) + pow(u.y, n), 1.0 / n);
	vec2 g = vec2(pow(u.x, n - 1.0) / lens_half.x, pow(u.y, n - 1.0) / lens_half.y) * pow(r, 1.0 - n);
	return (r - 1.0) / max(length(g), 1e-6);
}

// Rim line intensity for signed distance sd (line centred rim_width/2 inside the edge).
float rim_line(float sd) {
	float c = abs(sd + rim_width * 0.5);
	return 1.0 - smoothstep(rim_width * 0.5 - 1.0, rim_width * 0.5 + 1.0, c);
}

// 1.0 inside clear_rect, fading to 0.0 over clear_fade outside it.
float clear_mask(vec2 px) {
	vec2 lo = clear_rect.xy;
	vec2 hi = clear_rect.xy + clear_rect.zw;
	vec2 out_d = max(max(lo - px, px - hi), vec2(0.0));
	return 1.0 - smoothstep(0.0, clear_fade, length(out_d));
}

vec4 over(vec4 top, vec4 base) {
	float a = top.a + base.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + base.rgb * base.a * (1.0 - top.a)) / max(a, 1e-5);
	return vec4(rgb, a);
}

void fragment() {
	vec2 px = UV * canvas;
	float fx = clamp(effects, 0.0, 1.0);
	float gl = clamp(glitch, 0.0, 1.0);
	// Horizontal slice offset: ambient (short window every jitter_period) plus the burst.
	float cycle = floor(TIME / jitter_period);
	float ambient = step(fract(TIME / jitter_period), 0.03) * fx;
	float band = floor(px.y / 24.0);
	float hb = hash(vec2(band, cycle + floor(TIME * 30.0) * gl));
	float slice_on = step(0.72, hb) * max(ambient, gl);
	float shift = (hb - 0.86) * 2.0 * mix(jitter_px, 16.0, gl) * slice_on;
	vec2 q = vec2(px.x + shift, px.y);
	float sd = lens_sd(q);
	float inside = 1.0 - smoothstep(-1.0, 1.0, sd);
	// Dark base: opaque mask outside the lens, heavy vignette rising toward the rim inside.
	float vig = vignette * pow(1.0 - clamp(-sd / vignette_width, 0.0, 1.0), 2.0);
	float dark = mix(mask_alpha, vig, inside);
	float line = step(0.5, fract(UV.y * scan_lines));
	dark = 1.0 - (1.0 - dark) * (1.0 - scan * line * fx * inside);
	vec4 col = vec4(0.0, 0.0, 0.0, dark);
	// Static glass sheen: the lens reads as lit glass against the black frame (both modes).
	float glass = sheen * inside * clamp(-sd / vignette_width, 0.0, 1.0);
	col = over(vec4(0.91, 0.90, 0.94, glass), col);
	// Fine grain (off-white specks), animated, effects only.
	float n = hash(floor(px) + vec2(fract(TIME * 7.0) * 517.0, fract(TIME * 3.0) * 211.0));
	col = over(vec4(0.91, 0.90, 0.94, n * grain * fx), col);
	float sweep_y = fract(TIME / sweep_period) * (canvas.y + 240.0) - 120.0;
	float sweep = (1.0 - smoothstep(0.0, 120.0, abs(px.y - sweep_y))) * sweep_alpha * fx * inside;
	col = over(vec4(0.91, 0.90, 0.94, sweep), col);
	// Rim: soft glow, solid red line with a hot centre, faint bevel further in.
	float glow = (1.0 - smoothstep(0.0, rim_glow, abs(sd + rim_width * 0.5))) * 0.35;
	col = over(vec4(rim_hot.rgb, glow), col);
	float rim = rim_line(sd);
	col = over(vec4(rim_color.rgb, rim * 0.95), col);
	float hot = 1.0 - smoothstep(0.5, 1.5, abs(sd + rim_width * 0.5));
	col = over(vec4(rim_hot.rgb, hot * 0.8), col);
	float bevel = (1.0 - smoothstep(0.5, 1.5, abs(sd + rim_width + bevel_gap))) * 0.3;
	col = over(vec4(rim_hot.rgb, bevel), col);
	// RGB split on the rim only: static 2.5px, widened by the glitch burst.
	float split = chroma_px + 6.0 * gl;
	float cy = max(rim_line(lens_sd(q + vec2(split, 0.0))) - rim, 0.0) * 0.6;
	float rd = max(rim_line(lens_sd(q - vec2(split, 0.0))) - rim, 0.0) * 0.6;
	col = over(vec4(0.02, 0.85, 0.91, cy), col);
	col = over(vec4(1.0, 0.12, 0.29, rd), col);
	// Burst edge flash: a thin red/cyan tint on the frame edge band while glitching.
	float edge = (1.0 - smoothstep(0.0, 40.0, abs(sd))) * gl * 0.25;
	col = over(vec4(mix(vec3(1.0, 0.12, 0.29), vec3(0.02, 0.85, 0.91), step(0.5, hb)), edge), col);
	// Highway stays pristine: exactly zero inside clear_rect.
	col.a *= 1.0 - clear_mask(px);
	COLOR = vec4(col.rgb, clamp(col.a, 0.0, 1.0));
}
