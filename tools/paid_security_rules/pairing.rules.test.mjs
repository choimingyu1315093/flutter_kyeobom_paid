import { test, before, beforeEach, after } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc, collection, getDoc, getDocs, setDoc, updateDoc,
  Timestamp, serverTimestamp, writeBatch,
} from 'firebase/firestore';

let env;
const stationUid = 'station-a';
const viewerUid = 'viewer-a';
const intruderUid = 'viewer-intruder';
const email = 'viewer@example.com';
const code = 'ABCDEFGHJK';

const station = () => env.authenticatedContext(stationUid, {
  firebase: { sign_in_provider: 'anonymous' },
}).firestore();
const viewer = () => env.authenticatedContext(viewerUid, {
  email,
  firebase: { sign_in_provider: 'password' },
}).firestore();
const intruder = () => env.authenticatedContext(intruderUid, {
  email: 'intruder@example.com',
  firebase: { sign_in_provider: 'password' },
}).firestore();
const path = 'homecamStations/' + stationUid;
const invitationPath = 'homecamPairings/' + code;
const expiresAt = () => Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000));

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-kyeobom-paid-security',
    firestore: {
      // Dedicated rules-test instance. Never target the device QA port 8080.
      host: '127.0.0.1',
      port: 8281,
      rules: readFileSync(resolve('../../firestore.rules'), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), path), {
      viewerUid: '', viewerEmail: '', command: 'idle',
      onlineHint: true, updatedAt: Timestamp.now(),
    });
  });
});

after(async () => {
  if (env) await env.cleanup();
});

test('only the anonymous station can read or update its station record', async () => {
  await assertSucceeds(getDoc(doc(station(), path)));
  await assertFails(getDoc(doc(viewer(), path)));
  await assertFails(getDoc(doc(intruder(), path)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), path)));
  await assertSucceeds(updateDoc(doc(station(), path), {onlineHint: false}));
  await assertFails(updateDoc(doc(viewer(), path), {viewerUid: viewerUid}));
  await assertFails(getDocs(collection(station(), 'homecamStations')));
});

test('legacy email-only station identity must migrate before rule rollout', async () => {
  const legacyPath = 'homecamStations/' + viewerUid;
  // Existing versions may use the same email Auth UID for both station/viewer.
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), legacyPath), {
      command: 'idle', updatedAt: Timestamp.now(), onlineHint: true,
    });
  });
  await assertFails(getDoc(doc(viewer(), legacyPath)));
  await assertFails(updateDoc(doc(viewer(), legacyPath), {
    command: 'start',
  }));
  await assertFails(setDoc(doc(viewer(), 'homecamStations/new-email-only'), {
    viewerUid: '', viewerEmail: '',
  }));
});

test('pairing code can be created by the station but not by viewers', async () => {
  const payload = {
    stationUid, status: 'open', pendingViewerUid: '',
    pendingViewerEmail: '', expiresAt: expiresAt(),
    createdAt: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(station(), invitationPath), payload));
  await assertFails(setDoc(doc(intruder(), 'homecamPairings/ABCDEFGHJL'), payload));
  await assertFails(getDocs(collection(viewer(), 'homecamPairings')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), invitationPath)));
});

