#!/usr/bin/env bash
#
# Aria installer — builds from source, installs to /Applications, and registers
# a login agent so Aria auto-starts and stays running in the background (menu
# bar, no terminal needed).
#
#   curl -fsSL https://raw.githubusercontent.com/coderarush/Aria/main/install.sh | bash
#
set -euo pipefail

REPO_URL="https://github.com/coderarush/Aria.git"
APP_NAME="Aria"
LABEL="com.aria.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo ""
echo "  Installing Aria — your AI agent for the Mac"
echo ""

# 1. macOS only.
if [ "$(uname)" != "Darwin" ]; then
  echo "  Aria runs on macOS only." >&2
  exit 1
fi

# 2. Toolchain (Xcode Command Line Tools provide git + swift).
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  echo "  Xcode Command Line Tools are required to build Aria."
  echo "  Run this, then re-run the installer:"
  echo ""
  echo "      xcode-select --install"
  echo ""
  exit 1
fi
command -v git >/dev/null 2>&1 || { echo "  git is required." >&2; exit 1; }

# 3. Build in a throwaway checkout.
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
echo "  → Fetching source…"
git clone --depth 1 "$REPO_URL" "$BUILD_DIR/aria" >/dev/null 2>&1
cd "$BUILD_DIR/aria"

echo "  → Creating a stable signing identity (one-time; may ask for keychain access)…"
make cert >/dev/null 2>&1 || true

echo "  → Building Aria (takes a minute)…"
make release >/dev/null

APP_SRC=".build/$APP_NAME.app"
[ -d "$APP_SRC" ] || { echo "  Build failed: $APP_SRC not found." >&2; exit 1; }

# 4. Install to /Applications (fall back to ~/Applications if not writable).
DEST="/Applications/$APP_NAME.app"
if [ ! -w "/Applications" ]; then
  mkdir -p "$HOME/Applications"
  DEST="$HOME/Applications/$APP_NAME.app"
fi
# Stop any running copy before replacing it.
launchctl unload "$PLIST" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$DEST"
cp -R "$APP_SRC" "$DEST"
echo "  → Installed to $DEST"

EXEC="$DEST/Contents/MacOS/$APP_NAME"

# 5. Login agent: start now, start at every login, relaunch if it ever crashes.
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$EXEC</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardOutPath</key><string>/tmp/aria.out</string>
    <key>StandardErrorPath</key><string>/tmp/aria.out</string>
</dict>
</plist>
PLISTEOF

launchctl load -w "$PLIST"

echo ""
echo "  ✓ Aria is installed and running. It auto-starts at login."
echo "  ✓ It lives in the menu bar — no terminal needed."
echo ""
echo "  First launch will ask for Microphone, Speech Recognition, and Screen"
echo "  Recording — allow them. Then open Aria's Settings to add your free Gemini"
echo "  API key (aistudio.google.com) and, for the best voice, install a free"
echo "  Premium voice via the Voice tab."
echo ""
echo "  Say \"Hey Aria\" to begin."
echo ""
