"""Download only pinned public evaluation artifacts into an owned temporary folder."""
import argparse
import json
import random
import shutil
import zipfile
from pathlib import Path

from huggingface_hub import hf_hub_download, snapshot_download

MODELS = {
    "gemma": ("mlx-community/gemma-4-e4b-it-4bit", "475b9088d29754a3379866cf5aeb6b41acd313c2"),
    "minicpm": ("mlx-community/MiniCPM-V-4.7-1B-4bit", "13caa569f70e4b68b0ad7dd9574f15a241b34a7d"),
    "eyes": ("deskmind/eyes-4b", "1202bee8b9eea38070c83cadcc7f765e018364d7"),
}
DATASET = "OS-Copilot/ScreenSpot-v2"
REVISION = "5efbb1f1b5463a575f2eb7bc30fe29e49c15f93c"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--model", choices=MODELS)
    args = parser.parse_args()
    args.root.mkdir(parents=True, exist_ok=True)
    if args.model:
        repo, revision = MODELS[args.model]
        if shutil.disk_usage(args.root).free < 7_000_000_000:
            raise RuntimeError("Insufficient headroom for another benchmark model; remove completed temporary weights first")
        path = snapshot_download(repo, revision=revision, local_dir=args.root / args.model,
            allow_patterns=["*.json", "*.jinja", "*.safetensors", "*.txt"], max_workers=2)
        print(json.dumps({"model": args.model, "repo": repo, "revision": revision, "path": path}), flush=True)
        return
    directory = args.root / "dataset"
    labels = hf_hub_download(DATASET, "screenspot_desktop_v2.json", repo_type="dataset", revision=REVISION, local_dir=directory)
    rows = [r for r in json.loads(Path(labels).read_text()) if r["data_source"] == "macos"]
    # Fixed 50/50 text/icon split, sampled before seeing predictions. This is 100
    # targets, not 100 distinct screenshots. Retain source identifiers and hashes.
    rng = random.Random(20261102)
    selected = []
    for kind in ["text", "icon"]:
        group = sorted([r for r in rows if r["data_type"] == kind], key=lambda r: (r["img_filename"], r["instruction"]))
        selected += rng.sample(group, 50)
    rng.shuffle(selected)
    archive = Path(hf_hub_download(DATASET, "screenspotv2_image.zip", repo_type="dataset", revision=REVISION, local_dir=directory))
    images = directory / "images"
    images.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        files = {Path(name).name: name for name in z.namelist() if not name.endswith("/")}
        for row in selected:
            name = row["img_filename"]
            with z.open(files[name]) as source, (images / Path(name).name).open("wb") as destination:
                shutil.copyfileobj(source, destination)
    manifest = {"dataset": DATASET, "revision": REVISION, "seed": 20261102,
        "scope": "100 macOS target queries, 50 text and 50 icons; public benchmark, possible training contamination; no desktop execution",
        "unique_images": len({r["img_filename"] for r in selected}), "cases": selected}
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # Only our downloaded archive; preserve selected evidence until all runs finish.
    archive.unlink()
    print(json.dumps({k: v for k, v in manifest.items() if k != "cases"}), flush=True)


if __name__ == "__main__":
    main()