test('viewer can claim code but cannot approve or elevate station access', async () => {
  await assertSucceeds(setDoc(doc(station(), invitationPath), {
    stationUid, status: 'open', pendingViewerUid: '',
    pendingViewerEmail: '', expiresAt: expiresAt(),
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(viewer(), invitationPath), {
    status: 'pending', pendingViewerUid: viewerUid,
    pendingViewerEmail: email,
  }));
  await assertFails(updateDoc(doc(viewer(), invitationPath), {
    status: 'approved',
  }));
  await assertFails(updateDoc(doc(viewer(), invitationPath), {
    stationUid: 'station-evil',
  }));
  await assertFails(updateDoc(doc(intruder(), invitationPath), {
    status: 'pending',
    pendingViewerUid: intruderUid,
    pendingViewerEmail: 'intruder@example.com',
  }));
});

test('only approved viewer can signal; revocation blocks old sessions', async () => {
  await assertSucceeds(updateDoc(doc(station(), path), {
    viewerUid, viewerEmail: email, pairedAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(viewer(), path)));
  await assertFails(getDoc(doc(intruder(), path)));
  await assertFails(updateDoc(doc(viewer(), path), {viewerUid: intruderUid}));
  await assertSucceeds(updateDoc(doc(viewer(), path), {
    command: 'start', sessionId: 's1', commandId: 's1',
    updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(viewer(), path + '/sessions/s1'), {
    state: 'creating_offer',
  }));
  await assertSucceeds(getDoc(doc(viewer(), path + '/sessions/s1')));
  await assertFails(getDoc(doc(intruder(), path + '/sessions/s1')));

  await assertSucceeds(updateDoc(doc(station(), path), {
    viewerUid: '', viewerEmail: '',
  }));
  await assertFails(getDoc(doc(viewer(), path)));
  await assertFails(getDoc(doc(viewer(), path + '/sessions/s1')));
  await assertFails(updateDoc(doc(viewer(), path), {command: 'start'}));
});


test('station can approve the pending viewer in one atomic batch', async () => {
  // writeBatch and every document in that batch must share one Firestore
  // instance, even if authenticatedContext() uses the same Auth UID.
  const stationDb = station();
  const invite = doc(stationDb, invitationPath);
  await assertSucceeds(setDoc(invite, {
    stationUid, status: 'open', pendingViewerUid: '',
    pendingViewerEmail: '', expiresAt: expiresAt(),
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(viewer(), invitationPath), {
    status: 'pending', pendingViewerUid: viewerUid,
    pendingViewerEmail: email,
  }));
  const batch = writeBatch(stationDb);
  batch.update(doc(stationDb, path), {
    viewerUid, viewerEmail: email, pairedAt: serverTimestamp(),
  });
  batch.update(invite, { status: 'approved' });
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(doc(viewer(), path)));
  await assertFails(getDoc(doc(intruder(), path)));
  await assertFails(updateDoc(doc(viewer(), invitationPath), {
    status: 'open', pendingViewerUid: '', pendingViewerEmail: '',
  }));
});

test('pending viewer can cancel their own request; another viewer cannot', async () => {
  await assertSucceeds(setDoc(doc(station(), invitationPath), {
    stationUid, status: 'open', pendingViewerUid: '',
    pendingViewerEmail: '', expiresAt: expiresAt(),
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(viewer(), invitationPath), {
    status: 'pending', pendingViewerUid: viewerUid,
    pendingViewerEmail: email,
  }));
  await assertFails(updateDoc(doc(intruder(), invitationPath), {
    status: 'open', pendingViewerUid: '', pendingViewerEmail: '',
  }));
  await assertSucceeds(updateDoc(doc(viewer(), invitationPath), {
    status: 'open', pendingViewerUid: '', pendingViewerEmail: '',
  }));
});

test('viewer cannot read or write candidate subcollections after revocation', async () => {
  await assertSucceeds(updateDoc(doc(station(), path), {
    viewerUid, viewerEmail: email, pairedAt: serverTimestamp(),
  }));
  const candidate = path + '/sessions/test-1/viewerCandidates/candidate-1';
  await assertSucceeds(setDoc(doc(viewer(), candidate), {
    candidate: 'test-candidate',
  }));
  await assertSucceeds(getDoc(doc(viewer(), candidate)));
  await assertFails(getDoc(doc(intruder(), candidate)));
  await assertSucceeds(updateDoc(doc(station(), path), {
    viewerUid: '', viewerEmail: '',
  }));
  await assertFails(getDoc(doc(viewer(), candidate)));
  await assertFails(setDoc(doc(viewer(), candidate), {candidate:'other'}));
});

test('expired pairing codes cannot be claimed', async () => {
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), invitationPath), {
      stationUid, status: 'open', pendingViewerUid: '',
      pendingViewerEmail: '',
      expiresAt: Timestamp.fromDate(new Date(Date.now() - 60_000)),
      createdAt: serverTimestamp(),
    });
  });
  await assertFails(updateDoc(doc(viewer(), invitationPath), {
    status: 'pending', pendingViewerUid: viewerUid,
    pendingViewerEmail: email,
  }));
});
