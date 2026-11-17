#!/usr/bin/env python3
"""Three-way, non-destructive application of the ad Native Validator QA patch.

The user's local worktree may contain additional changes after the GitHub
baseline. First try a real three-way merge, then use tightly scoped semantic
changes ONLY for viewer_ads when the original hunk conflicts.
No checkout, reset, clean, stash, Firebase edits or launcher icon changes.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
from tempfile import TemporaryDirectory
import re
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


def run(args: list[str], *, input_data: str | None = None):
    return subprocess.run(
        args, cwd=ROOT, input=input_data, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )


def git_show(ref: str, path: str) -> str:
    result = run(["git", "show", f"{ref}:{path}"])
    if result.returncode:
        raise ValueError(
            f"Cannot retrieve {ref}:{path}. Run git fetch origin first.\n"
            f"{result.stderr}"
        )
    return result.stdout


def three_way(local: str, base: str, target: str) -> tuple[int, str]:
    with TemporaryDirectory(prefix="kyeobom-ad-merge-") as dirname:
        tmp = Path(dirname)
        a, b, c = (tmp / name for name in ("local", "base", "target"))
        for p, value in ((a, local), (b, base), (c, target)):
            p.write_text(value, encoding="utf-8")
        result = run([
            "git", "merge-file", "--stdout",
            str(a), str(b), str(c),
        ])
        return result.returncode, result.stdout


def update_viewer_ads_safely(source: str) -> str:
    """Only adjust the three requested ad conditions, preserving other edits."""
    updated = source

    # Insert the size guard at method boundaries: no assumptions about
    # newer local banner-request implementation, its callbacks or formatting.
    native_marker = "  void _loadNative() {"
    banner_marker = "  Future<void> _loadBanner() async {"
    if updated.count(native_marker) != 1 or updated.count(banner_marker) != 1:
        raise ValueError("Local ad loader signatures differ; no files changed.")

    n1 = updated.index(native_marker)
    n2 = updated.index(banner_marker)
    if n2 <= n1:
        raise ValueError("Native/banner loader order unexpected; no files changed.")

    native_section = updated[n1:n2]
    if "KyeobomAdPolicy.canFitHomeAd(" not in native_section:
        native_section = native_section.replace(
            native_marker,
            native_marker + """
    if (!mounted || _disposed) return;
    if (!KyeobomAdPolicy.canFitHomeAd(MediaQuery.sizeOf(context).width)) {
      unawaited(_loadBannerSafely());
      return;
    }""",
            1,
        )

    # Protect native template attribution/CTA without clobbering a larger
    # user-defined template height within Google's recommended range.
    sizes = list(re.finditer(r"_adHeight\s*=\s*(\d+)\s*;", native_section))
    if len(sizes) != 1:
        raise ValueError(
            "Cannot locate exactly one native-ad height; no files changed."
        )
    size = int(sizes[0].group(1))
    if not 1 <= size <= 200:
        raise ValueError(
            f"Unexpected locally customized native ad height {size}; "
            "no files changed."
        )
    if size < 160:
        native_section = (
            native_section[:sizes[0].start(1)] + "160" +
            native_section[sizes[0].end(1):]
        )

    updated = updated[:n1] + native_section + updated[n2:]
    n2 = updated.index(banner_marker)
    end = updated.find("\n  void _clearAd()", n2)
    if end < 0:
        raise ValueError("Could not determine banner loader scope; no files changed.")
    banner_section = updated[n2:end]

    if "KyeobomAdPolicy.canFitHomeAd(" not in banner_section:
        banner_section = banner_section.replace(
            banner_marker,
            banner_marker + """
    if (!mounted || _disposed) return;
    if (!KyeobomAdPolicy.canFitHomeAd(MediaQuery.sizeOf(context).width)) {
      // Never crop or overflow the actual 320x50 banner on narrow screens.
      return;
    }""",
            1,
        )
    updated = updated[:n2] + banner_section + updated[end:]

    if ("!KyeobomAdPolicy.canFitHomeAd(" not in native_section or
            "!KyeobomAdPolicy.canFitHomeAd(" not in banner_section):
        raise ValueError("Ad size guards missing after merge; no files changed.")
    return updated


def main() -> int:
    # All four files are planned in memory before any file is modified.
    planned: dict[str, str] = {}
    merged_paths: list[str] = []
    for path in FILES:
        file = ROOT / path
        if not file.is_file():
            raise ValueError(f"Missing local file: {path}. No files changed.")
        staged = run(["git", "diff", "--cached", "--quiet", "--", path])
        if staged.returncode:
            raise ValueError(
                f"Staged local changes found in {path}; refusing to overwrite."
            )
        current = file.read_text(encoding="utf-8")
        ancestor, new = git_show(BASE, path), git_show(HEAD, path)
        if current == new:
            print("이미 적용됨:", path)
            continue

        status, result = three_way(current, ancestor, new)
        if status == 0:
            candidate = result
            method = "3-way"
        elif status == 1 and path == "lib/kyeobom_viewer_ads.dart":
            # The user's viewer_ads is newer than the GitHub baseline.
            # Never replace it with the repository version or accept conflict
            # markers; patch only the native/banner slot guards.
            candidate = update_viewer_ads_safely(current)
            method = "local semantic patch"
        else:
            raise ValueError(
                f"Three-way conflict in {path}; NO files were changed. "
                "Send the file path and current git diff for targeted review."
            )

        if "<<<<<<<" in candidate or ">>>>>>>" in candidate:
            raise ValueError(
                f"Unresolved conflict marker in {path}; no changes made."
            )
        if candidate != current:
            planned[path] = candidate
            merged_paths.append(f"{path} ({method})")

    if not planned:
        print("광고 Native Validator QA 변경이 이미 적용되어 있습니다.")
        return 0

    backup = Path.home() / "Desktop" / (
        "kyeobom_admob_qa_backup_" +
        datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    )
    backup.mkdir(parents=True, exist_ok=False)
    for path in planned:
        saved = backup / path
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / path, saved)

    for path, data in planned.items():
        (ROOT / path).write_text(data, encoding="utf-8")

    print("안전 적용:", ", ".join(merged_paths))
    print("원본 백업:", backup)
    print("앱 아이콘, Firebase, Android ID, iOS Bundle ID, 서명 파일: 변경하지 않음")
    print("다음: flutter test test/kyeobom_ad_policy_test.dart && flutter test")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
