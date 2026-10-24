# Pennyworth

A keyboard launcher for macOS in the spirit of Alfred, built to be bent to your
own workflow. Native Swift (AppKit + SwiftUI), no dependencies.

Currently it finds applications and Firefox bookmarks, and is themeable — Tokyo Night by default.

## Build and run

Requires macOS 14+ and the Xcode Command Line Tools (full Xcode not needed).

```sh
make test      # unit tests (PennyworthCore)
make run       # build dist/Pennyworth.app and launch it
make install   # copy to ~/Applications and launch
```

Pennyworth lives in the menu bar (magnifying glass icon) and has no Dock icon.
To start it at login, add it under System Settings → General → Login Items.

## Using it

| Key | Action |
| --- | --- |
| ⌥Space | Show / hide (configurable) |
| ↑ ↓ or ⌃N ⌃P / ⌃J ⌃K | Move selection |
| ↩ | Open |
| ⌘↩ | Reveal app in Finder · copy bookmark URL |
| ⌘1 – ⌘9 | Open the nth visible result |
| ⇥ | Autocomplete the selected result |
| ⎋ | Close |

Multi-word queries match in any order. Pennyworth learns from what you open: pick
Chrome after typing `c` and `c` ranks Chrome higher next time (picks fade over a couple
of months; reset with **Forget Learned Rankings** in the menu bar menu). Learned
rankings are stored in `~/Library/Application Support/Pennyworth/knowledge.json`.

**Firefox bookmarks:** type `b` and a space, then your search (`b vento`). Bookmarks
match by title, and also by URL, folder, tags and Firefox keyword (an exact Firefox
keyword ranks first). ↩ opens a bookmark in Firefox and ⌘↩ copies its URL. Bookmarks
stay in sync while Firefox is running.

**Calculator and units:** `= 24*7` (or just `24*7`) and `3 GB in MB` show the answer;
↩ copies the number and ⌘↩ the whole line. ⇥ puts `= <answer>` back in the search field
to keep calculating. Supports `+ - * / % ^ !`, parentheses, `sqrt`, `log`, `sin`, `round`,
`min`/`max` and friends, `pi` and `e`, hex (`0xff`) and binary (`0b101`). Conversions
cover data (`GB` = 10⁹ bytes, `GiB` = 2³⁰, `Mb` = megabits), length, mass, volume (US),
temperature (`100 f to c`), time, speed, area, energy and angles.

**Themes:** type `theme` and a space (or `theme` then ↩) to browse themes; the selected
one is previewed live and ↩ applies it. `theme sto` filters. Themes can also be switched
from the menu bar icon.

> **Alfred users:** Alfred also defaults to ⌥Space. Alfred doesn't claim its hotkey
> exclusively, so Pennyworth can't detect the clash and both would open — give them
> different shortcuts.

## Configuration

`~/.config/pennyworth/config.json` (or `$XDG_CONFIG_HOME/pennyworth`). Every key is
optional, and changes apply as soon as the file is saved:

```json
{
  "theme": "tokyo-night",
  "hotkey": "option+space",
  "maxVisibleResults": 8,
  "applicationFolders": ["~/Developer/Apps"],
  "firefoxBookmarks": true,
  "bookmarksKeyword": "b"
}
```

- **hotkey** — `+`-separated modifiers (`cmd`, `option`/`alt`, `ctrl`, `shift`) and a key
  (`a`–`z`, `0`–`9`, `space`, `return`, `tab`, `f1`–`f20`, punctuation).
- **applicationFolders** — searched in addition to `/Applications`, `/System/Applications`,
  `~/Applications` and the system CoreServices apps.
- **firefoxBookmarks** — set to `false` to turn bookmark search off. All Firefox
  profiles are read, default profile first.
- **bookmarksKeyword** — what to type before a bookmark search. Set to `""` to mix
  bookmarks into every search instead.

Problems with the config or theme files are listed in the menu bar menu.

## Themes

Built in: Tokyo Night, Tokyo Night Storm, Tokyo Night Moon, Tokyo Night Day,
Catppuccin Mocha, Dracula, Nord.

Add your own as JSON files in `~/.config/pennyworth/themes/`. The file name is the
theme id. The easiest way is to extend an existing theme and override a few colors:

```json
{
  "name": "Tokyo Night Purple",
  "extends": "tokyo-night",
  "colors": { "accent": "#bb9af7", "border": "#bb9af7" },
  "cornerRadius": 14
}
```

A theme without `extends` must set `appearance` (`"dark"` or `"light"`) and every color:

| Color | Used for |
| --- | --- |
| `background` | Window background |
| `border` | Window outline |
| `separator` | Line under the search field |
| `text` / `secondaryText` | Result titles / subtitles |
| `placeholder` | Empty search field hint |
| `accent` | Search icon, caret, symbol icons |
| `match` | Characters matching the query |
| `selectionBackground` / `selectionText` / `selectionSecondaryText` | Selected row |

Colors are `#RRGGBB` or `#RRGGBBAA`. Optional: `cornerRadius` (default 12), `borderWidth` (default 1).
A file named after a built-in theme (e.g. `tokyo-night.json`) replaces it.

## Development

```
Sources/PennyworthCore   UI-free engine: fuzzy matching, providers, themes, config
Sources/Pennyworth       The app: panel, hotkey, SwiftUI views, menu bar
```

Results come from `SearchProvider`s, which the `SearchEngine` queries concurrently and
ranks by score. A provider with a `keyword` is searched only when the query starts with
that word and a space, and then exclusively; otherwise it can offer `suggestions`. To add
a new kind of result, implement `SearchProvider` and register it in `AppDelegate.updateEngine()`.

Debug flags for the app binary (`dist/Pennyworth.app/Contents/MacOS/Pennyworth`):

- `--search <query>` prints ranked results and exits
- `--show [query]` opens the launcher at startup
- `--theme <id>` uses a theme without saving it
- `--type <text>` types into the launcher one key at a time (`↓ ↑ ⇥ ↩` are sent as keys;
  `--type-interval <ms>` sets the pace)
- `--snapshot <file.png>` renders the launcher to an image and quits (no screen recording permission needed)

With `--type` or `--snapshot` the panel is drawn off-screen and never takes keyboard focus,
so scripted runs don't interfere with whatever you're typing.

For example, `--type "fire↓" --snapshot /tmp/out.png` reproduces typing and moving the selection.

The Makefile uses SwiftPM's native build system because the newer default fails on
machines with a malformed SDK in `/Library/Developer/CommandLineTools/SDKs`. Override
with `make SWIFT_FLAGS=` if your toolchain is fine.
