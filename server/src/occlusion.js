// Anti-wallhack: players fully hidden behind a place's solid blocks aren't sent to you,
// so an ESP has nothing to draw. Looked at from where your camera can be (around your
// head, pulled in by walls like the real camera), toward a few points of each player.
// Generous on purpose: when in doubt, a player is visible.

const CELL = 16;
const FAR = 1e9;

export class Occluders {
  /** boxes: [x, y, z, hx, hy, hz, m11..m33] from the place (the runtime's __occluders). */
  constructor(boxes) {
    this.boxes = [];
    this.grid = new Map();
    this.stamp = 0;
    for (const b of boxes || []) {
      if (!Array.isArray(b) || b.length < 15 || !b.every(Number.isFinite)) continue;
      const [x, y, z, hx, hy, hz, ...m] = b;
      // World-space extents of the rotated box.
      const ex = Math.abs(m[0]) * hx + Math.abs(m[1]) * hy + Math.abs(m[2]) * hz;
      const ey = Math.abs(m[3]) * hx + Math.abs(m[4]) * hy + Math.abs(m[5]) * hz;
      const ez = Math.abs(m[6]) * hx + Math.abs(m[7]) * hy + Math.abs(m[8]) * hz;
      const box = { c: [x, y, z], h: [hx, hy, hz], m, lo: [x - ex, y - ey, z - ez], hi: [x + ex, y + ey, z + ez], seen: 0 };
      const i = this.boxes.push(box) - 1;
      // Huge parts (a baseplate) would fill thousands of cells: kept apart, always checked.
      const cx0 = Math.floor(box.lo[0] / CELL), cx1 = Math.floor(box.hi[0] / CELL);
      const cz0 = Math.floor(box.lo[2] / CELL), cz1 = Math.floor(box.hi[2] / CELL);
      if ((cx1 - cx0 + 1) * (cz1 - cz0 + 1) > 400) {
        this._add('big', i);
        continue;
      }
      for (let cx = cx0; cx <= cx1; cx++) for (let cz = cz0; cz <= cz1; cz++) this._add(key(cx, cz), i);
    }
  }

  _add(key, i) {
    const list = this.grid.get(key);
    if (list) list.push(i);
    else this.grid.set(key, [i]);
  }

  /**
   * How far along a→b (0..1) the first block in the way starts; 1 if none. `through`:
   * only blocks it passes all the way through count (not one it starts or ends inside).
   */
  hit(a, b, through = true) {
    const stamp = ++this.stamp;
    let best = 1;
    const test = (list) => {
      if (!list) return;
      for (const i of list) {
        const box = this.boxes[i];
        if (box.seen === stamp) continue;
        box.seen = stamp;
        const t = crossing(box, a, b, through);
        if (t < best) best = t;
      }
    };
    test(this.grid.get('big'));
    // Walk the cells the segment crosses on the ground plane, in order.
    let cx = Math.floor(a[0] / CELL), cz = Math.floor(a[2] / CELL);
    const ex = Math.floor(b[0] / CELL), ez = Math.floor(b[2] / CELL);
    const dx = b[0] - a[0], dz = b[2] - a[2];
    const sx = Math.sign(dx), sz = Math.sign(dz);
    const tdx = sx ? CELL / Math.abs(dx) : Infinity, tdz = sz ? CELL / Math.abs(dz) : Infinity;
    let tx = sx ? ((sx > 0 ? (cx + 1) * CELL : cx * CELL) - a[0]) / dx : Infinity;
    let tz = sz ? ((sz > 0 ? (cz + 1) * CELL : cz * CELL) - a[2]) / dz : Infinity;
    for (let n = 0; n < 2000; n++) {
      test(this.grid.get(key(cx, cz)));
      if ((cx === ex && cz === ez) || Math.min(tx, tz) > best) break;
      if (tx < tz) {
        cx += sx;
        tx += tdx;
      } else {
        cz += sz;
        tz += tdz;
      }
    }
    return best;
  }

  blocked(a, b) {
    return this.hit(a, b) < 1;
  }
}

const key = (cx, cz) => (cx + 4096) * 8192 + (cz + 4096);

// Where a→b enters the box (0..1), else FAR. With `through`, only if it comes out the
// other side too: a block the segment starts or ends inside doesn't hide anything.
function crossing(box, a, b, through) {
  if (Math.max(a[0], b[0]) < box.lo[0] || Math.min(a[0], b[0]) > box.hi[0]) return FAR;
  if (Math.max(a[1], b[1]) < box.lo[1] || Math.min(a[1], b[1]) > box.hi[1]) return FAR;
  if (Math.max(a[2], b[2]) < box.lo[2] || Math.min(a[2], b[2]) > box.hi[2]) return FAR;
  const m = box.m;
  const ra = [a[0] - box.c[0], a[1] - box.c[1], a[2] - box.c[2]];
  const rd = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  let t0 = -Infinity, t1 = Infinity;
  for (let j = 0; j < 3; j++) {
    // Local axis j is column j of the rotation.
    const o = m[j] * ra[0] + m[3 + j] * ra[1] + m[6 + j] * ra[2];
    const d = m[j] * rd[0] + m[3 + j] * rd[1] + m[6 + j] * rd[2];
    const h = box.h[j];
    if (Math.abs(d) < 1e-9) {
      if (Math.abs(o) > h) return FAR;
      continue;
    }
    let u0 = (-h - o) / d, u1 = (h - o) / d;
    if (u0 > u1) [u0, u1] = [u1, u0];
    if (u0 > t0) t0 = u0;
    if (u1 < t1) t1 = u1;
    if (t0 > t1) return FAR;
  }
  if (t0 <= 0 || t0 >= 1) return FAR;
  return !through || t1 < 1 ? t0 : FAR;
}

// Directions the camera can sit in from the head: above, and around at a raised angle.
const CAM_DIRS = [[0, 1, 0], [1, 0.6, 0], [-1, 0.6, 0], [0, 0.6, 1], [0, 0.6, -1], [0.7, 0.6, 0.7], [-0.7, 0.6, 0.7], [0.7, 0.6, -0.7], [-0.7, 0.6, -0.7]].map((d) => {
  const l = Math.hypot(...d);
  return d.map((v) => v / l);
});

/** Where a player at `pos` can be looking from: the head and camera spots, pulled in by walls. */
export function eyes(occ, pos, zoom) {
  const head = [pos[0], pos[1] + 1.5, pos[2]];
  const out = [head];
  if (zoom <= 1) return out;
  for (const d of CAM_DIRS) {
    const far = [head[0] + d[0] * zoom, head[1] + d[1] * zoom, head[2] + d[2] * zoom];
    const t = occ.hit(head, far, false);
    const k = Math.max(0, t * zoom - 0.5);
    if (k > 1) out.push([head[0] + d[0] * k, head[1] + d[1] * k, head[2] + d[2] * k]);
  }
  return out;
}

/** Points of a player worth seeing: head, middle, feet, and a bit to each side. */
function targets(pos) {
  const [x, y, z] = pos;
  return [
    [x, y + 1.5, z], [x, y + 0.5, z], [x, y - 0.8, z],
    [x + 1.5, y + 1, z], [x - 1.5, y + 1, z], [x, y + 1, z + 1.5], [x, y + 1, z - 1.5],
  ];
}

export function canSee(occ, fromEyes, pos) {
  const pts = targets(pos);
  for (const e of fromEyes) for (const p of pts) if (!occ.blocked(e, p)) return true;
  return false;
}
