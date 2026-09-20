const { test } = require('node:test');
const assert = require('node:assert/strict');
const { detectPlatform } = require('../../docs/download/platform.js');
test('download guidance distinguishes desktop platforms and leaves mobile/Linux unselected', () => {
  assert.equal(detectPlatform('Mozilla/5.0 (Windows NT 10.0; Win64; x64)'), 'windows');
  assert.equal(detectPlatform('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'), 'mac');
  assert.equal(detectPlatform('Mozilla/5.0 (iPad; CPU OS 17 like Mac OS X)'), null);
  assert.equal(detectPlatform('Mozilla/5.0 (X11; Linux x86_64)'), null);
});
