#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# start-tunnel.sh
# Starts a Cloudflare quick tunnel, captures the assigned URL, and
# automatically pushes it to your GitHub repo so the status page updates.
#
# SETUP (one time):
#   1. Add your token to ~/.zshrc (NEVER put it in this file):
#        echo 'export GITHUB_TOKEN="ghp_your_token_here"' >> ~/.zshrc
#        source ~/.zshrc
#   2. Edit GITHUB_REPO below (safe to commit — it's just your repo name)
#   3. chmod +x start-tunnel.sh
#   4. ./start-tunnel.sh 8080
# ─────────────────────────────────────────────────────────────────────────────

# ── ✏️  Edit this one line (safe to commit) ───────────────────────────────────
GITHUB_REPO="YOUR-USERNAME/YOUR-REPO-NAME"   # e.g. johndoe/tunnel-status
LOCAL_PORT="${1:-8080}"                       # or change default port here
# ─────────────────────────────────────────────────────────────────────────────

# ── Token comes from environment — never hardcode it here ────────────────────
# Set once in terminal: echo 'export GITHUB_TOKEN="ghp_..."' >> ~/.zshrc
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo -e "\033[0;31m[tunnel]\033[0m GITHUB_TOKEN is not set in your environment."
  echo -e "\033[0;31m[tunnel]\033[0m Run this once, then open a new terminal:"
  echo -e "\033[1m         echo 'export GITHUB_TOKEN=\"ghp_your_token_here\"' >> ~/.zshrc\033[0m"
  exit 1
fi

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${CYAN}[tunnel]${NC} $*"; }
ok()   { echo -e "${GREEN}[tunnel]${NC} $*"; }
warn() { echo -e "${YELLOW}[tunnel]${NC} $*"; }
err()  { echo -e "${RED}[tunnel]${NC} $*"; }

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
  err "cloudflared not found. Install with: brew install cloudflared"
  exit 1
fi
if ! command -v curl &>/dev/null; then
  err "curl not found — required for GitHub API calls."
  exit 1
fi
if [[ "$GITHUB_TOKEN" == ghp_XXX* ]]; then
  err "Please edit GITHUB_TOKEN in this script first."
  exit 1
fi
if [[ "$GITHUB_REPO" == YOUR-* ]]; then
  err "Please edit GITHUB_REPO in this script first."
  exit 1
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Cloudflare Tunnel Auto-Updater         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
log "Port: ${BOLD}${LOCAL_PORT}${NC}"
log "Repo: ${BOLD}https://github.com/${GITHUB_REPO}${NC}"
echo ""

# ── Temp files ───────────────────────────────────────────────────────────────
LOGFILE="$(mktemp /tmp/cloudflared-XXXXXX.log)"
trap 'rm -f "$LOGFILE"; kill "$CF_PID" 2>/dev/null || true' EXIT INT TERM

# ── Start cloudflared in background, tee its stderr to log ──────────────────
log "Starting cloudflared tunnel on localhost:${LOCAL_PORT} …"
cloudflared tunnel --url "http://localhost:${LOCAL_PORT}" 2>&1 | tee "$LOGFILE" &
CF_PID=$!

# ── Watch log for the assigned URL ───────────────────────────────────────────
log "Waiting for Cloudflare to assign a URL …"
TUNNEL_URL=""
WAIT=0
MAX_WAIT=60  # seconds

while [[ -z "$TUNNEL_URL" && $WAIT -lt $MAX_WAIT ]]; do
  sleep 1
  WAIT=$((WAIT + 1))

  # cloudflared prints the URL in a line like:
  #   Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):
  #   https://xxxx.trycloudflare.com
  # or inline: | https://xxxx.trycloudflare.com |
  TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOGFILE" | head -1 || true)
done

if [[ -z "$TUNNEL_URL" ]]; then
  err "Timed out waiting for a tunnel URL (${MAX_WAIT}s). Check cloudflared output above."
  exit 1
fi

echo ""
ok "✅ Tunnel URL: ${BOLD}${TUNNEL_URL}${NC}"
echo ""

# ── Push to GitHub ────────────────────────────────────────────────────────────
push_to_github() {
  local url="$1"
  local today
  today=$(date +%Y-%m-%d)

  # Build the JSON payload for tunnel-config.json
  local content
  content=$(printf '{
  "tunnel_url": "%s",
  "github_repo": "https://github.com/%s",
  "last_updated": "%s"
}' "$url" "$GITHUB_REPO" "$today")

  # Base64-encode the content (macOS compatible)
  local encoded
  encoded=$(echo -n "$content" | base64)

  # Fetch the current file SHA (needed for updates)
  log "Fetching current tunnel-config.json SHA from GitHub …"
  local api_response sha
  api_response=$(curl -sf \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/contents/tunnel-config.json" 2>/dev/null || echo "{}")

  sha=$(echo "$api_response" | grep -o '"sha": *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"' || true)

  # Build PUT body
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
    ok "   View: ${BOLD}https://$(echo "$GITHUB_REPO" | tr '/' '.').github.io/$(echo "$GITHUB_REPO" | cut -d'/' -f2)/${NC}"
  else
    warn "GitHub API returned HTTP ${http_code}. Check your token has 'repo' scope."
    warn "Tunnel is still running — update tunnel-config.json manually."
  fi
}

push_to_github "$TUNNEL_URL"

# ── Keep running & show live logs ────────────────────────────────────────────
echo ""
echo -e "${BOLD}────────────────────────────────────────────────${NC}"
log "Tunnel is running. Press ${BOLD}Ctrl+C${NC} to stop."
echo -e "${BOLD}────────────────────────────────────────────────${NC}"
echo ""

# Stream the rest of cloudflared output
wait "$CF_PID" 2>/dev/null || true
