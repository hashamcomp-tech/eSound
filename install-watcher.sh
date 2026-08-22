#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install-watcher.sh
#
# Installs watch-esound-tunnel.sh as a macOS LaunchAgent so it starts at
# login and keeps running forever in the background — no terminal window
# needed. Mirrors the same launchd pattern esound itself uses for its
# server and tunnel.
#
# Requires GITHUB_TOKEN to already be exported in your shell profile
# (see watch-esound-tunnel.sh setup instructions) — launchd will inherit
# it via the EnvironmentVariables block below, which this script fills in
# from your current environment at install time.
#
# Usage:
#   export GITHUB_TOKEN="ghp_your_token_here"   # if not already in ~/.zshrc
#   ./install-watcher.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SCRIPT="$SCRIPT_DIR/watch-esound-tunnel.sh"
PLIST_PATH="$HOME/Library/LaunchAgents/com.esound.tunnel-watcher.plist"
LOG_DIR="$HOME/esound"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

if [[ ! -f "$WATCH_SCRIPT" ]]; then
  echo -e "${RED}[install]${NC} Can't find watch-esound-tunnel.sh next to this script."
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo -e "${RED}[install]${NC} GITHUB_TOKEN is not set in your environment."
  echo -e "${RED}[install]${NC} Export it first (or add it to ~/.zshrc and source it):"
  echo -e "${BOLD}           export GITHUB_TOKEN=\"ghp_your_token_here\"${NC}"
  exit 1
fi

chmod +x "$WATCH_SCRIPT"
mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

cat << EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.esound.tunnel-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$WATCH_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/tunnel-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/tunnel-watcher.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>GITHUB_TOKEN</key>
        <string>$GITHUB_TOKEN</string>
    </dict>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo -e "${GREEN}[install]${NC} ✅ Watcher installed and running as a background service."
echo -e "${CYAN}[install]${NC} Logs: ${BOLD}$LOG_DIR/tunnel-watcher.log${NC}"
echo -e "${CYAN}[install]${NC} It will now push a new tunnel-config.json every time esound's"
echo -e "${CYAN}[install]${NC} tunnel gets a new URL — including after restarts and reboots."
echo ""
echo -e "${CYAN}[install]${NC} To stop it:   launchctl unload $PLIST_PATH"
echo -e "${CYAN}[install]${NC} To uninstall: launchctl unload $PLIST_PATH && rm $PLIST_PATH"
echo ""
