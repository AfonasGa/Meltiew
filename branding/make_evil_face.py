# The "evil" face (>:)), drawn by hand: a rotated >:) doesn't read as angry.
# Run from the repo root: python3 branding/make_evil_face.py
import math
from PIL import Image, ImageDraw

INK = (28, 26, 34, 255)
S = 4  # drawn 4x, scaled down for smooth edges
img = Image.new('RGBA', (256 * S, 256 * S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def dot(x, y, r):
    d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=INK)


def stroke(points, w):
    d.line([(x * S, y * S) for x, y in points], fill=INK, width=w * S, joint='curve')
    for x, y in (points[0], points[-1]):
        dot(x, y, w / 2)


for cx in (94, 162):
    dot(cx, 112, 15)
# Brows slanting down to the middle.
stroke([(58, 66), (112, 88)], 18)
stroke([(198, 66), (144, 88)], 18)
# A wide grin.
grin = [(128 + 70 * math.cos(math.radians(a)), 150 + 38 * math.sin(math.radians(a))) for a in range(15, 166, 5)]
stroke(grin, 18)

img = img.resize((256, 256), Image.LANCZOS)
for path in ('client/assets/faces/evil.png', 'server/public/img/faces/evil.png'):
    img.save(path)
