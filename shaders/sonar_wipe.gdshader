shader_type canvas_item;
// Sonar wipe screen transition (02.2 UI-SPEC 9.7 / 11, D-13). Drawn on ScreenTransition's
// full-screen ColorRect; no screen texture read. Cover: a disc of fill_color grows from
// `centre` with an edge_px ring of edge_color at its rim. Reveal: a hole grows from `centre`
// in a full cover, the ring on the hole's rim. glow = false (Low effects) drops the soft
// halo outside the covered area; the ring stays. Every colour arrives as a uniform set from
// Palette by the owner (ScreenTransition); this file holds no colour constants (VIS-01).

uniform vec2 centre = vec2(960.0, 540.0);
uniform float radius = 0.0;
uniform float edge_px = 6.0;
uniform vec4 fill_color : source_color;
uniform vec4 edge_color : source_color;
uniform bool reveal = false;
uniform bool glow = true;

const float GLOW_PX = 28.0;
const float GLOW_ALPHA = 0.45;

// Local position in the rect's pixels (the rect covers the 1920x1080 design canvas).
varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float d = distance(v_pos, centre);
	// s < 0 inside the covered area, s > 0 in the open (uncovered) area.
	float s = reveal ? (radius - d) : (d - radius);
	float cov = 1.0 - clamp(s + 0.5, 0.0, 1.0);
	float ring = cov * clamp(s + edge_px + 0.5, 0.0, 1.0);
	vec3 base = mix(fill_color.rgb, edge_color.rgb, ring);
	float g = 0.0;
	if (glow && radius > 0.0) {
		float k = 1.0 - clamp(s / GLOW_PX, 0.0, 1.0);
		g = k * k * GLOW_ALPHA * edge_color.a * step(0.0, s);
	}
	float a = max(cov * mix(fill_color.a, edge_color.a, ring), g);
	COLOR = vec4(mix(edge_color.rgb, base, cov), a);
}
