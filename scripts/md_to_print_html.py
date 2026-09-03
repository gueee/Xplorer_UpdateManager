#!/usr/bin/env python3
"""Render a Markdown document as a single self-contained, print-optimised HTML file.

Written for the bench documents in docs/ so the Markdown stays the single source of
truth. Open the output in a browser and print or "Save as PDF" — the stylesheet sets
A4 geometry, repeats table headers across page breaks and keeps tables, callouts and
headings from splitting awkwardly.

Supports the Markdown subset those documents use: ATX headings, pipe tables,
blockquote callouts, ordered/unordered/task lists, horizontal rules, and inline
code / bold / italic.

    python scripts/md_to_print_html.py docs/Octopus_V1.1_Wiring.md
    python scripts/md_to_print_html.py docs/Octopus_V1.1_Wiring.md --pdf

With --pdf it also drives headless Chrome or Edge to write a PDF alongside the HTML.
No third-party packages are needed either way.
"""

import html
import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

CSS = """
:root { --rule: #b9bfc7; --rule-soft: #dde1e6; --shade: #eef1f4; --warn: #8a5a00; }

@page { size: A4 portrait; margin: 14mm 13mm 15mm; }

* { box-sizing: border-box; }

html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }

body {
  margin: 0 auto;
  max-width: 190mm;
  padding: 10mm 6mm;
  font-family: "Segoe UI", -apple-system, "Helvetica Neue", Arial, sans-serif;
  font-size: 9.8pt;
  line-height: 1.38;
  color: #14181d;
  hyphens: none;
}

h1 {
  font-size: 17pt;
  line-height: 1.2;
  margin: 0 0 2mm;
  padding-bottom: 2.5mm;
  border-bottom: 2.5px solid #14181d;
  letter-spacing: -0.15pt;
}

h2 {
  font-size: 12.5pt;
  margin: 7mm 0 2.5mm;
  padding-bottom: 1.2mm;
  border-bottom: 1px solid var(--rule);
  break-after: avoid;
  page-break-after: avoid;
  break-inside: avoid;
}

h3 {
  font-size: 10.6pt;
  margin: 5mm 0 2mm;
  break-after: avoid;
  page-break-after: avoid;
  break-inside: avoid;
}

p { margin: 0 0 2.6mm; orphans: 3; widows: 3; }

hr { display: none; }

code {
  font-family: "Cascadia Mono", Consolas, "SF Mono", Menlo, monospace;
  font-size: 0.88em;
  background: #f2f4f6;
  border: 1px solid var(--rule-soft);
  border-radius: 2px;
  padding: 0 0.3em;
  white-space: nowrap;
}

strong { font-weight: 650; }

/* ---- tables ---- */

table {
  width: 100%;
  border-collapse: collapse;
  margin: 0 0 3.5mm;
  font-size: 8.9pt;
  break-inside: auto;
}

thead { display: table-header-group; }
tfoot { display: table-footer-group; }

th {
  background: var(--shade);
  text-align: left;
  font-weight: 650;
  font-size: 8.4pt;
  text-transform: uppercase;
  letter-spacing: 0.3pt;
  border: 1px solid var(--rule);
  padding: 1.5mm 2mm;
}

td {
  border: 1px solid var(--rule-soft);
  border-left-color: var(--rule);
  border-right-color: var(--rule);
  padding: 1.4mm 2mm;
  vertical-align: top;
}

tr { break-inside: avoid; page-break-inside: avoid; }
tbody tr:nth-child(even) td { background: #f8f9fa; }
td code { background: none; border: none; padding: 0; font-size: 0.92em; }

/* ---- callouts ---- */

blockquote {
  margin: 0 0 3.5mm;
  padding: 2.4mm 3mm 2.4mm 3.4mm;
  border: 1px solid #e0cfa6;
  border-left: 3.5px solid #c79a24;
  background: #fdf8ec;
  break-inside: avoid;
  page-break-inside: avoid;
}

blockquote p { margin: 0; }
blockquote strong { color: var(--warn); }

/* ---- lists ---- */

ul, ol { margin: 0 0 3mm; padding-left: 6.5mm; }
li { margin-bottom: 1.4mm; break-inside: avoid; page-break-inside: avoid; }

ul.task { list-style: none; padding-left: 1mm; }

ul.task li { padding-left: 7mm; position: relative; margin-bottom: 2.2mm; }

ul.task li::before {
  content: "";
  position: absolute;
  left: 0;
  top: 0.35em;
  width: 3.6mm;
  height: 3.6mm;
  border: 1.2px solid #4a5560;
  border-radius: 0.6mm;
  background: #fff;
}

/* ---- meta ---- */

.subtitle {
  margin: 0 0 6mm;
  font-size: 8.4pt;
  color: #5b656f;
  letter-spacing: 0.2pt;
}

.appendix { break-before: page; page-break-before: always; }

@media screen {
  body { box-shadow: 0 0 0 1px #e5e8eb; background: #fff; margin: 8mm auto; }
  html { background: #f4f6f8; }
}
"""


