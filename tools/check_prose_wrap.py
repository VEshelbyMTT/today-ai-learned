"""Find, and optionally repair, prose that is hard-wrapped mid-sentence in Markdown.

One paragraph is one line. A line that continues the previous line's text is a
wrap, wherever it appears: plain paragraphs, list items, block quotes and
front matter all count. Only fenced code and table rows are exempt, because
neither can hold wrapped prose.

A sentence split across a blank line is also flagged, since that is the other
way to defeat the check.

Findings report the file, line and rule name only.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence

EXCLUDED_DIRECTORIES = {".git", ".venv", "__pycache__", ".pytest_cache", "private"}

FENCE = re.compile(r"^\s*(```|~~~)")
HEADING = re.compile(r"^\s{0,3}#{1,6}(\s|$)")
LIST_MARKER = re.compile(r"^\s*([-*+]|\d+[.)])\s")
HORIZONTAL_RULE = re.compile(r"^\s{0,3}([-*_])(\s*\1){2,}\s*$")
SETEXT_UNDERLINE = re.compile(r"^\s{0,3}(=+|-+)\s*$")
LINK_DEFINITION = re.compile(r"^\s{0,3}\[[^\]]+\]:\s")
TABLE_ROW = re.compile(r"^\s*\|")
HTML_START = re.compile(r"^\s*<")
YAML_KEY = re.compile(r"^\s*[\w.-]+\s*:(\s|$)")
BLOCK_SCALAR = re.compile(r":\s*[|>][+-]?\d?\s*$")
SENTENCE_END = ".!?:;)]}\"'`*_>|"

CONTINUATION = "wrapped-line"
SPLIT = "split-sentence"


def _normalise(text: str) -> tuple[list[str], str]:
    newline = "\r\n" if "\r\n" in text else "\n"
    return text.replace("\r\n", "\n").split("\n"), newline


def _is_block_start(line: str) -> bool:
    return bool(
        HEADING.match(line)
        or LIST_MARKER.match(line)
        or HORIZONTAL_RULE.match(line)
        or SETEXT_UNDERLINE.match(line)
        or LINK_DEFINITION.match(line)
        or TABLE_ROW.match(line)
        or HTML_START.match(line)
        or FENCE.match(line)
    )


def _quote_depth(line: str) -> tuple[int, str]:
    depth = 0
    rest = line
    while True:
        match = re.match(r"^\s{0,3}>\s?", rest)
        if not match:
            return depth, rest
        depth += 1
        rest = rest[match.end():]


def classify(lines: Sequence[str]) -> list[tuple[int, str]]:
    """Return (zero-based line index, rule) for every violation."""
    found: list[tuple[int, str]] = []
    index = 0
    previous_kind = "blank"
    previous_last_char = ""
    previous_depth = 0
    in_fence = False
    in_comment = False

    if lines and lines[0].strip() == "---":
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
        if end is not None:
            in_block_scalar = False
            previous_has_value = False
            for i in range(1, end):
                line = lines[i]
                if not line.strip():
                    previous_has_value = False
                    continue
                if in_block_scalar:
                    if line.startswith((" ", "\t")):
                        continue
                    in_block_scalar = False
                if YAML_KEY.match(line) and not line.startswith((" ", "\t")):
                    in_block_scalar = bool(BLOCK_SCALAR.search(line))
                    previous_has_value = not in_block_scalar
                    continue
                is_plain_continuation = (
                    line.startswith((" ", "\t"))
                    and not line.lstrip().startswith("- ")
                    and not YAML_KEY.match(line)
                )
                if is_plain_continuation and previous_has_value:
                    found.append((i, CONTINUATION))
                previous_has_value = True
            index = end + 1

    while index < len(lines):
        raw = lines[index]
        if in_comment:
            if "-->" in raw:
                in_comment = False
            index += 1
            continue
        if FENCE.match(raw):
            in_fence = not in_fence
            previous_kind = "blank"
            previous_last_char = ""
            index += 1
            continue
        if in_fence:
            index += 1
            continue
        if raw.lstrip().startswith("<!--"):
            if "-->" not in raw:
                in_comment = True
            previous_kind = "blank"
            previous_last_char = ""
            index += 1
            continue

        depth, line = _quote_depth(raw)
        if not line.strip():
            previous_kind = "blank"
            index += 1
            continue

        starts_block = _is_block_start(line)
        is_list_item = bool(LIST_MARKER.match(line))

        if not starts_block and previous_kind == "text" and depth == previous_depth:
            found.append((index, CONTINUATION))
        elif (
            not starts_block
            and previous_kind == "blank"
            and previous_last_char
            and previous_last_char not in SENTENCE_END
            and line.strip()[:1].islower()
            and depth == previous_depth
        ):
            found.append((index, SPLIT))

        if starts_block and not is_list_item:
            previous_kind = "structure"
            previous_last_char = ""
        else:
            previous_kind = "text"
            previous_last_char = "" if is_list_item else line.rstrip()[-1:]
        previous_depth = depth
        index += 1

    return found


def scan(text: str) -> list[tuple[int, str]]:
    """Return (one-based line number, rule) for each violation in the text."""
    lines, _ = _normalise(text)
    return [(i + 1, rule) for i, rule in classify(lines)]


def unwrap(text: str) -> str:
    """Join wrapped lines onto the line they continue. Split sentences are left alone."""
    lines, newline = _normalise(text)
    continuations = {i for i, rule in classify(lines) if rule == CONTINUATION}
    output: list[str] = []
    for i, line in enumerate(lines):
        if i in continuations and output:
            _, content = _quote_depth(line)
            output[-1] = output[-1].rstrip(" \\") + " " + content.strip()
        else:
            output.append(line)
    return newline.join(output)


def markdown_files(root: Path) -> list[Path]:
    return sorted(
        p for p in root.rglob("*.md")
        if not EXCLUDED_DIRECTORIES & set(p.relative_to(root).parts)
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("paths", nargs="*", type=Path, help="Markdown files; default is every file in the repository")
    parser.add_argument("--fix", action="store_true", help="Join wrapped lines in place")
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parents[1]
    paths = args.paths or markdown_files(root)
    failures = 0
    for path in paths:
        text = path.read_bytes().decode("utf-8")
        if args.fix:
            fixed = unwrap(text)
            if fixed != text:
                path.write_bytes(fixed.encode("utf-8"))
                print(f"fixed: {path}")
            text = fixed
        for line_number, rule in scan(text):
            failures += 1
            print(f"{path}:{line_number}: {rule}")
    if failures:
        print(f"{failures} prose-wrap finding(s). One paragraph is one line.")
        return 1
    print("Prose wrap check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
