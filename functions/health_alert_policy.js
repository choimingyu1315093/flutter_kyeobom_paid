'use strict';

/**
 * The only three alert types the product sends.
 * No 5% battery alert, Wi-Fi alert or recovery push.
 * Station telemetry is sampled every ~30s even while video is streaming.
 */
const ALERTS = Object.freeze({
  battery_low: {
    title: '켜봄 · 거치폰 배터리 부족',
    body: '거치폰 배터리가 20% 이하입니다. 충전기를 연결해 주세요.',
  },
  thermal_serious: {
    title: '켜봄 · 거치폰 발열 높음',
    body: '거치폰의 발열이 심해 영상 품질을 낮추고 있어요.',
  },
  thermal_critical: {
    title: '켜봄 · 거치폰 과열 위험',
    body: '거치폰을 보호하기 위해 영상 송출이 제한됐어요.',
  },
});

function thermalTier(snapshot) {
  const thermal = Number.isInteger(snapshot.thermal) ? snapshot.thermal : -1;
  if (thermal < 0) return null;
  if (snapshot.platform === 'iOS') {
    return thermal >= 3 ? 2 : thermal >= 2 ? 1 : 0;
  }
  if (snapshot.platform === 'android') {
    return thermal >= 4 ? 2 : thermal >= 3 ? 1 : 0;
  }
  return null;
}

/**
 * State survives app restarts and Cloud Functions duplicate invocations.
 * Hysteresis: battery rearms only above 25% or once charging.
 * Thermal rearms only after normalizing below SERIOUS.
 */
function planHealthAlerts(previous, snapshot) {
  const old = previous || {};
  let batteryArmed = old.batteryAlertActive === true;
  let heatPeak = [0, 1, 2].includes(old.heatPeak) ? old.heatPeak : 0;
  const alerts = [];

  const battery = Number.isInteger(snapshot.battery) &&
    snapshot.battery >= 0 && snapshot.battery <= 100
    ? snapshot.battery
    : null;
  if (snapshot.charging === true || (battery !== null && battery >= 25)) {
    batteryArmed = false;
  } else if (battery !== null && battery <= 20 && !batteryArmed) {
    alerts.push('battery_low');
    batteryArmed = true;
  }

  const heat = thermalTier(snapshot);
  if (heat === 0) {
    heatPeak = 0;
  } else if (heat !== null && heat > heatPeak) {
    alerts.push(heat === 2 ? 'thermal_critical' : 'thermal_serious');
    heatPeak = heat;
  }

  return {
    alerts,
    state: {batteryAlertActive: batteryArmed, heatPeak},
  };
}

module.exports = {ALERTS, planHealthAlerts, thermalTier};