def inline(text):
    """Render inline markup, protecting code spans from emphasis processing."""
    spans = []

    def stash(match):
        spans.append(match.group(1))
        return "\x00%d\x00" % (len(spans) - 1)

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", text)
    return re.sub(
        r"\x00(\d+)\x00",
        lambda m: "<code>%s</code>" % html.escape(spans[int(m.group(1))], quote=False),
        text,
    )


def split_row(line):
    cells = line.strip().split("|")
    if cells and not cells[0].strip():
        cells = cells[1:]
    if cells and not cells[-1].strip():
        cells = cells[:-1]
    return [c.strip() for c in cells]


def is_separator(line):
    return bool(re.fullmatch(r"\|[\s:|-]+\|", line.strip()))


def render_table(rows):
    out = ["<table>"]
    header, body = rows[0], rows[1:]
    out.append("<thead><tr>")
    out += ["<th>%s</th>" % inline(c) for c in header]
    out.append("</tr></thead><tbody>")
    for row in body:
        out.append("<tr>")
        out += ["<td>%s</td>" % inline(c) for c in row]
        out.append("</tr>")
    out.append("</tbody></table>")
    return "".join(out)


def convert(md):
    lines = md.split("\n")
    out = []
    para = []
    i = 0

    def flush():
        if para:
            out.append("<p>%s</p>" % inline(" ".join(para)))
            para.clear()

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            flush()
            i += 1
            continue

        if re.fullmatch(r"-{3,}", stripped):
            flush()
            out.append("<hr>")
            i += 1
            continue

        heading = re.match(r"(#{1,4})\s+(.*)", stripped)
        if heading:
            flush()
            level = len(heading.group(1))
            text = heading.group(2)
            cls = ' class="appendix"' if text.lower().startswith("appendix") else ""
            out.append("<h%d%s>%s</h%d>" % (level, cls, inline(text), level))
            i += 1
            continue

        # Pipe table
        if stripped.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                if not is_separator(lines[i]):
                    rows.append(split_row(lines[i]))
                i += 1
            if rows:
                out.append(render_table(rows))
            continue

        # Blockquote callout
        if stripped.startswith(">"):
            flush()
            chunk = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                chunk.append(re.sub(r"^\s*>\s?", "", lines[i]).strip())
                i += 1
            out.append("<blockquote><p>%s</p></blockquote>" % inline(" ".join(chunk)))
            continue

        # Lists
        bullet = re.match(r"([-*])\s+(.*)", stripped)
        number = re.match(r"(\d+)\.\s+(.*)", stripped)
        if bullet or number:
            flush()
            ordered = bool(number)
            items = []
            task = False
            while i < len(lines):
                cur = lines[i]
                cur_stripped = cur.strip()
                if not cur_stripped:
                    # A blank line ends the list unless the next line continues an item.
                    nxt = lines[i + 1] if i + 1 < len(lines) else ""
                    if not (nxt.startswith("  ") and nxt.strip()):
                        break
                    i += 1
                    continue
                match = (
                    re.match(r"\d+\.\s+(.*)", cur_stripped)
                    if ordered
                    else re.match(r"[-*]\s+(.*)", cur_stripped)
                )
                if match:
                    text = match.group(1)
                    box = re.match(r"\[([ xX])\]\s+(.*)", text)
                    if box:
                        task = True
                        text = box.group(2)
                    items.append([text])
                elif cur.startswith("  ") and items:
                    items[-1].append(cur_stripped)
                else:
                    break
                i += 1
            tag = "ol" if ordered else "ul"
            cls = ' class="task"' if task else ""
            out.append("<%s%s>" % (tag, cls))
            out += ["<li>%s</li>" % inline(" ".join(p)) for p in items]
            out.append("</%s>" % tag)
            continue

        para.append(stripped)
        i += 1

    flush()
    return "\n".join(out)


