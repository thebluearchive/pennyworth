#!/usr/bin/env bash
# Builds dist/Pennyworth.app from the SwiftPM executable.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
config="${CONFIG:-release}"
# Intentionally unquoted below so multiple flags split.
swift_flags="${SWIFT_FLAGS:-}"

cd "$root"
# shellcheck disable=SC2086
swift build $swift_flags -c "$config" --product Pennyworth
# shellcheck disable=SC2086
bin="$(swift build $swift_flags -c "$config" --show-bin-path)/Pennyworth"

app="$root/dist/Pennyworth.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Pennyworth"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

# Ad-hoc signature so macOS treats it as a stable, launchable bundle.
codesign --force --sign - "$app" >/dev/null
echo "Built $app"
