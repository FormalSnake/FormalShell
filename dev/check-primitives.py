#!/usr/bin/env python3
"""Primitive-adoption guard (M48).

Chrome lives in shell/Components: a bordered box is a `Cell` or a `Card`, a
rail is a `Track`, an on/off is a `Switch`. A surface that draws its own
`Rectangle` with a border or a corner radius is drawing chrome a primitive
already owns, which is how six panels ended up with six slightly different
rows before the redesign.

So: every `Rectangle` under the scanned trees that assigns `border.width` or
`radius` is an error, unless the comment block directly above it carries
`primitive-exempt:` and says why. The exemption is a comment rather than a
path list so it travels with the code it describes and cannot go stale.

Run by hand as `dev/check-primitives.py`; `nix flake check` runs it too.
"""

import re
import sys
from pathlib import Path

# The subtrees held to the rule. Everything under shell/Components is the
# primitives themselves, so it is never scanned.
#
# Three subtrees are not on the list yet, each for a stated reason rather
# than because nobody looked:
#   shell/Surfaces/Menu, shell/Surfaces/Notifications  their own M48 passes
#     are landing alongside this one; adding markers to files being rewritten
#     buys a merge conflict and nothing else.
#   shell/Surfaces/Capture  RegionPicker's name list and toolbar are two
#     card-shaped Rectangles that `Card` would draw, but the toolbar's
#     click-absorbing MouseArea spans its chrome and would have to be
#     re-anchored past the card's padding. That needs the `--capture` rig
#     leg to re-verify, which is not this task's rig scope.
SCANNED = [
    "shell/Surfaces/Panels",
    "shell/Surfaces/Bar",
    "shell/Surfaces/Gallery",
]

BANNED = re.compile(r"^\s*(border\.width|radius)\s*:")
OPENER = re.compile(r"^\s*Rectangle\s*\{\s*$")
COMMENT = re.compile(r"^\s*//")
MARKER = "primitive-exempt:"


def exempt(lines, opener_index):
    """True when the comment block directly above the opener claims one."""
    i = opener_index - 1
    while i >= 0 and COMMENT.match(lines[i]):
        if MARKER in lines[i]:
            return True
        i -= 1
    return False


def scan(path):
    lines = path.read_text().splitlines()
    # (depth at which the block opened) for every open Rectangle, and whether
    # that one was exempted.
    rectangles = []
    depth = 0
    problems = []
    for index, line in enumerate(lines):
        stripped = line.split("//", 1)[0]
        if OPENER.match(line):
            rectangles.append((depth, exempt(lines, index)))
        elif rectangles and BANNED.match(line) and depth == rectangles[-1][0] + 1:
            if not rectangles[-1][1]:
                problems.append((index + 1, line.strip()))
        depth += stripped.count("{") - stripped.count("}")
        while rectangles and depth <= rectangles[-1][0]:
            rectangles.pop()
    return problems


def main():
    root = Path(__file__).resolve().parent.parent
    failures = []
    for tree in SCANNED:
        for path in sorted((root / tree).rglob("*.qml")):
            for line_no, text in scan(path):
                failures.append(f"{path.relative_to(root)}:{line_no}: {text}")
    if failures:
        print("Surfaces may not draw their own bordered or rounded Rectangle.")
        print("Use the primitive that already draws it (Cell, Card, Track,")
        print("Switch, ButtonGroup), or put a `// primitive-exempt: <why>`")
        print("comment directly above the Rectangle saying what no primitive")
        print("covers.")
        print("")
        for failure in failures:
            print(failure)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
