'use strict';

/** Security boundary: a station alert may reach ONLY its currently approved
 * viewer UID, not a stale FCM registration left by a previously paired user.
 * Pure function for deterministic tests without Firebase dependencies.
 */
function approvedRecipients(registrations, approvedUid) {
  if (typeof approvedUid !== 'string' || approvedUid.length === 0) return [];
  return registrations.filter((entry) =>
    entry.role === 'viewer' &&
    entry.authUid === approvedUid &&
    typeof entry.fcmToken === 'string' &&
    entry.fcmToken.length >= 20 &&
    entry.fcmToken.length <= 4096);
}

module.exports = {approvedRecipients};
