# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Clemens Kressmann
"""Select CI jobs from a complete git diff. Unknown inputs run all checks."""

import json
import os
from pathlib import Path
import re
import subprocess


# Each deployable web app has its own CI job, named after its folder.
WEB_APPS = ("web", "cms")
REPOSITORY = Path(__file__).resolve().parents[2]


def full_scope():
    return {**dict.fromkeys(WEB_APPS, True), "native": True, "integration": True}


def workspace_dependents(root=REPOSITORY):
    """Map each webapp/packages/<name> folder to the apps that depend on it.

    Read from the workspace manifests, including packages that depend on other
    packages, so a shared change runs exactly the apps that use it.
    """
    webapp = root / "webapp"
    names = {}
    requires = {}
    for manifest in [*webapp.glob("apps/*/package.json"), *webapp.glob("packages/*/package.json")]:
        data = json.loads(manifest.read_text())
        key = f"{manifest.parent.parent.name}/{manifest.parent.name}"
        names[data["name"]] = key
        requires[key] = {dep for section in ("dependencies", "devDependencies")
                         for dep, version in data.get(section, {}).items() if str(version).startswith("workspace:")}
    dependents = {}
    for package in (key for key in requires if key.startswith("packages/")):
        users, frontier = set(), {package}
        while frontier:
            current = frontier.pop()
            for key, deps in requires.items():
                if key not in users and any(names.get(dep) == current for dep in deps):
                    users.add(key)
                    frontier.add(key)
        dependents[package.split("/", 1)[1]] = {key.split("/", 1)[1] for key in users if key.startswith("apps/")}
    return dependents


def classify(paths, dependents=None):
    scope = dict.fromkeys(full_scope(), False)
    for path in paths:
        if path.endswith(".md") or path.startswith(
            ("docs/", "macos/docs/", ".github/ISSUE_TEMPLATE/")
        ) or re.match(r"webapp/(apps|packages)/[^/]+/docs/", path) or Path(path).name in {"LICENSE", "NOTICE"}:
            continue
        if path.startswith("macos/"):
            scope["native"] = scope["integration"] = True
        elif match := re.match(r"webapp/apps/([^/]+)/", path):
            app = match.group(1)
            if app not in WEB_APPS:
                return full_scope()  # A new app must not silently skip CI.
            scope[app] = True
            if app == "web" and path.startswith((
                "webapp/apps/web/server/", "webapp/apps/web/openapi/",
                "webapp/apps/web/shared/contracts/", "webapp/apps/web/shared/provenance/",
            )) or path in {"webapp/apps/web/package.json", "webapp/apps/web/tsconfig.json"}:
                scope["integration"] = True
        elif match := re.match(r"webapp/packages/([^/]+)/", path):
            dependents = workspace_dependents() if dependents is None else dependents
            users = dependents.get(match.group(1))
            if users is None:
                return full_scope()
            for app in users:
                scope[app] = True
        elif path.startswith("webapp/"):
            # Workspace root: manifest, lockfile, Docker and Compose files affect every app.
            scope.update(dict.fromkeys(WEB_APPS, True), integration=True)
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
