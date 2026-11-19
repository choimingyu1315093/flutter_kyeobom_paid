'use strict';
function isFreshEvent(detected, received, now) {
  return Number.isFinite(detected) && Number.isFinite(received) &&
    detected >= now - 60000 && detected <= now + 15000 &&
    received >= now - 60000 && received <= now + 15000;
}
function canClaimCry(detected, last) {
  return Number.isFinite(detected) && Number.isFinite(last) &&
    detected > last && detected - last >= 90000;
}
module.exports = {isFreshEvent, canClaimCry};
