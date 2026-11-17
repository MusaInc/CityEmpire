// Authored UV textures; garment fit and skinning live in the Blender asset.
shader_type spatial;
// Both sides: looking into an opening (waistband, cuff, hem, collar) shows
// the garment's shaded inside, never the sky through the body.
render_mode cull_disabled, diffuse_burley;
#include "res://src/player/shaders/hero_pbr.gdshaderinc"
