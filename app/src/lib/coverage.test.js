// Run with: npm test  (from app/)

import test from 'node:test';
import assert from 'node:assert/strict';

import { bandFor, coverageFor, hasOrdinance, COVERAGE_BANDS } from './coverage.js';

const city = (status) => ({ status });

test('only passed and enforced count as having an ordinance', () => {
  assert.equal(hasOrdinance(city('not_started')), false);
  assert.equal(hasOrdinance(city('contacted')), false);
  assert.equal(hasOrdinance(city('meeting_scheduled')), false);
  // A draft is not policy — counting it would overstate real progress.
  assert.equal(hasOrdinance(city('ordinance_drafted')), false);
  assert.equal(hasOrdinance(city('passed')), true);
  assert.equal(hasOrdinance(city('enforced')), true);
});

test('0% is its own band, so the first ordinance is visible', () => {
  assert.equal(bandFor(0).key, 'none');
  // One city out of a hundred must NOT look like zero.
  assert.notEqual(bandFor(1).key, 'none');
  assert.equal(bandFor(1).key, 'starting');
});

test('band edges are upper-inclusive', () => {
  assert.equal(bandFor(20).key, 'starting');  // not 'building'
  assert.equal(bandFor(20.1).key, 'building');
  assert.equal(bandFor(40).key, 'building');
  assert.equal(bandFor(40.1).key, 'halfway');
  assert.equal(bandFor(60).key, 'halfway');
  assert.equal(bandFor(80).key, 'most');
  assert.equal(bandFor(80.1).key, 'nearly');
  assert.equal(bandFor(100).key, 'nearly');
});

test('every band has a distinct color', () => {
  const colors = COVERAGE_BANDS.map((b) => b.color);
  assert.equal(new Set(colors).size, colors.length);
});

test('counties with no incorporated cities do not divide by zero', () => {
  // Alpine, Mariposa and Trinity really have none.
  const c = coverageFor({ cities: [] });
  assert.equal(c.percent, null);
  assert.equal(c.totalCities, 0);
  assert.equal(c.withOrdinance, 0);
  assert.equal(c.band.key, 'none');
  assert.ok(!Number.isNaN(c.percent));
});

test('counts and percentage are computed from the city list', () => {
  const c = coverageFor({
    cities: [
      city('passed'), city('enforced'), city('not_started'),
      city('contacted'), city('ordinance_drafted'),
    ],
  });
  assert.equal(c.withOrdinance, 2);
  assert.equal(c.totalCities, 5);
  assert.equal(c.percent, 40);
  assert.equal(c.band.key, 'building');
});

test('a missing or absent city list is treated as no cities', () => {
  assert.equal(coverageFor({}).totalCities, 0);
  assert.equal(coverageFor(null).totalCities, 0);
  assert.equal(coverageFor(undefined).percent, null);
});
