shader_type canvas_item;
// Liquid-glass surface for floating chrome (sidebar, tab bar, sheets,
// floating buttons, HUD panels): whatever is behind, blurred (screen mip
// chain) and a little more saturated, under a tint. The node's own style
// box is only the shape: its alpha is the coverage (rounded corners, AA).

uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.6);
uniform float blur = 3.2;
uniform float sat = 1.45;
uniform float lift = 0.0;

void fragment() {
	float cov = COLOR.a;
	vec3 b = textureLod(scr, SCREEN_UV, blur).rgb;
	float l = dot(b, vec3(0.299, 0.587, 0.114));
	b = mix(vec3(l), b, sat) + lift;
	vec3 c = mix(b, tint.rgb, tint.a);
	COLOR = vec4(c, cov);
}
