"""WorldState rear ends: one rear-end kit for every vehicle (owned cars,
traffic, police), so no car has a flat placeholder back.

The rear is what you look at most (the chase camera sits behind your car,
and you follow traffic), so every body gets, fitted to its own shell:

  * tail clusters in recesses wrapping round the corners: a dark housing,
    a chrome reflector bowl behind a red brake block, a light-guide
    signature (C / L / bar), a white reverse segment, an amber indicator,
    trim dividers, a gasket and a clear red lens flush with the paint
    (sealed traffic bodies: a dark red lens with the guides on top);
  * an optional full-width light bar in its own slot between the lamps;
  * shut lines that line up with the lamps: boot lid / tailgate / bed gate,
    the rear-bumper split running round the corners to the arches;
  * a recessed number plate with two plate lamps, the maker's badge and a
    chrome model script;
  * a dark valance (or a carbon diffuser with strakes) with exhaust
    cut-outs, rolled-lip tips with dark inner pipes;
  * red reflex reflectors in the bumper corners, a rear fog on the offside,
    a third brake lamp at the roof end.

Everything is placed by casting at the body (rear view rays converge, so
lamps wrap round a corner square-on), left = right mirrored.
"""
import math

import bmesh
import bpy
from mathutils import Vector as V

import kestrel as K
import ws_fleet as F
import build_kit as kit
from build_kit import box, cyl

V3 = V


def extra_mats(m):
    """Materials the rear kit adds (CarVisual knows them: reflex, badge)."""
    m.setdefault("reflex", kit.mat("reflex", (0.3, 0.01, 0.012), 0.22, 0.0))
    m.setdefault("badge", kit.mat("chrome", (0.8, 0.8, 0.82), 0.12, 1.0))
    if "amber" not in m:
        m["amber"] = kit.mat("lamp_amber", (0.95, 0.5, 0.05), 0.2, 0.0, emit=(1.0, 0.5, 0.05))
    return m


def _navg(g):
    return sum((c[1] for row in g for c in row if c), V()).normalized()


def _hits(g):
    return sum(1 for row in g for c in row if c)


def _sub(g, i0, i1, j0, j1):
    """Sub-grid of cells i0..i1, j0..j1 (inclusive vertex ranges)."""
    return [row[i0:i1 + 1] for row in g[j0:j1 + 1]]


def _row_pts(g, j, i0, i1, inset, navg):
    return [g[j][i][0] - navg * inset for i in range(i0, i1 + 1) if g[j][i]]


