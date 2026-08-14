import test from 'node:test';
import assert from 'node:assert/strict';

import { passwordStrength, STRENGTH_LEVELS, MIN_LENGTH } from './password.js';

test('an empty box is not scored as anything', () => {
  const r = passwordStrength('');
  assert.equal(r.score, 0);
  assert.equal(r.meetsMinimum, false);
  // No nagging before a single character has been typed.
  assert.deepEqual(r.hints, []);
});

test('anything the server will reject can never look acceptable', () => {
  // The real risk here is a green bar over a password that then fails on
  // submit, so short input is pinned to the bottom whatever else it does.
  for (const pw of ['aB3$', 'x', 'Qw3!rt']) {
    const r = passwordStrength(pw);
    assert.equal(r.meetsMinimum, false, pw);
    assert.equal(r.score, 0, pw);
  }
});

test('length beats character-class theater', () => {
  const scrambled = passwordStrength('P@ssw1rd');       // 8 chars, all 4 classes
  const passphrase = passwordStrength('correct horse battery staple'); // long, plain

  assert.ok(
    passphrase.score > scrambled.score,
    `passphrase (${passphrase.score}) should beat scrambled (${scrambled.score})`
  );
  assert.equal(passphrase.level.key, 'very-strong');
});

test('common passwords are floored regardless of length or variety', () => {
  for (const pw of ['password', 'Password123', 'iloveyou', 'darksky']) {
    const r = passwordStrength(pw);
    assert.equal(r.score, 0, pw);
    assert.match(r.hints[0], /commonly used/i);
  }
});

test('project-flavored guesses are covered too', () => {
  // Someone setting up this exact site is more likely than average to reach
  // for these, so they are in the list.
  assert.equal(passwordStrength('starlight').score, 0);
  assert.equal(passwordStrength('nightsky').score, 0);
});

test('runs and repeats are capped even when long', () => {
  const run = passwordStrength('abcdefghijklmnop');
  assert.ok(run.score <= 2, `sequential run scored ${run.score}`);
  assert.ok(run.hints.some((h) => /runs like/i.test(h)));

  const repeat = passwordStrength('aaabbbcccdddeee');
  assert.ok(repeat.score <= 2, `repeated chars scored ${repeat.score}`);
});

test('a single repeated character is rejected outright', () => {
  const r = passwordStrength('aaaaaaaaaaaa');
  assert.equal(r.score, 0);
  assert.match(r.hints[0], /repeated character/i);
});

test('score always indexes a real level', () => {
  const samples = ['', 'a', 'abcdefgh', 'Tr0ub4dor&3', 'a much longer passphrase here', '!!!!!!!!!!'];
  for (const pw of samples) {
    const r = passwordStrength(pw);
    assert.ok(r.score >= 0 && r.score <= 4, pw);
    assert.equal(r.level, STRENGTH_LEVELS[r.score], pw);
  }
});

test('the minimum matches what the form advertises', () => {
  assert.equal(MIN_LENGTH, 8);
  assert.equal(passwordStrength('a'.repeat(MIN_LENGTH - 1)).meetsMinimum, false);
  assert.equal(passwordStrength('sunset-canyon').meetsMinimum, true);
});
