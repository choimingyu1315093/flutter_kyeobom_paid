#!/usr/bin/env python3
"""Safely install Android subscription UI/Google Play Billing into PAID repo.

Do not switch branches, alter free repo, run purchases, deploy Firebase,
overwrite local edits, change package ID, signing or advertising.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HEAD = "origin/paid/android-subscriptions-account-20261118"
MAIN = "lib/main.dart"
PUB = "pubspec.yaml"
NEW = (
    "lib/kyeobom_billing_controller.dart",
    "lib/kyeobom_subscription_screen.dart",
    "lib/kyeobom_premium_gate.dart",
    "test/kyeobom_premium_entitlement_test.dart",
    "docs/ANDROID_SUBSCRIPTION_BILLING_20261118.md",
)
OLD_IMPORT = "import 'health_push_messaging.dart';"
NEW_IMPORT = OLD_IMPORT + "\nimport 'kyeobom_subscription_screen.dart';"
OLD_CARD = (
    "          const SizedBox(height: 16),\n"
    "          Container(\n"
    "            padding: const EdgeInsets.all(14),"
)
DEPENDENCIES = (
    "  cloud_functions: ^6.5.1\n"
    "  in_app_purchase: ^3.3.1\n"
    "  in_app_purchase_android: ^0.5.5\n"
    "  crypto: ^3.0.8\n"
    "  url_launcher: ^6.3.3\n"
)


def git(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT,
                          capture_output=True, text=True, check=False)


def remote(path: str) -> str:
    found = git("show", f"{HEAD}:{path}")
    if found.returncode:
        raise ValueError(f"git fetch origin 필요: {path}")
    return found.stdout


def replace_once(text: str, old: str, new: str, name: str) -> str:
    if new in text:
        return text
    if text.count(old) != 1:
        raise ValueError(f"{name}: 로컬 변경과 충돌, 파일을 덮어쓰지 않습니다")
    return text.replace(old, new, 1)


def main() -> None:
    if git("rev-parse", "--verify", HEAD).returncode:
        raise ValueError("git fetch origin 먼저 실행하세요")

    changed: dict[str, str] = {}
    for path in (MAIN, PUB, *NEW):
        file = ROOT / path
        if file.is_symlink() or git("diff", "--cached", "--quiet",
                                    "--", path).returncode:
            raise ValueError(f"대상 staged 변경/링크가 있어 중단: {path}")
        existing = file.read_text(encoding="utf8") if file.is_file() else None
        target = remote(path)
        if path == MAIN:
            if existing is None:
                raise ValueError("paid lib/main.dart 없음")
            updated = replace_once(existing, OLD_IMPORT, NEW_IMPORT,
                                   "paid main imports")
            premium_title = target.index("title: '프리미엄 구독 및 관리'")
            start = target.rfind(
                "          const SizedBox(height: 14),\n"
                "          KyeobomRoleCard(", 0, premium_title
            )
            if start == -1:
                raise ValueError("프리미엄 카드 시작 지점을 찾지 못했습니다")
            end = target.index(OLD_CARD, premium_title)
            inserted = target[start:end] + OLD_CARD
            updated = replace_once(updated, OLD_CARD, inserted,
                                   "paid main premium card")
        elif path == PUB:
            if existing is None:
                raise ValueError("paid pubspec.yaml 없음")
            updated = replace_once(
                existing, "  firebase_auth: ^6.1.0\n",
                "  firebase_auth: ^6.1.0\n" + DEPENDENCIES,
                "paid pubspec dependencies")
        else:
            if existing not in (None, target):
                raise ValueError(f"기존 파일이 달라서 중단: {path}")
            updated = target
        if updated != existing:
            changed[path] = updated
    if not changed:
        print("paid Android 구독 코드가 이미 적용되어 있습니다.")
        return

    backup = Path.home() / "Desktop" / (
        "kyeobom_paid_billing_backup_" +
        datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    )
    backup.mkdir(parents=True, exist_ok=False)
    for path in changed:
        file = ROOT / path
        if file.is_file():
            dest = backup / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, dest)
    for path, content in changed.items():
        file = ROOT / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding="utf8")

    print("paid Android 구독 QA 모듈 반영:", ", ".join(changed))
    print("원본 백업:", backup)
    print("실제 결제 비활성(기본). 운영 Firebase/무료 앱/dev 병합 없음")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print("안전 중단:", error, file=sys.stderr)
        sys.exit(2)
