#!/usr/bin/env python3
"""Backend for Syntax Search: reads Dash/Zeal docsets and prints JSON."""

import argparse
import html
import json
import os
import re
import shutil
import sqlite3
import sys
import tarfile
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from urllib.parse import unquote

DASH_ENTRY_RE = re.compile(r"<dash_entry_[^>]*>")
HIDDEN_TYPES = ("File", "Category")

VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
DROP_TAGS = {"script", "style", "noscript", "svg", "nav", "button", "form", "input", "select", "textarea", "iframe", "template", "head", "title", "meta", "link"}
HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6"}
BLOCK_TAGS = {"p", "div", "section", "article", "main", "aside", "blockquote", "pre", "ul", "ol", "li", "dl", "dt", "dd", "table", "thead", "tbody", "tr", "th", "td", "figure", "figcaption", "details", "summary", "hr", "br"} | HEADINGS
KEEP_TAGS = {"p", "br", "hr", "pre", "code", "tt", "kbd", "samp", "var", "b", "strong", "i", "em", "u", "s", "sub", "sup", "ul", "ol", "li", "dl", "dt", "dd", "blockquote", "table", "tr", "th", "td", "a"} | HEADINGS
DROP_CLASSES = ("headerlink", "dashanchor", "permalink", "anchor-link", "sr-only", "visually-hidden", "sidebar", "toc", "breadcrumb")
MAX_BODY_CHARS = 24000


class Node:
    __slots__ = ("tag", "attrs", "children", "parent")

    def __init__(self, tag, attrs=None, parent=None):
        self.tag = tag
        self.attrs = dict(attrs or {})
        self.children = []
        self.parent = parent

    def elements(self):
        return [c for c in self.children if isinstance(c, Node)]

    def classes(self):
        return (self.attrs.get("class") or "").lower().split()

    def walk(self):
        yield self
        for c in self.children:
            if isinstance(c, Node):
                yield from c.walk()

    def dropped(self):
        return self.tag in DROP_TAGS or any(c in DROP_CLASSES for c in self.classes())

    def text(self):
        parts = []
        for c in self.children:
            if isinstance(c, Node):
                if c.dropped():
                    continue
                parts.append(c.text())
                if c.tag in BLOCK_TAGS:
                    parts.append(" ")
            else:
                parts.append(c)
        return "".join(parts)


class TreeBuilder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("document")
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.cur)
        self.cur.children.append(node)
        if tag not in VOID_TAGS:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, attrs, self.cur))

    def handle_endtag(self, tag):
        node = self.cur
        while node is not self.root and node.tag != tag:
            node = node.parent
        if node is not self.root:
            self.cur = node.parent

    def handle_data(self, data):
        if data:
            self.cur.children.append(data)


def parse_html(text: str) -> Node:
    builder = TreeBuilder()
    builder.feed(text)
    builder.close()
    return builder.root


def collapse_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def next_element_sibling(node: Node):
    if node.parent is None:
        return None
    sibs = node.parent.elements()
    idx = sibs.index(node)
    return sibs[idx + 1] if idx + 1 < len(sibs) else None


def heading_level(node: Node) -> int:
    return int(node.tag[1]) if node.tag in HEADINGS else 0


def first_heading(node: Node):
    best = None
    for n in node.walk():
        if n.tag in HEADINGS and not n.dropped() and not any(p.dropped() for p in ancestors(n, node)):
            if best is None or heading_level(n) < heading_level(best):
                best = n
            if heading_level(best) == 1:
                break
    return best


def ancestors(node: Node, stop: Node):
    p = node.parent
    while p is not None and p is not stop:
        yield p
        p = p.parent


def main_container(root: Node) -> Node:
    for n in root.walk():
        if n.attrs.get("role") == "main":
            return n
    for n in root.walk():
        if n.tag in ("main", "article"):
            return n
    for n in root.walk():
        if n.tag == "div" and (n.attrs.get("id") in ("content", "main", "main-content") or {"body", "content", "document", "main"} & set(n.classes())):
            return n
    body = next((n for n in root.walk() if n.tag == "body"), None)
    return body or root


def find_anchor(root: Node, anchor: str):
    if not anchor:
        return None
    wanted = {anchor, unquote(anchor)}
    for n in root.walk():
        if n.attrs.get("id") in wanted or (n.tag == "a" and n.attrs.get("name") in wanted):
            return n
    return None


