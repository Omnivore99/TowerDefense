"""Builds the rigged, animated monster models for Satisfying TD.

Run:  blender -b -P game/tools/blender/build_monsters.py -- [--only hopper,slinky] [--out DIR] [--meshy DIR]

Every archetype gets one .glb in game/assets/monsters/ with:
  * one skinned mesh at unit radius (r = 1), forward = +X, up = +Y in Godot
  * material slots named body / eye / pupil / dark (the game swaps in its own materials)
  * a small armature (4 to 16 bones) and three actions:
        move   one gait cycle, 1.0 s; the game seeks it from the simulation's gait phase
        hit    0.3 s recoil and squash
        death  0.8 s; soft bodies burst into a puddle, hard bodies topple and sink
If --meshy DIR holds <arch>.glb (a Meshy model), its mesh replaces the code-built body;
it is scaled to the same size and weighted to the same bones by distance.

Blender axes while building: forward = +X, lateral = Y, up = Z.
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

FPS = 30
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "monsters"))
MESHY = ""
ONLY = []

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
i = 0
while i < len(argv):
    if argv[i] == "--only":
        ONLY = argv[i + 1].split(","); i += 1
    elif argv[i] == "--out":
        OUT = os.path.abspath(argv[i + 1]); i += 1
    elif argv[i] == "--meshy":
        MESHY = os.path.abspath(argv[i + 1]); i += 1
    i += 1

MAT_COLORS = {"body": (0.45, 0.85, 0.55, 1), "eye": (0.95, 0.95, 0.92, 1), "pupil": (0.03, 0.03, 0.05, 1), "dark": (0.06, 0.06, 0.08, 1)}


# ------------------------------------------------------------------ scene helpers

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    for name, col in MAT_COLORS.items():
        m = bpy.data.materials.new(name)
        m.diffuse_color = col
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = col


def _finish(obj, mat, bone, scale=None, rot=None):
    if scale is not None:
        obj.scale = scale
    if rot is not None:
        obj.rotation_euler = rot
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(bpy.data.materials[mat])
    obj["bone"] = bone or ""
    obj.select_set(False)
    return obj


def sphere(loc, scale, mat="body", bone=None, seg=24, rings=14, rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1.0, location=loc)
    o = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    return _finish(o, mat, bone, scale, rot)


def torus(loc, major, minor, mat="body", bone=None, rot=None, seg=24, mseg=10, scale=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg, minor_segments=mseg, location=loc)
    o = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    return _finish(o, mat, bone, scale, rot)


def cyl(a, b, r1, r2, mat="body", bone=None, verts=10):
    """A tapered tube from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=d.length, location=(a + b) / 2)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bpy.ops.object.shade_smooth()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(o, mat, bone)


def cone(loc, r, h, mat="dark", bone=None, rot=None, verts=8):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0, depth=h, location=loc)
    o = bpy.context.active_object
    return _finish(o, mat, bone, None, rot)


def box(loc, size, bevel=0.15, mat="body", bone=None, segs=3):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = o.modifiers.new("bev", "BEVEL")
    mod.width = bevel
    mod.segments = segs
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()
    return _finish(o, mat, bone)


def eyes(pos, s, bone, look=0.12):
    """Two eyes facing +X: whites plus pupils, rigid on `bone`."""
    out = []
    for y in (-1, 1):
        p = Vector(pos) + Vector((0, y * s * 0.32, 0))
        out.append(sphere(p, (s * 0.2,) * 3, "eye", bone, 14, 8))
        out.append(sphere(p + Vector((s * look, 0, 0)), (s * 0.11,) * 3, "pupil", bone, 10, 6))
    return out


def blob_mesh(loc, radii, mat="body", bone=None, squash_bottom=0.0, subdiv=3):
    """A soft subdivided blob; squash_bottom flattens the lower half into a foot."""
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0, 0, 0))
    o = bpy.context.active_object
    mod = o.modifiers.new("sub", "SUBSURF")
    mod.levels = subdiv
    bpy.ops.object.modifier_apply(modifier=mod.name)
    me = o.data
    for v in me.vertices:
        v.co = v.co.normalized()
        if squash_bottom > 0 and v.co.z < 0:
            v.co.z *= (1.0 - squash_bottom)
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])) + Vector(loc)
    bpy.ops.object.shade_smooth()
    return _finish(o, mat, bone)


