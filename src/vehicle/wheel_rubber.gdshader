shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform bool sidewall = false;
uniform bool offroad = false;
global uniform float wetness;
varying vec3 wheel_point;

void vertex() {
	wheel_point = VERTEX;
}

void fragment() {
	// The authored wheels share a unit radius and an X axle. Sample the
	// moulded detail in wheel space so it turns with the rubber.
	vec2 radial = wheel_point.yz;
	float radius = length(radial);
	float angle = atan(radial.y, radial.x) / 6.2831853;
	float width = abs(wheel_point.x);
	float detail = 1.0 - smoothstep(2.0, 9.0, length(VERTEX));
	float px = max(length(dFdx(radial)), length(dFdy(radial)));
	float rubber = 0.017;
	float raised = 0.0;
	float cuts = 0.0;
	if (sidewall) {
		float bands = max(1.0 - smoothstep(0.004, 0.009 + px, abs(radius - 0.914)),
			1.0 - smoothstep(0.004, 0.008 + px, abs(radius - 0.893)));
		float mould = sin(angle * 226.1947) * sin(angle * 125.6637);
		float marks = smoothstep(0.29, 0.77, mould) *
			smoothstep(0.773, 0.794, radius) * (1.0 - smoothstep(0.835, 0.86, radius));
		raised = (bands * 0.26 + marks * 0.20) * (1.0 - smoothstep(0.03, 0.095, px));
		rubber = 0.018;
	} else {
		// Grooves already cut into the mesh handle the broad channels. These
		// fine, angled sipes break up highlight across each tread block.
		float pattern = angle * (offroad ? 24.0 : 58.0) + abs(wheel_point.x) * 5.5;
		float cell = abs(fract(pattern + 0.5) - 0.5);
		cuts = (1.0 - smoothstep(0.034, 0.112 + px * 2.0, cell)) *
			(1.0 - smoothstep(0.026, 0.10, px)) * smoothstep(0.91, 0.97, radius);
		raised = 0.12 * smoothstep(0.13, 0.22, width);
	}
	float wear = 0.065 * sin(angle * 427.2566) * (1.0 - smoothstep(0.018, 0.060, px));
	ALBEDO = vec3(rubber * (1.0 + detail * (raised * 1.25 + wear - cuts * 0.62)));
	SPECULAR = mix(0.28, 0.46, wetness);
	ROUGHNESS = clamp(0.84 - wetness * 0.26 - raised * 0.22 * detail + cuts * 0.11, 0.46, 0.95);
}
