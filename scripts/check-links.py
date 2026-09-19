#!/usr/bin/env python3
"""Fails if a relative link or image in any Markdown file points at something that is not
there. External URLs are not fetched, so this is fast and cannot fail because a site is down."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
pattern = re.compile(r'\]\(([^)#\s]+)(?:#[^)]*)?\)|(?:src|href)="([^"#]+)"')
broken = []
for md in sorted(root.rglob("*.md")):
    if any(part in {".git", "build", "dist", "node_modules"} for part in md.parts) or md.name == "NOTES.md":
        continue
    for match in pattern.finditer(md.read_text(encoding="utf-8")):
        target = match.group(1) or match.group(2)
        if re.match(r"[a-z][a-z0-9+.-]*:", target, re.I):  # http:, mailto:, ...
            continue
        if not (md.parent / target).exists():
            broken.append(f"{md.relative_to(root)}: {target}")
print("\n".join(broken) if broken else "all relative links resolve")
sys.exit(1 if broken else 0)
