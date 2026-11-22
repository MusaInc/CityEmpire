shader_type spatial;
render_mode cull_back, diffuse_burley, depth_prepass_alpha;
#define HAIR_SCALP
#define HAIR_FADE
#include "res://src/player/shaders/hero_pbr.gdshaderinc"
