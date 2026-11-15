// Packs on the shelves (ShopInterior goods MultiMeshes). The product colour
// comes in INSTANCE_CUSTOM.rgb; each vertex's alpha says how much of it to
// take: 1 = the pack's printed colour (body), 0 = a fixed colour (white
// labels, silver can rims, dark caps, cardboard tape), in between = a tinted
// print (pastel label panels). One material for every kind of pack, so a
// shelf of cola cans reads as red cans with silver tops, not red blocks.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 v_col;
varying float v_rough;

void vertex() {
	vec3 tint = INSTANCE_CUSTOM.rgb;
	v_col = mix(COLOR.rgb, COLOR.rgb * tint, COLOR.a);
	// Metal rims and glossy wrappers shine a little more than card.
	v_rough = COLOR.a < 0.05 ? 0.32 : 0.5;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = v_rough;
	SPECULAR = 0.45;
}
