#!/usr/bin/env python3
"""Applies MawjTVH-specific settings to Flutter's generated platform shells.

Everything here is idempotent: bootstrap.sh may be rerun on an existing
checkout without duplicating permissions or icons.
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
LINUX = ROOT / "linux"
BRANDING = ROOT / "assets" / "branding"

APP_ID = "com.mmbesar.mawjtvh"
APP_LABEL = "MawjTVH"

PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.WAKE_LOCK",
)

DESKTOP_FILE = """[Desktop Entry]
Type=Application
Name=MawjTVH
GenericName=Tvheadend Client
Comment=Tvheadend client with guide, recordings and signal info
Exec=mawjtvh
Icon=mawjtvh
Terminal=false
Categories=AudioVideo;Video;Player;TV;
Keywords=tvheadend;tv;dvr;epg;stream;
StartupWMClass=mawjtvh
"""


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def patch_android_manifest() -> None:
    manifest = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print("  AndroidManifest.xml not found; skipping")
        return

    text = read(manifest)
    missing = [
        permission for permission in PERMISSIONS if permission not in text
    ]
    if missing:
        lines = "".join(
            f'    <uses-permission android:name="{permission}" />\n'
            for permission in missing
        )
        match = re.search(r"<manifest\b[^>]*>", text)
        if not match:
            raise SystemExit("Could not find the <manifest> element")
        text = text[: match.end()] + "\n" + lines + text[match.end() :]

    if "usesCleartextTraffic" not in text:
        text = re.sub(
            r"<application\b",
            '<application\n        android:usesCleartextTraffic="true"',
            text,
            count=1,
        )

    text = re.sub(
        r'android:label="[^"]*"',
        f'android:label="{APP_LABEL}"',
        text,
        count=1,
    )
    write(manifest, text)
    print("  patched AndroidManifest.xml")


def patch_android_gradle() -> None:
    kts = ANDROID / "app" / "build.gradle.kts"
    groovy = ANDROID / "app" / "build.gradle"
    if kts.exists():
        text = read(kts)
        text = re.sub(
            r'applicationId\s*=\s*"[^"]*"',
            f'applicationId = "{APP_ID}"',
            text,
        )
        text = re.sub(
            r"minSdk\s*=\s*(flutter\.minSdkVersion|\d+)",
            "minSdk = 24",
            text,
        )
        write(kts, text)
        print("  patched android/app/build.gradle.kts")
    elif groovy.exists():
        text = read(groovy)
        text = re.sub(
            r'applicationId\s+"[^"]*"',
            f'applicationId "{APP_ID}"',
            text,
        )
        text = re.sub(
            r"minSdkVersion\s+(flutter\.minSdkVersion|\d+)",
            "minSdkVersion 24",
            text,
        )
        write(groovy, text)
        print("  patched android/app/build.gradle")


def patch_android_icons() -> None:
    source = BRANDING / "android"
    res = ANDROID / "app" / "src" / "main" / "res"
    if not source.is_dir() or not res.is_dir():
        print("  launcher icons not found; skipping")
        return

    for directory in sorted(source.iterdir()):
        if not directory.is_dir():
            continue
        destination = res / directory.name
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(directory / "ic_launcher.png", destination / "ic_launcher.png")

    # Flutter templates may ship adaptive icons that would hide our legacy
    # launcher PNGs on Android 8+. Remove them so every device uses MawjTVH.
    for anydpi in res.glob("mipmap-anydpi*"):
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            target = anydpi / name
            if target.exists():
                target.unlink()
    print("  installed Android launcher icons")


def patch_linux() -> None:
    cmake = LINUX / "CMakeLists.txt"
    if cmake.exists():
        text = read(cmake)
        text = re.sub(
            r'set\(APPLICATION_ID\s+"[^"]*"\)',
            f'set(APPLICATION_ID "{APP_ID}")',
            text,
        )
        write(cmake, text)
        print("  patched linux/CMakeLists.txt")

    runner = LINUX / "runner" / "my_application.cc"
    if runner.exists():
        text = read(runner)
        text = text.replace(
            'gtk_header_bar_set_title(header_bar, "mawjtvh");',
            'gtk_header_bar_set_title(header_bar, "MawjTVH");',
        )
        text = text.replace(
            'gtk_window_set_title(window, "mawjtvh");',
            'gtk_window_set_title(window, "MawjTVH");',
        )
        text = text.replace(
            "gtk_window_set_default_size(window, 1280, 720);",
            "gtk_window_set_default_size(window, 1280, 820);",
        )
        write(runner, text)
        print("  patched linux/runner/my_application.cc")


def write_desktop_entry() -> None:
    write(BRANDING / "mawjtvh.desktop", DESKTOP_FILE)


def main() -> int:
    if not ANDROID.is_dir() and not LINUX.is_dir():
        print("No generated platform directories found. Run tool/bootstrap.sh first.")
        return 1

    print("Configuring MawjTVH platform shells:")
    patch_android_manifest()
    patch_android_gradle()
    patch_android_icons()
    patch_linux()
    write_desktop_entry()
    print("Platform configuration complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
