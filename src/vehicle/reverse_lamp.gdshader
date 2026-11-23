shader_type spatial;

uniform float reverse_level = 0.0;
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	// Plate lamps can share this authored material. Only the rear lamp
	// clusters off the centre line are reverse lights.
	float bulb = step(0.15, abs(local_position.x)) * step(0.25, local_position.z);
	ALBEDO = vec3(0.68, 0.70, 0.75);
	ROUGHNESS = 0.23;
	SPECULAR = 0.5;
	EMISSION = vec3(0.84, 0.91, 1.0) * reverse_level * bulb;
}