def is_empty_anchor(node: Node) -> bool:
    return node.tag in ("a", "span") and not collapse_ws(node.text())


def has_content(nodes) -> bool:
    return any(len(collapse_ws(n.text())) > 20 for n in nodes)


def following_until_boundary(start: Node, level: int, include_start: bool):
    out = []
    node = start if include_start else next_element_sibling(start)
    while node is not None:
        if node.tag in HEADINGS and (level == 0 or heading_level(node) <= level):
            break
        if node.tag in ("dt", "section", "article") and not include_start:
            break
        if node.tag == "dl" and has_content(out):
            break
        out.append(node)
        node = next_element_sibling(node)
    return out


def enclosing_section_body(node: Node):
    p = node.parent
    while p is not None:
        if p.tag in ("section", "article") or (p.tag == "div" and "section" in p.classes()):
            h = first_heading(p)
            return [c for c in p.elements() if c is not h]
        if p.tag in ("dd",):
            return [p]
        p = p.parent
    return []


def select_section(root: Node, anchor: str, symbol: str):
    target = find_anchor(root, anchor)
    while target is not None and is_empty_anchor(target):
        nxt = next_element_sibling(target)
        if nxt is None:
            break
        target = nxt

    if target is None:
        container = main_container(root)
        h = first_heading(container)
        return (collapse_ws(h.text()) if h else symbol), [c for c in container.elements() if c is not h]

    if target.tag == "dt":
        sigs = [collapse_ws(target.text())]
        node = next_element_sibling(target)
        while node is not None and node.tag == "dt":
            sigs.append(collapse_ws(node.text()))
            node = next_element_sibling(node)
        body = [node] if node is not None and node.tag == "dd" else []
        if not has_content(body):
            body = enclosing_section_body(target)
        return "\n".join(sigs), body

    if target.tag in HEADINGS:
        return collapse_ws(target.text()), following_until_boundary(target, heading_level(target), False)

    inner = first_heading(target)
    if target.tag in ("section", "article", "div", "dl") and inner is not None:
        level = heading_level(inner)
        body = [c for c in target.elements() if c is not inner and c.tag not in HEADINGS]
        if not any(len(collapse_ws(c.text())) > 20 for c in body):
            body += following_until_boundary(target, level, False)
        return collapse_ws(inner.text()), body

    if target.tag in ("tr", "li", "td"):
        return symbol, [target]

    return symbol, following_until_boundary(target, 0, True)


class Sanitizer:
    def __init__(self, page: PurePosixPath):
        self.page = page
        self.parts = []
        self.size = 0

    def emit(self, s):
        self.parts.append(s)
        self.size += len(s)

    def href(self, raw: str) -> str:
        raw = (raw or "").strip()
        if not raw:
            return ""
        if re.match(r"^[a-z][a-z0-9+.-]*:", raw, re.I):
            return raw
        path, _, frag = raw.partition("#")
        resolved = str(self.page) if not path else os.path.normpath(str(self.page.parent / path))
        return "doc:" + resolved + ("#" + frag if frag else "")

    def render(self, node, in_pre=False):
        if self.size > MAX_BODY_CHARS:
            return
        if isinstance(node, str):
            self.emit(html.escape(node) if in_pre else html.escape(re.sub(r"\s+", " ", node)))
            return
        tag = node.tag
        if node.dropped():
            return
        if tag == "img":
            alt = node.attrs.get("alt")
            if alt:
                self.emit(html.escape(alt))
            return
        if tag == "br":
            self.emit("<br/>")
            return
        if tag == "hr":
            self.emit("<hr/>")
            return

        keep = tag in KEEP_TAGS
        block_wrapper = tag in ("div", "section", "article", "figure", "details", "summary", "main", "aside") and not in_pre
        if keep:
            if tag == "a":
                target = self.href(node.attrs.get("href", ""))
                self.emit(f'<a href="{html.escape(target, quote=True)}">' if target else "<span>")
            elif tag == "pre":
                self.emit('<pre style="font-family: monospace; white-space: pre-wrap">')
            elif tag in ("code", "tt", "kbd", "samp", "var"):
                self.emit('<code style="font-family: monospace">')
            else:
                self.emit(f"<{tag}>")
        elif block_wrapper:
            self.emit("<div>")

        child_pre = in_pre or tag == "pre"
        for c in node.children:
            self.render(c, child_pre)

        if keep:
            if tag == "a":
                self.emit("</a>" if self.href(node.attrs.get("href", "")) else "</span>")
            elif tag in ("code", "tt", "kbd", "samp", "var"):
                self.emit("</code>")
            else:
                self.emit(f"</{tag}>")
        elif block_wrapper:
            self.emit("</div>")


