#!/usr/bin/env python3
"""Check and extract the current AGW release section from CHANGELOG.md."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
VERSION_FILE = ROOT / "VERSION"
DATE_RE = r"\d{4}-\d{2}-\d{2}"


def current_version() -> str:
    return VERSION_FILE.read_text(encoding="utf-8").strip()


def read_changelog() -> str:
    if not CHANGELOG.is_file():
        raise RuntimeError("CHANGELOG.md 不存在")
    return CHANGELOG.read_text(encoding="utf-8")


def section_body(version: str) -> str:
    text = read_changelog()
    heading = re.compile(rf"^## \[{re.escape(version)}\] - {DATE_RE}\s*$", re.MULTILINE)
    matches = list(heading.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(
            f"CHANGELOG.md 必须且只能包含一个带日期的版本标题: ## [{version}] - YYYY-MM-DD"
        )

    start = matches[0].end()
    next_heading = re.search(r"^## ", text[start:], re.MULTILINE)
    end = start + next_heading.start() if next_heading else len(text)
    body = text[start:end].strip()
    if not body:
        raise RuntimeError(f"CHANGELOG.md 中 [{version}] 的内容为空")
    return body


def check() -> int:
    text = read_changelog()
    if re.search(r"^## \[3\.18\.", text, re.MULTILINE):
        raise RuntimeError("CHANGELOG.md 不应包含 3.18 版本条目")
    version = current_version()
    section_body(version)
    print(f"[changelog] {version} 条目有效")
    return 0


def extract(version: str) -> int:
    print(section_body(version))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("check", "extract"))
    parser.add_argument("version", nargs="?")
    args = parser.parse_args()

    try:
        if args.command == "check":
            return check()
        return extract(args.version or current_version())
    except RuntimeError as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