# ------------------------------------------------------------------ rig helpers

def make_rig(bones):
    """bones: list of (name, head, tail, parent or None)."""
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = "rig"
    arm.data.name = "rig"
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    for name, h, t, parent in bones:
        b = eb.new(name)
        b.head = Vector(h)
        b.tail = Vector(t)
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    return arm


def _seg_dist(p, a, b):
    ab = b - a
    tt = max(0.0, min(1.0, (p - a).dot(ab) / max(1e-9, ab.dot(ab))))
    return (p - (a + ab * tt)).length


def bind(arm, parts, soft_bones, sigma=0.45):
    """Join parts into one skinned mesh. A part with a 'bone' tag is rigid on that bone;
    untagged parts are weighted by distance to soft_bones (Gaussian falloff)."""
    bpy.ops.object.select_all(action="DESELECT")
    tags = [p["bone"] for p in parts]
    bone_pts = {b.name: (arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones}
    for p, tag in zip(parts, tags):
        names = [tag] if tag else soft_bones
        for n in set(names):
            if n not in p.vertex_groups:
                p.vertex_groups.new(name=n)
        if tag:
            p.vertex_groups[tag].add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
            continue
        for v in p.data.vertices:
            co = p.matrix_world @ v.co
            ws = [math.exp(-(_seg_dist(co, *bone_pts[n]) / sigma) ** 2) for n in soft_bones]
            tot = sum(ws) or 1.0
            for n, w in zip(soft_bones, ws):
                if w / tot > 0.01:
                    p.vertex_groups[n].add([v.index], w / tot, "REPLACE")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "body"
    body.data.name = "body"
    mod = body.modifiers.new("rig", "ARMATURE")
    mod.object = arm
    body.parent = arm
    return body


class Anim:
    """Keyframes one action on the rig. Times are in seconds."""

    def __init__(self, arm, name, length):
        self.arm = arm
        self.length = length
        self.act = bpy.data.actions.new(name)
        self.act.use_fake_user = True
        arm.animation_data_create()
        arm.animation_data.action = self.act
        for pb in arm.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_euler = (0, 0, 0)
            pb.scale = (1, 1, 1)

    def key(self, bone, t, loc=None, rot=None, scl=None):
        pb = self.arm.pose.bones[bone]
        f = 1 + t * FPS
        if loc is not None:
            pb.location = loc
            pb.keyframe_insert("location", frame=f)
        if rot is not None:
            pb.rotation_euler = rot
            pb.keyframe_insert("rotation_euler", frame=f)
        if scl is not None:
            pb.scale = scl if not isinstance(scl, (int, float)) else (scl, scl, scl)
            pb.keyframe_insert("scale", frame=f)

    def curve(self, bone, fn, steps=12, channels=("loc", "rot", "scl")):
        """Sample fn(u) -> dict(loc=, rot=, scl=) over u in [0, 1] for a smooth cycle."""
        for k in range(steps + 1):
            u = k / steps
            d = fn(u)
            self.key(bone, u * self.length, d.get("loc"), d.get("rot"), d.get("scl"))

    def done(self):
        self.act.frame_range = (1, 1 + self.length * FPS)
        tr = self.arm.animation_data.nla_tracks.new()
        tr.name = self.act.name
        tr.strips.new(self.act.name, 1, self.act)
        self.arm.animation_data.action = None


def bone_axes_scale(s_up, s_side):
    """Bones point along +Z in rest pose (head->tail up), so local Y of a bone = world up.
    Blender bone local axes: Y runs head->tail. For an upright bone, Y = up, X/Z = sideways."""
    return (s_side, s_up, s_side)


# ------------------------------------------------------------------ shared animations

def soft_hit(arm, root="root", body="body", length=0.3):
    a = Anim(arm, "hit", length)
    for t, sq in [(0, 1), (0.05, 0.78), (0.12, 1.12), (0.2, 0.95), (0.3, 1)]:
        a.key(body, t, scl=bone_axes_scale(sq, 1.0 / math.sqrt(sq)))
    # recoil: the root leans back around the lateral axis (local Z of an upright bone)
    for t, lean in [(0, 0), (0.05, -0.3), (0.14, 0.1), (0.3, 0)]:
        a.key(root, t, rot=(0, 0, lean))
    a.done()


def soft_death(arm, root="root", body="body", length=0.8):
    a = Anim(arm, "death", length)
    for t, up, side in [(0, 1, 1), (0.08, 1.25, 0.85), (0.18, 0.55, 1.35), (0.32, 0.18, 1.7), (0.5, 0.1, 1.85), (0.8, 0.06, 1.9)]:
        a.key(body, t, scl=bone_axes_scale(up, side))
    for t, s in [(0, 1), (0.5, 1), (0.8, 0.7)]:
        a.key(root, t, scl=s, rot=(0, 0, 0), loc=(0, 0, 0))
    a.done()


def hard_hit(arm, root="root", length=0.3):
    a = Anim(arm, "hit", length)
    for t, lean, s in [(0, 0, 1), (0.05, -0.35, 0.9), (0.14, 0.12, 1.05), (0.3, 0, 1)]:
        a.key(root, t, rot=(0, 0, lean), scl=(1, s, 1))
    a.done()


def hard_death(arm, root="root", length=0.8, roll_side=True):
    a = Anim(arm, "death", length)
    for t, tip, sink, s in [(0, 0, 0, 1), (0.1, 0.25, 0.15, 1.05), (0.35, 1.6, 0.0, 1.0), (0.45, 1.5, -0.05, 0.95), (0.8, 1.57, -0.8, 0.7)]:
        rot = (tip, 0, 0) if roll_side else (0, 0, -tip)
        a.key(root, t, rot=rot, loc=(0, sink, 0), scl=s)
    a.done()


def jiggle(u, amt=1.0, freq=2):
    return math.sin(u * math.tau * freq) * amt


# ------------------------------------------------------------------ archetypes
# Each builder returns (arm, parts, soft_bones) before binding and records animations after.

def build_hopper():
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("body", (0, 0, 0), (0, 0, 1.0), "root"),
        ("top", (0, 0, 1.0), (0, 0, 2.0), "body"),
    ])
    parts = [blob_mesh((0, 0, 1.0), (1.0, 1.0, 1.0), squash_bottom=0.15)]
    parts += eyes((0.72, 0, 1.05), 1.0, "top")
    parts.append(sphere((-0.2, 0, 1.92), (0.16, 0.16, 0.16), "body", "top", 12, 8))  # little nub
    body = bind(arm, parts, ["body", "top"], 0.55)
    air = 0.45  # share of the hop cycle spent airborne (game: Bal.ARCH.hopperAir)
    a = Anim(arm, "move", 1.0)
    steps = 30
    for k in range(steps + 1):
        u = k / steps
        if u < air:
            q = u / air
            lift = math.sin(q * math.pi) * 1.15
            st = 1.0 + 0.32 * (1.0 - q) ** 2
            up, side = st, 1.0 / math.sqrt(st)
            lag = -0.25 * (1.0 - q) + 0.15 * q  # top trails on take-off, swings forward to land
        else:
            q = (u - air) / (1.0 - air)
            w = math.exp(-q * 5.0) * math.cos(q * 14.0)
            lift = 0.0
            up, side = 1.0 - 0.32 * w, 1.0 + 0.24 * w
            lag = 0.2 * w
        a.key("root", u, loc=(0, lift, 0))
        a.key("body", u, scl=bone_axes_scale(up, side))
        a.key("top", u, rot=(0, 0, lag))
    a.done()
    soft_hit(arm)
    soft_death(arm)
    return arm


