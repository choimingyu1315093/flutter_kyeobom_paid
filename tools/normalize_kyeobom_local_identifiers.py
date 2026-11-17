#!/usr/bin/env python3
"""Migrate identifiers in-place WITHOUT switching branches or losing local work.

Only changes Android namespace/applicationId, Kotlin MainActivity package/path
and iOS Runner + RunnerTests bundle IDs. Preserves icon PNGs, Firebase files,
Gradle plugins, Xcode capabilities, signing team and app logic. Always backs up
the original files to the Desktop before writing.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
GRADLE = ROOT / "android/app/build.gradle.kts"
XCODE = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
OLD_MAIN = ROOT / "android/app/src/main/kotlin/com/example/flutter_home_camera/MainActivity.kt"
NEW_MAIN = ROOT / "android/app/src/main/kotlin/com/mingyu/kyeobom/MainActivity.kt"
TARGET = "com.mingyu.kyeobom"
ALLOWED_RUNNER = {"com.example.flutterHomeCamera", TARGET}
ALLOWED_TEST = {"com.example.flutterHomeCamera.RunnerTests", TARGET + ".RunnerTests"}


def replace_one(text: str, field: str) -> str:
    pattern = re.compile(r'(\b' + field + r'\s*=\s*")[^"]+(")')
    result, count = pattern.subn(
        lambda m: m.group(1) + TARGET + m.group(2), text
    )
    if count != 1:
        raise ValueError(
            f"Expected exactly one {field}= in Android Gradle; found {count}"
        )
    return result


def main() -> None:
    # Validate every possible changed file before writing anything.
    gradle_original = GRADLE.read_text(encoding="utf-8")
    gradle_new = replace_one(
        replace_one(gradle_original, "namespace"), "applicationId"
    )

    xcode_original = XCODE.read_text(encoding="utf-8")
    found = {"runner": 0, "tests": 0}

    def update_bundle(match: re.Match[str]) -> str:
        current = match.group(2).strip().strip('"')
        if current in ALLOWED_RUNNER:
            found["runner"] += 1
            replacement = TARGET
        elif current in ALLOWED_TEST:
            found["tests"] += 1
            replacement = TARGET + ".RunnerTests"
        else:
            # Do NOT modify unrelated extensions/targets or unknown bundle IDs.
            return match.group(0)
        return match.group(1) + replacement + match.group(3)

    pattern = re.compile(
        r'(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)([^;]+)(;)'
    )
    xcode_new = pattern.sub(update_bundle, xcode_original)
    if found != {"runner": 3, "tests": 3}:
        raise ValueError(
            f"Xcode Runner/RunnerTests targets differ from expected: {found}. "
            "No files were changed. Check project.pbxproj manually."
        )

    old_exists, new_exists = OLD_MAIN.exists(), NEW_MAIN.exists()
    if old_exists and new_exists:
        raise ValueError(
            "Both old and new MainActivity.kt exist. "
            "No files were changed; inspect the duplicate manually."
        )
    if not old_exists and not new_exists:
        raise ValueError(
            "No Android MainActivity.kt found. "
            "No files were changed; check current Kotlin package path."
        )
    source = OLD_MAIN if old_exists else NEW_MAIN
    kotlin_original = source.read_text(encoding="utf-8")
    package = re.compile(r'(?m)^package\s+[^\n]+$')
    current_package = package.search(kotlin_original)
    if current_package is None or current_package.group(0) not in (
        "package com.example.flutter_home_camera",
        "package com.mingyu.kyeobom",
    ):
        raise ValueError(
            f"Unexpected MainActivity package in {source}; no files changed."
        )
    kotlin_new, pkg_count = package.subn("package " + TARGET, kotlin_original, count=1)
    if pkg_count != 1:
        raise ValueError("MainActivity.kt package update failed.")
    if "class MainActivity" not in kotlin_new:
        raise ValueError("Kotlin MainActivity class not found; no files changed.")

    # Full original-file backup. Never touch icons, Firebase or Podfiles.
    backup_root = Path.home() / "Desktop" / (
        "kyeobom_identity_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    )
    backup_root.mkdir(parents=True, exist_ok=False)
    for original in (GRADLE, XCODE, source):
        dest = backup_root / original.relative_to(ROOT)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(original, dest)

    GRADLE.write_text(gradle_new, encoding="utf-8")
    XCODE.write_text(xcode_new, encoding="utf-8")
    NEW_MAIN.parent.mkdir(parents=True, exist_ok=True)
    NEW_MAIN.write_text(kotlin_new, encoding="utf-8")
    if old_exists:
        OLD_MAIN.unlink()
    print("Android namespace, applicationId, Kotlin package/path:", TARGET)
    print("iOS Runner Bundle ID:", TARGET)
    print("iOS RunnerTests Bundle ID:", TARGET + ".RunnerTests")
    print("Original file backup:", backup_root)
    print("App icons, Firebase files, signing team, plugins and app logic: untouched")
    print("Next: python3 tools/check_kyeobom_platform_identity.py")


if __name__ == "__main__":
    main()
