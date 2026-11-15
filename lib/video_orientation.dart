/// The station video in the verified iPhone/Android pair arrives sideways.
///
/// When the viewer enters landscape, rotate the actual received pixels by
/// 90 degrees (not just the Flutter screen). The video surface uses cover
/// fitting to fill the landscape viewport without large black side bars.
///
/// RTCVideoRenderer.videoWidth/videoHeight cannot determine which way the
/// scene's floor and walls are oriented: relying on aspect ratio caused the
/// screenshot's video to stay sideways and narrow.
int videoQuarterTurns({required bool viewerLandscape}) =>
    viewerLandscape ? 1 : 0;