def build_crawler():
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("body", (0, 0, 0), (0, 0, 0.85), "root"),
        ("top", (0, 0, 0.85), (0, 0, 1.7), "body"),
        ("seg1", (-0.6, 0, 0), (-0.6, 0, 0.6), "root"),
        ("seg2", (-1.05, 0, 0), (-1.05, 0, 0.5), "root"),
        ("seg3", (-1.5, 0, 0), (-1.5, 0, 0.4), "root"),
    ])
    parts = [blob_mesh((0, 0, 0.85), (1.0, 0.95, 0.85), squash_bottom=0.3)]
    for k, (x, s) in enumerate([(-0.6, 0.6), (-1.05, 0.46), (-1.5, 0.34)]):
        parts.append(blob_mesh((x, 0, s * 0.85), (s, s, s * 0.85), bone="seg%d" % (k + 1), squash_bottom=0.3, subdiv=2))
    parts += eyes((0.72, 0, 0.9), 1.0, "top")
    bind(arm, parts, ["body", "top"], 0.5)
    a = Anim(arm, "move", 1.0)
    for k in range(25):
        u = k / 24
        wave = math.sin(u * math.tau * 2)
        a.key("body", u, scl=bone_axes_scale(1 + 0.1 * wave, 1 - 0.06 * wave))
        a.key("top", u, rot=(0, 0, -0.08 * wave - 0.06))
        for s in range(3):
            ph = math.sin(u * math.tau * 2 - (s + 1) * 0.9)
            a.key("seg%d" % (s + 1), u, loc=(0, 0.12 * max(0.0, ph), 0), scl=bone_axes_scale(1 + 0.15 * ph, 1 - 0.1 * ph))
    a.done()
    soft_hit(arm)
    soft_death(arm)
    return arm


