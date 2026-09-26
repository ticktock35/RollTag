#!/usr/bin/env bash
# Build RollTag.app for local use. No Apple Developer account required.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

configuration="Release"
run_tests=0
open_app=0

usage() {
  cat <<'EOF'
Build RollTag (macOS App).

Usage:
  ./scripts/build.sh
  ./scripts/build.sh --debug
  ./scripts/build.sh --test
  ./scripts/build.sh --run

Options:
  --debug   Build the Debug configuration
  --test    Run unit tests after building
  --run     Open the app when the build finishes
  -h        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) configuration="Debug" ;;
    --test) run_tests=1 ;;
    --run) open_app=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "RollTag only builds on a Mac (macOS 14+)." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode from the App Store, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "$developer_dir" || "$developer_dir" == "/Library/Developer/CommandLineTools" ]]; then
  echo "Full Xcode is required (Command Line Tools alone is not enough)." >&2
  echo "Install Xcode, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

derived="$root/build/DerivedData"
mkdir -p "$root/build" "$derived"

common=(
  -project RollTag.xcodeproj
  -scheme RollTag
  -destination "platform=macOS"
  -derivedDataPath "$derived"
  CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual
  DEVELOPMENT_TEAM=
)

echo "Using $(xcodebuild -version | tr '\n' ' ')"
echo "Building RollTag ($configuration)…"

xcodebuild \
  "${common[@]}" \
  -configuration "$configuration" \
  build

product="$derived/Build/Products/$configuration/RollTag.app"
if [[ ! -d "$product" ]]; then
  echo "Build succeeded but RollTag.app was not found at:" >&2
  echo "  $product" >&2
  exit 1
fi

dest="$root/build/RollTag.app"
rm -rf "$dest"
ditto "$product" "$dest"

if [[ "$run_tests" -eq 1 ]]; then
  echo "Running tests…"
  xcodebuild \
    "${common[@]}" \
    -configuration Debug \
    test
fi

echo
echo "App: $dest"
echo "Open it with:"
echo "  open \"$dest\""

if [[ "$open_app" -eq 1 ]]; then
  open "$dest"
fi
