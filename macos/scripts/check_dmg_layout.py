#!/usr/bin/env python3
"""Check the packaged Finder assets. Visual review remains a release step."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def check_volume(volume: Path, background: Path, expected_app: Path | None = None):
    layout = volume / ".DS_Store"
    if not layout.is_file() or layout.stat().st_size == 0:
        raise ValueError("Finder layout is missing; rebuild without HUSH_DMG_HEADLESS=1")
    packaged_background = volume / ".background" / background.name
    if not packaged_background.is_file():
        raise ValueError("Installer background is missing")
    if hashlib.sha256(packaged_background.read_bytes()).digest() != hashlib.sha256(background.read_bytes()).digest():
        raise ValueError("Installer background is missing or differs from the reviewed asset")
    applications = volume / "Applications"
    if not applications.is_symlink() or applications.readlink() != Path("/Applications"):
        raise ValueError("Applications must be a link to /Applications")
    app_plist = volume / "hush.app/Contents/Info.plist"
    with app_plist.open("rb") as source:
        metadata = plistlib.load(source)
    if expected_app is not None:
        with (expected_app / "Contents/Info.plist").open("rb") as source:
            expected = plistlib.load(source)
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "HushReleaseSlug"):
            if not metadata.get(key) or metadata[key] != expected.get(key):
                raise ValueError(f"DMG app does not match the exported app: {key}")


def check_image(artifact: Path, background: Path, expected_app: Path | None):
    # hdiutil verifies the image checksum while attaching. A fresh read-only
    # mount avoids Finder changing metadata or reusing a user's writable mount.
    with tempfile.TemporaryDirectory(prefix="hush-dmg-layout-") as directory:
        mount = Path(directory) / "volume"
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-verify",
                        "-mountpoint", str(mount), str(artifact.resolve())],
                       check=True, capture_output=True, text=True, timeout=120)
        try:
            check_volume(mount, background, expected_app)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True,
                           capture_output=True, text=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--app", type=Path, help="Require the packaged release identity to match this export")
    args = parser.parse_args()
    try:
        check_image(args.artifact, Path(__file__).with_name("dmg-background.png"), args.app)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"DMG layout: failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        return 1
    print(f"DMG layout assets: passed ({args.artifact}); visual review still required")
    return 0


if __name__ == "__main__":
    sys.exit(main())
