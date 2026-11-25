shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/world/shaders/terminal_light.gdshaderinc"

uniform vec2 terminal_anchor;
uniform float floor_height = 3.06;
uniform bool roof = false;
uniform sampler2D terrazzo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 p = terminal_axes(world_position, terminal_anchor);
	float up = max(world_normal.y, 0.0);
	float floor_mask = smoothstep(0.75, 0.96, up) * (1.0 - smoothstep(floor_height + 0.028, floor_height + 0.07, world_position.y));
	vec3 col = roof ? vec3(0.79, 0.81, 0.84) : pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float grout = min(abs(fract(p.x / 2.0 + 0.5) - 0.5), abs(fract(p.y / 2.0 + 0.5) - 0.5));
	float tile = texture(terrazzo, p * 0.5).r * 0.23 + 0.76;
	col *= mix(1.0, tile * mix(0.88, 1.0, smoothstep(0.002, 0.009 + fwidth(grout), grout)), floor_mask);
	ALBEDO = col;
	ROUGHNESS = mix(0.59, 0.30, floor_mask);
	float soffit = roof ? smoothstep(0.05, 0.85, -world_normal.y) : 1.0;
	EMISSION = col * terminal_irradiance(p, up) * soffit;

	// Intersect the reflection ray with the luminous strips on the ceiling.
	// The broad edges approximate the polished stone's rough reflection.
	vec3 ray = reflect(-VIEW, NORMAL);
	ray = (INV_VIEW_MATRIX * vec4(ray, 0.0)).xyz;
	vec3 reflected = world_position + ray * (floor_height + 10.25 - world_position.y) / max(ray.y, 0.06);
	vec2 r = terminal_axes(reflected, terminal_anchor);
	vec2 d = abs(terminal_fixture_offset(r));
	float strip = (1.0 - smoothstep(2.7, 4.1, d.x)) * (1.0 - smoothstep(0.05, 0.95, d.y));
	float edge = smoothstep(-9.0, 0.0, r.x) * (1.0 - smoothstep(272.0, 281.0, r.x));
	float fade = 1.0 - smoothstep(10.0, 52.0, distance(reflected, world_position));
	EMISSION += vec3(1.0, 0.94, 0.82) * strip * edge * fade * floor_mask * 0.16;
}
