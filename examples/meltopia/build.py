#!/usr/bin/env python3
"""Builds examples/meltopia.melt: Meltopia, a killer-vs-survivors round game.

    python3 build.py              # writes ../meltopia.melt

The lobby and both maps are generated here from parts (seeded, so every build is
the same); the game itself is in the .luau files next to this script. Sounds and
the character pictures are uploads: set their asset://ids in ReplicatedStorage >
Assets (see README.md), everything works with built-in stand-ins until then.
"""
import json
import math
import os
import random

here = os.path.dirname(os.path.abspath(__file__))
R = random.Random(20260926)


def src(name):
    with open(os.path.join(here, name), encoding='utf-8') as f:
        return f.read()


def v3(x, y, z):
    return {'$v3': [round(x, 3), round(y, 3), round(z, 3)]}


def c3(h):
    return {'$c3': h}


def u2(a, b, c, d):
    return {'$u2': [a, b, c, d]}


# --------------------------------------------------------------------------------------
# Parts
# --------------------------------------------------------------------------------------

COUNT = [0]


def part(name, size, pos, color, mat='SmoothPlastic', rot=(0, 0, 0), shape=None, collide=True, shadow=True,
         transp=0.0, kids=None, climb=False, touch=None, cls='Part'):
    COUNT[0] += 1
    p = {'Size': v3(*size), 'Position': v3(*pos), 'Color': c3(color), 'Material': mat}
    if any(abs(r) > 1e-6 for r in rot):
        p['Rotation'] = v3(*rot)
    if shape and cls == 'Part':
        p['Shape'] = shape
    if not collide:
        p['CanCollide'] = False
    if not shadow:
        p['CastShadow'] = False
    if transp:
        p['Transparency'] = transp
    if climb:
        p['Climbable'] = True
    if touch is not None:
        p['CanTouch'] = touch
    node = {'c': cls, 'n': name, 'p': p}
    if kids:
        node['k'] = kids
    return node


def light(color, brightness=1.5, rng=16, name='PointLight', offset=None):
    p = {'Color': c3(color), 'Brightness': brightness, 'Range': rng}
    if offset:
        p['Offset'] = v3(*offset)
    return {'c': 'PointLight', 'n': name, 'p': p}


def model(name, kids):
    return {'c': 'Model', 'n': name, 'k': kids}


def text3d(name, text, pos, color='#ffffff', size=64, rot=(0, 0, 0), billboard=False, outline='#1c1a22', font='Black'):
    p = {'Text': text, 'Position': v3(*pos), 'TextColor': c3(color), 'TextSize': size, 'Font': font,
         'OutlineColor': c3(outline), 'Billboard': billboard}
    if any(rot):
        p['Rotation'] = v3(*rot)
    COUNT[0] += 1
    return {'c': 'Text3D', 'n': name, 'p': p}


def censor():
    """The killer's face: a big black square worn on the head, always turned to the viewer."""
    t = text3d('Censor', '\u25a0', (0, 0, 0), '#000000', 92, billboard=True, outline='#000000')
    return t


class Frame:
    """A local frame: build in local coordinates, place and turn the result anywhere."""

    def __init__(self, ox, oy, oz, yaw=0.0):
        self.o = (ox, oy, oz)
        self.yaw = yaw
        r = math.radians(yaw)
        self.c, self.s = math.cos(r), math.sin(r)

    def at(self, x, y, z):
        # Rotation about Y by `yaw` (Godot/Meltiew convention: +yaw turns +Z toward +X).
        wx = x * self.c + z * self.s
        wz = -x * self.s + z * self.c
        return (self.o[0] + wx, self.o[1] + y, self.o[2] + wz)

    def p(self, name, size, pos, color, mat='SmoothPlastic', rot=(0, 0, 0), **kw):
        return part(name, size, self.at(*pos), color, mat, (rot[0], rot[1] + self.yaw, rot[2]), **kw)


def jitter(hexcol, amount=0.06):
    h = hexcol.lstrip('#')
    rgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    k = 1 + R.uniform(-amount, amount)
    rgb = [min(1, max(0, c * k)) for c in rgb]
    return '#' + ''.join(f'{int(c * 255):02x}' for c in rgb)


# --------------------------------------------------------------------------------------
# Props used on several maps
# --------------------------------------------------------------------------------------

def pine(x, z, h=None, dark=False):
    h = h or R.uniform(9, 15)
    trunk_h = h * 0.35
    out = [part('Trunk', (0.9, trunk_h, 0.9), (x, trunk_h / 2, z), jitter('#3b2a1f'), 'Wood', shape='Cylinder')]
    base = '#16301f' if dark else '#1d3a26'
    tiers = 4
    for i in range(tiers):
        r = (h * 0.34) * (1 - i / (tiers + 0.6))
        th = h * 0.22
        y = trunk_h * 0.8 + i * th * 0.78 + th / 2
        out.append(part('Needles', (r * 2, th, r * 2), (x, y, z), jitter(base, 0.12), 'Grass', shape='Cylinder', shadow=i == 0))
    return out


def leafy(x, z, h=None):
    h = h or R.uniform(7, 10)
    trunk_h = h * 0.55
    out = [part('Trunk', (1.0, trunk_h, 1.0), (x, trunk_h / 2, z), jitter('#3d2c21'), 'Wood', shape='Cylinder')]
    for k in range(3):
        s = R.uniform(4.5, 6.5)
        out.append(part('Leaves', (s, s, s), (x + R.uniform(-1.4, 1.4), trunk_h + R.uniform(0.5, 2.5), z + R.uniform(-1.4, 1.4)),
                        jitter('#23402a', 0.15), 'Grass', shape='Ball'))
    return out


def rock(x, z, s=None, color='#4b4d55'):
    s = s or R.uniform(1.2, 3.2)
    return part('Rock', (s * R.uniform(1, 1.5), s * 0.7, s), (x, s * 0.25, z), jitter(color, 0.1), 'Concrete', shape='Ball')


def bush(x, z):
    s = R.uniform(2, 3.4)
    return part('Bush', (s * 1.3, s, s * 1.2), (x, s * 0.35, z), jitter('#1f3a25', 0.15), 'Grass', shape='Ball', collide=False)


def lamp_post(x, z, color='#ffd9a0', on=True, flicker=False, h=8, rng=24, brightness=1.6):
    kids = [light(color, brightness, rng, 'Flicker' if flicker else 'PointLight')] if on else None
    return [
        part('Pole', (0.35, h, 0.35), (x, h / 2, z), '#2b2c33', 'Metal', shape='Cylinder'),
        part('Arm', (0.25, 0.25, 1.6), (x, h - 0.2, z + 0.7), '#2b2c33', 'Metal'),
        part('Lamp', (0.9, 0.35, 0.9), (x, h - 0.45, z + 1.4), color if on else '#3a3a40', 'Neon' if on else 'Glass', kids=kids,
             collide=False, shadow=False),
    ]


