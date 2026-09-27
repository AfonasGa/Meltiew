import test from 'node:test';
import assert from 'node:assert/strict';
import { Occluders, eyes, canSee } from '../src/occlusion.js';

const I = [1, 0, 0, 0, 1, 0, 0, 0, 1];
const floor = [0, -1, 0, 500, 1, 500, ...I];
const wall = [0, 5, 0, 1, 5, 20, ...I]; // x = 0, 10 high, z -20..20
const A = [-10, 1, 0];
const B = [10, 1, 0];

test('a wall hides players behind it, open ground and low cover do not', () => {
  const occ = new Occluders([floor, wall]);
  assert.equal(canSee(occ, eyes(occ, A, 14), B), false);
  assert.equal(canSee(occ, eyes(occ, A, 0.5), B), false);
  const open = new Occluders([floor]);
  assert.equal(canSee(open, eyes(open, A, 14), B), true);
  const low = new Occluders([floor, [0, 1, 0, 1, 1.5, 20, ...I]]);
  assert.equal(canSee(low, eyes(low, A, 14), B), true);
});

test('from high above everyone is seen', () => {
  const occ = new Occluders([floor, wall]);
  assert.equal(canSee(occ, eyes(occ, [-10, 30, 0], 14), B), true);
});

test('the camera is pulled in by walls, not placed inside or past them', () => {
  // Standing right by the wall: the camera can't swing over to the other side.
  const occ = new Occluders([floor, [0, 10, 0, 1, 10, 20, ...I]]);
  assert.equal(canSee(occ, eyes(occ, [-2, 1, 0], 14), [6, 1, 0]), false);
});
