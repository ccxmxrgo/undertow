shader_type canvas_item;
// Menu wordmark shimmer (02.2 UI-SPEC section 5 "Logo", section 11). A 2 px vertical sine
// UV wobble (period 3.2 s) plus a slanted caustic band, 30% brighter, crossing every 6 s.
// Every colour arrives as a uniform set from Palette by the owner (LogoWordmark); this file
// holds no colour constants (VIS-01). enabled = false outputs the plain texture (Low effects,
// Reduce motion).

uniform bool enabled = true;
uniform float time_scale = 1.0;
// Wobble amplitude in UV units (owner sets 2 px / rect height).
uniform float wobble_uv = 0.013;
uniform vec4 caustic_color : source_color;

const float WOBBLE_SEC = 3.2;
const float BAND_SEC = 6.0;
const float BAND_GAIN = 0.3;
const float BAND_HALF = 0.07;

varying vec4 v_modulate;

void vertex() {
	// Vertex COLOR already includes the node's modulate / self_modulate.
	v_modulate = COLOR;
}

void fragment() {
	vec2 uv = UV;
	float band = 0.0;
	if (enabled) {
		float t = TIME * time_scale;
		uv.y += sin(t * TAU / WOBBLE_SEC + UV.x * 9.0) * wobble_uv;
		float pos = fract(t / BAND_SEC) * 1.6 - 0.3;
		float d = UV.x - pos + (UV.y - 0.5) * 0.18;
		band = smoothstep(BAND_HALF, 0.0, abs(d));
	}
	vec4 tex = texture(TEXTURE, uv);
	vec4 c = tex * v_modulate;
	c.rgb = mix(c.rgb, caustic_color.rgb, band * BAND_GAIN * caustic_color.a) * (1.0 + BAND_GAIN * band);
	COLOR = c;
}
