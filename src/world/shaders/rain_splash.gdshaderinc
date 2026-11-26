// Raindrops hitting the ground (2026-11-26): drawn in the ground shader
// itself – no particles, no geometry. Each 0.45 m cell owns one drop that
// lands at a random spot and time; it flashes a bright impact dot, then a
// thin crown ring that spreads ~11 cm and fades within a fifth of its cycle.
// How many cells fire scales with `amount`; only near the camera (fades out
// 12–26 m) and only while the pixel footprint `aa` is small (no shimmer).
// Needs hash12(vec2) declared before the include.
float rain_splash(vec2 p, float dist, float aa_, float amount, float t) {
	if (amount < 0.02 || dist > 26.0 || aa_ > 0.15) {
		return 0.0;
	}
	vec2 sc = p * 2.2;
	vec2 cell = floor(sc);
	float h = hash12(cell);
	float rate = 1.4 + h * 1.1;
	float cycle = t * rate + h * 13.0;
	float ph = fract(cycle);
	// a new spot and a fresh coin toss every cycle
	float k = floor(cycle);
	vec2 at = vec2(hash12(cell + k * 1.31 + 7.1), hash12(cell - k * 0.77 + 3.3)) * 0.6 + 0.2;
	float on = step(hash12(cell + k * 2.17), amount * 0.85);
	float r = length(fract(sc) - at) / 2.2;   // (metres)
	float life = 1.0 - smoothstep(0.02, 0.2, ph);
	float crown = (1.0 - smoothstep(0.004, 0.012, abs(r - ph * 0.55))) * life;
	float impact = (1.0 - smoothstep(0.006, 0.02, r)) * (1.0 - smoothstep(0.0, 0.05, ph));
	return (crown * 0.75 + impact) * on
		* (1.0 - smoothstep(12.0, 26.0, dist)) * (1.0 - smoothstep(0.04, 0.15, aa_));
}
