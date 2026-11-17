#!/usr/bin/env python3
"""Read-only local migration checks for Kyeobom's Android/iOS identities.

Firebase configuration files are intentionally NOT committed into the feature
branch. Regenerate them in the SAME Firebase project after registering both
new app identifiers. This check never modifies or deletes local user files.
"""
from __future__ import annotations

import json
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED = "com.mingyu.kyeobom"
failures: list[str] = []
pending: list[str] = []


def report(label: str, good: bool, note: str) -> None:
    print(f"{'OK' if good else '확인 필요'}  {label}: {note}")
    if not good:
        failures.append(label)


gradle = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
ns = re.search(r'namespace\s*=\s*"([^"]+)"', gradle)
app = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle)
report("Android namespace", bool(ns and ns.group(1) == EXPECTED),
       ns.group(1) if ns else "not found")
report("Android applicationId", bool(app and app.group(1) == EXPECTED),
       app.group(1) if app else "not found")

kotlin = ROOT / "android/app/src/main/kotlin/com/mingyu/kyeobom/MainActivity.kt"
report("Android Kotlin MainActivity", kotlin.exists() and
       kotlin.read_text(encoding="utf-8").startswith("package com.mingyu.kyeobom"),
       str(kotlin.relative_to(ROOT)))

xcode = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
runner = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);', xcode)
app_ids = [v.strip().strip('"') for v in runner if not v.endswith("RunnerTests")]
tests = [v.strip().strip('"') for v in runner if v.endswith("RunnerTests")]
report("iOS Runner Bundle ID", len(app_ids) >= 3 and
       all(value == EXPECTED for value in app_ids), ", ".join(sorted(set(app_ids))))
report("iOS RunnerTests ID", len(tests) >= 3 and
       all(value == EXPECTED + ".RunnerTests" for value in tests),
       ", ".join(sorted(set(tests))))

android_firebase = ROOT / "android/app/google-services.json"
if android_firebase.exists():
    try:
        cfg = json.loads(android_firebase.read_text(encoding="utf-8"))
        packages = sorted({
            client.get("client_info", {}).get("android_client_info", {})
            .get("package_name", "")
            for client in cfg.get("client", [])
        })
        if EXPECTED in packages:
            print("OK  Firebase Android config: package match")
        else:
            pending.append(f"Firebase Android config package mismatch: {packages}")
    except Exception as error:
        pending.append(f"Firebase Android config unreadable: {error}")
else:
    pending.append("Firebase Android google-services.json missing")

ios_firebase = ROOT / "ios/Runner/GoogleService-Info.plist"
if ios_firebase.exists():
    try:
        with ios_firebase.open("rb") as handle:
            cfg = plistlib.load(handle)
        bid = cfg.get("BUNDLE_ID")
        if bid == EXPECTED:
            print("OK  Firebase iOS config: bundle match")
        else:
            pending.append(f"Firebase iOS config BUNDLE_ID mismatch: {bid}")
    except Exception as error:
        pending.append(f"Firebase iOS config unreadable: {error}")
else:
    pending.append("Firebase iOS GoogleService-Info.plist missing")

flutter_options = ROOT / "lib/firebase_options.dart"
if flutter_options.exists():
    try:
        dart = flutter_options.read_text(encoding="utf-8")
        matches = dict(re.findall(
            r"static const FirebaseOptions (android|ios)\\s*=\\s*FirebaseOptions\\((.*?)\\n\\s*\\);",
            dart, re.DOTALL,
        ))
        for platform in ("android", "ios"):
            block = matches.get(platform)
            app_id_match = re.search(r"appId:\\s*['\\\"]([^'\\\"]+)['\\\"]", block or "")
            dart_app_id = app_id_match.group(1) if app_id_match else None
            if platform == "android" and android_firebase.exists():
                cfg = json.loads(android_firebase.read_text(encoding="utf-8"))
                clients = [
                    client for client in cfg.get("client", [])
                    if client.get("client_info", {}).get("android_client_info", {})
                        .get("package_name") == EXPECTED
                ]
                native_id = clients[0]["client_info"].get("mobilesdk_app_id") if clients else None
            elif platform == "ios" and ios_firebase.exists():
                with ios_firebase.open("rb") as handle:
                    native_id = plistlib.load(handle).get("GOOGLE_APP_ID")
            else:
                native_id = None
            if dart_app_id and native_id and dart_app_id == native_id:
                print(f"OK  Flutter FirebaseOptions {platform}: App ID match")
            else:
                pending.append(
                    f"Flutter FirebaseOptions {platform}: App ID mismatch "
                    f"(Dart={dart_app_id}, native={native_id})"
                )
        ios_block = matches.get("ios") or ""
        bundle_match = re.search(r"iosBundleId:\\s*['\\\"]([^'\\\"]+)['\\\"]", ios_block)
        if bundle_match and bundle_match.group(1) != EXPECTED:
            pending.append(
                f"Flutter FirebaseOptions iosBundleId mismatch: {bundle_match.group(1)}"
            )
    except Exception as error:
        pending.append(f"Flutter firebase_options.dart read/parse error: {error}")
else:
    pending.append("Firebase generated lib/firebase_options.dart missing")

# The owner manually restored their installed launcher icons.
# A separate master file is NOT required; inspect the actual platform assets
# instead of falsely reporting missing assets/branding/app_icon_real.png.
android_icons = list((ROOT / "android/app/src/main/res").glob("mipmap-*/ic_launcher.png"))
ios_contents = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
if len(android_icons) >= 5 and all(p.stat().st_size > 0 for p in android_icons):
    print("OK  Android launcher icon images present")
else:
    pending.append("Android launcher icons missing or incomplete")
if ios_contents.exists():
    try:
        ios_base = ios_contents.parent
        definitions = json.loads(ios_contents.read_text(encoding="utf-8")).get("images", [])
        referenced = [ios_base / v["filename"] for v in definitions if v.get("filename")]
        if referenced and all(p.is_file() and p.stat().st_size > 0 for p in referenced):
            print(f"OK  iOS AppIcon images present ({len(referenced)} PNGs)")
        else:
            pending.append("iOS AppIcon Contents.json references missing/empty PNG files")
    except Exception as error:
        pending.append(f"iOS AppIcon assets unreadable: {error}")
else:
    pending.append("iOS AppIcon Contents.json missing")

if pending:
    print("\nFirebase/아이콘 후속 조치 (삭제하거나 자동 덮어쓰지 않음):")
    for item in pending:
        print(" - " + item)
if failures:
    print("\n앱 식별자가 아직 모두 일치하지 않습니다.")
    sys.exit(2)
if pending:
    print("\n식별자 코드 확인 완료. 단 Firebase/아이콘 후속 작업 전까지 실기기 QA 완료로 간주하지 마세요.")
    sys.exit(1)
print("\n기본 식별자 및 로컬 Firebase 앱 설정 일치. 실제 로그인/스트리밍은 실기기로 검증하세요.")
sys.exit(0)
