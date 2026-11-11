#!/usr/bin/env python3
"""Read a locally opted-in development trace. No network or desktop actions."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", help="A turn directory; defaults to the latest turn")
    parser.add_argument("--root", type=Path, default=Path.home() / "Library/Application Support/Hush/Development/AssistantTraces")
    parser.add_argument("--content", action="store_true", help="Also print the captured transcript, context, and model output")
    args = parser.parse_args()
    if args.directory:
        directory = Path(args.directory)
    else:
        reports = list(args.root.glob("*/trace.json"))
        if not reports:
            parser.exit(1, "No development trace exists yet. Enable diagnostics and make one assistant request.\n")
        directory = max(reports, key=lambda path: path.stat().st_mtime).parent
    report = json.loads((directory / "trace.json").read_text())
    output = {"directory": str(directory), "trace": report}
    if args.content:
        names = ["transcript.txt", "context.json", "prompt.json", "model-output.txt", "reply.json"]
        names += sorted(name for name in report.get("artifacts", {}) if name.startswith("step-") and name.endswith((".json", ".txt")))
        for name in names:
            path = directory / name
            if path.exists():
                output[name] = path.read_text()
    print(json.dumps(output, indent=2, ensure_ascii=True))


if __name__ == "__main__":
    main()
