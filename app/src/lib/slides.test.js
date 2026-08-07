// Run with: npm test  (from app/)
//
// These guard a security boundary, not just a parser. embedUrl() output goes
// straight into an <iframe src>, and anyone with edit rights on a county can
// set the underlying value — so "rejects hostile input" is the point of the
// module, and a regression here is a framing/clickjacking hole rather than a
// cosmetic bug.

import test from 'node:test';
import assert from 'node:assert/strict';

import { parseSlidesUrl, embedUrl, editUrl } from './slides.js';

const ID = '1a2B3c4D5e6F7g8H9i0JkLmNoPqRsTuVwXyZ_-abcdef';

test('accepts the URL shapes people actually paste', () => {
  const shapes = [
    `https://docs.google.com/presentation/d/${ID}/edit#slide=id.p`,
    `https://docs.google.com/presentation/d/${ID}/edit?usp=sharing`,
    `https://docs.google.com/presentation/d/${ID}/embed?start=false`,
    `https://docs.google.com/presentation/d/${ID}/pub?start=true`,
    `  https://docs.google.com/presentation/d/${ID}/edit  `,
  ];
  for (const s of shapes) {
    assert.equal(parseSlidesUrl(s)?.id, ID, `should parse: ${s.trim()}`);
  }
});

test('published-to-web URLs keep their /e/ segment and have no editor', () => {
  const pub = `https://docs.google.com/presentation/d/e/${ID}/pubembed`;

  assert.equal(parseSlidesUrl(pub).published, true);
  assert.equal(
    embedUrl(pub),
    `https://docs.google.com/presentation/d/e/${ID}/embed?start=false&loop=false&delayms=60000`
  );
  // A publish ID is not a document ID, so there is no /edit form to offer.
  assert.equal(editUrl(pub), null);
});

test('rebuilds the URL from the ID rather than forwarding the input', () => {
  // The fragment and the stray query param must not survive into the iframe.
  assert.equal(
    embedUrl(`https://docs.google.com/presentation/d/${ID}/edit#slide=99`),
    `https://docs.google.com/presentation/d/${ID}/embed?start=false&loop=false&delayms=60000`
  );
  assert.equal(
    editUrl(`https://docs.google.com/presentation/d/${ID}/pub?evil=1`),
    `https://docs.google.com/presentation/d/${ID}/edit`
  );
});

test('rejects hostile and malformed input', () => {
  const bad = {
    'javascript scheme': 'javascript:alert(1)',
    'data scheme': 'data:text/html,<script>alert(1)</script>',
    'plain http': `http://docs.google.com/presentation/d/${ID}/edit`,
    'lookalike host': `https://docs.google.com.evil.tld/presentation/d/${ID}/edit`,
    'host in path': `https://evil.com/docs.google.com/presentation/d/${ID}/edit`,
    // Reads as docs.google.com but the real host is evil.tld.
    'userinfo spoof': `https://docs.google.com@evil.tld/presentation/d/${ID}/edit`,
    'wrong google product': `https://docs.google.com/document/d/${ID}/edit`,
    'missing id': 'https://docs.google.com/presentation/d//edit',
    'id too short': 'https://docs.google.com/presentation/d/abc/edit',
    'traversal in id': 'https://docs.google.com/presentation/d/..%2F..%2Fx/edit',
    'empty string': '',
    'null': null,
    'not a url': 'just some text',
  };

  for (const [name, input] of Object.entries(bad)) {
    assert.equal(parseSlidesUrl(input), null, `parse should reject ${name}`);
    assert.equal(embedUrl(input), null, `embed should reject ${name}`);
    assert.equal(editUrl(input), null, `edit should reject ${name}`);
  }
});