def build_blob():
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("body", (0, 0, 0), (0, 0, 0.8), "root"),
        ("top", (0, 0, 0.8), (0, 0, 1.6), "body"),
        ("lobeL", (0, 0.7, 0.3), (0, 1.15, 0.3), "body"),
        ("lobeR", (0, -0.7, 0.3), (0, -1.15, 0.3), "body"),
    ])
    parts = [blob_mesh((0, 0, 0.8), (1.15, 1.15, 0.8), squash_bottom=0.4)]
    parts += eyes((0.85, 0, 0.95), 0.95, "top")
    bind(arm, parts, ["body", "top", "lobeL", "lobeR"], 0.55)
    a = Anim(arm, "move", 1.0)
    for k in range(25):
        u = k / 24
        wave = math.sin(u * math.tau)
        a.key("body", u, scl=bone_axes_scale(1 + 0.12 * wave, 1 - 0.07 * wave))
        a.key("top", u, rot=(0, 0, -0.12 * math.sin(u * math.tau - 0.8)))
        for side, nm in ((1, "lobeL"), (-1, "lobeR")):
            a.key(nm, u, scl=(1, 1 + 0.25 * math.sin(u * math.tau + side * 1.5), 1))
    a.done()
    soft_hit(arm)
    soft_death(arm)
    return arm


def build_slinky():
    n = 7
    bones = [("root", (0, 0, 0), (0, 0, 0.3), None)]
    for k in range(n):
        x = -k * 0.32
        bones.append(("ring%d" % k, (x, 0, 0.75), (x + 0.3, 0, 0.75), "root"))
    arm = make_rig(bones)
    parts = []
    for k in range(n):
        x = -k * 0.32
        s = 0.75 * (1.0 - 0.04 * k)
        parts.append(torus((x, 0, 0.75), 0.62 * s * 1.25, 0.2 * s, "body", "ring%d" % k, rot=(0, math.pi / 2, 0), seg=20, mseg=8))
    parts += eyes((0.4, 0, 1.0), 0.8, "ring0")
    bind(arm, parts, [], 0.5)
    # rear anchors, front stretches forward to 2x, then the rear is pulled up in an arch
    a = Anim(arm, "move", 1.0)
    for k in range(25):
        u = k / 24
        s = 0.5 + 0.5 * math.sin(u * math.tau)
        for r in range(n):
            frac = r / (n - 1)
            dx = -r * 0.32 * s + s * 0.8
            dz = math.sin(frac * math.pi) * s * 0.9
            # bone local axes: Y along bone (+X world), Z = world up for a bone pointing +X with roll 0
            a.key("ring%d" % r, u, loc=(0, dx, dz))
            a.key("ring%d" % r, u, rot=(0, math.cos(frac * math.pi) * s * 0.6, 0))
    a.done()
    a = Anim(arm, "hit", 0.3)
    for t, sq in [(0, 0), (0.06, 1), (0.3, 0)]:
        for r in range(n):
            a.key("ring%d" % r, t, loc=(0, -sq * 0.08 * r, 0), scl=1 + 0.2 * sq * (1 - r / n))
    a.done()
    a = Anim(arm, "death", 0.8)
    for t, s in [(0, 0), (0.15, 0.4), (0.5, 1), (0.8, 1)]:
        for r in range(n):
            ang = r * 0.9 * s
            a.key("ring%d" % r, t, loc=(math.sin(ang) * r * 0.25 * s, r * 0.15 * s, -0.55 * s), rot=(ang, 0, 0), scl=1 - 0.4 * s * (t >= 0.5))
    a.done()
    return arm


