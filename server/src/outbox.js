// What the server sends to one app, in order and at a pace the app can take.
//
// Godot's WebSocketPeer drops a message without a word when it doesn't fit the
// app's receive buffer, and it reads everything that has arrived once per frame.
// Apps up to 1.6.1 have 256 KB: a place's whole map arriving in one tick (or a
// mid-round snapshot) didn't fit, so that player just never got the map.
// Big replication batches are cut into pieces, and for small-buffer apps the
// pieces are spread out so a frame never gets more than the buffer holds.

// Apps that don't say how big their buffer is (1.6.1 and older).
export const OLD_APP_BUFFER = 1 << 18;
// Replication messages are cut into pieces of about this size.
export const CHUNK_BYTES = 48 * 1024;
// Small-buffer apps: at most this much at once, then this many bytes per ms.
const SLOW_BURST = 128 * 1024;
const SLOW_RATE = 2 * 1024;
// A close waits for the queue (a kick message must arrive), but not forever.
const CLOSE_WAIT_MS = 5000;

/** Cuts replication ops into lists whose JSON stays under `max` bytes (a bigger op goes alone). */
export function splitOps(ops, max = CHUNK_BYTES) {
  if (Buffer.byteLength(JSON.stringify(ops)) <= max) return [ops];
  const out = [];
  let cur = [];
  let size = 2;
  for (const op of ops) {
    const n = Buffer.byteLength(JSON.stringify(op)) + 1;
    if (cur.length && size + n > max) {
      out.push(cur);
      cur = [];
      size = 2;
    }
    cur.push(op);
    size += n;
  }
  if (cur.length) out.push(cur);
  return out;
}

/**
 * The world snapshot for a joining app, split so the welcome fits its buffer:
 * everything outside Workspace (scripts, GUI, storage) stays in the welcome, what's
 * in Workspace follows right after as replication. Small snapshots stay whole.
 */
export function splitSnapshot(snapshot, max) {
  if (Buffer.byteLength(JSON.stringify(snapshot)) <= max) return { head: snapshot, rest: [] };
  const inWorld = new Set();
  const head = [];
  const rest = [];
  for (const op of snapshot) {
    if (op.c === 'Workspace') {
      inWorld.add(op.id);
      head.push(op);
    } else if (inWorld.has(op.parent)) {
      inWorld.add(op.id);
      rest.push(op);
    } else {
      head.push(op);
    }
  }
  return { head, rest };
}

export function createOutbox(ws, buffer = OLD_APP_BUFFER) {
  // Apps with a big buffer get everything right away.
  const paced = buffer < 4 * 1024 * 1024;
  const queue = [];
  let tokens = SLOW_BURST;
  let last = Date.now();
  let timer = null;
  let closing = null;

  function refill() {
    const now = Date.now();
    tokens = Math.min(SLOW_BURST, tokens + (now - last) * SLOW_RATE);
    last = now;
  }

  function pump() {
    timer = null;
    if (ws.readyState !== 1) {
      queue.length = 0;
      return;
    }
    refill();
    while (queue.length) {
      const data = queue[0];
      const n = Buffer.byteLength(data);
      // One message bigger than the burst goes alone, when the bucket is full.
      if (paced && n > tokens && tokens < SLOW_BURST) break;
      queue.shift();
      tokens -= n;
      ws.send(data);
    }
    if (queue.length) {
      timer = setTimeout(pump, Math.max(5, Math.ceil((Math.min(Buffer.byteLength(queue[0]), SLOW_BURST) - tokens) / SLOW_RATE)));
      timer.unref?.();
    } else if (closing) {
      ws.close(closing.code, closing.reason);
    }
  }

  return {
    buffer,
    /** Queues an already-encoded message. */
    send(data) {
      if (ws.readyState !== 1 || closing) return;
      if (!paced && !queue.length) {
        ws.send(data);
        return;
      }
      queue.push(data);
      if (!timer) pump();
    },
    /** Closes the socket once what's queued has gone out. */
    close(code, reason) {
      if (closing) return;
      closing = { code, reason };
      if (!queue.length) return ws.close(code, reason);
      setTimeout(() => ws.readyState === 1 && ws.close(code, reason), CLOSE_WAIT_MS).unref?.();
    },
  };
}
