import io
import json
import os
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BACKEND = REPO / "docset_index.py"

PAGE = """<!doctype html><html><head><title>demo</title><script>alert(1)</script>
<style>p{}</style></head><body>
<div class="sphinxsidebar"><h3>Table of Contents</h3></div>
<div class="body" role="main">
<h1>Demo module<a class="headerlink" href="#top">¶</a></h1>
<p>Intro paragraph that is long enough to count as content for the guide fallback.</p>
<dl class="py function">
<a class="dashAnchor" name="//apple_ref/Function/demo.run"></a>
<dt class="sig" id="demo.run">demo.<span class="pre">run</span>(x)<a class="headerlink" href="#demo.run">¶</a></dt>
<dd><p>Runs <em>x</em> using <a href="other.html#thing">thing</a> and <a href="#demo.stop">stop</a>.</p>
<pre>run(1)</pre></dd>
</dl>
<h2 id="section-two">Section Two<a class="headerlink" href="#section-two">¶</a></h2>
<p>Second section body text.</p>
<h2 id="section-three">Section Three</h2>
<p>Third section body text.</p>
</div></body></html>
"""

ROWS = [
    ("demo.run", "Function", "index.html#demo.run"),
    ("operator|", "Function", "index.html"),
    ("operator||", "Function", "index.html"),
    ("Section Two", "Section", "<dash_entry_name=Section%20Two>index.html#section-two"),
    ("SomeFile", "File", "index.html"),
]


def make_index(db: Path, rows):
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT)")
    con.executemany("INSERT INTO searchIndex(name, type, path) VALUES (?, ?, ?)", rows)
    con.commit()
    con.close()


def make_plain_docset(root: Path, name: str, title: str):
    docset = root / f"{name}.docset"
    res = docset / "Contents" / "Resources"
    docs = res / "Documents"
    docs.mkdir(parents=True)
    make_index(res / "docSet.dsidx", ROWS)
    (docs / "index.html").write_text(PAGE, encoding="utf-8")
    (docset / "meta.json").write_text(json.dumps({"name": name, "title": title, "version": "1.2.3"}))
    (docset / "icon.png").write_bytes(b"\x89PNG\r\n\x1a\n")
    return docset


def make_tarix_docset(root: Path, name: str):
    docset = root / f"{name}.docset"
    res = docset / "Contents" / "Resources"
    res.mkdir(parents=True)
    make_index(res / "docSet.dsidx", ROWS)
    with tarfile.open(res / "tarix.tgz", "w:gz") as tar:
        data = PAGE.encode("utf-8")
        info = tarfile.TarInfo(f"{name}.docset/Contents/Resources/Documents/index.html")
        info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
    return docset


class BackendTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.docsets = base / "docsets"
        self.docsets.mkdir()
        make_plain_docset(self.docsets, "Demo", "Demo Docs")
        make_tarix_docset(self.docsets, "Packed")
        self.env = dict(os.environ, SYNTAX_SEARCH_DOCSETS=str(self.docsets), XDG_CACHE_HOME=str(base / "cache"))

    def tearDown(self):
        self.tmp.cleanup()

    def run_backend(self, *args, expect_ok=True):
        proc = subprocess.run([sys.executable, str(BACKEND), *args], env=self.env, capture_output=True, text=True)
        if expect_ok:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout)

    def test_list_docsets_reads_meta_and_icon(self):
        out = self.run_backend("--list-docsets")
        self.assertEqual(out["status"], "ok")
        names = [d["name"] for d in out["docsets"]]
        self.assertEqual(names, ["Demo", "Packed"])
        demo = out["docsets"][0]
        self.assertEqual(demo["title"], "Demo Docs")
        self.assertEqual(demo["version"], "1.2.3")
        self.assertTrue(demo["icon"].endswith("icon.png"))
        packed = out["docsets"][1]
        self.assertEqual(packed["title"], "Packed")
        self.assertEqual(packed["icon"], "")
        self.assertEqual(out["active"], "Demo")

    def test_set_active_and_symbols(self):
        self.run_backend("--set-active", "Packed")
        self.assertEqual(self.run_backend("--get-active")["active"], "Packed")
        bad = self.run_backend("--set-active", "Nope", expect_ok=False)
        self.assertEqual(bad["status"], "error")

        out = self.run_backend("--symbols", "Demo")
        self.assertEqual(out["status"], "ok")
        self.assertEqual(out["title"], "Demo Docs")
        names = [s[0] for s in out["symbols"]]
        self.assertIn("operator|", names)
        self.assertIn("operator||", names)
        self.assertNotIn("SomeFile", names)
        section = next(s for s in out["symbols"] if s[0] == "Section Two")
        self.assertEqual(section[2], "index.html#section-two")

    def test_tarix_docset_is_extracted_to_cache(self):
        out = self.run_backend("--symbols", "Packed")
        self.assertEqual(out["status"], "ok")
        docs = Path(out["docsDir"])
        self.assertTrue(str(docs).startswith(self.env["XDG_CACHE_HOME"]))
        self.assertTrue((docs / "index.html").is_file())
        described = self.run_backend("--describe", "Packed", "index.html#demo.run", "--name=demo.run")
        self.assertEqual(described["status"], "ok")

    def test_describe_function_section(self):
        out = self.run_backend("--describe", "Demo", "index.html#demo.run", "--name=demo.run")
        self.assertEqual(out["status"], "ok")
        self.assertEqual(out["signature"], "demo.run(x)")
        self.assertIn("Runs <em>x</em>", out["html"])
        self.assertIn('href="doc:other.html#thing"', out["html"])
        self.assertIn('href="doc:index.html#demo.stop"', out["html"])
        self.assertIn("<pre", out["html"])
        self.assertNotIn("<script", out["html"])
        self.assertNotIn("¶", out["html"])
        self.assertTrue(out["summary"].startswith("Runs x using thing"))
        self.assertEqual(out["pageTitle"], "Demo module")

    def test_describe_heading_section_stops_at_next_heading(self):
        out = self.run_backend("--describe", "Demo", "index.html#section-two", "--name=Section Two")
        self.assertEqual(out["signature"], "Section Two")
        self.assertIn("Second section body text", out["html"])
        self.assertNotIn("Third section body text", out["html"])

    def test_describe_whole_page_without_anchor(self):
        out = self.run_backend("--describe", "Demo", "index.html", "--name=Demo")
        self.assertEqual(out["signature"], "Demo module")
        self.assertIn("Intro paragraph", out["html"])
        self.assertNotIn("Table of Contents", out["html"])

    def test_no_docsets(self):
        env = dict(self.env, SYNTAX_SEARCH_DOCSETS=str(Path(self.tmp.name) / "missing"))
        proc = subprocess.run([sys.executable, str(BACKEND), "--symbols"], env=env, capture_output=True, text=True)
        self.assertEqual(json.loads(proc.stdout)["status"], "no_docsets")
        proc = subprocess.run([sys.executable, str(BACKEND), "--list-docsets"], env=env, capture_output=True, text=True)
        self.assertEqual(json.loads(proc.stdout)["docsets"], [])


if __name__ == "__main__":
    unittest.main()