def build_roller():
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("body", (0, 0, 0), (0, 0, 1.0), "root"),
        ("ball", (0, 0, 1.0), (0, 0.6, 1.0), "body"),  # rolled by the game around its local axis
        ("face", (0.6, 0, 1.0), (0.6, 0, 1.6), "body"),
    ])
    parts = [sphere((0, 0, 1.0), (1, 1, 1), "body", "ball", 28, 16)]
    parts.append(torus((0, 0, 1.0), 1.0, 0.07, "dark", "ball", rot=(math.pi / 2, 0, 0), seg=32, mseg=8))
    parts.append(torus((0, 0, 1.0), 1.0, 0.07, "dark", "ball", rot=(0, 0, 0), seg=32, mseg=8))
    for k in range(6):
        ang = k * math.tau / 6
        parts.append(cone((0, math.cos(ang) * 1.02, 1.0 + math.sin(ang) * 1.02), 0.1, 0.25, "dark", "ball", rot=(-ang + math.pi / 2, 0, 0)))
    parts += eyes((0.85, 0, 1.2), 0.7, "face")
    bind(arm, parts, [], 0.5)
    a = Anim(arm, "move", 1.0)
    for k in range(13):
        u = k / 12
        b = abs(math.sin(u * math.tau))
        a.key("body", u, scl=bone_axes_scale(1 - 0.05 * b, 1 + 0.03 * b), loc=(0, 0, 0))
        a.key("face", u, rot=(0, 0, 0.05 * math.sin(u * math.tau)))
    a.done()
    hard_hit(arm)
    hard_death(arm)
    return arm


def build_tumbler():
    # the cube pivots on its front-bottom edge; flip happens in the last 30% of the cycle
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("pivot", (0.7, 0, 0), (0.7, 0.5, 0), "root"),
        ("cube", (0, 0, 0.7), (0, 0, 1.4), "pivot"),
    ])
    parts = [box((0, 0, 0.7), (1.4, 1.4, 1.4), 0.25, "body", "cube")]
    for x, y in ((0.7, 0.7), (0.7, -0.7), (-0.7, 0.7), (-0.7, -0.7)):
        parts.append(sphere((x * 0.95, y * 0.95, 1.38), (0.12, 0.12, 0.12), "dark", "cube", 10, 6))
    parts += eyes((0.72, 0, 1.0), 0.75, "cube")
    bind(arm, parts, [], 0.5)
    a = Anim(arm, "move", 1.0)
    for k in range(31):
        u = k / 30
        f = max(0.0, min(1.0, (u - 0.7) / 0.3))
        f = f * f * (3 - 2 * f)
        # pivot bone Y axis = world lateral; rotating about local Y tips the cube forward
        a.key("pivot", u, rot=(0, -f * math.pi / 2 * -1, 0))
        wob = math.exp(-u * 6) * math.sin(u * 40) * 0.08 if u < 0.7 else 0.0
        a.key("cube", u, scl=bone_axes_scale(1 - wob, 1 + wob * 0.5))
    a.done()
    hard_hit(arm)
    hard_death(arm)
    return arm


def build_swinger():
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("body", (0, 0, 0.6), (0, 0, 1.7), "root"),
        ("armL", (0, 0.75, 1.5), (0, 0.75, 0.45), "body"),
        ("armR", (0, -0.75, 1.5), (0, -0.75, 0.45), "body"),
        ("legL", (0, 0.3, 0.6), (0, 0.3, 0.0), "root"),
        ("legR", (0, -0.3, 0.6), (0, -0.3, 0.0), "root"),
    ])
    parts = [blob_mesh((0, 0, 1.2), (0.7, 0.7, 0.9))]
    for y, nm in ((0.75, "armL"), (-0.75, "armR")):
        parts.append(cyl((0, y, 1.5), (0, y, 0.5), 0.12, 0.1, "body", nm))
        parts.append(sphere((0, y, 0.45), (0.24, 0.24, 0.24), "dark", nm, 14, 8))
    for y, nm in ((0.3, "legL"), (-0.3, "legR")):
        parts.append(cyl((0, y, 0.65), (0, y, 0.05), 0.13, 0.1, "body", nm))
        parts.append(sphere((0.06, y, 0.05), (0.18, 0.14, 0.08), "dark", nm, 12, 6))
    parts += eyes((0.55, 0, 1.45), 0.7, "body")
    bind(arm, parts, ["body"], 0.6)
    a = Anim(arm, "move", 1.0)
    for k in range(25):
        u = k / 24
        s = math.sin(u * math.tau)
        # arms hang down (bone Y = down); local X rotation swings them fore/aft
        a.key("armL", u, rot=(s * 0.8, 0, 0))
        a.key("armR", u, rot=(-s * 0.8, 0, 0))
        a.key("legL", u, rot=(-s * 0.45, 0, 0))
        a.key("legR", u, rot=(s * 0.45, 0, 0))
        a.key("body", u, loc=(0, abs(s) * 0.06, 0), rot=(0, s * 0.12, 0))
    a.done()
    soft_hit(arm)
    hard_death(arm)
    return arm


