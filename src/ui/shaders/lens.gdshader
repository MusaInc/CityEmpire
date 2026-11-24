// Subtle fisheye toward the screen edges, drawn on a CanvasLayer under the
// HUD (LensFx), so it bends the 3D world and never the HUD or menus.
// The centre stays almost undistorted; the bend grows with radius², and the
// mapping is normalised so the corners stay filled (no black borders).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 0.06;   // barrel amount at the corners
uniform bool driving = false;
uniform float aspect = 1.78;     // width / height

void fragment() {
	vec2 p = SCREEN_UV - 0.5;
	vec2 q = vec2(p.x * aspect, p.y);
	float corner2 = 0.25 * (aspect * aspect + 1.0);
	float r2 = dot(q, q) / corner2;            // 0 centre … 1 corner
	float k = strength;
	// Barrel: an output pixel at radius r samples the image further out,
	// compressing the edges; ÷(1+k) keeps the corner mapped to the corner.
	float s = (1.0 + k * r2 * r2 * 0.35 + k * r2 * 0.65) / (1.0 + k);
	if (driving) {
		// Sample the centre at native coordinates. Taper outward displacement
		// back to zero at each screen boundary, even on a 4:3 tablet.
		float radial = smoothstep(0.08, 0.72, r2);
		vec2 room = 1.0 - 2.0 * abs(p);
		vec2 uv = SCREEN_UV + p * (k * radial) * room;
		COLOR = vec4(texture(screen_tex, uv).rgb, 1.0);
	} else {
		COLOR = vec4(texture(screen_tex, 0.5 + p * s).rgb, 1.0);
	}
}
