'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {isFreshEvent, canClaimCry} = require('../baby_cry_push_policy');
const now = 1800000000000;
test('fresh metadata only, reject delayed and future writes', () => {
  assert.equal(isFreshEvent(now-1000,now,now),true);
  assert.equal(isFreshEvent(now-60001,now,now),false);
  assert.equal(isFreshEvent(now,now-60001,now),false);
  assert.equal(isFreshEvent(now+15001,now,now),false);
  assert.equal(isFreshEvent(undefined,now,now),false);
});
test('server dedupes retries, older events and rapid repeated alerts', () => {
  assert.equal(canClaimCry(now,0),true);
  assert.equal(canClaimCry(now,now),false);
  assert.equal(canClaimCry(now-1,now),false);
  assert.equal(canClaimCry(now+89999,now),false);
  assert.equal(canClaimCry(now+90000,now),true);
});