def generator(name, x, z, yaw=0):
    """A generator: the survivors' puzzle box. Bulb1..3 show progress; Lamp is its status light."""
    f = Frame(x, 0, z, yaw)
    return model(name, [
        f.p('Base', (3.2, 2.4, 2.2), (0, 1.2, 0), '#3b3f46', 'Metal'),
        f.p('Skid', (3.6, 0.3, 2.6), (0, 0.15, 0), '#24262b', 'Metal'),
        f.p('Stripe', (3.22, 0.35, 2.22), (0, 2.0, 0), '#d8a31a', 'SmoothPlastic', shadow=False),
        f.p('Panel', (1.6, 1.1, 0.1), (-0.5, 1.25, 1.12), '#1b1d22', 'Metal', shadow=False),
        f.p('Bulb1', (0.42, 0.42, 0.42), (0.55, 1.55, 1.15), '#3a1f24', 'Neon', shape='Ball', collide=False, shadow=False),
        f.p('Bulb2', (0.42, 0.42, 0.42), (0.55, 1.05, 1.15), '#3a1f24', 'Neon', shape='Ball', collide=False, shadow=False),
        f.p('Bulb3', (0.42, 0.42, 0.42), (0.55, 0.55, 1.15), '#3a1f24', 'Neon', shape='Ball', collide=False, shadow=False),
        f.p('Exhaust', (0.4, 1.2, 0.4), (-1.1, 3.0, -0.5), '#26282d', 'Metal', shape='Cylinder'),
        f.p('Lamp', (0.55, 0.4, 0.55), (0.9, 2.6, -0.5), '#ff3b4f', 'Neon', shape='Cylinder', collide=False, shadow=False,
            kids=[light('#ff3b4f', 1.2, 9)]),
        f.p('Cable', (0.18, 0.18, 3.4), (1.3, 0.12, 2.6), '#111214', 'SmoothPlastic', collide=False, shadow=False),
    ])


def spawns(killer, survivors):
    kids = [part('Killer', (2, 1, 2), (killer[0], 0.5, killer[1]), '#ff0000', transp=1, collide=False, touch=False, shadow=False)]
    for x, z in survivors:
        kids.append(part('Survivor', (2, 1, 2), (x, 0.5, z), '#00ff00', transp=1, collide=False, touch=False, shadow=False))
    return model('Spawns', kids)


def walls(cx, cz, half, h=40):
    """Invisible walls around a square map."""
    t = 2
    return model('Bounds', [
        part('Wall', (half * 2 + 4, h, t), (cx, h / 2, cz - half - 1), '#000000', transp=1, shadow=False),
        part('Wall', (half * 2 + 4, h, t), (cx, h / 2, cz + half + 1), '#000000', transp=1, shadow=False),
        part('Wall', (t, h, half * 2 + 4), (cx - half - 1, h / 2, cz), '#000000', transp=1, shadow=False),
        part('Wall', (t, h, half * 2 + 4), (cx + half + 1, h / 2, cz), '#000000', transp=1, shadow=False),
    ])


def fence(x1, z1, x2, z2, color='#4a3a2c', mat='Wood', h=2.6, gap_every=None):
    dx, dz = x2 - x1, z2 - z1
    L = math.hypot(dx, dz)
    yaw = math.degrees(math.atan2(dx, dz))
    n = max(1, int(L / 4))
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(part('Post', (0.4, h, 0.4), (x1 + dx * t, h / 2, z1 + dz * t), jitter(color), mat))
    cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
    for y in (h * 0.4, h * 0.8):
        out.append(part('Rail', (0.18, 0.3, L), (cx, y, cz), jitter(color), mat, rot=(0, yaw, 0)))
    return out


def crate(x, y, z, s=2.2, yaw=0):
    return part('Crate', (s, s, s), (x, y + s / 2, z), jitter('#6b4d2e', 0.1), 'Wood', rot=(0, yaw, 0))


def barrel(x, z, color):
    return part('Barrel', (1.4, 2.0, 1.4), (x, 1.0, z), jitter(color, 0.1), 'Metal', shape='Cylinder')


# --------------------------------------------------------------------------------------
# Lobby: a cozy evening glade with the two characters on show
# --------------------------------------------------------------------------------------

