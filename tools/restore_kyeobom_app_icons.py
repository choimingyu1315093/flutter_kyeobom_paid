#!/usr/bin/env python3
"""Restore the owner's EXISTING Kyeobom artwork to Android/iOS icon assets.

Run on macOS, after checking assets/branding/app_icon_real.png.
Uses built-in 'sips' (no PIL, network, or paid image-generation service).
Never creates or invents artwork. Backs up the currently installed icons.
"""
from __future__ import annotations

from decimal import Decimal
from datetime import datetime
import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = pathlib.Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else (
    ROOT / "assets/branding/app_icon_real.png"
)
IOS_DIR = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_DIR = ROOT / "android/app/src/main/res"
ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def dimensions(path: pathlib.Path) -> tuple[int, int, str]:
    proc = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)],
        check=True, capture_output=True, text=True,
    )
    width = re.search(r"pixelWidth: (\d+)", proc.stdout)
    height = re.search(r"pixelHeight: (\d+)", proc.stdout)
    if width is None or height is None:
        raise ValueError(f"Cannot read pixel dimensions of {path}: {proc.stdout}")
    return int(width.group(1)), int(height.group(1)), proc.stdout


def main() -> int:
    if sys.platform != "darwin" or shutil.which("sips") is None:
        print("This tool must be run on the user's Mac with the built-in sips command.", file=sys.stderr)
        return 2
    if not SOURCE.is_file():
        print(f"원래 앱 아이콘 파일이 없습니다: {SOURCE}", file=sys.stderr)
        print("Mac의 git stash 또는 이전 백업에서 아이콘 원본을 먼저 복원하세요.", file=sys.stderr)
        print("예: git stash list; git stash show --include-untracked --name-only 'stash@{0}'", file=sys.stderr)
        print("기존 이미지 대신 새로운 디자인을 임의로 만들지 않습니다.", file=sys.stderr)
        return 2
    width, height, details = dimensions(SOURCE)
    if width != height or width < 1024:
        print(f"1024x1024 이상의 정사각 PNG 원본이 필요합니다: {width}x{height}", file=sys.stderr)
        return 2
    if "hasAlpha: yes" in details:
        print("주의: 원본 PNG에 alpha 채널이 있습니다. iOS App Store 제출 전 완전 불투명한 아이콘인지 확인하세요.")
    contents_path = IOS_DIR / "Contents.json"
    if not contents_path.exists():
        print("iOS AppIcon Contents.json이 없습니다. 다른 파일은 변경하지 않았습니다.", file=sys.stderr)
        return 2

    content = json.loads(contents_path.read_text(encoding="utf-8"))
    targets: list[tuple[pathlib.Path, int]] = []
    for image in content.get("images", []):
        filename, size, scale = image.get("filename"), image.get("size"), image.get("scale")
        if not filename:
            continue
        if pathlib.Path(filename).name != filename or not filename.endswith(".png"):
            raise ValueError(f"Unsafe iOS icon name: {filename}")
        if not size or not scale or "x" not in size or not scale.endswith("x"):
            raise ValueError(f"Invalid iOS icon size: {image}")
        edge = (Decimal(size.split("x")[0]) * Decimal(scale[:-1]))
        if edge != int(edge):
            raise ValueError(f"Non-integer iOS icon pixel edge: {image}")
        targets.append((IOS_DIR / filename, int(edge)))

    for density, edge in ANDROID_SIZES.items():
        targets.append((ANDROID_DIR / f"mipmap-{density}/ic_launcher.png", edge))
    if not targets:
        print("아이콘 출력 대상이 없습니다. 변경하지 않았습니다.", file=sys.stderr)
        return 2
    backups = pathlib.Path.home() / "Desktop" / (
        "kyeobom_icon_backup_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    )
    backups.mkdir(parents=True, exist_ok=False)

    for dest, size in targets:
        if dest.exists():
            backup = backups / dest.relative_to(ROOT)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dest, backup)

    for dest, size in targets:
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["sips", "-s", "format", "png", "-z", str(size), str(size),
             str(SOURCE), "--out", str(dest)],
            stdout=subprocess.DEVNULL, check=True,
        )
    print(f"기존 아이콘 원본: {SOURCE}")
    print(f"기존 아이콘 백업: {backups}")
    print(f"iOS {len(targets) - len(ANDROID_SIZES)}개 + Android {len(ANDROID_SIZES)}개 아이콘 재생성 완료")
    print("확인: git status --short, 그리고 iPhone/Android 앱을 재설치 후 아이콘을 직접 확인")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
