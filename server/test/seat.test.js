import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PlaceVM } from '../src/studio/vm.js';
import { templatePlace } from '../src/studio/places.js';

test('one player per seat: the second one is told to stand up', async () => {
  const melt = templatePlace('Seats');
  melt.tree.k.find((n) => n.c === 'Workspace').k.push({ c: 'Seat', n: 'Chair', p: { Position: { $v3: [0, 1, 0] } } });
  const vm = await PlaceVM.create();
  vm.init({ role: 'server', place: melt, seed: 1 });
  vm.start();
  for (const u of [1, 2]) vm.dispatch([{ e: 'player_add', userId: u, name: 'p' + u, display: 'p' + u, lang: 'en' }]);
  vm.step(0.05);
  const seat = vm.snapshot().find((o) => o.n === 'Chair').id;
  const first = vm.dispatch([{ e: 'seat', userId: 1, id: seat }]);
  assert.ok(first.some((o) => o.o === 'set' && o.id === seat && o.k === 'Occupant'));
  const second = vm.dispatch([{ e: 'seat', userId: 2, id: seat }]);
  assert.ok(second.some((o) => o.o === 'sit' && o.to === 2 && o.id === ''));
  assert.ok(!second.some((o) => o.o === 'set' && o.id === seat && o.k === 'Occupant'));
  // Once the first one gets up, the seat is free again.
  vm.dispatch([{ e: 'seat', userId: 1 }]);
  const again = vm.dispatch([{ e: 'seat', userId: 2, id: seat }]);
  assert.ok(again.some((o) => o.o === 'set' && o.id === seat && o.k === 'Occupant'));
  vm.close();
});
