import {test, before, beforeEach, after} from 'node:test';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {assertFails, assertSucceeds, initializeTestEnvironment}
  from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp,
  Timestamp} from 'firebase/firestore';

const projectId = 'demo-kyeobom-paid-security';
const stationUid = 'station-secure';
const viewerUid = 'viewer-approved';
const intruderUid = 'viewer-revoked';
const stationPath = 'homecamStations/' + stationUid;
let env;
const station = () => env.authenticatedContext(stationUid, {
  firebase: {sign_in_provider: 'anonymous'},
}).firestore();
const viewer = () => env.authenticatedContext(viewerUid, {
  email: 'viewer@example.com', firebase: {sign_in_provider: 'password'},
}).firestore();
const intruder = () => env.authenticatedContext(intruderUid, {
  email: 'other@example.com', firebase: {sign_in_provider: 'password'},
}).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1', port: 8281,
      rules: readFileSync(resolve('../../firestore.rules'), 'utf8'),
    },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), stationPath), {
      viewerUid, viewerEmail: 'viewer@example.com',
      command: 'idle', updatedAt: Timestamp.now(),
    });
  });
});
after(async () => {if (env) await env.cleanup();});

test('only station can update its health telemetry; approved viewer may read', async () => {
  const health = stationPath + '/telemetry/health';
  await assertSucceeds(setDoc(doc(station(), health), {
    active: true, platform: 'android', battery: 25,
    charging: false, thermal: 0, network: 'wifi', risk: 'normal',
    collectedAt: Timestamp.now(), lastSeen: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(viewer(), health)));
  await assertFails(getDoc(doc(intruder(), health)));
  await assertFails(updateDoc(doc(viewer(), health), {battery: 0}));
  await assertFails(setDoc(doc(station(), stationPath + '/telemetry/private'), {
    active: true,
  }));
  await assertSucceeds(updateDoc(doc(station(), health), {
    active: false, lastSeen: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(station(), stationPath), {
    viewerUid: '', viewerEmail: '',
  }));
  await assertFails(getDoc(doc(viewer(), health)));
});

test('FCM registration is scoped to approved viewer Auth UID', async () => {
  const path = stationPath + '/devices/installation-' + viewerUid;
  const valid = {
    authUid: viewerUid, role: 'viewer', platform: 'iOS',
    fcmToken: 'a'.repeat(160), updatedAt: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(viewer(), path), valid));
  await assertSucceeds(getDoc(doc(viewer(), path)));
  await assertFails(getDoc(doc(intruder(), path)));
  await assertFails(updateDoc(doc(intruder(), path), {
    fcmToken: 'c'.repeat(160),
  }));
  await assertFails(setDoc(doc(viewer(), stationPath + '/devices/spoof'), {
    ...valid, authUid: intruderUid,
  }));
  await assertFails(setDoc(doc(viewer(), stationPath + '/devices/spoof-station'), {
    ...valid, role: 'station', fcmToken: null,
  }));
  await assertSucceeds(updateDoc(doc(viewer(), path), {
    fcmToken: 'b'.repeat(160), updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(station(), stationPath), {
    viewerUid: '', viewerEmail: '',
  }));
  await assertFails(getDoc(doc(viewer(), path)));
  await assertFails(deleteDoc(doc(viewer(), path)));
});

test('station registration cannot supply a push token, and alert state is admin-only', async () => {
  const camera = stationPath + '/devices/station-' + stationUid;
  await assertSucceeds(setDoc(doc(station(), camera), {
    authUid: stationUid, role: 'station', platform: 'android',
    fcmToken: null, updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(station(), camera), {
    fcmToken: 'a'.repeat(160), updatedAt: serverTimestamp(),
  }));
  const state = stationPath + '/alertState/health';
  await assertFails(setDoc(doc(station(), state), {heatPeak: 0}));
  await assertFails(getDoc(doc(viewer(), state)));
});

test('free subscription grants remain read-only and scoped to their owner', async () => {
  const entitlement = 'homecamEntitlements/' + viewerUid;
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), entitlement), {isActive: true});
  });
  await assertSucceeds(getDoc(doc(viewer(), entitlement)));
  await assertFails(getDoc(doc(intruder(), entitlement)));
  await assertFails(updateDoc(doc(viewer(), entitlement), {isActive: false}));
});