def describe(docset: Path, rel_path: str, symbol: str) -> dict:
    documents = docs_dir(docset)
    rel_path = clean_path(rel_path)
    file_part, _, anchor = rel_path.partition("#")
    file_part = unquote(file_part)
    page = documents / file_part
    if not page.is_file():
        return {"status": "error", "message": f"page not found: {file_part}"}

    root = parse_html(page.read_text(encoding="utf-8", errors="replace"))
    signature, body_nodes = select_section(root, anchor, symbol)

    sanitizer = Sanitizer(PurePosixPath(file_part))
    for n in body_nodes:
        sanitizer.render(n)
    body_html = "".join(sanitizer.parts).strip()
    body_html = re.sub(r"(<div>\s*</div>|<p>\s*</p>|<span>\s*</span>)", "", body_html)
    body_html = re.sub(r"[ \t]{2,}", " ", body_html)

    plain = collapse_ws(" ".join(n.text() for n in body_nodes))
    summary = plain[:280] + ("…" if len(plain) > 280 else "")
    title = first_heading(root)

    return {
        "status": "ok",
        "signature": signature or symbol,
        "html": body_html,
        "summary": summary,
        "pageTitle": collapse_ws(title.text()) if title else "",
        "page": file_part,
        "anchor": anchor,
        "url": (documents / file_part).as_uri() + ("#" + anchor if anchor else ""),
        "truncated": sanitizer.size > MAX_BODY_CHARS,
    }


def docsets_dir() -> Path:
    override = os.environ.get("SYNTAX_SEARCH_DOCSETS")
    if override:
        return Path(override).expanduser()
    data = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(data) / "Zeal" / "Zeal" / "docsets"


def state_file() -> Path:
    cache = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(cache) / "syntax-search" / "current_docset"


def index_path(docset: Path) -> Path:
    return docset / "Contents" / "Resources" / "docSet.dsidx"


def cache_dir() -> Path:
    return state_file().parent


def docs_dir(docset: Path) -> Path:
    resources = docset / "Contents" / "Resources"
    direct = resources / "Documents"
    if direct.is_dir():
        return direct

    archive = resources / "tarix.tgz"
    if not archive.is_file():
        return direct

    target = cache_dir() / "extracted" / docset.stem
    marker = target / ".complete"
    if not marker.is_file() or marker.stat().st_mtime < archive.stat().st_mtime:
        shutil.rmtree(target, ignore_errors=True)
        target.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, "r:gz") as tar:
            try:
                tar.extractall(target, filter="data")
            except TypeError:
                # Python < 3.12 has no extraction filters; the archive comes from the user's own docset dir.
                tar.extractall(target)
        marker.touch()

    found = sorted(target.glob("*.docset/Contents/Resources/Documents"))
    return found[0] if found else direct


def docset_meta(docset: Path) -> dict:
    title, version = docset.stem.replace("_", " "), ""
    try:
        meta = json.loads((docset / "meta.json").read_text(encoding="utf-8"))
        title = str(meta.get("title") or title)
        version = str(meta.get("version") or "")
    except (OSError, ValueError):
        pass
    icon = ""
    for candidate in ("icon@2x.png", "icon.png"):
        if (docset / candidate).is_file():
            icon = str(docset / candidate)
            break
    return {"title": title, "version": version, "icon": icon}


def list_docsets() -> list[dict]:
    root = docsets_dir()
    if not root.is_dir():
        return []
    found = []
    for p in sorted(root.glob("*.docset"), key=lambda x: x.stem.lower()):
        if index_path(p).is_file():
            found.append({"name": p.stem, "path": str(p), **docset_meta(p)})
    return found


