#!/usr/bin/env python3
"""Fails when a log line could put dictated or written text in the system log (PRD R2).

Apple's Logger keeps dynamic strings private unless marked `privacy: .public`. This check
refuses `.public` on values that hold user text, and NSLog or print with interpolation
outside DEBUG code, where they reach the unified log or a console unredacted.
"""
import pathlib
import re
import sys

# Names that hold what the user said or what an AI wrote.
TEXT_NAMES = re.compile(
    r"^(raw|text|transcript|transcription|processed|output|prompt|reply|response|"
    r"content|draft|selection|dictation|spoken|request|input|result|words)$",
    re.IGNORECASE,
)
PUBLIC = re.compile(r"\\\(\s*([A-Za-z_][\w.]*)\s*(?:,[^)]*)?privacy:\s*\.public")
UNREDACTED = re.compile(r"\b(?:NSLog|print)\s*\(.*\\\(")


def violations(path: pathlib.Path) -> list[str]:
    found = []
    debug_depth = 0
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#if DEBUG"):
            debug_depth += 1
        elif stripped.startswith("#if"):
            debug_depth += 1 if debug_depth else 0
        elif stripped.startswith("#endif") and debug_depth:
            debug_depth -= 1
        for name in PUBLIC.findall(line):
            if TEXT_NAMES.match(name.split(".")[-1]):
                found.append(f"{path}:{number}: `{name}` is logged with privacy: .public")
        if not debug_depth and UNREDACTED.search(line):
            found.append(f"{path}:{number}: NSLog or print with interpolation outside DEBUG")
    return found


def main(roots: list[str]) -> int:
    problems = [p for root in roots for f in sorted(pathlib.Path(root).rglob("*.swift")) for p in violations(f)]
    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} log line(s) could expose user text. Log counts or ids, never the text.")
        return 1
    print("No user text in public log lines.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["Hush/Hush"]))