def lobby():
    k = []
    k.append(part('Ground', (110, 2, 110), (0, -1, 0), '#2f4a33', 'Grass', shape='Cylinder'))
    k.append(part('Edge', (112, 1.6, 112), (0, -1.6, 0), '#3a2c22', 'Sand', shape='Cylinder'))
    k.append(part('Plaza', (34, 0.2, 34), (0, 0.1, 0), '#7c7686', 'Concrete', shape='Cylinder'))
    k.append(part('PlazaRing', (36, 0.16, 36), (0, 0.06, 0), '#5d5868', 'Concrete', shape='Cylinder'))
    sp = part('Spawn', (8, 0.4, 8), (0, 0.25, 6), '#b89cff', 'SmoothPlastic', cls='SpawnLocation')
    k.append(sp)
    # Title over the stage.
    k.append(part('Stage', (40, 1.2, 12), (0, 0.6, -24), '#3b2d3f', 'Wood'))
    k.append(part('StageStep', (40, 0.6, 2), (0, 0.3, -17.2), '#4a3a50', 'Wood'))
    k.append(text3d('Title', '$title', (0, 14.5, -29.5), '#ff4d6d', 300))
    k.append(text3d('Subtitle', '$subtitle', (0, 10.6, -29.5), '#f4f1ec', 110, font='Bold'))
    # The two showcased characters on their pedestals.
    for name, x, color, anim, tag in (('KillerRig', -9, '#ff4d6d', 'idle', '$tag_killer_nrz'), ('SurvivorRig', 9, '#7ee0c3', 'wave', '$tag_survivor_melly')):
        k.append(part('Pedestal', (7, 1.4, 7), (x, 1.9, -24), '#1c1824', 'Metal', shape='Cylinder'))
        k.append(part('PedestalGlow', (7.4, 0.25, 7.4), (x, 2.65, -24), color, 'Neon', shape='Cylinder', shadow=False,
                      kids=[light(color, 2.4, 14, offset=(0, 3, 3))]))
        rig = {'c': 'Rig', 'n': name, 'p': {'Position': v3(x, 2.8, -24), 'Rotation': v3(0, 180 if x < 0 else 180, 0),
               'Animation': anim, 'DisplayName': ''}}
        if name == 'SurvivorRig':
            rig['p'].update({'HeadColor': c3('#f5f1ec'), 'TorsoColor': c3('#baa4e2'), 'LeftArmColor': c3('#f5f1ec'),
                             'RightArmColor': c3('#f5f1ec'), 'LeftLegColor': c3('#302d38'), 'RightLegColor': c3('#302d38'),
                             'Face': ':D', 'Accessories': ''})
        if name == 'KillerRig':
            rig['k'] = [censor()]
        k.append(rig)
        k.append(text3d('Tag', tag, (x, 7.8, -22), color, 80, billboard=True))
    # String lights: poles around the plaza with warm bulbs sagging between them.
    poles = []
    for i in range(10):
        a = i / 10 * math.tau + 0.3
        x, z = math.cos(a) * 19, math.sin(a) * 19
        poles.append((x, z))
        k.append(part('LightPole', (0.4, 7, 0.4), (x, 3.5, z), '#3a2b22', 'Wood', shape='Cylinder'))
    warm = ['#ffcf7a', '#ff9f6b', '#ffe8a8', '#ff8fb1', '#b89cff']
    for i in range(10):
        (x1, z1), (x2, z2) = poles[i], poles[(i + 1) % 10]
        for j in range(1, 8):
            t = j / 8
            sag = math.sin(t * math.pi) * 1.4
            bx, bz = x1 + (x2 - x1) * t, z1 + (z2 - z1) * t
            kids = [light(warm[(i + j) % 5], 0.8, 10)] if j == 4 and i % 2 == 0 else None
            k.append(part('Bulb', (0.32, 0.32, 0.32), (bx, 6.8 - sag, bz), warm[(i * 3 + j) % 5], 'Neon', shape='Ball',
                          collide=False, shadow=False, kids=kids))
    # Benches, a little campfire, lanterns.
    for i in range(4):
        a = i / 4 * math.tau + math.pi / 4
        f = Frame(math.cos(a) * 12, 0, math.sin(a) * 12, math.degrees(-a) + 90)
        k.append(f.p('Seat', (5, 0.3, 1.4), (0, 1.1, 0), '#6b4a31', 'Wood'))
        k.append(f.p('Back', (5, 1.2, 0.25), (0, 1.8, -0.6), '#6b4a31', 'Wood'))
        for sx in (-2, 2):
            k.append(f.p('Leg', (0.3, 1.0, 1.2), (sx, 0.5, 0), '#2d2a30', 'Metal'))
    for i in range(6):
        a = i / 6 * math.tau
        k.append(part('FireStone', (1, 0.7, 1), (math.cos(a) * 1.7 + 0, 0.35, math.sin(a) * 1.7 + 14), '#56535c', 'Concrete', shape='Ball'))
    for yaw in (0, 60, 120):
        k.append(part('Log', (0.45, 2.6, 0.45), (0, 0.3, 14), '#4a3322', 'Wood', shape='Cylinder', rot=(90, yaw, 0)))
    flames = [((0.9, 1.3, 0.9), (0, 0.9, 14), '#ff5a2e', (0, 20, 8)), ((0.7, 1.0, 0.7), (0.25, 1.05, 13.8), '#ff8a3d', (0, 55, -10)),
              ((0.6, 0.9, 0.6), (-0.25, 1.0, 14.2), '#ff8a3d', (0, 80, 12)), ((0.45, 0.8, 0.45), (0, 1.5, 14), '#ffd166', (0, 35, -6)),
              ((0.25, 0.5, 0.25), (0.1, 2.0, 14.05), '#fff1b0', (0, 10, 5))]
    for i, (size, pos, col, rot) in enumerate(flames):
        kids = [light('#ff9a4a', 2.2, 20, 'Flicker', offset=(0, 0.6, 0))] if i == 0 else None
        k.append(part('Flame', size, pos, col, 'Neon', collide=False, shadow=False, rot=rot, kids=kids))
    # How to play, on a board.
    f = Frame(24, 0, -6, -70)
    k.append(f.p('Board', (12, 7, 0.4), (0, 4.5, 0), '#2a2231', 'Wood'))
    for sx in (-5.5, 5.5):
        k.append(f.p('BoardLeg', (0.5, 4, 0.5), (sx, 1, 0), '#3a2b22', 'Wood'))
    board_lines = ['$how_title', '$how_1', '$how_2', '$how_3', '$how_4']
    for i, t in enumerate(board_lines):
        k.append(text3d('How', t, f.at(0, 7.2 - i * 1.25, 0.3), '#ffd166' if i == 0 else '#f4f1ec', 70 if i == 0 else 40,
                        rot=(0, -70, 0), font='Black' if i == 0 else 'Bold'))
    # Trees and bushes around, a fence, invisible walls.
    for i in range(46):
        a = R.uniform(0, math.tau)
        r = R.uniform(34, 52)
        x, z = math.cos(a) * r, math.sin(a) * r
        if abs(x) < 26 and -36 < z < -10:
            continue
        k.extend(pine(x, z) if R.random() < 0.6 else leafy(x, z))
    for i in range(20):
        a = R.uniform(0, math.tau)
        k.append(bush(math.cos(a) * R.uniform(24, 34), math.sin(a) * R.uniform(24, 34)))
    for i in range(12):
        a = i / 12 * math.tau
        k.append(part('Wall', (30, 30, 2), (math.cos(a) * 54, 15, math.sin(a) * 54), '#000000', transp=1, shadow=False,
                      rot=(0, math.degrees(-a) + 90, 0)))
    for x, z in ((-26, 10), (26, 12), (-22, -8)):
        k.extend(lamp_post(x, z, '#ffcf8a', flicker=False, brightness=1.2, rng=20))
    return model('Lobby', k)


# --------------------------------------------------------------------------------------
# Map 1: Pine Camp, an abandoned summer camp in the woods
# --------------------------------------------------------------------------------------

def cabin(x, z, yaw, lit=False, name='Cabin'):
    f = Frame(x, 0, z, yaw)
    W, D, H = 14, 10, 6.5
    wood = jitter('#4e3726')
    dark = jitter('#3a2a1e')
    k = [
        f.p('Floor', (W, 0.6, D), (0, 0.6, 0), dark, 'Wood'),
        f.p('Porch', (W, 0.4, 3.2), (0, 0.5, D / 2 + 1.6), dark, 'Wood'),
        f.p('Step', (3, 0.3, 1.2), (0, 0.15, D / 2 + 3.6), dark, 'Wood'),
        # Back wall with a window.
        f.p('Wall', (W, H, 0.5), (0, H / 2 + 0.9, -D / 2), wood, 'Wood'),
        # Front wall: door gap in the middle.
        f.p('Wall', (5.5, H, 0.5), (-(W / 2 - 2.75), H / 2 + 0.9, D / 2), wood, 'Wood'),
        f.p('Wall', (5.5, H, 0.5), (W / 2 - 2.75, H / 2 + 0.9, D / 2), wood, 'Wood'),
        f.p('Wall', (3, 2, 0.5), (0, H + 0.9 - 1, D / 2), wood, 'Wood'),
        # Side walls with a window gap.
        f.p('Wall', (0.5, H, 3.5), (-W / 2, H / 2 + 0.9, -D / 2 + 1.75), wood, 'Wood'),
        f.p('Wall', (0.5, H, 3.5), (-W / 2, H / 2 + 0.9, D / 2 - 1.75), wood, 'Wood'),
        f.p('Wall', (0.5, 2.2, 3.0), (-W / 2, 2.0, 0), wood, 'Wood'),
        f.p('Wall', (0.5, 1.6, 3.0), (-W / 2, H + 0.1, 0), wood, 'Wood'),
        f.p('Wall', (0.5, H, D), (W / 2, H / 2 + 0.9, 0), wood, 'Wood'),
        # A gable roof from two wedges, dark shingles.
        f.p('Roof', (W + 1.6, 3.0, D / 2 + 1.2), (0, H + 2.4, -(D / 4 + 0.3)), '#2a2226', 'Wood', rot=(0, 180, 0)),
        f.p('Roof', (W + 1.6, 3.0, D / 2 + 1.2), (0, H + 2.4, D / 4 + 0.3), '#2a2226', 'Wood'),
        f.p('Chimney', (1.2, 3.2, 1.2), (W / 2 - 2.5, H + 3.2, -1.5), '#4a3f3f', 'Brick'),
        # Inside: a table, a bunk, the glow in the window if someone left a lamp on.
        f.p('Table', (3, 0.25, 2), (2, 2.1, -1.5), '#5a3f2b', 'Wood'),
        f.p('TableLeg', (0.25, 1.2, 0.25), (1, 1.5, -1.5), '#3a2a1e', 'Wood'),
        f.p('TableLeg', (0.25, 1.2, 0.25), (3, 1.5, -1.5), '#3a2a1e', 'Wood'),
        f.p('Bunk', (2.4, 0.5, 6), (-W / 2 + 1.6, 1.6, -1), '#5a3f2b', 'Wood'),
        f.p('Mattress', (2.2, 0.4, 5.6), (-W / 2 + 1.6, 2.05, -1), '#6d4f5c', 'Fabric'),
    ]
    if lit:
        k.append(f.p('Lantern', (0.5, 0.7, 0.5), (2, 2.6, -1.5), '#ffcf7a', 'Neon', collide=False, shadow=False,
                     kids=[light('#ffb86b', 1.6, 18, 'Flicker')]))
    else:
        k.append(f.p('Lantern', (0.5, 0.7, 0.5), (2, 2.6, -1.5), '#4a3f33', 'Glass', collide=False))
    return model(name, k)


