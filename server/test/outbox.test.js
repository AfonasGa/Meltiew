import test from 'node:test';
import assert from 'node:assert/strict';
import { splitOps, splitSnapshot, createOutbox, CHUNK_BYTES, OLD_APP_BUFFER } from '../src/outbox.js';

const part = (id, parent) => ({ o: 'new', c: 'Part', id: String(id), parent: String(parent), n: 'P', p: { Name: 'x'.repeat(200) } });

test('big replication batches are cut in order, each piece under the chunk size', () => {
  const ops = Array.from({ length: 2000 }, (_, i) => part(i + 10, 1));
  const pieces = splitOps(ops);
  assert.ok(pieces.length > 1);
  assert.deepEqual(pieces.flat(), ops);
  for (const p of pieces) assert.ok(Buffer.byteLength(JSON.stringify(p)) <= CHUNK_BYTES);
  assert.deepEqual(splitOps(ops.slice(0, 3)), [ops.slice(0, 3)]);
});

test('a snapshot too big for the welcome sends Workspace contents after it', () => {
  const snap = [
    { o: 'new', c: 'Workspace', id: '1', parent: '0' },
    ...Array.from({ length: 1000 }, (_, i) => part(i + 100, 1)),
    { o: 'new', c: 'ReplicatedStorage', id: '2', parent: '0' },
    { o: 'new', c: 'Folder', id: '3', parent: '2' },
  ];
  const { head, rest } = splitSnapshot(snap, 64 * 1024);
  assert.deepEqual(head.map((o) => o.id), ['1', '2', '3']);
  assert.equal(rest.length, 1000);
  assert.deepEqual(splitSnapshot(snap, 1 << 24), { head: snap, rest: [] });
});

test('old apps never get more than their buffer at once; the close waits for the queue', async () => {
  const got = [];
  const ws = { readyState: 1, send: (d) => got.push({ at: Date.now(), n: Buffer.byteLength(d) }), close: () => (ws.readyState = 3) };
  const out = createOutbox(ws, OLD_APP_BUFFER);
  for (const p of splitOps(Array.from({ length: 4000 }, (_, i) => part(i, 1)))) out.send(JSON.stringify({ t: 'r', o: p }));
  out.close(4001, 'kick');
  assert.equal(ws.readyState, 1);
  while (ws.readyState === 1) await new Promise((r) => setTimeout(r, 20));
  const total = got.reduce((a, g) => a + g.n, 0);
  assert.ok(total > 900 * 1024);
  // Any 50 ms window (a slow frame) stays well under the 256 KB buffer.
  for (const g of got) {
    const w = got.filter((h) => h.at >= g.at && h.at < g.at + 50).reduce((a, h) => a + h.n, 0);
    assert.ok(w < OLD_APP_BUFFER * 0.9, `window ${w}`);
  }
});

test('big-buffer apps get everything right away', () => {
  const got = [];
  const ws = { readyState: 1, send: (d) => got.push(d), close() {} };
  const out = createOutbox(ws, 1 << 24);
  for (let i = 0; i < 20; i++) out.send('x'.repeat(100 * 1024));
  assert.equal(got.length, 20);
});
