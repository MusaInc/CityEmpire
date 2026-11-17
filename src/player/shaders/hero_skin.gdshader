// Skin (faces, necks, hands): wrapped diffuse softens the terminator so skin
// doesn't read as wax or plastic; pore micro-normal via the detail map.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
#define SKIN
#include "res://src/player/shaders/hero_pbr.gdshaderinc"
