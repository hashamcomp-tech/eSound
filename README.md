# Cloudflare Tunnel Status Page

A GitHub Pages status dashboard + automation. Every time Cloudflare assigns esound a new tunnel URL, it gets pushed to GitHub automatically — the status page updates itself within 30 seconds, no manual steps.

There are two ways to get a URL pushed:

| Script | What it does | When to use it |
|---|---|---|
| `watch-esound-tunnel.sh` | **Watches esound's own tunnel** (`~/esound/tunnel.log`, run by esound's `setup-tunnel.sh`/launchd) and pushes whenever the URL changes — including after esound restarts or your Mac reboots. Starts no tunnel itself. | Recommended. Run once (or install as a background service with `install-watcher.sh`) and forget it. |
| `start-tunnel.sh` | Starts its **own separate** `cloudflared` tunnel on a port you choose, then pushes that URL. | Only if you're tunneling something that isn't esound, or don't run esound as a launchd service. |

Using both at once will fight over `tunnel-config.json` — pick one.

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

### 4. Set your GitHub token in the environment (both scripts use this — never hardcode it)

```bash
echo 'export GITHUB_TOKEN="ghp_your_token_here"' >> ~/.zshrc
source ~/.zshrc
```

### 5. Configure the repo name

Open `watch-esound-tunnel.sh` (or `start-tunnel.sh` if you're using that instead) and edit:

```bash
GITHUB_REPO="your-username/tunnel-status"
```

Then make it executable:

```bash
chmod +x watch-esound-tunnel.sh install-watcher.sh
```

---

## Daily Use (recommended: auto-detect mode)

Run the watcher once in a terminal to try it out:

```bash
./watch-esound-tunnel.sh
```

**What happens automatically:**
1. It polls `~/esound/tunnel.log` (esound's real tunnel — no new tunnel is started)
2. As soon as a `*.trycloudflare.com` URL shows up, or changes, it's detected
3. It pushes the new URL to `tunnel-config.json` on GitHub via the API
4. Your status page picks it up within 30 seconds
5. It keeps watching — Ctrl+C to stop, or install it permanently:

```bash
./install-watcher.sh
```

This registers it as a macOS LaunchAgent (same pattern esound itself uses), so it starts at login and keeps running invisibly. From then on, every time esound's tunnel restarts and gets handed a new random URL, your status page updates itself with zero manual steps — even across reboots.

If esound's tunnel log lives somewhere other than `~/esound/tunnel.log`, point the watcher at it:

```bash
ESOUND_TUNNEL_LOG=/path/to/tunnel.log ./watch-esound-tunnel.sh
```

## Alternative: `start-tunnel.sh`

If you're not running esound as a launchd service, `start-tunnel.sh` starts its own `cloudflared` process on a port you choose (`./start-tunnel.sh 8080`) and pushes that URL the same way. Don't run this alongside the watcher — they'll overwrite each other's updates.

---

## Files

| File | Purpose |
|------|---------|
| `index.html` | Status page — polls config every 30s, probes tunnel liveness |
| `tunnel-config.json` | Single source of truth for the current tunnel URL |
| `watch-esound-tunnel.sh` | Recommended — detects esound's tunnel URL automatically and pushes it |
| `install-watcher.sh` | Installs the watcher as a background LaunchAgent (starts at login) |
| `start-tunnel.sh` | Alternative — starts its own tunnel on a port you choose, then pushes it |
| `README.md` | This file |
