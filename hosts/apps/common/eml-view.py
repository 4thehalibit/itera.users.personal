#!/usr/bin/env python3
"""Render an .eml (message/rfc822) file to a self-contained HTML page and open
it in the default browser. A lightweight *viewer* — not a mail client.

Usage: eml-view <file.eml>
"""
import base64
import html
import mimetypes
import os
import subprocess
import sys
import tempfile
from email import policy
from email.parser import BytesParser


def esc(value):
    return html.escape(str(value or ""))


def data_uri(part):
    ctype = part.get_content_type() or "application/octet-stream"
    payload = part.get_payload(decode=True) or b""
    return f"data:{ctype};base64," + base64.b64encode(payload).decode("ascii")


def human_size(n):
    size = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            if unit == "B":
                return f"{int(size)} B"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GB"


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: eml-view <file.eml>")
    path = sys.argv[1]
    with open(path, "rb") as fh:
        msg = BytesParser(policy=policy.default).parse(fh)

    # --- headers ---
    header_rows = []
    for label in ("From", "To", "Cc", "Bcc", "Reply-To", "Date", "Subject"):
        val = msg[label]
        if val:
            header_rows.append(
                f'<tr><th>{esc(label)}</th><td>{esc(val)}</td></tr>'
            )
    subject = esc(msg["Subject"] or "(no subject)")

    # --- map inline images (cid:) to data URIs ---
    cid_map = {}
    for part in msg.walk():
        cid = part.get("Content-ID")
        if cid:
            cid_map[cid.strip("<>")] = data_uri(part)

    # --- body: prefer html, fall back to plain text ---
    body_html = None
    try:
        body_part = msg.get_body(preferencelist=("html", "plain"))
    except Exception:
        body_part = None
    if body_part is not None:
        if body_part.get_content_type() == "text/html":
            body_html = body_part.get_content()
            for cid, uri in cid_map.items():
                body_html = body_html.replace(f"cid:{cid}", uri)
        else:
            body_html = f"<pre>{esc(body_part.get_content())}</pre>"
    else:
        body_html = "<p><em>No readable body.</em></p>"

    # --- attachments (skip inline images already rendered) ---
    att_rows = []
    for part in msg.iter_attachments():
        if part.get("Content-ID"):
            continue
        name = part.get_filename() or (
            "attachment" + (mimetypes.guess_extension(part.get_content_type()) or "")
        )
        payload = part.get_payload(decode=True) or b""
        att_rows.append(
            f'<li><a download="{esc(name)}" href="{data_uri(part)}">'
            f"{esc(name)}</a> "
            f'<span class="sz">{esc(human_size(len(payload)))} · '
            f"{esc(part.get_content_type())}</span></li>"
        )
    attachments = (
        f'<section class="atts"><h2>Attachments ({len(att_rows)})</h2>'
        f'<ul>{"".join(att_rows)}</ul></section>'
        if att_rows
        else ""
    )

    doc = f"""<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{subject}</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font: 15px/1.5 system-ui, sans-serif; margin: 0;
         background: Canvas; color: CanvasText; }}
  .hdr {{ padding: 1rem 1.25rem; border-bottom: 1px solid rgba(128,128,128,.3);
          background: color-mix(in srgb, Canvas 92%, gray); }}
  .hdr table {{ border-collapse: collapse; width: 100%; }}
  .hdr th {{ text-align: right; padding: 2px 10px 2px 0; white-space: nowrap;
             vertical-align: top; opacity: .6; font-weight: 600; width: 1%; }}
  .hdr td {{ padding: 2px 0; word-break: break-word; }}
  .body {{ padding: 1.25rem; max-width: 900px; }}
  .body pre {{ white-space: pre-wrap; word-wrap: break-word; font: inherit; }}
  .body img {{ max-width: 100%; height: auto; }}
  .atts {{ padding: 0 1.25rem 1.5rem; max-width: 900px; }}
  .atts h2 {{ font-size: .95rem; opacity: .7; }}
  .atts li {{ margin: .25rem 0; }}
  .sz {{ opacity: .55; font-size: .85em; }}
</style></head>
<body>
  <div class="hdr"><table>{"".join(header_rows)}</table></div>
  <div class="body">{body_html}</div>
  {attachments}
</body></html>"""

    out = tempfile.NamedTemporaryFile(
        "w", suffix=".html", prefix="eml-view-", delete=False, encoding="utf-8"
    )
    out.write(doc)
    out.close()
    subprocess.run(["xdg-open", out.name], check=False)


if __name__ == "__main__":
    main()
