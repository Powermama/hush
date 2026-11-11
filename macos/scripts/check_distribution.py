#!/usr/bin/env python3
"""Read-only Developer ID checks. Preflight does not predict Apple's acceptance."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def run(*args, required=True):
    result = subprocess.run(args, capture_output=True, text=True)
    if required and result.returncode:
        raise RuntimeError(f"{' '.join(map(str, args))}\n{result.stdout}{result.stderr}")
    return result


def check_signature(metadata, entitlements, team, executable):
    if not re.search(r"^Authority=Developer ID Application:", metadata, re.M):
        raise ValueError("Developer ID Application signature required")
    if f"TeamIdentifier={team}" not in metadata.splitlines():
        raise ValueError("Signing team does not match")
    if not re.search(r"^Timestamp=.+", metadata, re.M):
        raise ValueError("Secure timestamp missing")
    if entitlements.get("com.apple.security.get-task-allow"):
        raise ValueError("Debug entitlement get-task-allow is enabled")
    if executable and not re.search(r"flags=0x[0-9a-f]+\([^)]*runtime", metadata):
        raise ValueError("Executable requires hardened runtime")


def expected_missing_ticket(result):
    """Fail closed on unknown diagnostics, malformed JSON and tool failures."""
    if result.returncode != 70:
        return False
    try:
        findings = json.loads(result.stdout)["output"]
        return bool(findings) and all(
            finding.get("SyspolicyCheckShortError") == "Notary Ticket Missing"
            for finding in findings
        )
    except (ValueError, KeyError, TypeError, AttributeError):
        return False


def inspect_code(path, team, architecture=None, executable=False):
    args = ("--arch", architecture) if architecture else ()
    metadata = run("/usr/bin/codesign", "-d", "--verbose=4", *args, str(path)).stderr
    entitlements = {}
    if architecture:
        raw = run("/usr/bin/codesign", "-d", "--entitlements", ":-", *args, str(path)).stdout
        if raw.strip():
            entitlements = plistlib.loads(raw.encode())
    check_signature(metadata, entitlements, team, executable)
    return {"path": str(path), "architecture": architecture,
            "signature": metadata.splitlines(), "entitlements": entitlements}


def check(artifact, team, phase):
    report = {"artifact": str(artifact), "phase": phase, "team": team, "code": []}
    if artifact.suffix not in (".app", ".dmg") or not artifact.exists():
        raise ValueError("Expected an existing .app or .dmg")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict",
        "--all-architectures", str(artifact))
    if artifact.suffix == ".app":
        info = plistlib.loads((artifact / "Contents/Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != "com.decentralfreedom.hush":
            raise ValueError("Unexpected bundle identifier")
        main_binary = artifact / "Contents/MacOS" / info["CFBundleExecutable"]
        main_arches = run("/usr/bin/lipo", "-archs", str(main_binary)).stdout.split()
        if main_arches != ["arm64"]:
            raise ValueError("Hush releases must be Apple Silicon-only (arm64)")
        # Do not follow framework symlinks and inspect the same executable twice.
        for path in sorted(artifact.rglob("*")):
            if path.is_symlink() or not path.is_file():
                continue
            with path.open("rb") as source:
                magic = source.read(4)
            if magic not in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
                             b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce",
                             b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
                             b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
                continue
            architectures = run("/usr/bin/lipo", "-archs", str(path)).stdout.split()
            if "arm64" not in architectures:
                raise ValueError(f"Nested code does not support Apple Silicon: {path}")
            for arch in architectures:
                header = run("/usr/bin/otool", "-arch", arch, "-hv", str(path)).stdout
                report["code"].append(inspect_code(path, team, arch, "EXECUTE" in header))
        if not report["code"]:
            raise ValueError("No Mach-O binaries found")
        policy = run("/usr/bin/syspolicy_check", "distribution", str(artifact),
                     "--verbose", "--json", required=False)
        report["policy"] = {"exit": policy.returncode, "stdout": policy.stdout, "stderr": policy.stderr}
        if policy.returncode and not (phase == "preflight" and expected_missing_ticket(policy)):
            raise RuntimeError(f"Distribution assessment failed:\n{policy.stdout}{policy.stderr}")
        if phase == "postflight":
            run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", str(artifact))
    else:
        report["code"].append(inspect_code(artifact, team))
        run("/usr/bin/hdiutil", "verify", str(artifact))
        if phase == "postflight":
            run("/usr/sbin/spctl", "--assess", "--type", "open", "--context",
                "context:primary-signature", "--verbose=4", str(artifact))
    if phase == "postflight":
        run("/usr/bin/xcrun", "stapler", "validate", str(artifact))
    report["result"] = "passed"
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--phase", choices=("preflight", "postflight"), default="preflight")
    parser.add_argument("--team", default=os.environ.get("HUSH_DEVELOPMENT_TEAM", "3A22UK7C9L"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = check(args.artifact.resolve(), args.team, args.phase)
    except (RuntimeError, ValueError, OSError, KeyError) as error:
        report = {"artifact": str(args.artifact), "phase": args.phase, "result": "failed", "error": str(error)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2) if report["result"] == "failed" else
          f"{args.phase}: passed ({args.artifact})")
    if report["result"] == "passed" and args.phase == "preflight":
        print("Local checks only. Apple acceptance and final distribution checks are still required.")
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
