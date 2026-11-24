// MSAA-safe lightweight Cinematic post-process pass.
// Reads ONLY hint_screen_texture (ZERO hint_depth_texture), allowing MSAA 2x/4x
// to stay enabled on the Mobile renderer!
// Includes: HDR-preserving 5-tap CAS sharpening, subtle local clarity, SDR-only
// filmic S-curve + shadow toe, 8-tap soft night lens glare & anamorphic streaks,
// subtle filmic split-tone, vignette, and 10-bit debanding triangular dither.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, skip_vertex_transform, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D screen_mip : hint_screen_texture, filter_linear_mipmap, repeat_disable;
global uniform float night;

uniform float sharpen = 0.54;
uniform float clarity = 0.18;
uniform float film_contrast = 0.19;
uniform float film_toe = 0.006;
uniform float saturation = 1.08;
uniform float split_tone = 0.09;
uniform vec3 shadow_tint : source_color = vec3(0.84, 0.91, 1.06);
uniform vec3 light_tint : source_color = vec3(1.05, 1.01, 0.92);
uniform float vignette = 0.13;
uniform float lens = 0.44;
uniform float lens_threshold = 1.12;
uniform vec3 streak_tint : source_color = vec3(0.55, 0.74, 1.0);
uniform float lens_distort = 0.012;
uniform float dither = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 bright(vec3 c, float th) {
	float l = luma(c);
	return c * (max(l - th, 0.0) / max(l, 0.001));
}

// 8-tap mobile-budget soft lens glare + horizontal anamorphic streaks.
vec3 lens_light(sampler2D stex, vec2 uv, vec2 px, float th, vec3 tint, float t_night) {
	vec3 acc = vec3(0.0);
	float aspect = px.y / px.x;
	acc += (bright(textureLod(stex, uv + vec2(0.008, 0.0), 2.0).rgb, th)
		+ bright(textureLod(stex, uv - vec2(0.008, 0.0), 2.0).rgb, th)) * tint * 0.28;
	acc += (bright(textureLod(stex, uv + vec2(0.022, 0.0), 2.0).rgb, th)
		+ bright(textureLod(stex, uv - vec2(0.022, 0.0), 2.0).rgb, th)) * tint * 0.16;
	vec2 h_off = vec2(0.013, 0.013 * aspect);
	vec3 halo = bright(textureLod(stex, uv + h_off, 3.0).rgb, th * 0.85)
		+ bright(textureLod(stex, uv - h_off, 3.0).rgb, th * 0.85)
		+ bright(textureLod(stex, uv + vec2(-h_off.x, h_off.y), 3.0).rgb, th * 0.85)
		+ bright(textureLod(stex, uv + vec2(h_off.x, -h_off.y), 3.0).rgb, th * 0.85);
	acc += halo * (0.14 * mix(0.65, 1.0, t_night));
	return acc;
}

vec3 saturate_col(vec3 c, float s) {
	float l = luma(c);
	return max(mix(vec3(l), c, s), 0.0);
}

// HDR-preserving 5-tap cross CAS: clamps to local [mn, mx] instead of [0, 1]
// so sunlit glints, sky highlights and night lamps survive into AgX & bloom.
vec3 cas(vec3 c, vec3 n, vec3 s, vec3 e, vec3 w, float amount) {
	vec3 mn = min(c, min(min(n, s), min(e, w)));
	vec3 mx = max(c, max(max(n, s), max(e, w)));
	vec3 headroom = max(max(mx, vec3(1.0)) - mx, vec3(0.0));
	vec3 amp = sqrt(clamp(min(mn, headroom) / max(mx, vec3(1e-4)), 0.0, 1.0));
	vec3 wt = -amp * mix(0.125, 0.2, amount);
	return clamp((c + (n + s + e + w) * wt) / (1.0 + 4.0 * wt), mn, mx);
}

void fragment() {
	vec2 q_raw = SCREEN_UV - 0.5;
	float r2 = dot(q_raw, q_raw);
	// Subtle photographic barrel lens distortion, scaled so edges stay inside [0, 1].
	vec2 uv = clamp(0.5 + q_raw * (1.0 - lens_distort * 0.5 + lens_distort * r2 * 2.0), vec2(0.001), vec2(0.999));
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 g = vec3(1.0 / 2.2);
	vec3 centre = texture(screen_tex, uv).rgb;
	vec3 c = pow(max(centre, 0.0), g);
	if (sharpen > 0.005) {
		vec3 n = pow(max(texture(screen_tex, uv + vec2(0.0, -px.y)).rgb, 0.0), g);
		vec3 s = pow(max(texture(screen_tex, uv + vec2(0.0, px.y)).rgb, 0.0), g);
		vec3 e = pow(max(texture(screen_tex, uv + vec2(px.x, 0.0)).rgb, 0.0), g);
		vec3 w = pow(max(texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb, 0.0), g);
		c = mix(c, cas(c, n, s, e, w, sharpen), sharpen);
	}
	// Subtle local clarity against lod-2 blur, masked from blacks and highlights.
	if (clarity > 0.005) {
		float lc = luma(c);
		float lb = luma(pow(max(textureLod(screen_mip, uv, 2.0).rgb, 0.0), g));
		c *= 1.0 + clamp(lc - lb, -0.12, 0.12) * clarity * 4.0
			* smoothstep(0.04, 0.3, lc) * (1.0 - smoothstep(0.75, 1.05, lc));
	}
	// Filmic S-curve on SDR range [0, 1] only; HDR luminance > 1 passes through.
	float l = luma(c);
	float l_sdr = min(l, 1.0);
	float ls = l_sdr + film_contrast * (l_sdr - l_sdr * l_sdr) * (2.0 * l_sdr - 1.0) * 2.0 + max(l - 1.0, 0.0);
	c *= max(ls, 0.0) / max(l, 1e-4);
	c = c * (1.0 - film_toe) + film_toe;
	if (lens > 0.01) {
		float th = mix(lens_threshold * 2.2, lens_threshold, night);
		c += pow(max(lens_light(screen_mip, uv, px, th, streak_tint, night), 0.0), g)
			* lens * mix(0.32, 0.78, night);
	}
	c = saturate_col(c, saturation);
	float l_tone = luma(c);
	c = mix(c, c * mix(shadow_tint, light_tint, smoothstep(0.1, 0.7, l_tone)) * 1.06, split_tone);
	vec2 q = uv - 0.5;
	c *= 1.0 - vignette * smoothstep(0.3, 0.9, dot(q, q) * 2.2);
	// Triangular dither (±1 LSB of 8-bit display) prevents 10-bit sky/asphalt banding.
	vec2 h = fract(sin(vec2(dot(FRAGCOORD.xy, vec2(12.9898, 78.233)),
		dot(FRAGCOORD.xy, vec2(39.3468, 11.135)))) * 43758.5453);
	c += (h.x + h.y - 1.0) / 255.0 * dither;
	ALBEDO = pow(max(c, 0.0), vec3(2.2));
}