def tent(x, z, yaw, color):
    f = Frame(x, 0, z, yaw)
    return [
        f.p('Tent', (4.4, 3.2, 2.2), (0, 1.6, -1.1), color, 'Fabric', rot=(0, 180, 0)),
        f.p('Tent', (4.4, 3.2, 2.2), (0, 1.6, 1.1), color, 'Fabric'),
        f.p('TentFloor', (4.6, 0.1, 4.6), (0, 0.05, 0), '#2a2a2a', 'Fabric', collide=False),
    ]


def camp():
    OX, OZ = 0, 600
    k = []
    k.append(part('Ground', (200, 1, 200), (OX, -0.5, OZ), '#1c2a21', 'Grass'))
    # Dirt paths from the fire to everything.
    paths = [((0, -85), (0, 0)), ((0, 0), (-44, -38)), ((0, 0), (46, -36)), ((0, 0), (-46, 40)), ((0, 0), (40, 48)),
             ((0, 0), (58, 0)), ((0, 0), (-62, 0)), ((0, 0), (8, 48))]
    for (x1, z1), (x2, z2) in paths:
        dx, dz = x2 - x1, z2 - z1
        L = math.hypot(dx, dz)
        k.append(part('Path', (5, 0.1, L + 4), (OX + (x1 + x2) / 2, 0.05, OZ + (z1 + z2) / 2), jitter('#3a2f25', 0.08), 'Sand',
                      rot=(0, math.degrees(math.atan2(dx, dz)), 0), shadow=False))
    # The campfire in the middle, benches of logs around it.
    for i in range(10):
        a = i / 10 * math.tau
        k.append(part('FireStone', (1.2, 0.8, 1.2), (OX + math.cos(a) * 2.4, 0.3, OZ + math.sin(a) * 2.4), jitter('#57545c'), 'Concrete', shape='Ball'))
    for i in range(4):
        k.append(part('FireLog', (0.6, 3, 0.6), (OX, 0.5, OZ), '#2c1f16', 'Wood', shape='Cylinder', rot=(80, i * 45, 0)))
    k.append(part('Fire', (1.6, 1.8, 1.6), (OX, 1.0, OZ), '#ff7a2f', 'Neon', collide=False, shadow=False, rot=(0, 30, 0),
                  kids=[light('#ff8a3d', 2.6, 30, 'Flicker', offset=(0, 1.5, 0))]))
    k.append(part('Fire', (0.9, 1.3, 0.9), (OX + 0.2, 1.3, OZ - 0.1), '#ffd166', 'Neon', collide=False, shadow=False))
    for i in range(3):
        a = i / 3 * math.tau + 0.4
        k.append(part('LogSeat', (1.3, 5, 1.3), (OX + math.cos(a) * 7, 0.65, OZ + math.sin(a) * 7), jitter('#4a3322'), 'Wood',
                      shape='Cylinder', rot=(0, math.degrees(-a), 90)))
    # Cabins, one with a lamp still burning.
    k.append(cabin(OX - 46, OZ - 42, 35, lit=True))
    k.append(cabin(OX + 48, OZ - 40, -30))
    k.append(cabin(OX - 50, OZ + 44, 150))
    k.append(cabin(OX + 42, OZ + 52, 210, lit=True))
    # Tents.
    for x, z, yaw, col in ((16, -22, 20, '#6a3b2a'), (-20, 16, -40, '#2e4a5a'), (24, 22, 70, '#3f5a33'), (-14, -26, 100, '#5a4a2a')):
        k.extend(tent(OX + x, OZ + z, yaw, col))
    # The lake with a dock and a rowboat.
    k.append(part('Shore', (58, 0.14, 32), (OX + 2, 0.07, OZ + 70), '#4a4232', 'Sand', shadow=False))
    k.append(part('Lake', (52, 0.2, 26), (OX + 2, 0.12, OZ + 72), '#0f2a3d', 'Glass', transp=0.15, shadow=False))
    for i in range(7):
        k.append(part('Plank', (4, 0.3, 2), (OX + 8, 0.9, OZ + 56 + i * 2.1), jitter('#5b4330'), 'Wood'))
    for i in range(4):
        for sx in (6.2, 9.8):
            k.append(part('DockPost', (0.5, 2.4, 0.5), (OX + sx, 0.6, OZ + 57 + i * 4), '#3a2a1e', 'Wood', shape='Cylinder'))
    k.append(part('Boat', (2.6, 0.9, 6), (OX + 14, 0.5, OZ + 66), '#6a2f2a', 'Wood', rot=(0, 20, 6)))
    k.append(part('Oar', (0.2, 0.2, 4), (OX + 15.6, 1.0, OZ + 66), '#6b4d2e', 'Wood', rot=(0, 40, 0), collide=False))
    # The lookout tower with a ladder you can climb.
    tx, tz = OX - 68, OZ + 2
    for sx in (-3, 3):
        for sz in (-3, 3):
            k.append(part('TowerLeg', (0.7, 15, 0.7), (tx + sx, 7.5, tz + sz), '#3e2d20', 'Wood'))
    k.append(part('TowerDeck', (8, 0.6, 8), (tx, 15, tz), '#4a3524', 'Wood'))
    for side in ((0, -4, 8, 0.3), (0, 4, 8, 0.3), (-4, 0, 0.3, 8), (4, 0, 0.3, 8)):
        k.append(part('Rail', (side[2], 1.2, side[3]), (tx + side[0], 16, tz + side[1]), '#3e2d20', 'Wood'))
    k.append(part('TowerRoof', (9, 0.5, 9), (tx, 19.5, tz), '#2a2226', 'Wood'))
    for sx in (-3.8, 3.8):
        for sz in (-3.8, 3.8):
            k.append(part('RoofPost', (0.4, 4, 0.4), (tx + sx, 17.5, tz + sz), '#3e2d20', 'Wood'))
    k.append(part('Ladder', (1.8, 15, 0.3), (tx, 7.5, tz + 4.3), '#6b4d2e', 'Wood', climb=True))
    for i in range(10):
        k.append(part('Rung', (1.8, 0.2, 0.4), (tx, 1 + i * 1.45, tz + 4.45), '#7a5a3a', 'Wood', collide=False))
    # A school bus left to rot.
    f = Frame(OX + 62, 0, OZ + 4, 12)
    k.append(model('Bus', [
        f.p('Body', (7, 5.4, 22), (0, 3.4, 0), '#7a6a2e', 'Metal', rot=(0, 0, 4)),
        f.p('Roof', (7.2, 0.5, 22.2), (0, 6.2, 0), '#6a5b28', 'Metal', rot=(0, 0, 4)),
        f.p('Windows', (7.1, 1.6, 18), (0, 4.6, -1), '#141a22', 'Glass', rot=(0, 0, 4)),
        f.p('Bumper', (7.2, 0.8, 0.8), (0, 1.2, 11.2), '#2a2a2a', 'Metal'),
        f.p('Wheel', (1.2, 2.4, 2.4), (-3.6, 1.2, 7), '#1a1a1c', 'Plastic', shape='Cylinder', rot=(0, 0, 90)),
        f.p('Wheel', (1.2, 2.4, 2.4), (3.6, 1.0, 7), '#1a1a1c', 'Plastic', shape='Cylinder', rot=(0, 0, 90)),
        f.p('Wheel', (1.2, 2.4, 2.4), (-3.6, 1.2, -7), '#1a1a1c', 'Plastic', shape='Cylinder', rot=(0, 0, 90)),
    ]))
    # Outhouse, picnic tables, woodpile.
    f = Frame(OX - 26, 0, OZ + 62, 20)
    k.append(model('Outhouse', [
        f.p('Box', (3.4, 6, 3.4), (0, 3, 0), '#4e3726', 'Wood'),
        f.p('Roof', (4, 0.4, 4), (0, 6.2, 0), '#2a2226', 'Wood', rot=(8, 0, 0)),
        f.p('Door', (1.8, 4.4, 0.1), (0, 2.4, 1.72), '#3a2a1e', 'Wood'),
    ]))
    for x, z, yaw in ((14, -8, 30), (-12, 6, -20)):
        f = Frame(OX + x, 0, OZ + z, yaw)
        k.append(f.p('Table', (5, 0.3, 2.2), (0, 2.1, 0), '#5a3f2b', 'Wood'))
        for sz in (-1.8, 1.8):
            k.append(f.p('Bench', (5, 0.25, 0.9), (0, 1.2, sz), '#4a3322', 'Wood'))
        for sx in (-2, 2):
            k.append(f.p('Leg', (0.3, 2, 3.6), (sx, 1, 0), '#3a2a1e', 'Wood'))
    for i in range(6):
        k.append(part('Firewood', (1, 4, 1), (OX - 36 + (i % 3) * 1.05, 0.5 + (i // 3) * 0.95, OZ - 26), jitter('#4a3322'), 'Wood',
                      shape='Cylinder', rot=(0, 0, 90)))
    # Lamps along the paths: a few still work, one flickers, some are dead.
    for x, z, on, fl in ((0, -40, True, False), (-24, -20, True, True), (24, -20, False, False), (-24, 22, True, False),
                         (22, 26, True, True), (32, 0, False, False), (-34, 0, True, False), (4, 30, True, False)):
        k.extend(lamp_post(OX + x, OZ + z, '#bcd7ff' if on else '#555', on=on, flicker=fl, rng=22, brightness=1.4))
    # Camp sign at the entrance.
    for sx in (-6, 6):
        k.append(part('SignPost', (0.6, 7, 0.6), (OX + sx, 3.5, OZ - 84), '#3e2d20', 'Wood'))
    k.append(part('Sign', (13, 2.6, 0.4), (OX, 6.2, OZ - 84), '#4a3524', 'Wood'))
    # Text3D shows from both sides (mirrored on the back), so each face gets its own copy.
    k.append(text3d('SignText', '$camp_sign', (OX, 6.2, OZ - 83.7), '#e8d9b0', 48, font='Black'))
    k.append(text3d('SignText', '$camp_sign', (OX, 6.2, OZ - 84.3), '#e8d9b0', 48, rot=(0, 180, 0), font='Black'))
    # Fences.
    for (x1, z1, x2, z2) in ((-30, -60, -12, -70), (12, -70, 30, -60), (-60, 20, -60, 34), (70, -28, 80, -10)):
        k.extend(fence(OX + x1, OZ + z1, OX + x2, OZ + z2))
    # Trees: a dense wall at the edge, scattered ones inside where nothing stands.
    busy = [(0, 0, 12), (-46, -42, 11), (48, -40, 11), (-50, 44, 11), (42, 52, 11), (2, 70, 30), (-68, 2, 8), (62, 4, 14),
            (-26, 62, 5), (16, -22, 5), (-20, 16, 5), (24, 22, 5), (-14, -26, 5), (14, -8, 5), (-12, 6, 5), (0, -84, 9)]

    def free(x, z, pad=3):
        for bx, bz, r in busy:
            if math.hypot(x - bx, z - bz) < r + pad:
                return False
        for (x1, z1), (x2, z2) in paths:
            dx, dz = x2 - x1, z2 - z1
            t = max(0, min(1, ((x - x1) * dx + (z - z1) * dz) / (dx * dx + dz * dz)))
            if math.hypot(x - (x1 + dx * t), z - (z1 + dz * t)) < 4.5:
                return False
        return True

    for i in range(120):
        a = R.uniform(0, math.tau)
        r = R.uniform(76, 96)
        x, z = math.cos(a) * r, math.sin(a) * r
        if abs(x) < 8 and z < -70:
            continue
        k.extend(pine(OX + x, OZ + z, R.uniform(12, 18), dark=True))
    placed = 0
    while placed < 42:
        x, z = R.uniform(-74, 74), R.uniform(-74, 74)
        if free(x, z):
            k.extend(pine(OX + x, OZ + z) if R.random() < 0.7 else leafy(OX + x, OZ + z))
            busy.append((x, z, 2))
            placed += 1
    for i in range(34):
        x, z = R.uniform(-80, 80), R.uniform(-80, 80)
        if free(x, z, 1):
            k.append(rock(OX + x, OZ + z) if R.random() < 0.45 else bush(OX + x, OZ + z))
    # Generators, spawns, walls.
    gens = [generator('Gen1', OX - 36, OZ - 30, 35), generator('Gen2', OX + 54, OZ + 14, -80), generator('Gen3', OX + 18, OZ + 50, 180),
            generator('Gen4', OX - 60, OZ + 10, 90), generator('Gen5', OX + 30, OZ - 50, -20)]
    k.append(model('Generators', gens))
    k.append(spawns((OX, OZ - 80), [(OX - 30, OZ + 10), (OX + 30, OZ - 10), (OX - 10, OZ + 32), (OX + 14, OZ + 34),
                                     (OX - 40, OZ + 28), (OX + 38, OZ + 30), (OX - 6, OZ + 12)]))
    k.append(walls(OX, OZ, 98))
    return model('Camp', k)


# --------------------------------------------------------------------------------------
# Map 2: Old Factory, a closed plant with a warehouse, a container yard and a water tower
# --------------------------------------------------------------------------------------

def container(x, y, z, yaw, color):
    f = Frame(x, y, z, yaw)
    k = [f.p('Container', (5.4, 5.6, 12), (0, 2.8, 0), jitter(color, 0.08), 'Metal')]
    for i in range(-5, 6, 2):
        k.append(f.p('Rib', (5.5, 5.2, 0.2), (0, 2.8, i), jitter(color, 0.12), 'Metal', collide=False, shadow=False))
    k.append(f.p('Doors', (5.5, 5.4, 0.15), (0, 2.8, 6.02), jitter(color, 0.15), 'Metal', collide=False))
    return k


def factory():
    OX, OZ = 0, 600
    k = []
    k.append(part('Ground', (190, 1, 190), (OX, -0.5, OZ), '#1d1f21', 'Concrete'))
    # Painted lines and cracks.
    for i in range(8):
        k.append(part('Line', (0.3, 0.06, 6), (OX + 30 + i * 4, 0.03, OZ + 60), '#9a8a3a', 'SmoothPlastic', shadow=False, collide=False))
    for i in range(18):
        x, z = R.uniform(-85, 85), R.uniform(-85, 85)
        k.append(part('Crack', (R.uniform(0.2, 0.5), 0.05, R.uniform(4, 12)), (OX + x, 0.03, OZ + z), '#111213', 'Concrete',
                      rot=(0, R.uniform(0, 180), 0), shadow=False, collide=False))
    for i in range(10):
        x, z = R.uniform(-80, 80), R.uniform(-80, 80)
        s = R.uniform(3, 8)
        k.append(part('Puddle', (s, 0.06, s * 0.7), (OX + x, 0.04, OZ + z), '#0e1a22', 'Glass', shape='Cylinder', transp=0.2,
                      shadow=False, collide=False))
    # The warehouse: walls with doorways, a broken roof, machines, a catwalk.
    WX, WZ = OX - 8, OZ - 28
    W, D, H = 64, 40, 16
    wall = '#3f3a36'
    wk = [part('Floor', (W, 0.2, D), (WX, 0.1, WZ), '#2a2a2c', 'Concrete', shadow=False)]
    wk += [
        part('Wall', (W, H, 1), (WX, H / 2, WZ - D / 2), wall, 'Brick'),
        part('Wall', ((W - 14) / 2, H, 1), (WX - (W / 2 - (W - 14) / 4), H / 2, WZ + D / 2), wall, 'Brick'),
        part('Wall', ((W - 14) / 2, H, 1), (WX + (W / 2 - (W - 14) / 4), H / 2, WZ + D / 2), wall, 'Brick'),
        part('Wall', (14, 6, 1), (WX, H - 3, WZ + D / 2), wall, 'Brick'),
        part('Wall', (1, H, 16), (WX - W / 2, H / 2, WZ - 12), wall, 'Brick'),
        part('Wall', (1, H, 16), (WX - W / 2, H / 2, WZ + 12), wall, 'Brick'),
        part('Wall', (1, H - 6, 8), (WX - W / 2, H / 2 + 3, WZ), wall, 'Brick'),
        part('Wall', (1, H, D), (WX + W / 2, H / 2, WZ), wall, 'Brick'),
    ]
    # Roof strips with gaps where it caved in (moonlight gets in).
    for i, (zc, w) in enumerate(((-15, 10), (-2, 8), (12, 12))):
        wk.append(part('Roof', (W, 0.8, w), (WX, H + 0.4, WZ + zc), '#2b2a2d', 'Metal'))
    for i in range(-2, 3):
        wk.append(part('Beam', (0.6, 0.8, D), (WX + i * 14, H - 0.4, WZ), '#4a4d55', 'Metal', collide=False))
    for i in (-18, 0, 18):
        for zc in (-10, 10):
            wk.append(part('Pillar', (1.2, H, 1.2), (WX + i, H / 2, WZ + zc), '#4a4d55', 'Metal'))
    # Machines and a conveyor.
    for i, (x, z, sx, sy, sz) in enumerate(((-20, -8, 7, 5, 5), (-4, -12, 5, 7, 4), (12, -10, 8, 4.5, 6), (22, 6, 5, 6, 5))):
        wk.append(part('Machine', (sx, sy, sz), (WX + x, sy / 2, WZ + z), jitter('#5a5f58', 0.1), 'Metal'))
        wk.append(part('MachineTop', (sx * 0.6, 1.2, sz * 0.6), (WX + x, sy + 0.6, WZ + z), jitter('#6b4a2e', 0.1), 'Metal'))
        wk.append(part('Warning', (sx + 0.02, 0.4, sz + 0.02), (WX + x, sy * 0.3, WZ + z), '#b8901c', 'SmoothPlastic', collide=False, shadow=False))
    wk.append(part('Conveyor', (30, 1, 3), (WX - 4, 2.2, WZ + 6), '#2f3136', 'Metal'))
    for i in range(10):
        wk.append(part('Roller', (0.5, 3.1, 0.5), (WX - 18 + i * 3, 2.75, WZ + 6), '#6a6d75', 'Metal', shape='Cylinder', rot=(90, 0, 0), collide=False))
    for i in range(6):
        wk.append(part('ConvLeg', (0.4, 1.8, 2.6), (WX - 17 + i * 5.5, 0.9, WZ + 6), '#26282d', 'Metal'))
    for i in range(4):
        wk.append(crate(WX - 12 + i * 2.4, 2.7, WZ + 6))
    # Catwalk along the back wall, stairs up.
    wk.append(part('Catwalk', (46, 0.4, 3.5), (WX + 2, 8, WZ - D / 2 + 2.4), '#3a3d44', 'Metal'))
    wk.append(part('CatRail', (46, 1.1, 0.2), (WX + 2, 8.8, WZ - D / 2 + 4.1), '#56595f', 'Metal'))
    wk.append(part('Stairs', (3.5, 8, 12), (WX - 23, 4, WZ - D / 2 + 9.5), '#3a3d44', 'Metal', shape='Wedge', rot=(0, 0, 0)))
    # Hanging lamps, two broken.
    for i, (x, z, on, fl) in enumerate(((-16, -6, True, True), (4, 4, True, False), (18, -6, False, False), (-4, -14, True, True))):
        wk.append(part('Chain', (0.12, 4, 0.12), (WX + x, H - 2, WZ + z), '#2a2a2a', 'Metal', collide=False, shadow=False))
        wk.append(part('Lamp', (1.6, 0.5, 1.6), (WX + x, H - 4.2, WZ + z), '#ffd28a' if on else '#3a3a3a', 'Neon' if on else 'Metal',
                       shape='Cylinder', collide=False, shadow=False,
                       kids=[light('#ffc27a', 1.8, 24, 'Flicker' if fl else 'PointLight', offset=(0, -1, 0))] if on else None))
    # Pipes along the outside wall.
    for y in (5, 6.2):
        wk.append(part('Pipe', (0.8, W, 0.8), (WX, y, WZ + D / 2 + 1.2), '#5a4a3a', 'Metal', shape='Cylinder', rot=(0, 0, 90)))
    k.append(model('Warehouse', wk))
    # Container yard: rows with alleys, some stacked.
    colors = ['#7a2e22', '#1f4e6b', '#2f5a3a', '#9a5a1c', '#5a2f5f', '#6b6b6b']
    for row, z in enumerate((30, 50)):
        for i in range(5):
            x = 22 + i * 7
            k.extend(container(OX + x, 0, OZ + z, 0, colors[(row * 5 + i) % len(colors)]))
            if (i + row) % 3 == 0:
                k.extend(container(OX + x, 5.6, OZ + z, 0, colors[(row * 5 + i + 2) % len(colors)]))
    for i, (x, z, yaw) in enumerate(((70, 10, 90), (70, 24, 90), (-30, 55, 30))):
        k.extend(container(OX + x, 0, OZ + z, yaw, colors[i % len(colors)]))
    # Water tower you can climb.
    tx, tz = OX - 62, OZ + 20
    for sx in (-4, 4):
        for sz in (-4, 4):
            k.append(part('TowerLeg', (0.8, 16, 0.8), (tx + sx, 8, tz + sz), '#3a3d44', 'Metal'))
    k.append(part('Brace', (0.4, 0.4, 11), (tx - 4, 8, tz), '#3a3d44', 'Metal', rot=(45, 0, 0), collide=False))
    k.append(part('Brace', (0.4, 0.4, 11), (tx + 4, 8, tz), '#3a3d44', 'Metal', rot=(-45, 0, 0), collide=False))
    k.append(part('Deck', (11, 0.5, 11), (tx, 16.2, tz), '#2f3136', 'Metal'))
    k.append(part('Tank', (10, 8, 10), (tx, 20.6, tz), '#5b5347', 'Metal', shape='Cylinder'))
    k.append(part('TankTop', (10.6, 1.6, 10.6), (tx, 25.2, tz), '#4a443b', 'Metal', shape='Cylinder'))
    k.append(part('Ladder', (1.6, 16, 0.3), (tx, 8, tz + 4.6), '#6a6d75', 'Metal', climb=True))
    k.append(text3d('TankText', '$tank_text', (tx, 21, tz + 5.1), '#c9b98a', 40, font='Black'))
    # The smokestack with a red warning light.
    sx_, sz_ = OX + 62, OZ - 62
    k.append(part('Stack', (6, 44, 6), (sx_, 22, sz_), '#5a3a30', 'Brick', shape='Cylinder'))
    k.append(part('StackRing', (6.6, 1, 6.6), (sx_, 36, sz_), '#3a3d44', 'Metal', shape='Cylinder'))
    k.append(part('StackLight', (0.8, 0.8, 0.8), (sx_, 44.6, sz_), '#ff2d3d', 'Neon', shape='Ball', collide=False, shadow=False,
                  kids=[light('#ff2d3d', 3, 40, 'Flicker')]))
    # A small office with lit windows.
    f = Frame(OX + 50, 0, OZ - 18, -90)
    k.append(model('Office', [
        f.p('Box', (16, 8, 12), (0, 4, 0), '#4d4a52', 'Concrete'),
        f.p('Roof', (17, 0.6, 13), (0, 8.3, 0), '#2b2a2d', 'Metal'),
        f.p('Window', (3, 2, 0.1), (-4, 5, 6.02), '#ffcf7a', 'Neon', collide=False, shadow=False, kids=[light('#ffb86b', 1.4, 16)]),
        f.p('Window', (3, 2, 0.1), (4, 5, 6.02), '#3a3a40', 'Glass', collide=False),
        f.p('Door', (2.4, 4.4, 0.1), (0, 2.2, 6.02), '#2a2a2d', 'Metal', collide=False),
        f.p('Sign', (6, 1.2, 0.2), (0, 7.2, 6.1), '#1f2a3a', 'Metal', collide=False),
    ]))
    k.append(text3d('OfficeSign', '$office_sign', f.at(0, 7.2, 6.3), '#bcd7ff', 30, rot=(0, f.yaw, 0), font='Bold'))
    # Box trucks and a forklift.
    for x, z, yaw, col in ((34, -4, 0, '#7a7a80'), (-36, 48, 90, '#5a2f2a')):
        f = Frame(OX + x, 0, OZ + z, yaw)
        k.append(model('Truck', [
            f.p('Cargo', (5.4, 5.6, 11), (0, 3.6, -1.5), col, 'Metal'),
            f.p('Cab', (5.2, 4.2, 4), (0, 2.9, 6), '#2f3a4a', 'Metal'),
            f.p('Glass', (5.0, 1.6, 0.2), (0, 3.8, 8.05), '#12161c', 'Glass', collide=False),
            f.p('Wheel', (1, 2.2, 2.2), (-2.6, 1.1, 5.5), '#1a1a1c', 'Plastic', shape='Cylinder', rot=(0, 0, 90)),
            f.p('Wheel', (1, 2.2, 2.2), (2.6, 1.1, 5.5), '#1a1a1c', 'Plastic', shape='Cylinder', rot=(0, 0, 90)),
            f.p('Wheel', (1, 2.2, 2.2), (-2.6, 1.1, -4), '#1a1a1c', 'Plastic', shape='Cylinder', rot=(0, 0, 90)),
            f.p('Wheel', (1, 2.2, 2.2), (2.6, 1.1, -4), '#1a1a1c', 'Plastic', shape='Cylinder', rot=(0, 0, 90)),
        ]))
    f = Frame(OX + 14, 0, OZ + 2, 30)
    k.append(model('Forklift', [
        f.p('Body', (3, 2.4, 4), (0, 1.6, 0), '#c9a21c', 'Metal'),
        f.p('Mast', (2.6, 5, 0.3), (0, 2.8, 2.2), '#2a2a2d', 'Metal'),
        f.p('Fork', (0.3, 0.2, 2.4), (-0.8, 0.5, 3.4), '#2a2a2d', 'Metal'),
        f.p('Fork', (0.3, 0.2, 2.4), (0.8, 0.5, 3.4), '#2a2a2d', 'Metal'),
        f.p('Cage', (2.8, 0.2, 2.6), (0, 4.4, -0.3), '#2a2a2d', 'Metal'),
    ]))
    # Barrels, crates, pallets.
    for i in range(22):
        x, z = R.uniform(-70, 70), R.uniform(-70, 70)
        if -45 < x < 30 and -52 < z < -4:
            continue
        if 16 < x < 58 and 20 < z < 60:
            continue
        if R.random() < 0.55:
            for j in range(R.randint(1, 3)):
                k.append(barrel(OX + x + j * 1.5, OZ + z + R.uniform(-0.4, 0.4), R.choice(['#6a2a24', '#1f3f5a', '#3a4a2a'])))
        else:
            for j in range(R.randint(1, 3)):
                k.append(crate(OX + x + j * 2.3, 0, OZ + z, yaw=R.uniform(-15, 15)))
    # Street lamps: sodium orange, some dead, some flickering.
    for x, z, on, fl in ((-20, 10, True, False), (10, 20, True, True), (40, -30, True, False), (-50, -50, False, False),
                         (-50, 0, True, False), (0, 70, True, True), (60, 50, True, False), (-70, 60, False, False), (74, -2, True, False)):
        k.extend(lamp_post(OX + x, OZ + z, '#ffb35a' if on else '#555', on=on, flicker=fl, h=9, rng=26, brightness=1.5))
    # Perimeter fence with a gate gap in the south.
    for (x1, z1, x2, z2) in ((-88, -88, 88, -88), (88, -88, 88, 88), (88, 88, 12, 88), (-12, 88, -88, 88), (-88, 88, -88, -88)):
        dx, dz = x2 - x1, z2 - z1
        L = math.hypot(dx, dz)
        yaw = math.degrees(math.atan2(dx, dz))
        k.append(part('Mesh', (0.1, 5, L), (OX + (x1 + x2) / 2, 2.5, OZ + (z1 + z2) / 2), '#6a6d75', 'Glass', rot=(0, yaw, 0),
                      transp=0.72, shadow=False))
        n = int(L / 8)
        for i in range(n + 1):
            t = i / n
            k.append(part('FencePost', (0.3, 5.6, 0.3), (OX + x1 + dx * t, 2.8, OZ + z1 + dz * t), '#4a4d55', 'Metal', shape='Cylinder'))
    for sx in (-12, 12):
        k.append(part('GatePost', (1, 7, 1), (OX + sx, 3.5, OZ + 88), '#3a3d44', 'Metal'))
    k.append(part('GateSign', (22, 2, 0.3), (OX, 7.4, OZ + 88), '#3a1f1f', 'Metal'))
    k.append(text3d('GateText', '$factory_sign', (OX, 7.4, OZ + 88.3), '#e8c9a0', 44, font='Black'))
    k.append(text3d('GateText', '$factory_sign', (OX, 7.4, OZ + 87.7), '#e8c9a0', 44, rot=(0, 180, 0), font='Black'))
    # Generators, spawns, walls.
    gens = [generator('Gen1', WX - 18, WZ + 12, 0), generator('Gen2', OX + 40, OZ + 40, 90), generator('Gen3', OX - 54, OZ + 20, 270),
            generator('Gen4', OX + 42, OZ - 24, 90), generator('Gen5', OX - 8, OZ + 70, 180)]
    k.append(model('Generators', gens))
    k.append(spawns((OX - 76, OZ - 76), [(OX + 10, OZ + 50), (OX - 20, OZ + 30), (OX + 60, OZ + 70), (OX - 60, OZ + 60),
                                         (OX + 20, OZ - 60), (OX + 70, OZ - 30), (OX - 30, OZ + 70)]))
    k.append(walls(OX, OZ, 88))
    return model('Factory', k)


# --------------------------------------------------------------------------------------
# Everything else: services, values, remotes, UI, looks, the spike
# --------------------------------------------------------------------------------------

def appearance(name, colors, face, acc):
    keys = ['HeadColor', 'TorsoColor', 'LeftArmColor', 'RightArmColor', 'LeftLegColor', 'RightLegColor']
    parts = ['head', 'torso', 'arm_l', 'arm_r', 'leg_l', 'leg_r']
    p = {k: c3(colors[pt]) for k, pt in zip(keys, parts)}
    p['Face'] = face
    p['Accessories'] = ','.join(acc)
    return {'c': 'Appearance', 'n': name, 'p': p}


def main():
    # nrz's look as saved when this file was built (the game fetches the live one when it starts).
    look_path = os.path.join(here, 'nrz_look.json')
    if os.path.exists(look_path):
        with open(look_path, encoding='utf-8') as f:
            nrz = json.load(f)
    else:
        nrz = {'colors': {'head': '#f5f1ec', 'torso': '#1c1a22', 'arm_l': '#f5f1ec', 'arm_r': '#f5f1ec', 'leg_l': '#1c1a22', 'leg_r': '#1c1a22'},
               'face': ':|', 'accessories': []}
    melly = {'head': '#f5f1ec', 'torso': '#baa4e2', 'arm_l': '#f5f1ec', 'arm_r': '#f5f1ec', 'leg_l': '#302d38', 'leg_r': '#302d38'}

    lob = lobby()
    # The showcase rig wears the saved nrz look until the live one loads.
    for node in lob['k']:
        if node.get('n') == 'KillerRig':
            node['p'].update({k: v for k, v in appearance('x', nrz['colors'], nrz['face'], nrz['accessories'])['p'].items()})

    sounds = ['MusicLobby', 'MusicCalm', 'MusicChase', 'SfxGenDone', 'SfxGenFail', 'SfxPunch', 'SfxSpikeThrow', 'SfxSpikeHit',
              'SfxRoundStart', 'SfxSurvivorsWin', 'SfxKillerWin', 'SfxTick', 'RenderKiller', 'RenderSurvivor']
    ids_path = os.path.join(here, 'asset_ids.json')
    ids = {}
    if os.path.exists(ids_path):
        with open(ids_path, encoding='utf-8') as f:
            ids = json.load(f)
    assets = {'c': 'Folder', 'n': 'Assets', 'k': [{'c': 'StringValue', 'n': n, 'p': {'Value': ids.get(n, '')}} for n in sounds]}

    def val(cls, name, v):
        return {'c': cls, 'n': name, 'p': {'Value': v}}

    state = {'c': 'Folder', 'n': 'State', 'k': [
        val('StringValue', 'Phase', 'Lobby'), val('NumberValue', 'Countdown', -1), val('NumberValue', 'Waiting', 0),
        val('StringValue', 'Map', ''), val('NumberValue', 'KillerId', 0), val('NumberValue', 'GensDone', 0),
        val('NumberValue', 'GensTotal', 5), val('NumberValue', 'TimeLeft', 0), val('NumberValue', 'Release', 0),
        val('NumberValue', 'Alive', 0),
    ]}
    remotes = {'c': 'Folder', 'n': 'Remotes', 'k': [{'c': 'RemoteEvent', 'n': n} for n in
                                                     ['Action', 'GenStart', 'GenSolve', 'GenFail', 'Notify', 'Sfx', 'Result', 'Hit']]}
    spike = part('Spike', (0.35, 0.35, 2.6), (0, -500, 0), '#ff3b4f', 'Neon', collide=False, shadow=False, touch=False,
                 kids=[light('#ff3b4f', 1.8, 10)])

    tree = {'c': 'DataModel', 'k': [
        {'c': 'Workspace', 'n': 'Workspace', 'p': {'Gravity': 22, 'FallHeight': -40}, 'k': [lob]},
        {'c': 'Lighting', 'n': 'Lighting', 'p': {'ClockTime': 19.2, 'Brightness': 0.75, 'Ambient': c3('#5a4a6e'),
                                                  'SkyTop': c3('#2a2f6b'), 'SkyHorizon': c3('#f29a7a'), 'FogEnabled': True,
                                                  'FogColor': c3('#3b2f4f'), 'FogEnd': 260, 'Shadows': True},
         'k': [{'c': 'Sky', 'n': 'Sky', 'p': {'Preset': 'Sunset', 'StarsVisible': True}}]},
        {'c': 'ReplicatedStorage', 'n': 'ReplicatedStorage', 'k': [
            {'c': 'ModuleScript', 'n': 'Shared', 'p': {'Source': src('Shared.luau')}}, assets, state, remotes]},
        {'c': 'ServerScriptService', 'n': 'ServerScriptService', 'k': [
            {'c': 'Script', 'n': 'Game', 'p': {'Source': src('Server.luau')}}]},
        {'c': 'ServerStorage', 'n': 'ServerStorage', 'k': [
            {'c': 'Folder', 'n': 'Maps', 'k': [camp(), factory()]},
            {'c': 'Folder', 'n': 'Looks', 'k': [appearance('Killer', nrz['colors'], nrz['face'], nrz['accessories']),
                                                 appearance('Survivor', melly, ':D', [])]},
            spike, censor()]},
        {'c': 'StarterGui', 'n': 'StarterGui', 'k': [
            {'c': 'ScreenGui', 'n': 'Hud', 'k': [{'c': 'LocalScript', 'n': 'Client', 'p': {'Source': src('Client.luau')}}]}]},
        {'c': 'StarterPlayer', 'n': 'StarterPlayer', 'p': {
            'WalkSpeed': 5, 'SprintSpeed': 7, 'MaxStamina': 100, 'RespawnTime': 4, 'EmotesEnabled': True, 'CameraMaxZoom': 16,
            'AntiCheat': True},
         'k': [{'c': 'StarterPlayerScripts', 'n': 'StarterPlayerScripts', 'k': [
             {'c': 'LocalScript', 'n': 'Ambience', 'p': {'Source': src('Ambience.luau')}}]}]},
    ]}
    with open(os.path.join(here, 'strings.json'), encoding='utf-8') as f:
        strings = json.load(f)
    melt = {
        'format': 'melt',
        'version': 1,
        'meta': {
            'name': 'Meltopia',
            'description': 'One of you is the killer, everyone else must survive the night. Fix the generators to make the night shorter, '
                           'hide, run and don\'t get caught. Two maps, a new killer every round.',
            'i18n': {'name': {'ru': 'Meltopia'},
                     'description': {'ru': 'Один из вас убийца, остальные должны пережить ночь. Чините генераторы, чтобы ночь кончилась '
                                           'быстрее, прячьтесь, бегите и не попадайтесь. Две карты, каждый раунд новый убийца.'}},
        },
        'strings': strings,
        'tree': tree,
    }
    out = os.path.join(here, '..', 'meltopia.melt')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(melt, f, ensure_ascii=False, separators=(',', ':'))
    print(f'wrote {out}: {os.path.getsize(out) // 1024} KB, {COUNT[0]} parts')


if __name__ == '__main__':
    main()
