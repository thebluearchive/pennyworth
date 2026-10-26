#!/usr/bin/env bash
# Renders docs/demo.gif (or the path given) by typing example queries into the launcher
# and snapshotting each step.
#
# The app runs against a throwaway home, config and state folder with made-up Firefox
# bookmarks, so your own bookmarks, config and learned rankings stay out of it. Your
# installed apps do show up: look through the contact sheet before committing the GIF.
#
# Needs dist/Pennyworth.app (make app) and Python 3 with Pillow.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$root/dist/Pennyworth.app/Contents/MacOS/Pennyworth"
out="${1:-$root/docs/demo.gif}"
[ -x "$bin" ] || { echo "Build the app first: make app" >&2; exit 1; }
python3 -c 'import PIL' 2>/dev/null || { echo "Needs Pillow: python3 -m pip install Pillow" >&2; exit 1; }

work="$(mktemp -d -t pennyworth-demo)"
frames="$work/frames"
firefox="$work/home/Library/Application Support/Firefox"
mkdir -p "$frames" "$work/state" "$work/config/pennyworth" "$firefox/Profiles/demo"
# An unusual hotkey, so it can't clash with a running Pennyworth.
echo '{"hotkey": "ctrl+option+shift+f19", "maxVisibleResults": 6}' > "$work/config/pennyworth/config.json"
printf '[Profile0]\nName=demo\nIsRelative=1\nPath=Profiles/demo\nDefault=1\n' > "$firefox/profiles.ini"
python3 "$root/scripts/demo-gif.py" bookmarks "$firefox/Profiles/demo/places.sqlite"

export CFFIXED_USER_HOME="$work/home" HOME="$work/home" \
    XDG_CONFIG_HOME="$work/config" XDG_STATE_HOME="$work/state"

count=0
# frame <ms> <text>: the launcher after typing <text>, shown for <ms>.
frame() {
    local png args
    png="$(printf '%s/%03d.png' "$frames" "$count")"
    if [ -n "$2" ]; then args=(--type "$2"); else args=(--show); fi
    echo "  $count: \"$2\""
    # Give up on a frame rather than hang, e.g. on an unexpected alert.
    perl -e 'alarm 30; exec @ARGV' -- "$bin" --snapshot "$png" "${args[@]}" > "${png%.png}.log" 2>&1 \
        || { echo "Frame $count failed; see ${png%.png}.log" >&2; exit 1; }
    printf '%s\t%s\n' "$1" "$2" >> "$frames/frames.tsv"
    count=$((count + 1))
}

# scene <ms> <text>: types <text> one character per frame, then holds the result for <ms>.
scene() {
    local i
    for ((i = 1; i < ${#2}; i++)); do frame 110 "${2:0:i}"; done
    frame "$1" "$2"
}

echo "Rendering frames in $work"
frame 800 ""
scene 1700 "sys set"
frame 350 ""
scene 1500 "= 24*7"
frame 350 ""
scene 1600 "3 GB in MB"
frame 350 ""
scene 1700 "b swift"
frame 350 ""
scene 900 "theme "
frame 800 "theme ↓"
frame 800 "theme ↓↓"
frame 800 "theme ↓↓↓"
frame 1800 "theme ↓↓↓↓"

python3 "$root/scripts/demo-gif.py" gif "$frames" "$out" "$work/contact-sheet.png"
echo "Before committing, check every frame for anything you'd rather not publish:"
echo "  open $work/contact-sheet.png"
