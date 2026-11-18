# Live free Firestore rules: strictly additive paid health/FCM permissions

The supplied live Firestore rules match the free secure-pairing baseline. The
file `production_free_additive.rules` preserves EVERY existing free rule
verbatim and inserts ONLY three nested `homecamStations/{stationUid}` matches:

- `telemetry/health` — anonymous station may write, station/approved viewer may get, no list
- `devices/{deviceId}` — Auth UID-bound FCM registration, approved viewer only, no list
- `alertState/{alertId}` — client read/write forbidden; server Admin SDK only

It deliberately does NOT contain the `homecamEntitlements` and
`homecamPlayTokens` match blocks from the working paid branch, because they
are not in the user-supplied currently published free rules and are not
needed to resolve this specific failure.

### Test on your Mac (no production deployment)

```bash
cd ~/Flutter/flutter_kyeobom_paid
git fetch origin
git switch --track origin/paid/live-firestore-health-fcm-compat-20261118
cd tools/paid_security_rules
npm install
cd ../..
bash tools/paid_security_rules/run_production_compat_tests.sh
```

Expected: 12 security tests pass and 1 unrelated entitlement grant test is
skipped because it belongs to a separate unreleased subscription branch.
A failure blocks rollout. Default rule tests can still run unchanged with
`bash tools/paid_security_rules/run_emulator_tests.sh`.

### Production precautions

Do NOT run `firebase deploy` from this paid repository as-is. Its
`firebase.json` points to the *different* working
`firestore.rules` and its Functions source does not include every
free subscription/account function. Publishing it wholesale could
change unrelated features.

Before any publication, verify no intervening live rule changes occurred,
back up the entire Firebase Console rules text, compare the additive file
line by line, and run both emulator suites. Only then paste the verified
file into Firebase Console > Firestore > Rules and manually Publish (or
use a dedicated audited rules-only deployment config).
After publication, re-check FREE QR pairing/revocation/streaming and paid
telemetry/token registration on both platforms.

Push notifications also require separately validating the deployed
`notifyOnHealthChange` function. Updating rules alone restores FCM token
registration but does not prove actual server-side dispatch.

No source code in the free repository has been modified by this branch.
