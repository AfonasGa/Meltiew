// Giveaways: the platform owner offers orbs or pieces until a set time; anyone with a
// confirmed email can enter (one account per network), and when time's up one entry
// wins at random. Shown on top of the site and the app while it runs, and for a day
// after with the winner.
import crypto from 'node:crypto';

const SHOW_AFTER_MS = 24 * 3600 * 1000;
const MAX_AMOUNT = 1_000_000;

export function createGiveaways({ db, economy, HttpError, bad, cleanText, requireAuth, clientIp, log = () => {} }) {
  db.exec(`CREATE TABLE IF NOT EXISTS giveaways (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    title      TEXT NOT NULL,
    currency   TEXT NOT NULL,
    amount     INTEGER NOT NULL,
    ends_at    INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    winner_id  INTEGER,
    done       INTEGER NOT NULL DEFAULT 0,
    cancelled  INTEGER NOT NULL DEFAULT 0
  )`);
  db.exec(`CREATE TABLE IF NOT EXISTS giveaway_entries (
    giveaway_id INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    ip          TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    PRIMARY KEY (giveaway_id, user_id),
    UNIQUE (giveaway_id, ip)
  )`);
  const q = {
    current: db.prepare('SELECT * FROM giveaways WHERE cancelled = 0 AND (done = 0 OR ends_at > ?) ORDER BY id DESC LIMIT 1'),
    active: db.prepare('SELECT * FROM giveaways WHERE cancelled = 0 AND done = 0 ORDER BY id DESC LIMIT 1'),
    due: db.prepare('SELECT * FROM giveaways WHERE cancelled = 0 AND done = 0 AND ends_at <= ?'),
    insert: db.prepare('INSERT INTO giveaways (title, currency, amount, ends_at, created_at) VALUES (?, ?, ?, ?, ?)'),
    cancel: db.prepare('UPDATE giveaways SET cancelled = 1 WHERE id = ?'),
    finish: db.prepare('UPDATE giveaways SET done = 1, winner_id = ? WHERE id = ?'),
    count: db.prepare('SELECT COUNT(*) AS n FROM giveaway_entries WHERE giveaway_id = ?'),
    entered: db.prepare('SELECT 1 FROM giveaway_entries WHERE giveaway_id = ? AND user_id = ?'),
    byIp: db.prepare('SELECT 1 FROM giveaway_entries WHERE giveaway_id = ? AND ip = ?'),
    enter: db.prepare('INSERT INTO giveaway_entries (giveaway_id, user_id, ip, created_at) VALUES (?, ?, ?, ?)'),
    // Entries still eligible at the draw: not banned since.
    pool: db.prepare('SELECT e.user_id FROM giveaway_entries e JOIN users u ON u.id = e.user_id WHERE e.giveaway_id = ? AND u.banned = 0'),
    user: db.prepare('SELECT id, username, display_name FROM users WHERE id = ?'),
  };

  function view(g, userId) {
    if (!g) return null;
    const winner = g.winner_id ? q.user.get(g.winner_id) : null;
    return {
      id: g.id,
      title: g.title,
      currency: g.currency,
      amount: g.amount,
      ends_at: g.ends_at,
      done: !!g.done,
      entries: q.count.get(g.id).n,
      entered: userId ? !!q.entered.get(g.id, userId) : false,
      winner: winner ? { id: winner.id, username: winner.username, display_name: winner.display_name } : null,
    };
  }

  // The one running now, or the last one for a day after it ended (with its winner).
  function current() {
    const g = q.active.get() || q.current.get(Date.now() - SHOW_AFTER_MS);
    if (g && g.done && Date.now() - g.ends_at > SHOW_AFTER_MS) return null;
    return g;
  }

  /** Draws the ones whose time is up. Called every few seconds. */
  function tick(now = Date.now()) {
    for (const g of q.due.all(now)) {
      const pool = q.pool.all(g.id);
      const winner = pool.length ? pool[crypto.randomInt(pool.length)].user_id : null;
      db.exec('BEGIN');
      try {
        if (winner) economy.change(winner, g.currency, g.amount, 'giveaway', String(g.id));
        q.finish.run(winner, g.id);
        db.exec('COMMIT');
      } catch (err) {
        db.exec('ROLLBACK');
        throw err;
      }
      log(`giveaway ${g.id} "${g.title}": ${pool.length} entries, winner ${winner ?? 'none'}`);
    }
  }

  function owner(req) {
    const auth = requireAuth(req);
    if (auth.user.role !== 'owner') throw new HttpError(403, 'forbidden');
    return auth;
  }

  const routes = {
    'GET /api/giveaway': (req) => {
      let userId = 0;
      try {
        userId = requireAuth(req).user.id;
      } catch {
        // signed out: still sees it
      }
      return { giveaway: view(current(), userId) };
    },

    'POST /api/giveaway/enter': (req) => {
      const { user } = requireAuth(req);
      const g = q.active.get();
      if (!g || g.ends_at <= Date.now()) throw new HttpError(404, 'giveaway_over');
      if (!user.email) throw new HttpError(403, 'giveaway_email');
      if (q.entered.get(g.id, user.id)) return { giveaway: view(g, user.id) };
      const ip = clientIp(req);
      if (q.byIp.get(g.id, ip)) throw new HttpError(409, 'giveaway_ip');
      q.enter.run(g.id, user.id, ip, Date.now());
      return { giveaway: view(g, user.id) };
    },

    // The owner's admin panel: start one (a new one replaces a running one), or stop it.
    'POST /api/admin/giveaway': (req, body) => {
      owner(req);
      const title = cleanText(body.title, 60);
      const currency = body.currency === 'pieces' ? 'pieces' : 'orbs';
      const amount = Math.trunc(Number(body.amount));
      const endsAt = Math.trunc(Number(body.ends_at));
      if (title.length < 2) throw bad('bad_name');
      if (!(amount > 0 && amount <= MAX_AMOUNT)) throw bad('bad_amount');
      if (!(endsAt > Date.now() + 60_000 && endsAt < Date.now() + 90 * 86_400_000)) throw bad('bad_time');
      const running = q.active.get();
      if (running) q.cancel.run(running.id);
      const id = Number(q.insert.run(title, currency, amount, endsAt, Date.now()).lastInsertRowid);
      log(`giveaway ${id} "${title}": ${amount} ${currency} until ${new Date(endsAt).toISOString()}`);
      return { giveaway: view(q.active.get(), 0) };
    },

    'DELETE /api/admin/giveaway': (req) => {
      owner(req);
      const running = q.active.get();
      if (running) q.cancel.run(running.id);
      return { ok: true };
    },
  };

  return { routes, tick };
}
