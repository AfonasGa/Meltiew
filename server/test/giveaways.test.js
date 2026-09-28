import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.js';
import { createGiveaways } from '../src/giveaways.js';

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}

test('giveaway: email and one entry per network, the draw pays the winner', () => {
  const db = openDb(':memory:');
  const add = db.prepare("INSERT INTO users (username, pass_hash, display_name, created_at, last_seen) VALUES (?, 'x', ?, 0, 0)");
  const ids = ['owner', 'a', 'b', 'c'].map((n) => Number(add.run(n, n).lastInsertRowid));
  db.prepare("UPDATE users SET role = 'owner' WHERE id = ?").run(ids[0]);
  db.prepare("UPDATE users SET email = username || '@gmail.com' WHERE username IN ('a', 'b')").run();
  const paid = [];
  let who = null;
  let ip = '1.1.1.1';
  const g = createGiveaways({
    db,
    economy: { change: (uid, cur, n) => paid.push([uid, cur, n]) },
    HttpError,
    bad: (c) => new HttpError(400, c),
    cleanText: (s, n) => String(s ?? '').slice(0, n),
    requireAuth: () => ({ user: db.prepare('SELECT * FROM users WHERE id = ?').get(who) }),
    clientIp: () => ip,
  });
  who = ids[0];
  const ends = Date.now() + 120_000;
  g.routes['POST /api/admin/giveaway']({}, { title: 'Test', currency: 'orbs', amount: 500, ends_at: ends });
  who = ids[3];
  assert.throws(() => g.routes['POST /api/giveaway/enter']({}), /giveaway_email/);
  who = ids[1];
  assert.equal(g.routes['POST /api/giveaway/enter']({}).giveaway.entered, true);
  who = ids[2];
  assert.throws(() => g.routes['POST /api/giveaway/enter']({}), /giveaway_ip/);
  ip = '2.2.2.2';
  assert.equal(g.routes['POST /api/giveaway/enter']({}).giveaway.entries, 2);
  g.tick(ends - 1000);
  assert.equal(paid.length, 0);
  g.tick(ends + 1);
  assert.equal(paid.length, 1);
  assert.ok([ids[1], ids[2]].includes(paid[0][0]));
  assert.deepEqual(paid[0].slice(1), ['orbs', 500]);
  const shown = g.routes['GET /api/giveaway']({}).giveaway;
  assert.equal(shown.done, true);
  assert.equal(shown.winner.id, paid[0][0]);
  g.tick(ends + 10_000);
  assert.equal(paid.length, 1, 'drawn once');
});
