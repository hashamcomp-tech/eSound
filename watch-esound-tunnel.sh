#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# watch-esound-tunnel.sh
#
# Watches eSound's OWN Cloudflare tunnel (the one esound's setup-tunnel.sh
# runs as a launchd service, logging to ~/esound/tunnel.log) and pushes the
# URL to GitHub automatically whenever it changes — including every time the
# tunnel restarts and cloudflared hands out a brand-new *.trycloudflare.com
# address.
#
# This does NOT start a new cloudflared process. It just tails the log
# esound is already writing and reacts to it. Run this once and forget it —
# it keeps watching forever (or install it as a LaunchAgent, see below).
#
# SETUP (one time):
#   1. Add your token to ~/.zshrc (NEVER put it in this file):
#        echo 'export GITHUB_TOKEN="ghp_your_token_here"' >> ~/.zshrc
#        source ~/.zshrc
#   2. Edit GITHUB_REPO below (safe to commit — it's just your repo name)
#   3. chmod +x watch-esound-tunnel.sh
#   4. ./watch-esound-tunnel.sh
#
# To run it permanently in the background (auto-starts at login), use:
#   ./install-watcher.sh
# ─────────────────────────────────────────────────────────────────────────────

# ── ✏️  Edit this one line (safe to commit) ───────────────────────────────────
GITHUB_REPO="YOUR-USERNAME/YOUR-REPO-NAME"   # e.g. johndoe/tunnel-status
# ─────────────────────────────────────────────────────────────────────────────

# Where esound's own tunnel writes its log. Override with:
#   ESOUND_TUNNEL_LOG=/path/to/tunnel.log ./watch-esound-tunnel.sh
ESOUND_TUNNEL_LOG="${ESOUND_TUNNEL_LOG:-$HOME/esound/tunnel.log}"

# How often to check the log for a new URL (seconds).
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# ── Token comes from environment — never hardcode it here ────────────────────
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo -e "\033[0;31m[watch]\033[0m GITHUB_TOKEN is not set in your environment."
  echo -e "\033[0;31m[watch]\033[0m Run this once, then open a new terminal:"
  echo -e "\033[1m         echo 'export GITHUB_TOKEN=\"ghp_your_token_here\"' >> ~/.zshrc\033[0m"
  exit 1
fi

set -uo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${CYAN}[watch]${NC} $*"; }
ok()   { echo -e "${GREEN}[watch]${NC} $*"; }
warn() { echo -e "${YELLOW}[watch]${NC} $*"; }
err()  { echo -e "${RED}[watch]${NC} $*"; }

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
  err "curl not found — required for GitHub API calls."
  exit 1
fi
if [[ "$GITHUB_REPO" == YOUR-* ]]; then
  err "Please edit GITHUB_REPO in this script first."
  exit 1
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     eSound Tunnel Watcher (auto-detect)       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
log "Watching: ${BOLD}${ESOUND_TUNNEL_LOG}${NC}"
log "Repo:     ${BOLD}https://github.com/${GITHUB_REPO}${NC}"
log "Poll:     every ${BOLD}${POLL_INTERVAL}s${NC}"
echo ""

# ── Extract the most recent tunnel URL currently in the log ──────────────────
get_current_url() {
  if [[ -f "$ESOUND_TUNNEL_LOG" ]]; then
    grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$ESOUND_TUNNEL_LOG" 2>/dev/null | tail -1
  fi
}

# ── Push a URL to GitHub (same shape as start-tunnel.sh) ─────────────────────
push_to_github() {
  local url="$1"
  local today
  today=$(date +%Y-%m-%d)

  local content
  content=$(printf '{
  "tunnel_url": "%s",
  "github_repo": "https://github.com/%s",
  "last_updated": "%s"
}' "$url" "$GITHUB_REPO" "$today")

  local encoded
  encoded=$(echo -n "$content" | base64)

  log "Fetching current tunnel-config.json SHA from GitHub …"
  local api_response sha
  api_response=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/contents/tunnel-config.json" 2>/dev/null || echo "{}")

  sha=$(echo "$api_response" | grep -o '"sha": *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)

  local put_body
  if [[ -n "$sha" ]]; then
    put_body=$(printf '{"message":"Auto-update tunnel URL [skip ci]","content":"%s","sha":"%s"}' "$encoded" "$sha")
  else
    put_body=$(printf '{"message":"Auto-update tunnel URL [skip ci]","content":"%s"}' "$encoded")
  fi

  log "Pushing new URL to GitHub …"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -d "$put_body" \
    "https://api.github.com/repos/${GITHUB_REPO}/contents/tunnel-config.json")

  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    ok "✅ GitHub updated! Status page will refresh within ~30 seconds."
    ok "   View: ${BOLD}https://$(echo "$GITHUB_REPO" | cut -d'/' -f1).github.io/$(echo "$GITHUB_REPO" | cut -d'/' -f2)/${NC}"
    return 0
  else
    warn "GitHub API returned HTTP ${http_code}. Check your token has 'repo' scope."
    return 1
  fi
}

# ── Main watch loop ───────────────────────────────────────────────────────────
LAST_URL=""

# If the log already has a URL when we start, treat it as new so the page
# is guaranteed correct as soon as the watcher comes up.
log "Waiting for esound's tunnel to appear in the log …"

while true; do
  CURRENT_URL="$(get_current_url)"

  if [[ -n "$CURRENT_URL" && "$CURRENT_URL" != "$LAST_URL" ]]; then
    echo ""
    ok "🌐 Detected tunnel URL: ${BOLD}${CURRENT_URL}${NC}"
    if push_to_github "$CURRENT_URL"; then
      LAST_URL="$CURRENT_URL"
    else
      warn "Will retry on the next detected change or poll cycle."
    fi
    echo ""
  fi

  sleep "$POLL_INTERVAL"
done
