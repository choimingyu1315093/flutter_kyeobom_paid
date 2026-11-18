'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {approvedRecipients} = require('../health_recipient_policy');

const validToken = 'a'.repeat(152);
const registrations = [
  {authUid: 'approved', role: 'viewer', fcmToken: validToken},
  {authUid: 'revoked', role: 'viewer', fcmToken: 'b'.repeat(152)},
  {authUid: 'approved', role: 'station', fcmToken: validToken},
  {authUid: 'approved', role: 'viewer', fcmToken: null},
];

test('only the currently approved viewer receives station alerts', () => {
  assert.equal(approvedRecipients(registrations, 'approved').length, 1);
  assert.equal(approvedRecipients(registrations, 'approved')[0].authUid, 'approved');
});

test('revocation stops all alerts even with stale token documents', () => {
  assert.deepEqual(approvedRecipients(registrations, ''), []);
  assert.deepEqual(approvedRecipients(registrations, null), []);
  assert.equal(approvedRecipients(registrations, 'anotherViewer').length, 0);
});

test('invalid tokens and station role are never deliverable', () => {
  const registrations = [
    {authUid: 'approved', role: 'viewer', fcmToken: 'short'},
    {authUid: 'approved', role: 'viewer', fcmToken: 'z'.repeat(4097)},
    {authUid: 'approved', role: 'station', fcmToken: validToken},
  ];
  assert.deepEqual(approvedRecipients(registrations, 'approved'), []);
});
