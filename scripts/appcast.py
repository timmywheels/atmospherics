#!/usr/bin/env python3
"""Prints the Sparkle update feed for one Mac release, to attach to its GitHub release as
appcast.xml beside the DMG. The app reads the feed from releases/latest/download/appcast.xml, so
the newest release's feed is the one that counts, and it only needs the newest version.

  python3 -I scripts/appcast.py <version> <build> <dmg> <edSignature> <length> [notes.md] > appcast.xml

With release notes, what's new (from their "**New in" line on, if they have one) shows in the
update window.
"""
import datetime
import html
import re
import sys
from email.utils import format_datetime
from pathlib import Path

version, build, dmg, signature, length = sys.argv[1:6]
notes = Path(sys.argv[6]).read_text() if len(sys.argv) > 6 else ""
url = f"https://github.com/timmywheels/atmospherics/releases/download/v{version}/{Path(dmg).name}"


def notes_html(markdown: str) -> str:
    """The notes' bullets as a list and the rest as paragraphs, with **bold** kept."""
    if "**New in" in markdown:
        markdown = markdown[markdown.index("**New in"):]
    out, items = [], []
    for raw in markdown.splitlines():
        line = raw.strip()
        text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", html.escape(line[2:] if line.startswith("- ") else line))
        if line.startswith("- "):
            items.append(f"<li>{text}</li>")
            continue
        if items:
            out.append("<ul>" + "".join(items) + "</ul>")
            items = []
        if line:
            out.append(f"<p>{text}</p>")
    if items:
        out.append("<ul>" + "".join(items) + "</ul>")
    return "\n".join(out)


description = f"\n      <description><![CDATA[{notes_html(notes)}]]></description>" if notes else ""
print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Atmospherics</title>
    <item>
      <title>Atmospherics {version}</title>
      <pubDate>{format_datetime(datetime.datetime.now(datetime.timezone.utc))}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>{description}
      <enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
  </channel>
</rss>""")
