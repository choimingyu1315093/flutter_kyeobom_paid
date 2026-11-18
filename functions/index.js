'use strict';

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {ALERTS, planHealthAlerts} = require('./health_alert_policy');
const {approvedRecipients} = require('./health_recipient_policy');

initializeApp();

const MAX_VIEWERS = 20;
const SAMPLE_MAX_AGE_MS = 10 * 60 * 1000;

/**
 * FCM is sent from a trusted backend only. The camera phone never holds
 * service account keys and never sends directly to another person's token.
 * The function is triggered by the SAME telemetry doc updated during
 * standby and live camera viewing; it does not touch the WebRTC session.
 */
exports.notifyOnHealthChange = onDocumentWritten(
  {
    document: 'homecamStations/{uid}/telemetry/health',
    region: 'asia-northeast3',
    memory: '256MiB',
    maxInstances: 3,
    retry: false,
  },
  async (event) => {
    const uid = event.params.uid;
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data();
    if (!data || data.active !== true) return;
    if (data.platform !== 'iOS' && data.platform !== 'android') return;

    // Do not alert for a delayed offline write replay or future timestamps.
    const collectedMs = data.collectedAt?.toMillis?.();
    const now = Date.now();
    if (!Number.isFinite(collectedMs) ||
        collectedMs > now + 60 * 1000 ||
        now - collectedMs > SAMPLE_MAX_AGE_MS) return;

    const db = getFirestore();
    const station = db.collection('homecamStations').doc(uid);
    // Unlike the original same-account P2 build, station and viewer have
    // DIFFERENT Auth UIDs. Never notify a viewer after station revocation.
    const approvedUid = (await station.get()).get('viewerUid');
    if (typeof approvedUid !== 'string' || approvedUid.length === 0) return;
    const registrations = await station.collection('devices')
      .where('authUid', '==', approvedUid)
      .limit(MAX_VIEWERS)
      .get();
    const receivers = approvedRecipients(registrations.docs.map((doc) => ({
      ref: doc.ref,
      authUid: doc.get('authUid'),
      role: doc.get('role'),
      fcmToken: doc.get('fcmToken'),
    })), approvedUid).map((device) => ({
      ref: device.ref, token: device.fcmToken,
    }));
    if (receivers.length === 0) return;

    // Firestore triggers are at-least-once and can be delivered out of order.
    // A transaction serializes latching, and sample time rejects retries.
    const stateRef = station.collection('alertState').doc('health');
    const alerts = await db.runTransaction(async (transaction) => {
      const currentStation = await transaction.get(station);
      if (currentStation.get('viewerUid') !== approvedUid) return [];
      const previousSnapshot = await transaction.get(stateRef);
      const previous = previousSnapshot.data() || {};
      const last = previous.lastSampleAt?.toMillis?.() || 0;
      if (collectedMs <= last) return [];
      const decision = planHealthAlerts(previous, data);
      transaction.set(stateRef, {
        ...decision.state,
        lastSampleAt: data.collectedAt,
      }, {merge: true});
      return decision.alerts;
    });
    if (alerts.length === 0) return;

    const messaging = getMessaging();
    for (const type of alerts) {
      // An owner may revoke pairing between processing and FCM dispatch.
      if ((await station.get()).get('viewerUid') !== approvedUid) return;
      const definition = ALERTS[type];
      if (!definition) continue;
      const response = await messaging.sendEachForMulticast({
        tokens: receivers.map((entry) => entry.token),
        notification: {
          title: definition.title,
          body: definition.body,
        },
        data: {
          kind: 'health_alert',
          type,
          uid,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'kyeobom_health_alerts',
            priority: 'high',
          },
        },
        apns: {
          headers: {'apns-priority': '10'},
          payload: {aps: {sound: 'default'}},
        },
      });
      // Only invalid tokens are removed; a transient network/APNs failure
      // must not delete legitimate viewer subscriptions.
      await Promise.all(response.responses.map(async (delivery, index) => {
        if (delivery.success) return;
        const code = delivery.error?.code;
        if (code !== 'messaging/registration-token-not-registered' &&
            code !== 'messaging/invalid-registration-token') return;
        const device = receivers[index];
        const current = await device.ref.get();
        if (current.get('fcmToken') === device.token) {
          await device.ref.delete();
        }
      }));
      console.info('Kyeobom health push result', {
        type,
        recipients: receivers.length,
        delivered: response.successCount,
        failed: response.failureCount,
      });
    }
  },
);
