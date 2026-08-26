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

The second rule is the card count. A surface is ONE card (DESIGN.md §1's
separation ladder, rung 5): the frame at its outer edge, and nothing inside
it. A `Card` opened inside another `Card` in the same file is an error with
no exemption, which is what MediaPanel's album-art frame and the launcher's
split preview pane both were before 2026-08-26. Same-file only, so a
component that is itself a `Card` and gets embedded in one elsewhere
(NotificationCard inside the centre) is out of reach here and stays the
reviewer's job; that one carries a `flat` property for exactly this reason.

Run by hand as `dev/check-primitives.py`; `nix flake check` runs it too.
"""

import re
import sys
from pathlib import Path

# The subtrees held to the rule. Everything under shell/Components is the
# primitives themselves, so it is never scanned.
#
# shell/Surfaces/Menu and shell/Surfaces/Notifications are not on the list
# yet: their own M48 passes are landing alongside this one, and adding markers
# to files being rewritten buys a merge conflict and nothing else.
SCANNED = [
    "shell/Surfaces/Panels",
    "shell/Surfaces/Bar",
    "shell/Surfaces/Capture",
    "shell/Surfaces/Gallery",
]

# The card-count rule below is cheap and has no exemptions, so it runs over
# every surface rather than the subset above.
CARD_SCANNED = ["shell/Surfaces"]

BANNED = re.compile(r"^\s*(border\.width|radius)\s*:")
OPENER = re.compile(r"^\s*Rectangle\s*\{\s*$")
CARD_OPENER = re.compile(r"^\s*Card\s*\{\s*$")
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


def nested_cards(path):
    """Line numbers of every `Card {` opened inside another one."""
    lines = path.read_text().splitlines()
    cards = []
    depth = 0
    problems = []
    for index, line in enumerate(lines):
        stripped = line.split("//", 1)[0]
        if CARD_OPENER.match(line):
            if cards:
                problems.append(index + 1)
            cards.append(depth)
        depth += stripped.count("{") - stripped.count("}")
        while cards and depth <= cards[-1]:
            cards.pop()
    return problems


def main():
    root = Path(__file__).resolve().parent.parent
    failures = []
    nested = []
    for tree in CARD_SCANNED:
        for path in sorted((root / tree).rglob("*.qml")):
            for line_no in nested_cards(path):
                nested.append(f"{path.relative_to(root)}:{line_no}")
    for tree in SCANNED:
        for path in sorted((root / tree).rglob("*.qml")):
            for line_no, text in scan(path):
                failures.append(f"{path.relative_to(root)}:{line_no}: {text}")
    if nested:
        print("A surface is one card, and nothing inside it is a card")
        print("(DESIGN.md \u00a71, the separation ladder's rung 5). Mark the")
        print("block off with a Separator, a SectionLabel or space instead.")
        print("")
        for line in nested:
            print(line)
        if failures:
            print("")
    if failures:
        print("Surfaces may not draw their own bordered or rounded Rectangle.")
        print("Use the primitive that already draws it (Cell, Card, Track,")
        print("Switch, ButtonGroup), or put a `// primitive-exempt: <why>`")
        print("comment directly above the Rectangle saying what no primitive")
        print("covers.")
        print("")
        for failure in failures:
            print(failure)
    return 1 if (failures or nested) else 0


if __name__ == "__main__":
    sys.exit(main())
