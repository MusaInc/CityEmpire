class_name Shoreline
extends MeshInstance3D
## One foam strip along a coastline (shore_foam.gdshader): a quad per edge
## from the wall out to `width` m over the sea, just above the water.
## Edges: [[a: Vector2, b: Vector2, outward: Vector2], ...].

const SEA_Y := -1.56
static var _mat: ShaderMaterial


static func build(edges: Array, width := 6.0) -> Shoreline:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var o: Vector2 = e[2]
		var L := a.distance_to(b)
		if L < 0.5:
			continue
		var q := [Vector3(a.x, SEA_Y, a.y), Vector3(b.x, SEA_Y, b.y),
			Vector3(b.x + o.x * width, SEA_Y, b.y + o.y * width), Vector3(a.x + o.x * width, SEA_Y, a.y + o.y * width)]
		var u := [Vector2(0, along), Vector2(0, along + L), Vector2(width, along + L), Vector2(width, along)]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(u[j])
			st.add_vertex(q[j])
		along += L
	var sl := Shoreline.new()
	sl.name = "Shoreline"
	sl.mesh = st.commit()
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://src/world/shaders/shore_foam.gdshader")
	sl.material_override = _mat
	sl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sl


## Edges of a closed polygon with the outward side (away from its inside).
static func polygon_edges(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := (b - a).normalized()
		var o := Vector2(d.y, -d.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + o * 0.5, poly):
			o = -o
		out.append([a, b, o])
	return out
