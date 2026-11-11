"""Derive comparison metrics without modifying raw model outputs."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
from statistics import median


def summarize(path):
    raw = json.loads(path.read_text())
    meta, actions = raw["metadata"], raw["actions"]
    assert "error" not in meta, (path, meta.get("error"))
    assert len(actions) == 54, (path, len(actions))
    layout = meta.get("tool_layout", "dispatcher")
    allowed = {tool["function"]["name"] for tool in meta["tools"]}
    action_names = {"insert_draft", "highlight", "preview_moves", "fill_field", "press_element", "answer_only", "clarify"}
    cases = defaultdict(list)
    parsed, schema, semantic, strict = 0, 0, 0, 0
    for row in actions:
        calls = row["parsed_calls"]
        one = len(calls) == 1
        arguments = calls[0].get("arguments", {}) if one else {}
        keys = {"target"} if layout == "named" else {"target", "action"}
        valid = one and calls[0].get("name") in allowed and isinstance(arguments, dict) and set(arguments) == keys
        valid = valid and (arguments["target"] is None or isinstance(arguments["target"], str))
        if valid and layout == "dispatcher":
            valid = arguments["action"] in action_names
        correct = one and calls[0] == row["expected"]
        exact = correct and row["native_format_ok"]
        assert correct == row["decision_ok"] and exact == row["pass"], (path, row["case"], row["seed"])
        if "schema_ok" in row:
            assert bool(valid) == row["schema_ok"], (path, row["case"], "schema mismatch")
        parsed += one
        schema += bool(valid)
        semantic += correct
        strict += exact
        cases[row["case"]].append({"seed": row["seed"], "decision_ok": correct, "strict_ok": exact})
    assert len(cases) == 18
    assert all(sorted(r["seed"] for r in rows) == [0, 1, 2] for rows in cases.values())
    return {
        "raw_file": path.name,
        "raw_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "model_id": meta["model_id"],
        "layout": layout,
        "case_set_sha256": meta["case_set_sha256"],
        "distinct_cases": len(cases),
        "trials": len(actions),
        "single_parsed_call": parsed,
        "schema_valid": schema,
        "correct_decision": semantic,
        "strict_no_prose_success": strict,
        "cases_correct_all_three_seeds": sum(all(r["decision_ok"] for r in rows) for rows in cases.values()),
        "budget_exhausted": sum(row["budget_exhausted"] for row in actions),
        "action_median_seconds": median(row["elapsed_seconds"] for row in actions),
        "action_first_token_median_seconds": median(row["first_token_seconds"] for row in actions),
        "max_mlx_bytes": max(row["mlx_peak_bytes"] for row in actions + raw["drafts"]),
        "artifact_bytes": meta["artifact_bytes"],
        "case_results": {name: {"correct": sum(r["decision_ok"] for r in rows), "strict": sum(r["strict_ok"] for r in rows)} for name, rows in cases.items()},
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("inputs", nargs="+", type=Path)
    args = p.parse_args()
    rows = [summarize(path) for path in args.inputs]
    assert len({row["case_set_sha256"] for row in rows}) == 1, "Different fixture sets"
    report = {"generated_by": "summarize_tasks.py", "interpretation": "18 development cases, three seeds each; not 54 independent tasks. Separate protocols must not be pooled. Correct decision ignores surrounding prose; strict success additionally enforces the no-prose response contract.", "results": rows}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    for row in rows:
        print(row["model_id"], row["layout"], "decision", row["correct_decision"], "strict", row["strict_no_prose_success"], "median", round(row["action_median_seconds"], 3))


if __name__ == "__main__":
    main()
