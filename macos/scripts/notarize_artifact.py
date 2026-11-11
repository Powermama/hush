#!/usr/bin/env python3
"""Explicit submission command, with durable IDs and safe resume after timeouts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

from check_distribution import check, run


def fingerprint(path):
    digest = hashlib.sha256()
    paths = sorted(path.rglob("*")) if path.is_dir() else [path]
    for item in paths:
        digest.update(str(item.relative_to(path) if item != path else item.name).encode())
        digest.update(b"\0")
        if item.is_symlink():
            digest.update(b"link\0" + os.readlink(item).encode())
        elif item.is_file():
            digest.update(b"file\0")
            with item.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            digest.update(b"directory\0")
    return digest.hexdigest()


def save(path, data):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def notarize(artifact, profile, team, reports, resume=None):
    artifact = artifact.resolve()
    check(artifact, team, "preflight")
    reports.mkdir(parents=True, exist_ok=True)
    if run("/usr/bin/xcrun", "stapler", "validate", str(artifact), required=False).returncode == 0:
        check(artifact, team, "postflight")
        print("Already stapled and verified. No submission needed.")
        return
    identity = fingerprint(artifact)
    state_path = reports / f"{artifact.name}-{identity}.json"
    auth = ("--keychain-profile", profile)
    if resume:
        resume = str(uuid.UUID(resume))
        if not state_path.exists() or json.loads(state_path.read_text())["id"] != resume:
            raise ValueError("Resume ID does not match this artifact's saved submission")
        state = json.loads(state_path.read_text())
    else:
        if state_path.exists():
            state = json.loads(state_path.read_text())
            raise ValueError(f"Artifact already submitted. Resume with --resume {state['id']}")
        # The ZIP is only a transport. The app, not this ZIP, gets stapled later.
        with tempfile.TemporaryDirectory(prefix="hush-notary-") as temporary:
            submission = artifact
            if artifact.suffix == ".app":
                submission = Path(temporary) / "hush.zip"
                run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                    str(artifact), str(submission))
            result = run("/usr/bin/xcrun", "notarytool", "submit", str(submission),
                         *auth, "--no-wait", "--output-format", "json")
            state = json.loads(result.stdout)
            state["id"] = str(uuid.UUID(state["id"]))
            state.update(artifact=str(artifact), sha256=identity)
            save(state_path, state)
    submission_id = state["id"]
    print(f"Submission saved: {submission_id}\nReport: {state_path}", flush=True)
    result = run("/usr/bin/xcrun", "notarytool", "wait", submission_id, *auth,
                 "--timeout", os.environ.get("HUSH_NOTARY_TIMEOUT", "15m"),
                 "--output-format", "json", required=False)
    # Query explicitly: command completion alone is not evidence of acceptance.
    status = run("/usr/bin/xcrun", "notarytool", "info", submission_id, *auth,
                 "--output-format", "json", required=False)
    if status.returncode:
        raise RuntimeError(f"Unable to read status. Resume {submission_id}.\n{status.stderr}")
    state["result"] = json.loads(status.stdout)
    save(state_path, state)
    decision = state["result"].get("status")
    if decision in ("Accepted", "Invalid", "Rejected"):
        run("/usr/bin/xcrun", "notarytool", "log", submission_id, *auth,
            str(reports / f"{submission_id}-apple-log.json"))
    if decision != "Accepted":
        raise RuntimeError(f"Apple status: {decision}. Resume with --resume {submission_id}.\n"
                           f"{result.stderr}")
    if fingerprint(artifact) != identity:
        raise RuntimeError("Artifact changed while Apple was checking it; refusing to staple")
    run("/usr/bin/xcrun", "stapler", "staple", str(artifact))
    report = check(artifact, team, "postflight")
    save(reports / f"{submission_id}-postflight.json", report)
    print(f"Accepted, stapled and verified: {artifact}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--resume")
    args = parser.parse_args()
    if os.environ.get("HUSH_NOTARIZE") != "1":
        parser.error("Submission is opt-in. Review the candidate before setting HUSH_NOTARIZE=1.")
    root = Path(__file__).resolve().parent.parent
    try:
        notarize(args.artifact, os.environ.get("HUSH_NOTARY_KEYCHAIN_PROFILE", "HushNotary"),
                 os.environ.get("HUSH_DEVELOPMENT_TEAM", "3A22UK7C9L"),
                 Path(os.environ.get("HUSH_NOTARY_REPORTS", str(root / "artifacts/notarization"))),
                 args.resume)
    except (RuntimeError, ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
