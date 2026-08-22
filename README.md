# Cloudflare Tunnel Status Page

A GitHub Pages status dashboard + automation script. Every time Cloudflare assigns a new tunnel URL, `start-tunnel.sh` captures it and pushes it to GitHub automatically — the status page updates itself within 30 seconds, no manual steps.

---

## One-Time Setup

### 1. Create a GitHub Personal Access Token

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)**
2. Click **Generate new token (classic)**
3. Give it a name (e.g. `tunnel-updater`), set expiry as desired
4. Check the **`repo`** scope
5. Click **Generate token** and copy it — you won't see it again

### 2. Create the GitHub repo

1. Create a new **public** repo (e.g. `tunnel-status`)
2. Upload all four files from this folder:
   - `index.html`
   - `tunnel-config.json`
   - `start-tunnel.sh`
   - `README.md`

### 3. Enable GitHub Pages

1. Go to **Settings → Pages**
2. Source: **Deploy from a branch**, branch: `main`, folder: `/ (root)`
3. Save — your page will be at `https://YOUR-USERNAME.github.io/YOUR-REPO-NAME/`

### 4. Configure the script

Open `start-tunnel.sh` and fill in the top three lines:

```bash
GITHUB_TOKEN="ghp_your_token_here"
GITHUB_REPO="your-username/tunnel-status"
LOCAL_PORT="${1:-8080}"   # change default port if needed
```

Then make it executable:

```bash
chmod +x start-tunnel.sh
```

---

## Daily Use

Just run the script instead of `cloudflared` directly:

```bash
./start-tunnel.sh 8080
```

Or if 8080 is your default port, just:

```bash
./start-tunnel.sh
```

**What happens automatically:**
1. `cloudflared` starts and gets a new `*.trycloudflare.com` URL
2. The script captures it from cloudflared's output
3. It pushes the new URL to `tunnel-config.json` on GitHub via the API
4. Your status page picks it up within 30 seconds
5. The tunnel keeps running — Ctrl+C to stop

---

## Files

| File | Purpose |
|------|---------|
| `index.html` | Status page — polls config every 30s, probes tunnel liveness |
| `tunnel-config.json` | Single source of truth for the current tunnel URL |
| `start-tunnel.sh` | Run this instead of `cloudflared` — handles everything |
| `README.md` | This file |
