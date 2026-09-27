import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PlaceVM } from '../src/studio/vm.js';
import { templatePlace } from '../src/studio/places.js';

test('ProximityPrompt: Triggered fires for a player close by, not from across the map', async () => {
  const melt = templatePlace('Prompts');
  melt.tree.k.find((n) => n.c === 'Workspace').k.push({
    c: 'Part', n: 'Door', p: { Position: { $v3: [0, 2, 0] }, Anchored: true },
    k: [{ c: 'ProximityPrompt', n: 'Open', p: { ActionText: 'Open', MaxActivationDistance: 8 } }],
  });
  melt.tree.k.find((n) => n.c === 'ServerScriptService').k[0].p.Source =
    'workspace.Door.Open.Triggered:Connect(function(p) print("opened by", p.Name) end)';
  const vm = await PlaceVM.create();
  vm.init({ role: 'server', place: melt, seed: 1 });
  vm.start();
  vm.dispatch([{ e: 'player_add', userId: 1, name: 'a', display: 'a', lang: 'en' }]);
  vm.step(0.05);
  const id = vm.snapshot().find((o) => o.n === 'Open').id;
  const printed = (ops) => ops.filter((o) => o.o === 'print').map((o) => o.msg);
  vm.dispatch([{ e: 'pos', userId: 1, p: { $v3: [60, 1, 0] } }]);
  assert.deepEqual(printed(vm.dispatch([{ e: 'prompt', userId: 1, id }])), []);
  vm.dispatch([{ e: 'pos', userId: 1, p: { $v3: [3, 1, 0] } }]);
  assert.deepEqual(printed(vm.dispatch([{ e: 'prompt', userId: 1, id }])), ['opened by a']);
  vm.close();
});
