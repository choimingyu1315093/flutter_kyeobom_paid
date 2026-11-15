/// Server-cost guardrails for the existing peer-to-peer HomeCamera transport.
///
/// Firestore is reserved for starting/stopping a session, SDP and ICE.
/// Repeating connection liveness messages travel over the existing WebRTC
/// peer connection instead of causing Firestore writes every 10 seconds.
abstract final class HomeCamCostPolicy {
  static const dataChannelLabel = 'kyeobom-liveness-v1';
  static const heartbeatPeriod = Duration(seconds: 10);
  static const watchdogPeriod = Duration(seconds: 5);
  static const stationTimeout = Duration(seconds: 45);
  // Only old clients or a failed SCTP channel need this Firestore fallback.
  static const fallbackStartAfter = Duration(seconds: 20);
  static const fallbackEvery = Duration(seconds: 20);
  static const directAckFreshFor = Duration(seconds: 30);

  /// STUN-only by design. Do not add TURN credentials without implementing
  /// authenticated relay access, quota metering and a hard budget cap.
  static const Map<String, dynamic> directIceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  static String heartbeat(String sessionId) => 'kb-live-v1:$sessionId';
  static String acknowledge(String sessionId) => 'kb-live-ack-v1:$sessionId';

  static bool isHeartbeatForSession(String text, String sessionId) =>
      sessionId.isNotEmpty && text == heartbeat(sessionId);

  static bool isAcknowledgementForSession(String text, String sessionId) =>
      sessionId.isNotEmpty && text == acknowledge(sessionId);

  /// Returns false for normal direct-channel sessions (zero heartbeat writes).
  /// A bounded, slower Firestore fallback supports mixed app versions and
  /// devices whose SCTP channel fails while video can still connect.
  static bool shouldWriteFallback({
    required DateTime now,
    required DateTime startedAt,
    DateTime? lastDirectAcknowledgement,
    DateTime? lastFallbackWrite,
  }) {
    if (now.difference(startedAt) < fallbackStartAfter) return false;
    if (lastDirectAcknowledgement != null &&
        now.difference(lastDirectAcknowledgement) < directAckFreshFor) {
      return false;
    }
    if (lastFallbackWrite != null &&
        now.difference(lastFallbackWrite) < fallbackEvery) {
      return false;
    }
    return true;
  }

  static bool stationTimedOut(DateTime lastHeartbeat, DateTime now) =>
      now.difference(lastHeartbeat) > stationTimeout;
}