def get_active(docsets: list[dict]) -> str:
    names = {d["name"] for d in docsets}
    try:
        name = state_file().read_text().strip()
    except OSError:
        name = ""
    if name in names:
        return name
    if docsets:
        set_active(docsets[0]["name"])
        return docsets[0]["name"]
    return ""


def set_active(name: str) -> None:
    sf = state_file()
    sf.parent.mkdir(parents=True, exist_ok=True)
    sf.write_text(name + "\n")


def clean_path(path: str) -> str:
    return DASH_ENTRY_RE.sub("", path or "")


def read_symbols(docset: Path) -> list[list[str]]:
    db = index_path(docset)
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "searchIndex" in tables:
            placeholders = ",".join("?" * len(HIDDEN_TYPES))
            rows = con.execute(
                f"SELECT name, type, path FROM searchIndex WHERE type NOT IN ({placeholders}) ORDER BY name",
                HIDDEN_TYPES,
            )
        elif "ZTOKEN" in tables:
            rows = con.execute(
                """
                SELECT t.ZTOKENNAME, tt.ZTYPENAME,
                       f.ZPATH || CASE WHEN m.ZANCHOR IS NULL OR m.ZANCHOR = '' THEN '' ELSE '#' || m.ZANCHOR END
                FROM ZTOKEN t
                JOIN ZTOKENTYPE tt ON t.ZTOKENTYPE = tt.Z_PK
                JOIN ZTOKENMETAINFORMATION m ON t.ZMETAINFORMATION = m.Z_PK
                JOIN ZFILEPATH f ON m.ZFILE = f.Z_PK
                ORDER BY t.ZTOKENNAME
                """
            )
        else:
            raise RuntimeError(f"unrecognized docset index schema in {db}")
        return [[n or "", t or "", clean_path(p)] for n, t, p in rows]
    finally:
        con.close()


def cmd_list() -> dict:
    docsets = list_docsets()
    return {"status": "ok", "active": get_active(docsets), "docsets": docsets}


def cmd_symbols(name: str | None) -> dict:
    docsets = list_docsets()
    if not docsets:
        return {"status": "no_docsets", "docsetsDir": str(docsets_dir())}
    name = name or get_active(docsets)
    match = next((d for d in docsets if d["name"] == name), None)
    if match is None:
        return {"status": "error", "message": f"docset not found: {name}"}
    docset = Path(match["path"])
    try:
        symbols = read_symbols(docset)
        documents = docs_dir(docset)
    except (sqlite3.Error, RuntimeError, OSError, tarfile.TarError) as exc:
        return {"status": "error", "message": str(exc)}
    return {
        "status": "ok",
        "docset": name,
        "title": match["title"],
        "version": match["version"],
        "icon": match["icon"],
        "docsDir": str(documents),
        "symbols": symbols,
    }


def cmd_describe(name: str, rel_path: str, symbol: str) -> dict:
    match = next((d for d in list_docsets() if d["name"] == name), None)
    if match is None:
        return {"status": "error", "message": f"docset not found: {name}"}
    try:
        return describe(Path(match["path"]), rel_path, symbol)
    except (OSError, tarfile.TarError) as exc:
        return {"status": "error", "message": str(exc)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Syntax Search docset backend")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--list-docsets", action="store_true")
    group.add_argument("--symbols", nargs="?", const="", metavar="DOCSET")
    group.add_argument("--get-active", action="store_true")
    group.add_argument("--set-active", metavar="DOCSET")
    group.add_argument("--describe", nargs=2, metavar=("DOCSET", "PATH"))
    parser.add_argument("--name", default="", help="symbol name (used as fallback title for --describe)")
    args = parser.parse_args()

    if args.list_docsets:
        out = cmd_list()
    elif args.symbols is not None:
        out = cmd_symbols(args.symbols or None)
    elif args.describe:
        out = cmd_describe(args.describe[0], args.describe[1], args.name)
    elif args.get_active:
        out = {"status": "ok", "active": get_active(list_docsets())}
    else:
        names = {d["name"] for d in list_docsets()}
        if args.set_active not in names:
            out = {"status": "error", "message": f"docset not found: {args.set_active}"}
        else:
            set_active(args.set_active)
            out = {"status": "ok", "active": args.set_active}

    json.dump(out, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0 if out.get("status") != "error" else 1


if __name__ == "__main__":
    sys.exit(main())
