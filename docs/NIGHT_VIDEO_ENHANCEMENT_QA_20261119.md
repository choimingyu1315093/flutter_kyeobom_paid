# Paid station: automatic low-light pre-encoder enhancement
Base: P2 real-device core QA passed, 50ae890. Free repository untouched.
Existing Full HD/24 fps/3 Mbps preferences, fallback, signaling, camera/audio
permissions, baby cry policy and FCM backend unchanged. No new dependencies.
On a paid station's live video only, attach the flutter_webrtc 1.6.3 local
video processor before encoding. Android reads I420 (assumes normal limited
video range); iOS handles NV12 full range and video range while preserving
crop, rotation and timestamp. No extra camera, torch, or video upload.
Normal lighting returns the original frame, except hysteresis at transitions.
Sample actual captured luminance 400 ms apart: enter after 3 dark samples
(mean <= .23 and >=80% sampled pixels below .30), exit after 2 brighter
samples; bypass immediately on clearly bright/backlit or nearly black frames.
Bounded shadow lift (0.65 gamma candidate, max +18% normalized luminance,
black floor and highlight taper, eight-frame entry ramp), retain chroma.
No claim of sensor sensitivity improvement, denoising, infrared or recovering
detail with zero light. Noise may become more visible. This is an initial
candidate for real-device A/B evaluation, not proven superior night vision.
Detach under existing reduced video health policy and on end; processing
bypasses for 10 s after three consecutive >35 ms frames or Android exception.
iOS pool allocation threshold 4; any unsupported buffer or exhausted pool
returns original. Android conversions during daylight sampling can still cost
CPU. Do not extend monitoring into background or modify capture settings.
Build same paid station with --dart-define=KYEOBOM_NIGHT_ENHANCE=false for
control; true/default for treatment. Keep same device, scene, illumination,
distance, angle, Wi-Fi, camera and viewer. Compare day and dim (not only
brightness; face/clothing details, noise, motion, fps and heat), lights on/off,
audio ON/OFF, baby cry push and event recording, disconnect and re-connect.
Physical tests and native builds are required; native code not compiled here.

Temporary live A/B button: build with --dart-define=KYEOBOM_NIGHT_COMPARE_QA=true (leave KYEOBOM_NIGHT_ENHANCE at true/default). Only the live station screen shows one button. ON indicates processor attached, not proof current illumination is dark. OFF detaches it; camera, encoder and session remain unchanged. Toggle after stable dark scene, wait 2–3 seconds in each state and compare viewer screenshots. Normal builds hide the button; health protection disables comparison, and recovering health respects an explicit OFF selection. New sessions default ON. No native code or backend changed for this button.

## Adaptive v2 review before evening QA
Replaces fixed gamma with 17 monotone LUT levels (0–16). Use p10/p95 to preserve useful dim signal instead of rejecting every low mean scene. Automatic entry slightly widened to mean <= .29 and dark fraction >= .70, bright safety exit remains immediate. Near-black flat signal remains bypassed, and lift is reduced near the signal floor; this is not a physical noise estimator. Strength follows illumination and available signal gradually. Increased input cap from 2.1M to 3.2M pixels for common 4:3 sensor frames; existing performance circuit and iOS pool guard retained. Chroma untouched. No new camera exposure, temporal denoising, or capture settings. QA-only native logs KyeobomNightQA indicate original, enhanced, insufficient_signal, unsupported_size/format/buffer, buffer_busy, or performance_bypass; ON button still means attachment, not active enhancement. Compare real scenes before claiming image quality improvement. The code does not guarantee differentiation in darkness with no signal or on a slow/unsupported device.

Reproducible portable native policy tests: `python3 tools/test_night_luma_policy.py`. Requires swiftc or kotlinc + java; both for parity. The tests do not require Flutter, Xcode SDK or Android SDK. Both pure policy implementations were independently compiled/tested with equivalent fixtures on Linux, and all 8,704 LUT entries matched. Native app integration and actual camera QA remain pending.
