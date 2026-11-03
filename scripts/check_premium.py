#!/usr/bin/env python3
"""Validate premium plan structure without claiming any server integration was tested."""
from pathlib import Path
import csv
import re
root = Path(__file__).resolve().parents[1]
docs = sorted(root.joinpath("docs").glob("[2-3][0-9]-*.md"))
premium = [p for p in docs if 21 <= int(p.stem[:2]) <= 36]
assert len(premium) == 16, f"Expected 16 docs (21-36), got {len(premium)}"
for index in range(21, 37):
    assert any(p.stem.startswith(f"{index:02}-") for p in premium), f"Missing {index}"
for doc in premium:
    t = doc.read_text(encoding="utf-8")
    assert t.startswith("# "), f"Missing H1: {doc}"
    assert len(t) >= 1000, f"Doc too short: {doc}"
    for target in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", t):
        if target.startswith(("http://", "https://", "mailto:", "/")):
            continue
        assert (doc.parent / target).exists(), f"Broken link: {doc} -> {target}"
p = root / "docs" / "premium-feature-catalog.csv"
with p.open(encoding="utf-8", newline="") as fh:
    rows = list(csv.DictReader(fh))
assert len(rows) >= 100, f"Expected at least 100 planned features; got {len(rows)}"
assert len({r["feature_id"] for r in rows}) == len(rows), "Duplicate feature ID"
assert all(r["verification"] == "planned_unimplemented" for r in rows), "False verified claim"
assert all(r["release_lane"] in {"F0","F1","F2","F3","F4"} for r in rows), "Bad phase"
assert all(r["risk"] in {"R0","R1","R2","R3","R4"} for r in rows), "Bad risk"
readme = (root / "README.md").read_text(encoding="utf-8")
assert "premium-feature-catalog.csv" in readme, "README not linked"
for target in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", readme):
    if target.startswith(("http://", "https://", "mailto:", "/")):
        continue
    assert (root / target).exists(), f"Broken README link: {target}"
print(f"Premium plan check passed: {len(premium)} docs, {len(rows)} planned features.")
