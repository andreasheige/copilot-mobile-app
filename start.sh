#!/usr/bin/env bash
set -e

echo "🚀 Copilot Mobile Server Setup"
echo "================================"

SERVER_DIR="$(cd "$(dirname "$0")/server" && pwd)"

# 1. Check for .env
if [ ! -f "$SERVER_DIR/.env" ]; then
  cp "$SERVER_DIR/.env.example" "$SERVER_DIR/.env"
  echo ""
  echo "✅ Created server/.env from template."
  echo ""
  echo "⚠️  You must edit server/.env before continuing:"
  echo "   - Set GITHUB_TOKEN to your GitHub personal access token"
  echo "   - Set API_KEY to a strong random secret"
  echo ""
  echo "   Open it now with:"
  echo "   open -e server/.env"
  echo ""
  exit 0
fi

# 2. Check for cloudflared
if ! command -v cloudflared &>/dev/null; then
  echo "Installing cloudflared via Homebrew…"
  brew install cloudflared
fi

PORT=$(grep -E '^PORT=' "$SERVER_DIR/.env" | cut -d= -f2)
PORT=${PORT:-3000}

echo ""
echo "Starting server on port $PORT…"
cd "$SERVER_DIR"
node server.js &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

sleep 1

echo ""
echo "Starting Cloudflare Tunnel…"
echo "(Copy the https://... URL shown below into the iOS app Settings)"
echo ""
cloudflared tunnel --url "http://localhost:$PORT"

# Cleanup on exit
kill $SERVER_PID 2>/dev/null || true
