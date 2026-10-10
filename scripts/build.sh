#!/usr/bin/env bash
# Build RollTag.app for local use. No Apple Developer account required.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

configuration="Release"
run_tests=0
open_app=0
install_app=0

usage() {
  cat <<'EOF'
Build RollTag (macOS App).

Usage:
  ./scripts/build.sh
  ./scripts/build.sh --debug
  ./scripts/build.sh --test
  ./scripts/build.sh --run
  ./scripts/build.sh --install

Options:
  --debug    Build the Debug configuration
  --test     Run unit tests after building
  --run      Open the app when the build finishes
  --install  Copy to /Applications (or ~/Applications) and open it.
             Finder lists it there. macOS Apps / Gemini grids often hide unsigned local builds.
  -h         Show this help

A Release build also writes build/RollTag.zip (app + first-launch note)
for GitHub Releases.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) configuration="Debug" ;;
    --test) run_tests=1 ;;
    --run) open_app=1 ;;
    --install) install_app=1 ;;
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

zip=""
if [[ "$configuration" == "Release" ]]; then
  dist="$root/build/dist/RollTag"
  rm -rf "$root/build/dist"
  mkdir -p "$dist"
  ditto "$dest" "$dist/RollTag.app"
  cp "$root/scripts/first-launch.txt" "$dist/第一次打開.txt"
  zip="$root/build/RollTag.zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$dist" "$zip"
fi

if [[ "$run_tests" -eq 1 ]]; then
  echo "Running tests…"
  xcodebuild \
    "${common[@]}" \
    -configuration Debug \
    test
fi

install_dest=""
if [[ "$install_app" -eq 1 ]]; then
  if [[ -d /Applications && -w /Applications ]]; then
    install_dest="/Applications/RollTag.app"
  else
    mkdir -p "$HOME/Applications"
    install_dest="$HOME/Applications/RollTag.app"
  fi
  rm -rf "$install_dest"
  ditto "$dest" "$install_dest"
  xattr -cr "$install_dest" 2>/dev/null || true
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$install_dest" >/dev/null 2>&1 || true
  fi
  if [[ ! -d "$install_dest" ]]; then
    echo "Install failed: $install_dest was not created." >&2
    exit 1
  fi
fi

echo
echo "App: $dest"
if [[ -n "$zip" ]]; then
  echo "Zip for GitHub Releases: $zip"
  echo "Paste scripts/github-release-notes.md into the Release description so people see Gatekeeper steps before they download."
fi
if [[ -n "$install_dest" ]]; then
  echo "Installed: $install_dest"
  echo "Finder → Applications has it. macOS Apps / Gemini icon grids often hide unsigned local builds."
  echo "Search in that grid, open Finder’s Applications folder, or drag the app to the Dock."
  echo "Opening it now."
  open "$install_dest"
elif [[ "$open_app" -eq 1 ]]; then
  echo "Opening this repo build (not in Applications):"
  echo "  $dest"
  open "$dest"
else
  echo "This copy is only in the repo build folder. Finder → Applications will not show it until you install."
  echo "To copy it there and open it:"
  echo "  ./scripts/build.sh --install"
  echo "Open this copy with:"
  echo "  open \"$dest\""
fi
