/// The incoming rear camera frame needs a quarter-turn for the full-screen
/// viewer. On the opposite landscape side the rotation must reverse, or the
/// scene appears upside down after the phone is physically rotated 180°.
///
/// [landscapeRight] is determined by the native display/UI orientation,
/// not by MediaQuery width/height (which are identical for both sides).
int videoQuarterTurns({
  required bool viewerLandscape,
  bool landscapeRight = false,
}) {
  if (!viewerLandscape) return 0;
  return landscapeRight ? 3 : 1;
}
