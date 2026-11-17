#!/usr/bin/env python3
"""Idempotent migration for local Gradle/Xcode config after restoring stashes.

This edits only Android namespace/applicationId and Xcode PRODUCT_BUNDLE_IDENTIFIER;
Firebase plugins, signing team, build modes and local private config are preserved.
"""
from __future__ import annotations

from datetime import datetime
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
XCODE = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
TARGET = "com.mingyu.kyeobom"


def replace_one(text: str, field: str) -> str:
    pattern = re.compile(r'(\b' + field + r'\s*=\s*")[^"]+(")')
    result, count = pattern.subn(lambda m: m.group(1) + TARGET + m.group(2), text)
    if count != 1:
        raise ValueError(f"Expected exactly one {field}= in Gradle; found {count}")
    return result


def main() -> None:
    gradle = GRADLE.read_text(encoding="utf-8")
    gradle = replace_one(replace_one(gradle, "namespace"), "applicationId")
    xcode = XCODE.read_text(encoding="utf-8")
    pattern = re.compile(r'(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)([^;]+)(;)')
    found: list[str] = []

    def callback(match: re.Match[str]) -> str:
        current = match.group(2).strip().strip('"')
        test_target = current.endswith(".RunnerTests")
        found.append("tests" if test_target else "runner")
        replacement = TARGET + (".RunnerTests" if test_target else "")
        return match.group(1) + replacement + match.group(3)

    xcode, count = pattern.subn(callback, xcode)
    if count != 6 or found.count("runner") != 3 or found.count("tests") != 3:
        raise ValueError("Xcode bundle ID list differs from expected 3 Runner + 3 RunnerTests entries. No file changed.")

    backup_root = pathlib.Path.home() / "Desktop" / (
        "kyeobom_identity_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    )
    for old in (GRADLE, XCODE):
        save = backup_root / old.relative_to(ROOT)
        save.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(old, save)
    GRADLE.write_text(gradle, encoding="utf-8")
    XCODE.write_text(xcode, encoding="utf-8")
    print("Android namespace/applicationId and iOS Debug/Profile/Release Bundle IDs -> " + TARGET)
    print("원래 파일 백업: " + str(backup_root))
    print("기존 Firebase Gradle plugin, Xcode development team, 서명 설정은 보존했습니다.")
    print("다음: python3 tools/check_kyeobom_platform_identity.py")


if __name__ == "__main__":
    main()
