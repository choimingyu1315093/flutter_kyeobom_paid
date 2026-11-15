/// Determines whether the incoming WebRTC frame must be rotated to fit the
/// viewer's landscape presentation.
///
/// The RTCVideoRenderer often reports a portrait frame while a rear camera is
/// held sideways. Rotating those pixels (rather than only the Flutter page)
/// restores a horizontal picture. Already-landscape frames are left unchanged.
int videoQuarterTurns({
  required bool viewerLandscape,
  required int videoWidth,
  required int videoHeight,
}) {
  if (!viewerLandscape || videoWidth <= 0 || videoHeight <= 0) return 0;
  return videoHeight > videoWidth ? 1 : 0;
}
