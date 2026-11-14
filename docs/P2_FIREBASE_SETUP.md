# P2 Firebase remote control setup

This branch adds a **remote camera ON/OFF command smoke test**, NOT WebRTC streaming.

## Configure Firebase

1. In the Firebase Console HomeCamera project, enable Authentication > Sign-in method > Email/Password.
2. Create a Cloud Firestore database.
3. Install FlutterFire CLI if needed: `dart pub global activate flutterfire_cli`.
4. Run `flutterfire configure` from the project root and select **HomeCamera** for Android and iOS. Ensure Android package ID and iOS bundle ID match the project.
5. Deploy `firestore.rules` to the HomeCamera project (Firebase Console > Firestore > Rules) **before testing**. Do not use open/test rules.
6. `flutter pub get && flutter analyze && flutter run`.

## Test

- On device A, create a test account and sign in. Enter **station** and confirm the waiting dialog.
- On device B, sign in with the **same test account** and enter **viewer**.
- Tap remote camera ON; the station should show rear camera preview and the viewer should report camera_on.
- Tap remote camera OFF; the station should release the camera and viewer should report camera_off.
- Both devices must remain online. Station app must remain foreground, especially on iOS.

## Limitations

- This is a test-only account-sharing scheme, not secure end-user device pairing. Replace with scoped pairing and revocation before launch.
- The onlineHint is **not a reliable presence indicator**; app crashes can leave it stale.
- Command timestamps use client time for IDs and are not replay-proof.
- No WebRTC video, TURN, QR pairing, or 24-hour reliability validation yet.
- Firebase project config files are generated locally; never commit service-account keys.