def build_walker():
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("body", (0, 0, 1.8), (0, 0, 3.0), "root"),
        ("thighL", (0, 0.45, 1.8), (0.15, 0.45, 0.95), "body"),
        ("shinL", (0.15, 0.45, 0.95), (0, 0.45, 0.08), "thighL"),
        ("thighR", (0, -0.45, 1.8), (0.15, -0.45, 0.95), "body"),
        ("shinR", (0.15, -0.45, 0.95), (0, -0.45, 0.08), "thighR"),
    ])
    parts = [blob_mesh((0, 0, 2.3), (0.9, 0.8, 0.75))]
    for y, s in ((0.45, "L"), (-0.45, "R")):
        parts.append(cyl((0, y, 1.85), (0.15, y, 0.95), 0.17, 0.13, "body", "thigh" + s))
        parts.append(sphere((0.15, y, 0.95), (0.15, 0.15, 0.15), "dark", "thigh" + s, 12, 6))
        parts.append(cyl((0.15, y, 0.95), (0, y, 0.12), 0.13, 0.1, "body", "shin" + s))
        parts.append(box((0.1, y, 0.07), (0.5, 0.3, 0.15), 0.05, "dark", "shin" + s, 2))
    parts += eyes((0.8, 0, 2.45), 0.7, "body")
    for k in range(3):
        parts.append(cone((-0.3 + k * 0.3, 0, 2.95), 0.1, 0.35, "dark", "body", rot=(0, -0.3, 0)))
    bind(arm, parts, ["body"], 0.6)
    a = Anim(arm, "move", 1.0)
    for k in range(25):
        u = k / 24
        s = math.sin(u * math.tau)
        c = math.cos(u * math.tau)
        for side, ph in (("L", 0.0), ("R", math.pi)):
            ss = math.sin(u * math.tau + ph)
            cc = math.cos(u * math.tau + ph)
            a.key("thigh" + side, u, rot=(ss * 0.5, 0, 0))
            a.key("shin" + side, u, rot=(max(0.0, cc) * -0.8, 0, 0))
        a.key("body", u, loc=(0, abs(c) * 0.12, 0), rot=(0, s * 0.06, 0))
    a.done()
    hard_hit(arm)
    hard_death(arm, roll_side=False)
    return arm


def build_beetle():
    bones = [("root", (0, 0, 0), (0, 0, 0.3), None), ("shell", (0, 0, 0.25), (0, 0, 1.2), "root"), ("head", (0.9, 0, 0.45), (1.4, 0, 0.45), "shell")]
    for k in range(3):
        for s, y in (("L", 1), ("R", -1)):
            x = (k - 1) * 0.6
            bones.append(("leg%d%s" % (k, s), (x, y * 0.85, 0.3), (x, y * 1.35, 0.02), "shell"))
    arm = make_rig(bones)
    parts = [blob_mesh((0, 0, 0.3), (1.2, 1.0, 0.95), "body", "shell", squash_bottom=0.8)]
    parts.append(torus((0, 0, 0.3), 1.1, 0.06, "dark", "shell", scale=(1.08, 1.0, 1.0)))
    parts.append(box((0, 0, 1.2), (2.2, 0.06, 0.08), 0.02, "dark", "shell", 1))
    parts.append(sphere((1.0, 0, 0.45), (0.45, 0.5, 0.35), "dark", "head", 16, 10))
    for k in range(3):
        for s, y in (("L", 1), ("R", -1)):
            x = (k - 1) * 0.6
            parts.append(cyl((x, y * 0.8, 0.32), (x, y * 1.35, 0.02), 0.06, 0.04, "dark", "leg%d%s" % (k, s), 6))
    parts += eyes((1.25, 0, 0.55), 0.6, "head")
    bind(arm, parts, [], 0.5)
    a = Anim(arm, "move", 1.0)
    for k in range(25):
        u = k / 24
        for leg in range(3):
            for s in ("L", "R"):
                ph = (leg + (0 if s == "L" else 1)) % 2 * math.pi
                a.key("leg%d%s" % (leg, s), u, rot=(0, 0, math.sin(u * math.tau * 3 + ph) * 0.45))
        a.key("shell", u, loc=(0, abs(math.sin(u * math.tau * 3)) * 0.03, 0), rot=(0, math.sin(u * math.tau * 3) * 0.05, 0))
    a.done()
    hard_hit(arm)
    hard_death(arm)
    return arm


