#!/usr/bin/env bash
set -e

echo "🚀 Copilot Mobile — Starting up"
echo "================================"

SERVER_DIR="$(cd "$(dirname "$0")/server" && pwd)"
TMUX_BIN=$(which tmux 2>/dev/null || echo "/opt/homebrew/bin/tmux")
TMUX_SESSION="copilot-mobile"

# ── 1. Check for .env ────────────────────────────────────────────────────────
if [ ! -f "$SERVER_DIR/.env" ]; then
  cp "$SERVER_DIR/.env.example" "$SERVER_DIR/.env"
  echo ""
  echo "✅ Created server/.env from template."
  echo "⚠️  Edit server/.env before continuing (GITHUB_TOKEN, API_KEY, CLOUDFLARE_TUNNEL_TOKEN)"
  echo "   open -e server/.env"
  echo ""
  exit 0
fi

# ── 2. Check for cloudflared ──────────────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
  echo "Installing cloudflared via Homebrew…"
  brew install cloudflared
fi

PORT=$(grep -E '^PORT=' "$SERVER_DIR/.env" | cut -d= -f2)
PORT=${PORT:-3003}
TUNNEL_TOKEN=$(grep -E '^CLOUDFLARE_TUNNEL_TOKEN=' "$SERVER_DIR/.env" | cut -d= -f2)

# ── 3. Ensure copilot-mobile tmux session exists ──────────────────────────────
echo ""
echo "🖥  Setting up tmux session '$TMUX_SESSION'…"
$TMUX_BIN has-session -t "$TMUX_SESSION" 2>/dev/null || \
  $TMUX_BIN new-session -d -s "$TMUX_SESSION" -x 220 -y 50

# ── 4. Open terminal with the tmux session attached ───────────────────────────
ATTACH_SCRIPT=/tmp/copilot-mobile-attach.sh
cat > "$ATTACH_SCRIPT" <<EOF
#!/bin/bash
exec $TMUX_BIN attach -t $TMUX_SESSION
EOF
chmod +x "$ATTACH_SCRIPT"

echo "   Opening terminal…"
LSINFO=$(lsappinfo list 2>/dev/null || true)
FRONTMOST=$(echo "$LSINFO" | grep -o '"[^"]*" ASN:[^:]*: (in front)' | sed 's/" ASN:.*//' | tr -d '"' | head -1)

open_in_terminal() {
  local app="$1"
  open -a "$app" "$ATTACH_SCRIPT" 2>/dev/null && echo "   ✅ Opened in $app" && return 0
  return 1
}

opened=false
# Try frontmost first if it's a known terminal
for term in Warp Ghostty kitty iTerm2; do
  if [ "$FRONTMOST" = "$term" ]; then
    open_in_terminal "$term" && opened=true && break
  fi
done

# Fall back to any running terminal
if [ "$opened" = false ]; then
  for term in Warp Ghostty kitty iTerm2 Terminal; do
    if echo "$LSINFO" | grep -q "\"$term\" ASN:"; then
      open_in_terminal "$term" && opened=true && break
    fi
  done
fi

[ "$opened" = false ] && open -a Terminal "$ATTACH_SCRIPT"

# ── 5. Start server ───────────────────────────────────────────────────────────
echo ""
echo "⚙️  Starting server on port $PORT…"
cd "$SERVER_DIR"
node server.js &
SERVER_PID=$!
echo "   Server PID: $SERVER_PID"

sleep 1

# ── 6. Start Cloudflare tunnel ────────────────────────────────────────────────
echo ""
if [ -n "$TUNNEL_TOKEN" ]; then
  echo "🌐 Starting named tunnel (copilot.andreasheige.cc)…"
  cloudflared tunnel run --token "$TUNNEL_TOKEN" &
  TUNNEL_PID=$!
  echo "   Tunnel PID: $TUNNEL_PID"
  echo ""
  echo "✅ All running! Open https://copilot.andreasheige.cc in your app."
else
  echo "🌐 No CLOUDFLARE_TUNNEL_TOKEN set — starting quick tunnel…"
  echo "   (Copy the https://... URL into the iOS app Settings)"
  echo ""
  cloudflared tunnel --url "http://localhost:$PORT"
fi

echo ""
echo "Press Ctrl+C to stop everything."
wait $SERVER_PID
