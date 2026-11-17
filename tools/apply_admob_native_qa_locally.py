#!/usr/bin/env python3
"""Apply ONLY the Native Validator QA diff onto the user's existing worktree.

Safe when the local Android/iOS icons, Firebase files, signing settings and
other features have unsaved changes. Refuses overlapping changes; never
switches branches, resets, cleans, stashes or touches private config.
"""
from __future__ import annotations

from datetime import datetime
from difflib import unified_diff
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = "origin/feature/admob-banner-branding-ids-20261117"
HEAD = "origin/fix/admob-native-validator-qa-20261117"
FILES = (
    "lib/kyeobom_ad_policy.dart",
    "lib/kyeobom_screens.dart",
    "lib/kyeobom_viewer_ads.dart",
    "test/kyeobom_ad_policy_test.dart",
)


def git(*args: str, input: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args], cwd=ROOT, text=True, input=input,
        capture_output=True, check=False,
    )


def read_from_ref(ref: str, path: str) -> str:
    result = git("show", f"{ref}:{path}")
    if result.returncode:
        raise RuntimeError(
            f"Git reference unavailable: {ref}:{path}\n"
            f"Run git fetch origin first.\n{result.stderr}"
        )
    return result.stdout


def main() -> int:
    changes = []
    apply_parts = []
    for path in FILES:
        target = ROOT / path
        if not target.is_file():
            raise RuntimeError(f"Missing local file; no changes made: {path}")
        staged = git("diff", "--cached", "--quiet", "--", path)
        if staged.returncode != 0:
            raise RuntimeError(
                f"Staged changes detected in {path}; refuse automatic patch."
            )
        source = read_from_ref(BASE, path)
        destination = read_from_ref(HEAD, path)
        current = target.read_text(encoding="utf-8")
        if current == destination:
            print(f"이미 최신 적용: {path}")
            continue
        part = "".join(unified_diff(
            source.splitlines(keepends=True),
            destination.splitlines(keepends=True),
            fromfile=f"a/{path}",
            tofile=f"b/{path}",
            n=5,
        ))
        if not part:
            continue
        changes.append(path)
        apply_parts.append(part)

    if not changes:
        print("광고 Native Validator QA 코드가 이미 모두 적용돼 있습니다.")
        return 0
    patch = "".join(apply_parts)
    check = git("apply", "--check", "--whitespace=nowarn", "-", input=patch)
    if check.returncode:
        print(
            "현재 브랜치의 변경 사항과 겹쳐 패치할 수 없습니다. "
            "어떤 파일도 변경하지 않았습니다.",
            file=sys.stderr,
        )
        print(check.stderr or check.stdout, file=sys.stderr)
        return 2

    backup = Path.home() / "Desktop" / (
        "kyeobom_admob_qa_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    )
    backup.mkdir(parents=True, exist_ok=False)
    for path in changes:
        save = backup / path
        save.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, save)

    result = git("apply", "--whitespace=nowarn", "-", input=patch)
    if result.returncode:
        print(
            "Git patch unexpectedly failed. Original file backups are at: "
            + str(backup),
            file=sys.stderr,
        )
        print(result.stderr or result.stdout, file=sys.stderr)
        return 2

    print("수정 파일: " + ", ".join(changes))
    print("이전 파일 백업: " + str(backup))
    print("Android/iOS 아이콘, Firebase, Xcode 서명 및 기타 기능은 유지됨")
    print("다음: flutter test test/kyeobom_ad_policy_test.dart && flutter test")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
