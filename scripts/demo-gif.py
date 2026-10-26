"""Helpers for demo-gif.sh.

    demo-gif.py bookmarks <places.sqlite>
        Writes a Firefox bookmarks database with made-up bookmarks.
    demo-gif.py gif <frames dir> <out.gif> <contact-sheet.png>
        Turns the snapshots listed in <frames dir>/frames.tsv into an animated GIF, and
        lays them all out on one image for review.
"""

import sqlite3
import sys
from pathlib import Path

BOOKMARKS = {
    "Dev": [
        ("Swift Documentation", "https://www.swift.org/documentation/"),
        ("Swift Forums", "https://forums.swift.org/"),
        ("The Swift Programming Language", "https://docs.swift.org/swift-book/"),
        ("Apple Developer Documentation", "https://developer.apple.com/documentation/"),
        ("GitHub", "https://github.com/"),
        ("MDN Web Docs", "https://developer.mozilla.org/"),
        ("Stack Overflow", "https://stackoverflow.com/"),
    ],
    "Reading": [
        ("Hacker News", "https://news.ycombinator.com/"),
        ("Wikipedia", "https://en.wikipedia.org/"),
        ("The Rust Programming Language", "https://doc.rust-lang.org/book/"),
    ],
}

BACKDROP = (59, 66, 97)  # Tokyo Night Storm's #3b4261
PADDING, TOP = 32, 28


def bookmarks(path):
    """Just the tables and columns FirefoxBookmarks reads, folders on the toolbar."""
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
        CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER,
            parent INTEGER, position INTEGER, title TEXT, guid TEXT);
        CREATE TABLE moz_keywords (id INTEGER PRIMARY KEY, keyword TEXT, place_id INTEGER);
        INSERT INTO moz_bookmarks (id, type, parent, title, guid) VALUES
            (1, 2, 0, '', 'root________'), (2, 2, 1, 'menu', 'menu________'),
            (3, 2, 1, 'toolbar', 'toolbar_____'), (4, 2, 1, 'tags', 'tags________'),
            (5, 2, 1, 'unfiled', 'unfiled_____');
    """)
    place = 100
    for folder, marks in BOOKMARKS.items():
        folder_id = db.execute(
            "INSERT INTO moz_bookmarks (type, parent, title) VALUES (2, 3, ?)", (folder,)).lastrowid
        for title, url in marks:
            db.execute("INSERT INTO moz_places (id, url, title) VALUES (?, ?, ?)", (place, url, title))
            db.execute(
                "INSERT INTO moz_bookmarks (type, fk, parent, position, title) VALUES (1, ?, ?, ?, ?)",
                (place, folder_id, place, title))
            place += 1
    db.commit()


def gif(frames_dir, out, sheet_path):
    from PIL import Image, ImageDraw, ImageFilter

    frames_dir = Path(frames_dir)
    entries = [line.split("\t", 1) for line in
               (frames_dir / "frames.tsv").read_text(encoding="utf-8").splitlines()]
    shots = [Image.open(frames_dir / f"{index:03d}.png").convert("RGBA") for index in range(len(entries))]
    durations = [int(ms) for ms, _ in entries]

    # Every frame on the same canvas, top-aligned like the real panel, with a soft shadow.
    width = max(shot.width for shot in shots) + 2 * PADDING
    height = max(shot.height for shot in shots) + TOP + PADDING
    frames = []
    for shot in shots:
        shadow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        shadow.paste((0, 0, 0, 255), (PADDING, TOP + 8), shot.split()[3].point(lambda a: int(a * 0.55)))
        canvas = Image.alpha_composite(Image.new("RGBA", (width, height), BACKDROP + (255,)),
                                       shadow.filter(ImageFilter.GaussianBlur(14)))
        canvas.alpha_composite(shot, (PADDING, TOP))
        # No dithering: it speckles flat UI colors and text edges.
        frames.append(canvas.convert("RGB").quantize(256, method=Image.Quantize.MEDIANCUT,
                                                     dither=Image.Dither.NONE))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=durations, loop=0,
                   optimize=True, disposal=1)
    print(f"Wrote {out}: {width}×{height}, {len(frames)} frames, {sum(durations) / 1000:.1f} s")

    # Two columns at full size, so app names and paths are readable.
    label = 18
    rows = [shots[i:i + 2] for i in range(0, len(shots), 2)]
    column = max(shot.width for shot in shots) + 10
    sheet = Image.new("RGB", (2 * column, sum(max(s.height for s in row) + label + 10 for row in rows)),
                      (128, 128, 128))
    draw = ImageDraw.Draw(sheet)
    y = 0
    for r, row in enumerate(rows):
        for c, shot in enumerate(row):
            index = 2 * r + c
            draw.text((c * column + 4, y + 3), f"{index:03d}  \"{entries[index][1]}\"", fill="white")
            sheet.paste(shot, (c * column, y + label), shot)
        y += max(s.height for s in row) + label + 10
    sheet.save(sheet_path)


if __name__ == "__main__":
    command, *arguments = sys.argv[1:]
    {"bookmarks": bookmarks, "gif": gif}[command](*arguments)