def cluster(body, m, out, poly, depth=0.065, sig="C", sealed=False, res=(20, 8), view="rear"):
    """One tail-lamp cluster (right side; the left is mirrored).
    poly: (x, z) corners BL (inboard, low), BR (outboard, low), TR, TL."""
    surf = K.Surface([body])
    nu, nv = res
    g = K.patch(surf, view, K.poly_fn(poly), nu, nv)
    if _hits(g) < (nu + 1) * (nv + 1) * 0.7:
        print("LAMP MISSED cluster", poly)
        return False
    n0 = len(out)
    navg = _navg(g)
    pk = K.recess_cutter("tail_pocket", K.coarse(g), depth if not sealed else 0.025)
    pk2 = K.mirror_copy(pk)
    K.cut(body, pk, m["housing"])
    K.cut(body, pk2, m["housing"])
    out.append(K.sheet("tail_back", K.coarse(g), -depth + 0.004, m["housing"]))
    t = m["tail"]
    i_rev = max(1, int(nu * 0.16))           # inboard: reverse
    i_ind = int(nu * 0.62)                   # outboard of the brake: indicator
    if sealed:
        # Traffic: one opaque dark-red lens; the lit brake block, a white
        # reverse and an amber indicator set flush in it (no tubes: on the
        # decimated traffic shell they stood off the lamp).
        out.append(K.sheet("tail_lens", g, -0.0025, m["reflex"]))
        out.append(K.sheet("brake", _shrink(_sub(g, i_rev + 1, nu - 1, 1, nv - 1), 0.006), -0.0016, t))
        out.append(K.sheet("reverse", _shrink(_sub(g, 1, i_rev, 2, nv - 2), 0.005), -0.0016, m["rev"]))
        for o in list(out[n0:]):
            out.append(K.mirror_copy(o))
        return True
    # Layer 1 (deepest): faceted chrome reflector cells - a honeycomb of
    # little tilted mirrors that catches light behind the brake lamp.
    for j in range(2, nv - 1, 2):
        for i in range(i_rev + 1, nu - 1, 2):
            c = g[j][i]
            if not c:
                continue
            jit = V(((i * 7 % 5 - 2) * 0.09, (j * 3 % 5 - 2) * 0.05, ((i + j) % 3 - 1) * 0.09))
            cell = (g[0][1][0] - g[0][0][0]).length if g[0][0] and g[0][1] else 0.02
            out.append(K.disc_on("facet", c[0] - navg * (depth - 0.012), (navg + jit).normalized(), cell * 0.95, 0.003,
                                 m["reflector"], 6))
    # Reverse bowl (chrome) and the white reverse LED strip.
    out.append(K.sheet("rev_bowl", _sub(g, 1, i_rev, 1, nv - 1), -depth + 0.01, m["reflector"]))
    rv = _row_pts(g, nv // 2, 1, i_rev, 0.026, navg)
    if len(rv) > 1:
        out.append(K.tube_path("reverse", rv, 0.011, m["rev"], 8))
    # Layer 2: LED arrays - two rows of individual emitters across the brake
    # section, a column of amber ones in the indicator.
    for j in (3, nv - 3):
        for i in range(i_rev + 1, i_ind):
            c = g[j][i]
            if c:
                out.append(K.disc_on("led", c[0] - navg * 0.026, navg, 0.0058, 0.004, t, 8))
    for i in range(i_ind + 1, nu - 2):
        for j in (2, 3):
            c = g[j][i]
            if c:
                out.append(K.disc_on("led_amber", c[0] - navg * 0.026, navg, 0.0055, 0.004, m["amber"], 8))
    # Layer 3: light-guide signature (the tail-lamp graphic), in front of the LEDs.
    ins, r = 0.016, 0.0075
    if sig == "C":
        pts = (_row_pts(g, nv - 1, i_rev + 1, nu - 1, ins, navg) +
               [g[j][nu - 1][0] - navg * ins for j in range(nv - 2, 0, -1) if g[j][nu - 1]] +
               list(reversed(_row_pts(g, 1, i_rev + 1, nu - 2, ins, navg))))
    elif sig == "L":
        pts = (_row_pts(g, 1, i_rev + 1, nu - 1, ins, navg) +
               [g[j][nu - 1][0] - navg * ins for j in range(2, nv) if g[j][nu - 1]])
    else:  # "bar": two parallel guides
        pts = _row_pts(g, nv - 1, 1, nu - 1, ins, navg)
        p2 = _row_pts(g, nv - 3, i_rev + 1, nu - 1, ins, navg)
        if len(p2) > 2:
            out.append(K.tube_path("tail_guide2", p2, r * 0.8, t, 6))
    if len(pts) > 3:
        out.append(K.tube_path("tail_guide", pts, r, t, 6))
    # Chrome dividers between the sections.
    for i in (i_rev, i_ind):
        col = [g[j][i][0] - navg * 0.012 for j in range(1, nv) if g[j][i]]
        if len(col) > 2:
            out.append(K.tube_path("tail_div", col, 0.0035, m["chrome"], 4))
    # Layer 4: an inner red lens over the brake/indicator (the red you see
    # deep in a real lamp), then the outer lens flush with the paint: clear
    # over the reverse, red over the rest, with a black gasket round it.
    # (outer: a clear, glossy cover that takes the reflections; inner: the
    # red lens with the LEDs and guides behind it - depth you can see)
    out.append(K.sheet("lens_inner", _sub(g, i_rev, nu, 0, nv), -0.011, m["lens_red"]))
    out.append(K.sheet("tail_lens", g, -0.0025, m["lens"]))
    ring_pts = ([c for c in g[0]] + [g[j][-1] for j in range(len(g))] + list(reversed(g[-1])) +
                [g[j][0] for j in reversed(range(len(g)))])
    rp = [c[0] + c[1] * 0.0005 for c in ring_pts if c]
    if len(rp) > 4:
        out.append(K.tube_path("tail_gasket", rp + rp[:1], 0.0035, m["trim"], 4))
    for o in list(out[n0:]):
        out.append(K.mirror_copy(o))
    return True


def light_bar(body, m, out, x0, z, h=0.03, sealed=False):
    """Full-width bar between the lamps in its own slot (x0: its half-length)."""
    surf = K.Surface([body])
    g = K.patch(surf, "rear", K.poly_fn([(-x0, z - h / 2), (x0, z - h / 2), (x0, z + h / 2), (-x0, z + h / 2)]), 28, 2)
    if _hits(g) < 70:
        print("LAMP MISSED light_bar")
        return
    K.cut(body, K.recess_cutter("bar_slot", g, 0.025), m["housing"])
    navg = _navg(g)
    out.append(K.sheet("bar_back", g, -0.021, m["housing"]))
    pts = _row_pts(g, 1, 0, 28, 0.012 if not sealed else -0.003, navg)
    if len(pts) > 3:
        out.append(K.tube_path("bar_guide", pts, h * 0.22, m["tail"], 6))
    out.append(K.sheet("bar_lens", g, -0.002, m["lens_red"] if not sealed else m["reflex"]))


def seam(gs, m, out, line, view="rear", side=1, w=0.0055):
    F.gap_decal(gs, m, out, line, view, w=w, side=side)


def exhaust(body, m, out, x, z, r=0.045, shape="round", stick=0.05, both=True):
    """A tip through a cut-out in the valance: dark surround, rolled chrome
    lip, a dark inner pipe set well back (left = right mirrored)."""
    surf = K.Surface([body])
    h = surf.cast(*K.ray("rear", x, z))
    yb = h[0].y if h else K.YR + 0.05
    n0 = len(out)
    segs = 20 if shape == "round" else 6
    sx, sz = (1.0, 1.0) if shape != "oval" else (1.45, 0.8)

    def ring(rr, y):
        return [V((x + math.cos(a) * rr * sx, y, z + math.sin(a) * rr * sz))
                for a in (i * 2 * math.pi / segs + (math.pi / 6 if shape == "hex" else 0) for i in range(segs))]
    # Cut-out surround in the bumper.
    cut = K.prism("pipe_cut", [(x + math.cos(a) * (r + 0.016) * sx, z + math.sin(a) * (r + 0.016) * sz)
                               for a in (i * 2 * math.pi / 16 for i in range(16))], "y", yb - 0.2, yb + 0.06)
    K.cut(body, cut, m["liner"])
    bm = bmesh.new()
    prof = [(r * 0.9, yb + 0.14), (r, yb + 0.1), (r, yb - stick + 0.008), (r * 0.985, yb - stick), (r * 0.93, yb - stick + 0.004),
            (r * 0.88, yb - stick + 0.018), (r * 0.86, yb + 0.06)]
    rings = [[bm.verts.new(p) for p in ring(rr, y)] for rr, y in prof]
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(segs):
            bm.faces.new((r0[i], r0[(i + 1) % segs], r1[(i + 1) % segs], r1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tip = kit.new_obj("pipe_tip", bm, m["chrome"])
    for p in tip.data.polygons:
        p.use_smooth = True
    out.append(tip)
    # Inside: a heat-darkened inner pipe, a perforated baffle well back, a
    # black bezel round the cut-out.
    inner = [V(p) for p in ring(r * 0.72, yb - stick + 0.03)]
    inner2 = [V(p) for p in ring(r * 0.72, yb + 0.12)]
    bm = bmesh.new()
    a0 = [bm.verts.new(p) for p in inner]
    a1 = [bm.verts.new(p) for p in inner2]
    for i in range(segs):
        bm.faces.new((a0[i], a0[(i + 1) % segs], a1[(i + 1) % segs], a1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ip = kit.new_obj("pipe_inner", bm, kit.mat("disc", (0.36, 0.36, 0.37), 0.42, 0.85))
    out.append(ip)
    back = K.disc_on("pipe_in", V((x, yb + 0.1, z)), V((0, -1, 0)), r * 0.72, 0.004, m["liner"], segs)
    back.scale = (sx, 1, sz) if shape == "oval" else (1, 1, 1)
    out.append(back)
    for k in range(6):
        a = k * 2 * math.pi / 6
        hole = K.disc_on("baffle_hole", V((x + math.cos(a) * r * 0.38 * sx, yb + 0.098, z + math.sin(a) * r * 0.38 * sz)),
                         V((0, -1, 0)), r * 0.09, 0.002, m["trim"], 6)
        out.append(hole)
    bez = [V((x + math.cos(a) * (r + 0.012) * sx, yb + 0.004, z + math.sin(a) * (r + 0.012) * sz))
           for a in (i * 2 * math.pi / 24 for i in range(25))]
    out.append(K.tube_path("pipe_bezel", bez, 0.006, m["trim"], 6))
    if both:
        for o in list(out[n0:]):
            out.append(K.mirror_copy(o))
        cut2 = K.prism("pipe_cut", [(-x + math.cos(a) * (r + 0.016) * sx, z + math.sin(a) * (r + 0.016) * sz)
                                    for a in (i * 2 * math.pi / 16 for i in range(16))], "y", yb - 0.2, yb + 0.06)
        K.cut(body, cut2, m["liner"])


def script(out, m, text, at, normal, size=0.034):
    """Chrome model script (a real text mesh) facing along `normal`."""
    bpy.ops.object.text_add()
    t = bpy.context.object
    t.data.body = text
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.size = size
    t.data.extrude = 0.0018
    t.data.space_character = 1.15
    t.data.resolution_u = 2
    bpy.ops.object.convert(target="MESH")
    t = bpy.context.object
    t.data.materials.clear()
    t.data.materials.append(m["chrome"])
    t.rotation_mode = "QUATERNION"
    t.rotation_quaternion = normal.to_track_quat("Z", "Y")
    t.location = at + normal * 0.002
    out.append(t)


def rear_end(body, clean, m, out, kind, feats, *, belt, rear, label="", reg="WS24 EMP", sealed=False, doors=4,
             pipes=None, plate_z=None, seams=True):
    """The whole rear of a body. kind: saloon muscle coupe mid hatch estate
    suv box4x4 pickup van box. pipes: list of (x, z, r, shape) (right side,
    mirrored) or None for a hidden exhaust. Returns the lamp outline."""
    extra_mats(m)
    W2, RIDE, YR, AX, ARCH = K.W2, K.RIDE, K.YR, K.AX, K.ARCH
    gs = K.Surface([clean])
    # ---- lamps
    if kind == "mid":
        lz0, lz1 = rear - 0.13, rear - 0.045
        tl = [(W2 * 0.52, lz0 + 0.01), (W2 * 0.96, lz0), (W2 * 0.94, lz1), (W2 * 0.54, lz1)]
        sig = "bar"
    elif kind in ("saloon", "muscle", "coupe"):
        lz0, lz1 = rear - 0.19, rear - 0.035
        xin = 0.5 if kind != "muscle" else 0.56
        tl = [(W2 * xin, lz0 + 0.012), (W2 * 0.985, lz0), (W2 * 0.96, lz1), (W2 * (xin + 0.02), lz1 - 0.004)]
        sig = "C" if kind != "muscle" else "bar"
    elif kind in ("pickup", "van", "box4x4"):
        lz0, lz1 = RIDE + 0.42, RIDE + 0.98
        tl = [(W2 * 0.8, lz0), (W2 * 0.985, lz0), (W2 * 0.985, lz1), (W2 * 0.8, lz1)]
        sig = "L"
    elif kind == "box":
        tl = None
        lz0 = lz1 = RIDE + 0.5
        sig = "L"
    else:  # hatch, estate, suv: up the D-pillar corner
        lz0, lz1 = belt - 0.2, belt + 0.06
        tl = [(W2 * 0.6, lz0 + 0.02), (W2 * 0.975, lz0), (W2 * 0.95, lz1), (W2 * 0.64, lz1 - 0.005)]
        sig = "C"
    ok = False
    if tl:
        res = (20, 8) if kind not in ("pickup", "van", "box4x4") else (8, 16)
        if kind in ("pickup", "van", "box4x4"):
            ok = vertical_cluster(body, m, out, tl, sealed=sealed)
        else:
            ok = cluster(body, m, out, tl, sig=sig, sealed=sealed, res=res)
    if ("light_bar" in feats) and tl:
        light_bar(body, m, out, tl[0][0] - 0.03, (tl[0][1] + tl[3][1]) / 2 + 0.01, h=0.026, sealed=sealed)
    # ---- shut lines: real 6.5 mm gaps cut through the shell on close-up
    # bodies (a shadow line with depth), dark strips on sealed traffic.
    def seam(gs_, m_, out_, line, view="rear", side=1, w=0.0055, y1=None):
        if view == "rear" and not sealed:
            K.cut(body, K.slot("gap", line, "y", YR - 0.5, YR + (0.25 if y1 is None else y1), w=0.0065), m_["liner"])
        else:
            F.gap_decal(gs_, m_, out_, line, view, w=w, side=side)

    # (lines laid out on the uncut shell, so they line up with the lamps)
    xin = min(tl[0][0], tl[3][0]) - 0.018 if tl else W2 * 0.8
    hatch = kind in ("hatch", "estate", "suv")
    # Rear-bumper split height (hatches: the tailgate's bottom edge is it).
    zb = min(lz0 - 0.1, RIDE + 0.42) if kind not in ("pickup", "van", "box4x4", "box") else RIDE + 0.36
    if seams:
        if kind in ("saloon", "muscle", "coupe"):
            seam(gs, m, out, [(-xin, rear + 0.03), (-xin, lz0 - 0.03), (xin, lz0 - 0.03), (xin, rear + 0.03)])
        elif kind == "mid":
            seam(gs, m, out, [(-W2 * 0.48, lz1 + 0.02), (-W2 * 0.48, lz0 - 0.05), (W2 * 0.48, lz0 - 0.05),
                              (W2 * 0.48, lz1 + 0.02)])
        elif kind in ("hatch", "estate", "suv"):
            # Tailgate: down inboard of the lamps, across on the bumper line.
            seam(gs, m, out, [(-xin, K.ROOF - 0.06), (-xin, zb + 0.06), (-xin + 0.05, zb), (xin - 0.05, zb), (xin, zb + 0.06),
                              (xin, K.ROOF - 0.06)])
        elif kind == "box4x4":
            seam(gs, m, out, [(-W2 * 0.76, K.ROOF - 0.08), (-W2 * 0.76, RIDE + 0.42), (W2 * 0.76, RIDE + 0.42),
                              (W2 * 0.76, K.ROOF - 0.08)])
        elif kind == "pickup":
            seam(gs, m, out, [(-W2 * 0.78, rear + 0.02), (-W2 * 0.78, RIDE + 0.44), (W2 * 0.78, RIDE + 0.44),
                              (W2 * 0.78, rear + 0.02)])
        elif kind == "van":
            seam(gs, m, out, [(0.0, RIDE + 0.36), (0.0, K.ROOF - 0.06)])
            seam(gs, m, out, [(-W2 * 0.78, K.ROOF - 0.06), (-W2 * 0.78, RIDE + 0.36), (W2 * 0.78, RIDE + 0.36),
                              (W2 * 0.78, K.ROOF - 0.06)])
    # Rear-bumper split: across under the lamps (outboard of the tailgate on
    # hatches) and round the corners to the arches.
    if kind not in ("box",) and seams:
        if hatch:
            for sx in (1, -1):
                seam(gs, m, out, [(sx * (xin + 0.01), zb), (sx * W2 * 1.1, zb)], y1=0.36)
        else:
            seam(gs, m, out, [(-W2 * 1.1, zb), (W2 * 1.1, zb)], y1=0.36)
        for sd in (1, -1):
            seam(gs, m, out, [(YR + 0.36, zb), (AX[1] - ARCH - 0.04, zb - 0.02),
                              (AX[1] - ARCH - 0.02, RIDE + 0.2)], view="side", side=sd)
    # ---- plate in a recess, plate lamps
    surf = K.Surface([body])
    pz = plate_z if plate_z is not None else (
        (zb + lz0) / 2 + 0.01 if kind in ("saloon", "muscle", "coupe") else
        rear - 0.33 if kind == "mid" else RIDE + 0.5 if kind in ("hatch", "estate", "suv") else RIDE + 0.28)
    if kind in ("van", "box4x4", "box") and plate_z is None:
        pz = zb - 0.11
    elif kind == "pickup" and plate_z is None:
        pz = RIDE + 0.53          # on the tailgate, over the step bumper
    g = K.patch(surf, "rear", K.poly_fn([(-0.29, pz - 0.075), (0.29, pz - 0.075), (0.29, pz + 0.075), (-0.29, pz + 0.075)]), 10, 4)
    if _hits(g) > 40 and kind != "box":
        K.cut(body, K.recess_cutter("plate_pocket", g, 0.022), m["plastic"])
        surf = K.Surface([body])
        h = surf.cast(*K.ray("rear", 0.0, pz))
        if h:
            n = h[1]
            if abs(n.z) > 0.35:     # (a sloping recess back: stand the plate up)
                n = V((0, n.y, 0.12 * (1 if n.z > 0 else -1))).normalized()
            K.number_plate(out, m, h[0] + n * 0.006, n, rear=True, text=reg)
            for sx in (1, -1):
                out.append(box("plate_lamp", (0.05, 0.012, 0.012), h[0] + V((sx * 0.18, -0.004, 0.074)), m["rev"], bevel=0.003))
    # ---- badge and model script
    surf = K.Surface([body])
    bz = (pz + 0.075 + lz0) / 2 + 0.02 if kind in ("saloon", "muscle", "coupe") else (lz0 + lz1) / 2
    if kind == "mid":
        bz = lz1 + 0.05
    if kind in ("pickup", "van", "box4x4"):
        bz = (pz + 0.1 + K.ROOF) / 2 - 0.25
    if kind != "box":
        h = surf.cast(*K.ray("rear", 0.0, bz))
        if h:
            out.append(K.disc_on("badge_r", h[0] + h[1] * 0.002, h[1], 0.038, 0.007, m["chrome"], 28))
            out.append(K.disc_on("badge_in", h[0] + h[1] * 0.0095, h[1], 0.03, 0.0015, m["trim"], 28))
        if label:
            h = surf.cast(*K.ray("rear", W2 * 0.5, max(bz - 0.06, pz + 0.1)))
            if h:
                script(out, m, label, h[0], h[1])
    # ---- valance / diffuser, exhausts
    surf = K.Surface([body])
    # (fitted to where the tail's underside really is: on raked tails it sits
    # well above the ride height, and parts placed by ride height hung below)
    zlo = RIDE
    for k in range(60):
        z = RIDE + k * 0.01
        hh = surf.cast(*K.ray("rear", 0.0, z))
        if hh and hh[1].y < -0.3:
            zlo = z
            break
    vz0 = zlo + 0.025
    vz1 = vz0 + (0.15 if kind not in ("pickup", "van", "box4x4", "box") else 0.19)
    if kind != "box":
        dif = "diffuser" in feats
        g = K.patch(surf, "rear", K.poly_fn([(-W2 * 0.8, vz0), (W2 * 0.8, vz0), (W2 * 0.84, vz1), (-W2 * 0.84, vz1)]), 22, 3)
        if _hits(g) > 60:
            dd = 0.03 if not dif else 0.16
            K.cut(body, K.recess_cutter("valance", g, dd), m["plastic"])
            out.append(K.sheet("valance", g, -dd + 0.003, m["plastic"] if not dif else m.get("carbon", m["plastic"])))
            if dif:
                # Diffuser: a deep tunnel with a sloping carbon roof, tall
                # strakes running out past the bumper, a carbon lip.
                # Diffuser: a deep tunnel, a sloping carbon roof inside it and
                # vertical strakes standing in the tunnel, flush with the bumper.
                carb = m.get("carbon", m["plastic"])
                zm = (vz0 + vz1) / 2
                for i in range(7):
                    x = -W2 * 0.66 + i * W2 * 1.32 / 6
                    hh = surf.cast(*K.ray("rear", x, zm))
                    if not hh:
                        continue
                    y0s = hh[0].y + 0.004
                    out.append(box("strake", (0.008, 0.14, (vz1 - vz0) * 0.62), (x, y0s + 0.08, zm + 0.012), carb))
                hh = surf.cast(*K.ray("rear", 0.0, zm))
                if hh:
                    ramp = box("diff_roof", (2 * W2 * 0.78, 0.18, 0.01), (0, 0, 0), carb)
                    ramp.rotation_euler = (math.radians(-18), 0, 0)
                    ramp.location = (0, hh[0].y + 0.1, vz1 - 0.03)
                    out.append(ramp)
    if pipes:
        for (x, z, r, shape) in pipes:
            exhaust(body, m, out, x, max(z, vz0 + r + 0.012), r, shape)
    # ---- reflectors, rear fog, third brake lamp
    surf = K.Surface([body])
    rz = zb - 0.075
    n0 = len(out)
    g = K.patch(surf, "rear", K.poly_fn([(W2 * 0.8, rz - 0.013), (W2 * 0.93, rz - 0.013), (W2 * 0.93, rz + 0.013),
                                         (W2 * 0.8, rz + 0.013)]), 6, 1)
    if _hits(g) >= 12 and kind != "box":
        out.append(K.sheet("reflex_back", g, 0.0008, m["trim"], thick=0.004))
        cg = [[(c[0] + c[1] * 0.0005, c[1]) for c in row] for row in _shrink(g, 0.006)]
        out.append(K.sheet("reflex", cg, 0.0045, m["reflex"]))
        for o in list(out[n0:]):
            out.append(K.mirror_copy(o))
    if kind not in ("box",):
        g = K.patch(surf, "rear", K.poly_fn([(-W2 * 0.72, rz - 0.014), (-W2 * 0.62, rz - 0.014), (-W2 * 0.62, rz + 0.014),
                                             (-W2 * 0.72, rz + 0.014)]), 4, 1)
        if _hits(g) >= 8:
            out.append(K.sheet("fog_hous", g, 0.0008, m["trim"], thick=0.004))
            out.append(K.sheet("rear_fog", _shrink(g, 0.005), 0.0052, m["reflex"]))
    return tl


def _shrink(g, d):
    """The grid pulled in by ~d at its edges (inner panel of a part)."""
    nv, nu = len(g) - 1, len(g[0]) - 1
    out = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            c = g[j][i]
            if c is None:
                row.append(None)
                continue
            ci = g[min(max(j, 1), nv - 1) if nv > 1 else j][min(max(i, 1), nu - 1)]
            p = c[0]
            if ci is not None and (i in (0, nu) or j in (0, nv)):
                dv = ci[0] - p
                if dv.length > 1e-6:
                    p = p + dv.normalized() * min(d, dv.length)
            row.append((p, c[1]))
        out.append(row)
    return out


def vertical_cluster(body, m, out, poly, sealed=False):
    """Tall corner lamps (pickups, vans, 4x4s): stacked tail / brake,
    indicator and reverse cells in a black frame, each with its own bowl."""
    surf = K.Surface([body])
    g = K.patch(surf, "rear", K.poly_fn(poly), 6, 15)
    if _hits(g) < 80:
        print("LAMP MISSED vertical", poly)
        return False
    n0 = len(out)
    navg = _navg(g)
    pk = K.recess_cutter("tail_pocket", g, 0.06)
    pk2 = K.mirror_copy(pk)
    K.cut(body, pk, m["housing"])
    K.cut(body, pk2, m["housing"])
    out.append(K.sheet("tail_back", g, -0.056, m["housing"]))
    cells = [(0, 4, m["rev"]), (5, 8, m["amber"]), (9, 15, m["tail"])]
    for j0, j1, mt in cells:
        sub = _sub(g, 1, 5, j0 + 1, j1 - 1) if j1 - j0 > 2 else _sub(g, 1, 5, j0, j1)
        if not sealed:
            out.append(K.sheet("cell_bowl", sub, -0.05, m["reflector"]))
        out.append(K.sheet("cell", sub, -0.028 if not sealed else 0.0012, mt))
        if not sealed:
            # LED emitters across the cell, in front of its bowl.
            for j in range(j0 + 1, j1, 2):
                for i in (1, 3, 5):
                    c = g[j][i]
                    if c:
                        out.append(K.disc_on("led", c[0] - navg * 0.022, navg, 0.008, 0.004, mt, 8))
        row = [g[j1][i][0] - navg * (0.01 if not sealed else -0.002) for i in range(0, 7) if g[j1][i]]
        if len(row) > 2 and j1 < 15:
            out.append(K.tube_path("cell_div", row, 0.004, m["trim"], 4))
    col = [g[j][3][0] - navg * (0.014 if not sealed else -0.003) for j in range(10, 15) if g[j][3]]
    if len(col) > 2:
        out.append(K.tube_path("tail_guide", col, 0.008, m["tail"], 6))
    ring_pts = ([c for c in g[0]] + [g[j][-1] for j in range(len(g))] + list(reversed(g[-1])) +
                [g[j][0] for j in reversed(range(len(g)))])
    rp = [c[0] + c[1] * 0.0005 for c in ring_pts if c]
    out.append(K.tube_path("tail_gasket", rp + rp[:1], 0.006, m["trim"], 4))
    if sealed:
        out.append(K.sheet("tail_lens", g, -0.0025, m["reflex"]))
    else:
        # Clear outer cover; a red inner lens over the tail / brake cells only.
        out.append(K.sheet("lens_inner", _sub(g, 0, 6, 9, 15), -0.012, m["lens_red"]))
        out.append(K.sheet("tail_lens", g, -0.0025, m["lens"]))
    for o in list(out[n0:]):
        out.append(K.mirror_copy(o))
    return True


def third_brake(m, out, y, z, w=0.36):
    out.append(box("brake3_hous", (w + 0.03, 0.03, 0.026), (0, y, z), m["trim"], bevel=0.006))
    out.append(box("brake3", (w, 0.012, 0.012), (0, y - 0.014, z), m["tail"]))


# ------------------------------------------------------------------ front
def front_end(body, clean, m, out, kind, *, zl, lamp_poly=None, badge=True, seams=True, repeaters=True):
    """Front details shared by every body: the bonnet's leading shut line
    between the lamps, the bumper split round the corners to the arches, the
    maker's badge on the nose, amber side repeaters on the wings and red-free
    amber reflex markers in the bumper corners."""
    extra_mats(m)
    W2, RIDE, YF, AX, ARCH = K.W2, K.RIDE, K.YF, K.AX, K.ARCH
    gs = K.Surface([clean])
    xl = (min(lamp_poly[0][0], lamp_poly[3][0]) - 0.02) if lamp_poly else W2 * 0.4
    if seams and kind not in ("mid",):
        seam(gs, m, out, [(-xl, zl + 0.012), (xl, zl + 0.012)], view="front")
    if seams and kind not in ("box",):
        zb = RIDE + (0.36 if kind not in ("pickup", "box4x4", "van") else 0.46)
        for sd in (1, -1):
            seam(gs, m, out, [(YF - 0.42, zl - 0.04), (YF - 0.44, zb + 0.06), (AX[0] + ARCH + 0.04, zb),
                              (AX[0] + ARCH + 0.03, RIDE + 0.2)], view="side", side=sd)
    surf = K.Surface([body])
    if badge and kind != "mid":
        h = surf.cast(*K.ray("front", 0.0, zl - 0.05))
        if h:
            out.append(K.disc_on("badge_f", h[0] + h[1] * 0.006, h[1], 0.042, 0.009, m["chrome"], 28))
            out.append(K.disc_on("badge_f_in", h[0] + h[1] * 0.0155, h[1], 0.033, 0.0015, m["trim"], 28))
    if repeaters:
        n0 = len(out)
        y = AX[0] - ARCH - 0.12
        z = K.smooth(K.SWELL, y) + 0.04
        h = surf.cast(V((3.0, y, z)), V((-1, 0, 0)))
        if h:
            p, n = h[0], h[1]
            rp = box("repeater", (0.008, 0.07, 0.018), (0, 0, 0), m["amber"], bevel=0.004)
            rp.rotation_mode = "QUATERNION"
            rp.rotation_quaternion = n.to_track_quat("X", "Z")
            rp.location = p + n * 0.002
            out.append(rp)
            out.append(K.mirror_copy(rp))


# ------------------------------------------------------------------ glazing trim
def outline_trim(surf, m, out, poly, view, side=1, mat="trim", r=0.006, lift=0.002, step=0.05, name="seal"):
    """A rubber seal / bright frame round a window outline: the outline
    (plane coords) densified, cast onto the shell, a closed tube laid along
    it just proud of the surface - the opening's edge reads crisp and the
    glass looks fitted, not floating in a hole."""
    pts = [V(p) for p in poly] + [V(poly[0])]
    dense = []
    for a, b in zip(pts, pts[1:]):
        n = max(1, int((b - a).length / step))
        dense += [a.lerp(b, i / n) for i in range(n)]
    hits = []
    for p in dense:
        h = surf.cast(*K.ray(view, p.x, p.y, side))
        if h:
            hits.append(h[0] + h[1] * lift)
    if len(hits) > 4:
        out.append(K.tube_path(name, hits + hits[:1], r, m[mat], 6))


def wipers(m, out, y_cowl, z_cowl, half_w, rhd=True):
    """Two parked wipers on the scuttle: arm, blade with its spine, pivot
    caps; parked along the base of the windscreen."""
    for x0 in ((-0.05, 0.62) if rhd else (0.05, -0.62)):
        x0 = max(-half_w + 0.12, min(half_w - 0.12, x0 * half_w / 0.85))
        p0 = V((x0, y_cowl - 0.02, z_cowl))
        p1 = V((x0 - 0.56 * half_w / 0.85, y_cowl - 0.1, z_cowl + 0.05))
        out.append(K.disc_on("wiper_cap", p0, V((0, 0.2, 1)).normalized(), 0.022, 0.018, m["plastic"], 10))
        out.append(K.tube_path("wiper_arm", [p0 + V((0, 0, 0.012)), p1], 0.007, m["plastic"]))
        out.append(K.tube_path("wiper_blade", [p1 + (p0 - p1).normalized() * 0.04, p1 - (p0 - p1).normalized() * 0.5],
                               0.006, m["rubber"], 6))


def fog_lamp(body, m, out, x, z, r=0.032, view="front"):
    """A fog lamp set into the bumper (both sides): a pocket, black bezel,
    chrome bowl, clear lens, the bulb behind it."""
    surf = K.Surface([body])
    h = surf.cast(*K.ray(view, x, z))
    if not h:
        return
    p, n = h[0], h[1]
    n0 = len(out)
    cutter = K.disc_on("fog_cut", p - n * 0.03, n, r + 0.008, 0.06, None, 20)
    c2 = K.mirror_copy(cutter)
    K.cut(body, cutter, m["housing"])
    K.cut(body, c2, m["housing"])
    out.append(K.tube_path("fog_bezel", [p + n * 0.001 + (n.orthogonal().normalized() * math.cos(a) +
                                                             n.cross(n.orthogonal()).normalized() * math.sin(a)) * (r + 0.008)
                                         for a in (i * 2 * math.pi / 20 for i in range(21))], 0.006, m["trim"], 6))
    out.append(K.disc_on("fog_bowl", p - n * 0.028, n, r, 0.008, m["reflector"], 20))
    out.append(K.disc_on("fog_bulb", p - n * 0.018, n, r * 0.25, 0.012, m["rev"], 10))
    out.append(K.disc_on("fog_lens", p - n * 0.005, n, r, 0.004, m["lens"], 20))
    for o in list(out[n0:]):
        out.append(K.mirror_copy(o))
