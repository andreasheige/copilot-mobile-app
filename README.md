# Copilot Mobile

A native iOS app that gives you GitHub Copilot chat from anywhere on your phone.

```
Phone ──(WebSocket)──▶ Cloudflare Tunnel ──▶ Mac (Node.js server) ──▶ GitHub Copilot API
```

## Project Structure

```
app-test/
├── server/          # Node.js backend
│   ├── server.js
│   ├── package.json
│   └── .env.example
├── CopilotMobile/   # iOS Xcode project (SwiftUI)
│   ├── project.yml
│   └── Sources/
└── start.sh         # One-command launcher
```

---

## Setup

### 1. Configure the server

```bash
cp server/.env.example server/.env
# Then edit server/.env:
```

| Variable | Description |
|---|---|
| `GITHUB_TOKEN` | GitHub PAT with **copilot** scope → [Create one](https://github.com/settings/tokens) |
| `API_KEY` | Any strong random secret (e.g., `openssl rand -hex 32`) |
| `MODEL` | Copilot model: `gpt-4o`, `claude-3.5-sonnet`, `o1-mini` |

### 2. Start the server + tunnel

```bash
./start.sh
```

The script will:
1. Start the Node.js server on port 3000
2. Start a Cloudflare Tunnel (no account needed!)
3. Print a public URL like `https://abc-def.trycloudflare.com`

### 3. Open the iOS app in Xcode

```bash
open CopilotMobile/CopilotMobile.xcodeproj
```

- Select your iPhone as the target device
- Press **⌘R** to build and run
- In the app, tap **Settings** (gear icon) and enter:
  - **Server URL**: the `https://abc-def.trycloudflare.com` URL from step 2
  - **API Key**: the `API_KEY` value from your `.env` file
- Tap **Test Connection** → **Save**

---

## GitHub Token Scopes

When creating your GitHub PAT at https://github.com/settings/tokens:
- For **Classic tokens**: check `copilot`
- For **Fine-grained tokens**: no additional scopes needed beyond the default

---

## Running persistently (optional)

To keep the server running even when you close the terminal:

```bash
# Install pm2
npm install -g pm2

# Start server with pm2
cd server && pm2 start server.js --name copilot-mobile

# Start tunnel (run in a separate terminal or use pm2 too)
cloudflared tunnel --url http://localhost:3000
```

---

## Features

- 💬 Multi-session chat (like Claude/ChatGPT mobile)
- ⚡ Real-time streaming responses
- 🔄 Auto-reconnect on network changes
- 🔒 API key authentication
- 📱 iPad + iPhone support
- 🌙 Dark mode support
