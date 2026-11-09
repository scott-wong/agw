#!/usr/bin/env python3
"""Filter, rebrand, and package the pinned APISIX docs for the AGW Dashboard."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
BLACKLIST_FILES = {
    "CHANGELOG.md",
    "upgrade-guide-from-2.15.x-to-3.0.0.md",
}
BRAND_ASSETS = {
    "MA.jpeg",
    "OA.jpg",
    "apache.png",
    "apisix-multi-lang-support.png",
    "apisix-seed.svg",
    "apisix.png",
}
COMMUNITY_URL_MARKERS = (
    "/general/join",
    "/blog/",
    "apache-apisix.netlify.app",
    "contributors-svg",
    "landscape.cncf.io",
    "twitter.com",
    "youtube.com",
)
COMMUNITY_TEXT_MARKERS = (
    "Slack",
    "slack",
    "邮件列表",
    "mailing list",
    "GitHub Discussions",
    "github.com/apache/apisix/discussions",
    "github.com/apache/apisix/issues",
    "社区",
    "Community",
    "contributors",
    "用户实际使用案例",
    "APISIX 的用户有哪些",
    "Who uses APISIX",
    "视频和文章",
    "微信公众号",
)

IMAGE_MD_RE = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)(?:\s+[\"'][^\"']*[\"'])?\)")
IMAGE_HTML_RE = re.compile(
    r"<img\b([^>]*?)\bsrc=[\"']([^\"']+)[\"']([^>]*)>", re.IGNORECASE
)
LINK_MD_RE = re.compile(r"(?<!!)\[([^\]]*)\]\(([^)\s]+)([^)]*)\)")
CODE_RE = re.compile(r"(```.*?```|~~~.*?~~~|`[^`\n]+`)", re.DOTALL)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def strip_frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---\n", 4)
    return text[end + 5 :] if end != -1 else text


def beand_text(text: str) -> str:
    text = re.sub(r"\bApache\s+APISIX\b", "AGW", text, flags=re.IGNORECASE)
    text = re.sub(r"\bAPISIX\b", "AGW", text)
    text = re.sub(r"\bApisix\b", "AGW", text)
    text = text.replace("AGW Dashboard Dashboard", "AGW Dashboard")
    return text


def blacklisted_path(path: Path) -> bool:
    return path.name in BLACKLIST_FILES or path.name in BRAND_ASSETS


def copy_tree(source: Path, target: Path) -> None:
    def ignore(directory: str, names: list[str]) -> set[str]:
        return {name for name in names if name in BLACKLIST_FILES or name in BRAND_ASSETS}

    shutil.copytree(source, target, ignore=ignore)


def local_image_exists(output: Path, page_rel: str, url: str) -> bool:
    if url.startswith("/ui/docs/"):
        return (output / url.removeprefix("/ui/docs/")).is_file()
    if url.startswith("/") or "://" in url:
        return False
    candidate = (output / Path(page_rel).parent / url).resolve()
    try:
        candidate.relative_to(output.resolve())
    except ValueError:
        return False
    return candidate.is_file()


def local_asset_url(output: Path, page_rel: str, url: str) -> str | None:
    if local_image_exists(output, page_rel, url):
        return url
    return None


class ImageStore:
    def __init__(self, output: Path) -> None:
        self.output = output
        self.external_dir = output / "assets" / "external"
        self.external_dir.mkdir(parents=True, exist_ok=True)
        self.manifest: dict[str, dict[str, str]] = {}

    def resolve(self, url: str, page_rel: str) -> str | None:
        local = local_asset_url(self.output, page_rel, url)
        if local:
            return local
        if url.startswith(("data:", "/", "#")):
            return None

        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return None

        source_path = parsed.path
        if "/docs/assets/images/" in source_path:
            name = Path(source_path).name
            if name not in BRAND_ASSETS and (self.output / "assets" / "images" / name).is_file():
                return f"/ui/docs/assets/images/{name}"

        digest = sha256(url.encode("utf-8"))
        suffix = Path(source_path).suffix.lower()
        if suffix in {"", ".jpeg", ".jpg", ".png", ".gif", ".svg", ".webp"}:
            if suffix == "":
                suffix = ".bin"
        else:
            suffix = ".bin"
        target = self.external_dir / f"{digest}{suffix}"
        if target.is_file():
            self.manifest[url] = {"status": "ok", "path": f"/ui/docs/assets/external/{target.name}"}
            return f"/ui/docs/assets/external/{target.name}"

        request = urllib.request.Request(url, headers={"User-Agent": "AGW-docs-builder/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                content = response.read()
                content_type = response.headers.get_content_type()
        except (urllib.error.URLError, TimeoutError, ValueError, OSError):
            self.manifest[url] = {"status": "missing"}
            return None

        if content_type and suffix == ".bin":
            guessed = mimetypes.guess_extension(content_type) or ""
            if guessed:
                suffix = guessed
                target = self.external_dir / f"{digest}{suffix}"
        target.write_bytes(content)
        result = f"/ui/docs/assets/external/{target.name}"
        self.manifest[url] = {"status": "ok", "path": result}
        return result

    def write_manifest(self) -> None:
        (self.external_dir / "manifest.json").write_text(
            json.dumps(self.manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )


def rewrite_url(url: str, output: Path, page_rel: str) -> str | None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return url
    if any(marker in url for marker in COMMUNITY_URL_MARKERS):
        return None
    if "apisix.apache.org" in parsed.netloc:
        match = re.search(r"/(?:zh/)?docs/apisix/(.*?)(#.*)?$", parsed.path)
        if not match:
            return None
        language = "zh" if "/zh/" in parsed.path else "en"
        relative = match.group(1).strip("/")
        anchor = match.group(2) or ""
        if not relative:
            relative = "README"
        if not relative.endswith(".md"):
            relative += ".md"
        candidate = output / language / "latest" / relative
        if not candidate.is_file():
            candidate = output / language / "latest" / relative.replace(".md", "/README.md")
        if not candidate.is_file():
            return None
        return f"/ui/docs/{language}/latest/{relative}{anchor}"
    if parsed.netloc == "github.com" and parsed.path.startswith("/apache/apisix"):
        return None
    if "raw.githubusercontent.com" in parsed.netloc and "/docs/assets/images/" in parsed.path:
        name = Path(parsed.path).name
        if name not in BRAND_ASSETS and (output / "assets" / "images" / name).is_file():
            return f"/ui/docs/assets/images/{name}"
        return None
    return url


def clean_community_lines(text: str) -> str:
    kept: list[str] = []
    for line in text.splitlines():
        if any(marker in line for marker in COMMUNITY_TEXT_MARKERS):
            continue
        kept.append(line)
    return "\n".join(kept).rstrip() + "\n"


def remove_faq_community_tail(text: str) -> str:
    match = re.search(
        r"^## (?:If you have questions|Where can I get|如果在使用).*?(?:help|帮助).*?$",
        text,
        flags=re.MULTILINE | re.IGNORECASE,
    )
    if match:
        text = text[: match.start()]
    return text


def transform_segment(segment: str, output: Path, page_rel: str, images: ImageStore) -> str:
    def image_repl(match: re.Match[str]) -> str:
        alt, url = match.group(1), match.group(2)
        resolved = images.resolve(url, page_rel)
        return f"![{beand_text(alt)}]({resolved})" if resolved else beand_text(alt)

    def html_image_repl(match: re.Match[str]) -> str:
        before, url, after = match.group(1), match.group(2), match.group(3)
        resolved = images.resolve(url, page_rel)
        if not resolved:
            return beand_text(re.sub(r"\s+\balt=[\"'][^\"']*[\"']", "", match.group(0)))
        return f"<img{before}src=\"{resolved}\"{after}>"

    segment = IMAGE_MD_RE.sub(image_repl, segment)
    segment = IMAGE_HTML_RE.sub(html_image_repl, segment)

    def link_repl(match: re.Match[str]) -> str:
        label, url, suffix = match.group(1), match.group(2), match.group(3)
        rewritten = rewrite_url(url, output, page_rel)
        if rewritten is None:
            return label
        return f"[{label}]({rewritten}{suffix})"

    segment = LINK_MD_RE.sub(link_repl, segment)
    segment = re.sub(
        r"https?://apisix\.apache\.org(?:/[^\s)\"']*)?",
        "http://gateway.example.com",
        segment,
    )
    segment = re.sub(
        r"https?://github\.com/apache/apisix(?:[^\s)\"']*)?",
        "https://github.com/scott-wong/agw",
        segment,
    )
    segment = re.sub(
        r"https?://github\.com/apache/apisix-dashboard(?:[^\s)\"']*)?",
        "https://github.com/scott-wong/agw",
        segment,
    )
    return beand_text(segment)


def transform_code(segment: str) -> str:
    segment = re.sub(r"\bApache\s+APISIX\b", "AGW", segment, flags=re.IGNORECASE)
    segment = re.sub(r"\bAPISIX\b", "AGW", segment)
    segment = re.sub(
        r"https?://apisix\.apache\.org(?:/[^\s\"']*)?",
        "http://gateway.example.com",
        segment,
    )
    segment = re.sub(
        r"https?://github\.com/apache/apisix(?:[^\s\"']*)?",
        "https://github.com/scott-wong/agw",
        segment,
    )
    return segment


def transform_markdown(path: Path, output: Path, images: ImageStore) -> None:
    text = strip_frontmatter(path.read_text(encoding="utf-8"))
    page_rel = path.relative_to(output).as_posix()
    if path.name == "FAQ.md":
        text = remove_faq_community_tail(text)
    text = clean_community_lines(text)
    parts = CODE_RE.split(text)
    for index in range(0, len(parts), 2):
        parts[index] = transform_segment(parts[index], output, page_rel, images)
    for index in range(1, len(parts), 2):
        parts[index] = transform_code(parts[index])
    path.write_text("".join(parts), encoding="utf-8")


def sidebar_items(items: list[Any], output: Path, language: str, depth: int = 0) -> list[str]:
    lines: list[str] = []
    indent = "  " * depth
    for item in items:
        if isinstance(item, str):
            item = {"type": "doc", "id": item}
        if not isinstance(item, dict):
            continue
        if item.get("type") == "doc":
            doc = item.get("id", "")
            if not doc or Path(doc).name in BLACKLIST_FILES:
                continue
            target = output / language / "latest" / f"{doc}.md"
            if not target.is_file():
                continue
            label = beand_text(item.get("label") or Path(doc).stem.replace("-", " ").title())
            lines.append(f"{indent}- [{label}]({doc}.md)")
        elif item.get("type") == "category":
            nested = sidebar_items(item.get("items", []), output, language, depth + 1)
            if nested:
                lines.append(f"{indent}- **{beand_text(item.get('label', '更多'))}**")
                lines.extend(nested)
    return lines


def write_sidebar(config: Path, output: Path, language: str) -> None:
    data = json.loads(config.read_text(encoding="utf-8"))
    title = "AGW 文档" if language == "zh" else "AGW Documentation"
    lines = [f"- [{title}](README.md)"]
    lines.extend(sidebar_items(data.get("sidebar", []), output, language))
    (output / language / "latest" / "_sidebar.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def copy_docsify(viewer: Path, output: Path) -> None:
    assets = output / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    shutil.copy2(viewer / "index.html", output / "index.html")
    shutil.copy2(viewer / "agw.css", assets / "agw.css")
    shutil.copy2(viewer / "node_modules/docsify/lib/docsify.min.js", assets / "docsify.min.js")
    shutil.copy2(viewer / "node_modules/docsify/lib/themes/vue.css", assets / "docsify.css")
    license_file = viewer / "node_modules/docsify/LICENSE"
    if license_file.is_file():
        shutil.copy2(license_file, assets / "LICENSE-docsify")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--viewer", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-url", required=True)
    args = parser.parse_args()

    source_docs = args.source / "docs"
    if not source_docs.is_dir():
        raise SystemExit(f"错误: 找不到文档目录 {source_docs}")
    if args.output.exists():
        shutil.rmtree(args.output)
    args.output.mkdir(parents=True)

    copy_tree(source_docs / "zh" / "latest", args.output / "zh" / "latest")
    copy_tree(source_docs / "en" / "latest", args.output / "en" / "latest")
    copy_tree(source_docs / "assets", args.output / "assets")
    shutil.copy2(args.viewer / "home-zh.md", args.output / "zh" / "latest" / "README.md")
    shutil.copy2(args.viewer / "home-en.md", args.output / "en" / "latest" / "README.md")
    copy_docsify(args.viewer, args.output)

    images = ImageStore(args.output)
    for language in ("zh", "en"):
        for path in sorted((args.output / language / "latest").rglob("*.md")):
            if path.name == "_sidebar.md":
                continue
            transform_markdown(path, args.output, images)
        write_sidebar(source_docs / language / "latest" / "config.json", args.output, language)
    images.write_manifest()

    for name in ("LICENSE", "NOTICE"):
        source_file = args.source / name
        if not source_file.is_file():
            raise SystemExit(f"错误: 缺少上游法律文件 {source_file}")
        shutil.copy2(source_file, args.output / name)
    (args.output / "ATTRIBUTION.md").write_text(
        "# 文档来源\n\n"
        f"本目录文档基于 Apache APISIX {args.version} 文档整理，"
        "按 Apache License 2.0 使用。\n\n"
        f"来源：{args.source_url}\n",
        encoding="utf-8",
    )
    print(f"[docs] built {args.version}: {sum(1 for _ in args.output.rglob('*.md'))} markdown files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
