'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {ALERTS, planHealthAlerts, thermalTier} = require('../health_alert_policy');

const sample = (overrides = {}) => ({
  platform: 'android', battery: 75, charging: false,
  thermal: 0, active: true, ...overrides,
});

function transition(prev, snapshot) {
  return planHealthAlerts(prev, snapshot);
}

test('exactly three supported alert types', () => {
  assert.deepEqual(Object.keys(ALERTS), [
    'battery_low', 'thermal_serious', 'thermal_critical',
  ]);
});

test('battery 20% warns once while still under 20%', () => {
  let outcome = transition(null, sample({battery: 20}));
  assert.deepEqual(outcome.alerts, ['battery_low']);
  outcome = transition(outcome.state, sample({battery: 19}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({battery: 5}));
  assert.deepEqual(outcome.alerts, []);
});

test('battery does not rearm just from 21% bounce; resets at 25%', () => {
  let outcome = transition(null, sample({battery: 20}));
  outcome = transition(outcome.state, sample({battery: 22}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({battery: 19}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({battery: 26}));
  outcome = transition(outcome.state, sample({battery: 20}));
  assert.deepEqual(outcome.alerts, ['battery_low']);
});

test('charging resets battery alarm without sending extra notification', () => {
  let outcome = transition(null, sample({battery: 20}));
  outcome = transition(outcome.state, sample({battery: 19, charging: true}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({battery: 19}));
  assert.deepEqual(outcome.alerts, ['battery_low']);
});

test('Android severe raises one warning and critical escalates once', () => {
  let outcome = transition(null, sample({thermal: 3}));
  assert.deepEqual(outcome.alerts, ['thermal_serious']);
  outcome = transition(outcome.state, sample({thermal: 3}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({thermal: 4}));
  assert.deepEqual(outcome.alerts, ['thermal_critical']);
  outcome = transition(outcome.state, sample({thermal: 4}));
  assert.deepEqual(outcome.alerts, []);
});

test('direct jump to critical skips intermediate serious alert', () => {
  const outcome = transition(null, sample({thermal: 5}));
  assert.deepEqual(outcome.alerts, ['thermal_critical']);
});

test('thermal must recover below serious to rearm', () => {
  let outcome = transition(null, sample({thermal: 4}));
  outcome = transition(outcome.state, sample({thermal: 3}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({thermal: 4}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({thermal: 2}));
  assert.deepEqual(outcome.alerts, []);
  outcome = transition(outcome.state, sample({thermal: 3}));
  assert.deepEqual(outcome.alerts, ['thermal_serious']);
});

test('iOS serious and critical use OS-specific thresholds', () => {
  assert.equal(thermalTier(sample({platform:'iOS', thermal:2})), 1);
  assert.equal(thermalTier(sample({platform:'iOS', thermal:3})), 2);
  const first = transition(null, sample({platform:'iOS', thermal:2}));
  assert.deepEqual(first.alerts, ['thermal_serious']);
  const second = transition(first.state, sample({platform:'iOS', thermal:3}));
  assert.deepEqual(second.alerts, ['thermal_critical']);
});

test('unknown thermal does not clear existing warning state', () => {
  const previous = {batteryAlertActive: false, heatPeak: 2};
  assert.deepEqual(transition(previous, sample({thermal: -1})).state, previous);
});

test('battery and serious heat can both alert on same genuine transition', () => {
  const outcome = transition(null, sample({battery:18, thermal:3}));
  assert.deepEqual(outcome.alerts, ['battery_low', 'thermal_serious']);
});
