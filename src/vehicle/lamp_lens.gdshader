shader_type spatial;
// Head / tail lamp lenses (CarVisual): lit like the old StandardMaterial
// (albedo + emission × energy), but each side can be smashed on its own –
// a broken lamp goes dark, its lens crazed and its chrome reflector showing
// through the holes (Car.lamps_ok, vehicle damage overhaul 2026-11-25).
render_mode blend_mix, cull_back;

uniform vec3 albedo : source_color = vec3(0.95);
uniform vec3 emission_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float energy = 0.16;
uniform float broken_l = 0.0;
uniform float broken_r = 0.0;
varying vec3 v_p;

void vertex() {
	v_p = VERTEX;
}

float h3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	float broken = v_p.x < 0.0 ? broken_l : broken_r;
	float shard = h3(floor(v_p * 55.0));
	float hole = step(0.55, shard) * broken;
	ALBEDO = mix(albedo, mix(vec3(0.05), vec3(0.6, 0.6, 0.62), hole), broken * 0.9);
	METALLIC = mix(0.0, 0.85, hole);
	ROUGHNESS = mix(0.25, mix(0.55, 0.2, hole), broken);
	EMISSION = emission_color * energy * (1.0 - broken);
}
