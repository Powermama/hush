# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Clemens Kressmann
"""Select CI jobs from a complete git diff. Unknown inputs run all checks."""

import json
import os
from pathlib import Path
import re
import subprocess


def full_scope():
    return {"web": True, "native": True, "integration": True}


def classify(paths):
    scope = dict.fromkeys(full_scope(), False)
    for path in paths:
        if path.endswith(".md") or path.startswith(
            ("docs/", "macos/docs/", "webapp/apps/web/docs/", ".github/ISSUE_TEMPLATE/")
        ) or Path(path).name in {"LICENSE", "NOTICE"}:
            continue
        if path.startswith("macos/"):
            scope["native"] = scope["integration"] = True
        elif path.startswith("webapp/"):
            scope["web"] = True
            if path.startswith((
                "webapp/apps/web/server/", "webapp/apps/web/openapi/",
                "webapp/apps/web/shared/contracts/", "webapp/apps/web/shared/provenance/",
            )) or path in {
                "webapp/package.json", "webapp/bun.lock",
                "webapp/apps/web/package.json", "webapp/apps/web/tsconfig.json",
            }:
                scope["integration"] = True
        else:
            # CI, root configuration and future components must not silently skip.
            return full_scope()
    return scope


def scope_for_event(event_name, event, cwd=None):
    if event_name == "pull_request":
        base = event.get("pull_request", {}).get("base", {}).get("sha", "")
        head = event.get("pull_request", {}).get("head", {}).get("sha", "")
        comparison = f"{base}...{head}"
    elif event_name == "push":
        base, head = event.get("before", ""), event.get("after", "")
        comparison = f"{base}..{head}"
    else:
        return full_scope(), "Manual or unrecognized event: all checks."
    if not all(isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{40}", sha)
               and sha != "0" * 40 for sha in (base, head)):
        return full_scope(), "No complete comparison range: all checks."
    try:
        changed = subprocess.check_output(
            ["git", "diff", "--name-only", "--no-renames", "-z", comparison, "--"],
            cwd=cwd, stderr=subprocess.PIPE,
        ).decode("utf-8").split("\0")
    except (subprocess.CalledProcessError, UnicodeError):
        return full_scope(), "Comparison unavailable (for example, rewritten history): all checks."
    paths = [path for path in changed if path]
    return classify(paths), f"Compared {len(paths)} changed paths, including deletions."


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    scope, reason = scope_for_event(os.environ["GITHUB_EVENT_NAME"], event)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        for name, enabled in scope.items():
            output.write(f"{name}={str(enabled).lower()}\n")
    print(reason)
    print(json.dumps(scope))
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as output:
            output.write("## Selected checks\n\n" + reason + "\n\n")
            for name, enabled in scope.items():
                output.write(f"- {name}: {'run' if enabled else 'unaffected'}\n")


if __name__ == "__main__":
    main()
