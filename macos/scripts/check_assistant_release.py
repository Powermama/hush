#!/usr/bin/env python3
"""Fail if the shipping executable contains the development assistant recorder."""
import argparse
from pathlib import Path


MARKERS = (b"Hush/Development/AssistantTraces", b"--assistant-diagnostics", b"CoworkerTrace", b"CoworkerDiagnostics", b"--inspect-mail-editor", b"--test-mail-editor", b"--preview-assistant-sequence", b"--preview-assistant-progress", b"HUSH_COWORKER_LIVE", b"--inspect-browser", b"--test-browser-controls", b"--test-browser-agent", b"HUSH_OPERATION_AB", b"HUSH_BUNDLED_BROWSER_ACTIONS", b"HUSH_TEST_HOST", b"--hud-spaces")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release", type=Path, help="Release app executable")
    parser.add_argument("--debug", type=Path, help="Optional Debug executable/dylib positive control")
    args = parser.parse_args()
    release = args.release.read_bytes()
    found = [marker.decode() for marker in MARKERS if marker in release]
    if found:
        parser.exit(1, "Development diagnostics leaked into Release: " + ", ".join(found) + "\n")
    if args.debug:
        debug = args.debug.read_bytes()
        missing = [marker.decode() for marker in MARKERS if marker not in debug]
        if missing:
            parser.exit(1, "Debug positive control lacks recorder markers: " + ", ".join(missing) + "\n")
    print("PASS: development recorder markers absent from Release" + (" and present in Debug." if args.debug else "."))


if __name__ == "__main__":
    main()
