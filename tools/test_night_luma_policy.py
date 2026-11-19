#!/usr/bin/env python3
"""Compile the actual pure Kotlin/Swift luma policies outside mobile SDKs.
Run from any directory. Requires Python 3 and at least one installed compiler.
This does not test native camera callbacks, encoding, latency or real night scenes.
"""
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
KOTLIN = ROOT / "android/app/src/main/kotlin/com/mingyu/kyeobom/NightLumaPolicy.kt"
SWIFT = ROOT / "ios/Runner/AppDelegate.swift"

def main():
    outputs = {}
    with tempfile.TemporaryDirectory() as temp:
        tmp = pathlib.Path(temp)
        if shutil.which("kotlinc") and shutil.which("java"):
            jar = tmp / "policy.jar"
            subprocess.run(["kotlinc", str(KOTLIN),
                str(ROOT / "tools/night_luma_qa/Test.kt"),
                "-include-runtime", "-d", str(jar)], check=True)
            outputs["Kotlin"] = subprocess.check_output(["java", "-jar", str(jar)])
        if shutil.which("swiftc"):
            source = SWIFT.read_text()
            start = source.index("private final class NightLumaPolicy")
            end = source.index("private final class NightVideoProcessor", start)
            combined = tmp / "main.swift"
            combined.write_text("import Foundation\n" + source[start:end] +
                (ROOT / "tools/night_luma_qa/Test.swift").read_text())
            binary = tmp / "policy"
            subprocess.run(["swiftc", "-O", str(combined), "-o", str(binary)], check=True)
            outputs["Swift"] = subprocess.check_output([str(binary)])
        if not outputs:
            raise SystemExit("Install swiftc or kotlinc + java to test native luma policies.")
        for name, data in outputs.items():
            tables = data.decode().strip().splitlines()
            assert len(tables) == 34
            assert all(len(row.split(",")) == 256 for row in tables)
            print(f"{name}: policy assertions and 34 LUTs passed")
        if len(outputs) == 2:
            assert outputs["Kotlin"] == outputs["Swift"], "Platform LUT mismatch"
            print("Kotlin/Swift: all 8,704 LUT entries identical")
        else:
            print("One compiler unavailable: cross-platform parity not checked.")

if __name__ == "__main__":
    main()