def build(md_path, out_path):
    md = md_path.read_text(encoding="utf-8")
    body = convert(md)

    title_match = re.search(r"^#\s+(.*)$", md, re.MULTILINE)
    title = title_match.group(1) if title_match else md_path.stem

    subtitle = "%s &nbsp;·&nbsp; generated from %s &nbsp;·&nbsp; %s" % (
        "Printable bench copy",
        html.escape(md_path.as_posix().split("/")[-1]),
        date.today().isoformat(),
    )
    # Drop the source H1; it is re-emitted with the subtitle attached.
    body = re.sub(r"^<h1>.*?</h1>\n?", "", body, count=1)

    doc = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<style>%s</style>
</head>
<body>
<h1>%s</h1>
<p class="subtitle">%s</p>
%s
</body>
</html>
""" % (html.escape(title), CSS, inline(title), subtitle, body)

    out_path.write_text(doc, encoding="utf-8")
    return out_path


BROWSERS = [
    r"%ProgramFiles%\Google\Chrome\Application\chrome.exe",
    r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe",
    r"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe",
    r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe",
    r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]


def find_browser():
    for candidate in BROWSERS:
        path = Path(os.path.expandvars(candidate))
        if path.is_file():
            return path
    return None


def to_pdf(html_path, pdf_path):
    """Print the HTML to PDF with headless Chrome/Edge. Returns True on success."""
    browser = find_browser()
    if browser is None:
        print("no Chrome or Edge found; open the HTML and print it manually")
        return False
    profile = Path(os.path.expandvars("%TEMP%" if os.name == "nt" else "/tmp"))
    result = subprocess.run(
        [
            str(browser),
            "--headless",
            "--disable-gpu",
            "--no-first-run",
            "--no-pdf-header-footer",
            "--user-data-dir=%s" % (profile / "md-print-profile"),
            "--print-to-pdf=%s" % pdf_path.resolve(),
            html_path.resolve().as_uri(),
        ],
        capture_output=True,
        text=True,
    )
    if not pdf_path.is_file():
        print("PDF export failed:\n%s" % (result.stderr or result.stdout).strip())
        return False
    return True


def main():
    args = [a for a in sys.argv[1:] if a != "--pdf"]
    want_pdf = "--pdf" in sys.argv
    if not args:
        sys.exit(__doc__)
    src = Path(args[0])
    if not src.is_file():
        sys.exit("not a file: %s" % src)
    dest = Path(args[1]) if len(args) > 1 else src.with_suffix(".print.html")
    build(src, dest)
    print("wrote %s" % dest)

    if want_pdf:
        name = dest.name
        for ext in (".print.html", ".html"):
            if name.endswith(ext):
                name = name[: -len(ext)]
                break
        pdf = dest.with_name(name + ".pdf")
        if to_pdf(dest, pdf):
            print("wrote %s" % pdf)


if __name__ == "__main__":
    main()