def build_nautilus():
    bones = [("root", (0, 0, 0), (0, 0, 0.3), None), ("foot", (-0.4, 0, 0.3), (1.3, 0, 0.3), "root"), ("shell", (-0.1, 0, 0.6), (-0.1, 0, 1.8), "root")]
    for k, y in enumerate((-0.3, 0.0, 0.3)):
        bones.append(("ten%da" % k, (1.2, y, 0.3), (1.55, y, 0.2), "foot"))
        bones.append(("ten%db" % k, (1.55, y, 0.2), (1.85, y, 0.08), "ten%da" % k))
    arm = make_rig(bones)
    parts = [blob_mesh((0.5, 0, 0.35), (0.95, 0.55, 0.4), squash_bottom=0.5)]
    for k in range(6):
        s = 0.85 - k * 0.13
        parts.append(torus((-0.1 - k * 0.08, 0, 0.95 + k * 0.06), s, s * 0.42, "body", "shell", rot=(math.pi / 2, 0, 0), seg=24, mseg=10))
    parts.append(torus((-0.1, 0, 0.95), 0.86, 0.06, "dark", "shell", rot=(math.pi / 2, 0, 0)))
    for k, y in enumerate((-0.3, 0.0, 0.3)):
        parts.append(cyl((1.15, y, 0.3), (1.85, y, 0.08), 0.1, 0.03, "body"))
    parts += eyes((1.25, 0, 0.6), 0.55, "foot")
    bind(arm, parts, ["foot"] + ["ten%d%s" % (k, c) for k in range(3) for c in "ab"], 0.3)
    a = Anim(arm, "move", 1.0)
    for k in range(25):
        u = k / 24
        w = math.sin(u * math.tau)
        a.key("foot", u, scl=(1, 1 + 0.12 * w, 1))
        a.key("shell", u, rot=(0, 0, 0.05 * math.sin(u * math.tau - 1.0)), loc=(0, 0.03 * w, 0))
        for t in range(3):
            ph = u * math.tau * 2 + t * 1.3
            a.key("ten%da" % t, u, rot=(math.sin(ph) * 0.3, 0, math.cos(ph) * 0.2))
            a.key("ten%db" % t, u, rot=(math.sin(ph - 0.8) * 0.4, 0, 0))
    a.done()
    soft_hit(arm, body="foot")
    hard_death(arm)
    return arm


