import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tameMarks } from '../src/filter.js';

test('zalgo stacks are cut to three marks, real text is untouched', () => {
  const bomb = 'типа ' + '͓'.repeat(480) + '̏'.repeat(20);
  assert.equal(tameMarks(bomb), 'типа ' + '͓'.repeat(3));
  for (const s of ['Tiếng Việt', 'नमस्ते क्षत्रिय', 'Ёжик, ё-моё', 'é̂']) assert.equal(tameMarks(s), s);
  assert.equal(tameMarks(null), '');
});