def build_balloon():
    arm = make_rig([
        ("root", (0, 0, 0), (0, 0, 0.3), None),
        ("basket", (0, 0, 0), (0, 0, 0.4), "root"),
        ("rope", (0, 0, 0.4), (0, 0, 3.2), "basket"),
        ("balloon", (0, 0, 3.2), (0, 0, 5.4), "rope"),
    ])
    parts = [blob_mesh((0, 0, 4.2), (1.0, 1.0, 1.15), "body", "balloon")]
    parts.append(cone((0, 0, 3.05), 0.15, 0.2, "body", "balloon", rot=(math.pi, 0, 0)))
    parts.append(cyl((0, 0, 0.4), (0, 0, 3.05), 0.02, 0.02, "dark", "rope", 5))
    parts.append(box((0, 0, 0.2), (0.32, 0.32, 0.22), 0.04, "dark", "basket", 1))
    parts += eyes((0.85, 0, 4.4), 0.7, "balloon")
    bind(arm, parts, [], 0.5)
    a = Anim(arm, "move", 1.0)
    for k in range(13):
        u = k / 12
        a.key("rope", u, rot=(math.sin(u * math.tau) * 0.06, 0, math.cos(u * math.tau) * 0.04))
        a.key("balloon", u, scl=bone_axes_scale(1 + 0.04 * math.sin(u * math.tau * 2), 1 - 0.02 * math.sin(u * math.tau * 2)))
        a.key("basket", u, rot=(0, math.sin(u * math.tau) * 0.15, 0))
    a.done()
    a = Anim(arm, "hit", 0.3)
    for t, s in [(0, 1), (0.05, 0.85), (0.15, 1.08), (0.3, 1)]:
        a.key("balloon", t, scl=bone_axes_scale(s, 2 - s))
    a.done()
    a = Anim(arm, "death", 0.8)  # pops, then the basket drops
    for t, s in [(0, 1), (0.08, 1.35), (0.12, 0.05), (0.8, 0.0)]:
        a.key("balloon", t, scl=s)
    for t, d in [(0, 0), (0.12, 0), (0.6, -0.1), (0.8, -0.2)]:
        a.key("root", t, loc=(0, d, 0))
    for t, r in [(0, 0), (0.12, 0), (0.5, 0.9), (0.8, 1.4)]:
        a.key("rope", t, rot=(r, 0, 0), scl=max(0.05, 1 - t))
    a.done()
    return arm


BUILDERS = {
    "hopper": build_hopper, "crawler": build_crawler, "blob": build_blob, "slinky": build_slinky,
    "roller": build_roller, "tumbler": build_tumbler, "swinger": build_swinger, "walker": build_walker,
    "beetle": build_beetle, "nautilus": build_nautilus, "balloon": build_balloon,
}


def swap_in_meshy(arch, arm):
    """Replace the code-built body with a Meshy mesh of the same size, keeping eyes and dark parts."""
    path = os.path.join(MESHY, arch + ".glb")
    if not MESHY or not os.path.exists(path):
        return False
    body = bpy.data.objects["body"]
    bpy.ops.object.select_all(action="DESELECT")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in bpy.data.objects:
        if o not in before and o.type != "MESH":
            bpy.data.objects.remove(o)
    if not new:
        return False
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    m = bpy.context.active_object
    m.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # fit to the body slot's bounds
    def bounds(o):
        cs = [o.matrix_world @ v.co for v in o.data.vertices if o.data.materials[o.data.polygons[0].material_index].name == "body" or True]
        lo = Vector((min(c.x for c in cs), min(c.y for c in cs), min(c.z for c in cs)))
        hi = Vector((max(c.x for c in cs), max(c.y for c in cs), max(c.z for c in cs)))
        return lo, hi
    lo, hi = bounds(body)
    mlo, mhi = bounds(m)
    s = min((hi - lo).x / max(1e-6, (mhi - mlo).x), (hi - lo).z / max(1e-6, (mhi - mlo).z))
    for v in m.data.vertices:
        v.co = (v.co - Vector(((mlo.x + mhi.x) / 2, (mlo.y + mhi.y) / 2, mlo.z))) * s + Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    m.data.materials.clear()
    m.data.materials.append(bpy.data.materials["body"])
    # weights: copy from the code-built body by nearest vertex
    mod = m.modifiers.new("wt", "DATA_TRANSFER")
    mod.object = body
    mod.use_vert_data = True
    mod.data_types_verts = {"VGROUP_WEIGHTS"}
    mod.vert_mapping = "POLYINTERP_NEAREST"
    bpy.context.view_layer.objects.active = m
    bpy.ops.object.datalayout_transfer(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # drop the code-built body faces, keep eyes and dark trim
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(body.data)
    body_idx = [k for k, mt in enumerate(body.data.materials) if mt.name == "body"]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in body_idx], context="FACES_ONLY")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.update_edit_mesh(body.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    m.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    return True


def export(arch):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, arch + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False, export_apply=False,
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_frame_step=1, export_skins=True, export_morph=False, export_materials="EXPORT",
        export_yup=True, export_def_bones=False, export_optimize_animation_size=True,
    )
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons)
    print("built %-9s %5d tris %2d bones -> %s" % (arch, tris, len(bpy.data.objects["rig"].data.bones), path))


for arch, fn in BUILDERS.items():
    if ONLY and arch not in ONLY:
        continue
    reset()
    rig = fn()
    swap_in_meshy(arch, rig)
    export(arch)
