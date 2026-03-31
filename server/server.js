require("dotenv").config();
const express = require("express");
const http = require("http");
const { WebSocketServer } = require("ws");
const { execSync, exec } = require("child_process");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const os = require("os");

const app = express();
app.use(express.json());
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const API_KEY = process.env.API_KEY;
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const MODEL = process.env.MODEL || "gpt-4o";
const AGENT_API_URL = process.env.COPILOT_API_URL || "https://models.inference.ai.azure.com/chat/completions";
const TMUX = process.env.TMUX_BIN || "/opt/homebrew/bin/tmux";
const WORK_DIR = process.env.WORK_DIR || os.homedir();

if (!API_KEY || API_KEY === "change_me_to_a_strong_random_secret") {
  console.error("❌  API_KEY not set in .env"); process.exit(1);
}
if (!GITHUB_TOKEN) {
  console.error("❌  GITHUB_TOKEN not set in .env"); process.exit(1);
}

// ─── Tool definitions ─────────────────────────────────────────────────────────

const TOOLS = [
  {
    type: "function",
    function: {
      name: "bash",
      description: "Run a shell command on the Mac and return its output. Use for running scripts, git, gh copilot, file operations, etc.",
      parameters: {
        type: "object",
        properties: {
          command: { type: "string", description: "The shell command to run" },
          timeout: { type: "number", description: "Timeout in seconds (default 30)" },
        },
        required: ["command"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "read_file",
      description: "Read the contents of a file on the Mac.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute or relative path to the file" },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "write_file",
      description: "Write or overwrite a file on the Mac.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "Absolute or relative path to the file" },
          content: { type: "string", description: "Content to write" },
        },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_dir",
      description: "List files and directories at a given path.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "Directory path (default: home directory)" },
        },
      },
    },
  },
];

// ─── Tool execution ───────────────────────────────────────────────────────────

function executeTool(name, args) {
  try {
    switch (name) {
      case "bash": {
        const timeout = (args.timeout || 30) * 1000;
        try {
          const output = execSync(args.command, {
            encoding: "utf8", timeout, cwd: WORK_DIR,
            env: { ...process.env, TERM: "xterm-256color" },
          });
          return output || "(no output)";
        } catch (e) {
          return `Exit ${e.status || 1}:\n${e.stdout || ""}${e.stderr || e.message}`;
        }
      }
      case "read_file": {
        const filePath = path.resolve(WORK_DIR, args.path);
        return fs.readFileSync(filePath, "utf8");
      }
      case "write_file": {
        const filePath = path.resolve(WORK_DIR, args.path);
        fs.mkdirSync(path.dirname(filePath), { recursive: true });
        fs.writeFileSync(filePath, args.content, "utf8");
        return `Written ${args.content.length} chars to ${filePath}`;
      }
      case "list_dir": {
        const dirPath = path.resolve(WORK_DIR, args.path || ".");
        const entries = fs.readdirSync(dirPath, { withFileTypes: true });
        return entries.map(e => (e.isDirectory() ? `📁 ${e.name}/` : `📄 ${e.name}`)).join("\n");
      }
      default:
        return `Unknown tool: ${name}`;
    }
  } catch (e) {
    return `Error: ${e.message}`;
  }
}

// ─── Agent loop ───────────────────────────────────────────────────────────────

async function runAgent(history, onChunk, onToolCall) {
  const messages = [
    {
      role: "system",
      content: `You are GitHub Copilot CLI, an AI assistant running on the user's Mac (${os.hostname()}). You have tools to run shell commands, read/write files, and list directories. Working directory: ${WORK_DIR}. Be concise and helpful. When running commands, show the output.`,
    },
    ...history,
  ];

  while (true) {
    const response = await fetch(AGENT_API_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${GITHUB_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: MODEL, messages, tools: TOOLS, stream: true }),
    });

    if (!response.ok) {
      const err = await response.text();
      throw new Error(`API ${response.status}: ${err}`);
    }

    // Parse streaming response
    let assistantContent = "";
    let toolCalls = {};
    const decoder = new TextDecoder();

    for await (const chunk of response.body) {
      const text = decoder.decode(chunk, { stream: true });
      for (const line of text.split("\n")) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data:")) continue;
        const data = trimmed.slice(5).trim();
        if (data === "[DONE]") continue;
        try {
          const parsed = JSON.parse(data);
          const delta = parsed.choices?.[0]?.delta;
          if (!delta) continue;

          // Text chunk
          if (delta.content) {
            assistantContent += delta.content;
            onChunk(delta.content);
          }

          // Tool call accumulation
          if (delta.tool_calls) {
            for (const tc of delta.tool_calls) {
              const idx = tc.index ?? 0;
              if (!toolCalls[idx]) toolCalls[idx] = { id: "", name: "", arguments: "" };
              if (tc.id) toolCalls[idx].id = tc.id;
              if (tc.function?.name) toolCalls[idx].name = tc.function.name;
              if (tc.function?.arguments) toolCalls[idx].arguments += tc.function.arguments;
            }
          }
        } catch { /* skip malformed */ }
      }
    }

    const toolCallList = Object.values(toolCalls);

    // No tool calls → done
    if (toolCallList.length === 0) {
      messages.push({ role: "assistant", content: assistantContent });
      return assistantContent;
    }

    // Execute tools
    messages.push({
      role: "assistant",
      content: assistantContent || null,
      tool_calls: toolCallList.map(tc => ({
        id: tc.id,
        type: "function",
        function: { name: tc.name, arguments: tc.arguments },
      })),
    });

    for (const tc of toolCallList) {
      let args;
      try { args = JSON.parse(tc.arguments); } catch { args = {}; }

      onToolCall(tc.name, args);
      const result = executeTool(tc.name, args);

      messages.push({
        role: "tool",
        tool_call_id: tc.id,
        content: String(result),
      });
    }
    // Loop back to get the next response
  }
}

// ─── Session store ────────────────────────────────────────────────────────────

const agentSessions = new Map();   // sessionId -> [messages]
const terminalSessions = new Map(); // tmuxSession -> { ws, timer }

// ─── Tmux helpers ─────────────────────────────────────────────────────────────

function tmuxCmd(...args) {
  return execSync(`${TMUX} ${args.join(" ")}`, { encoding: "utf8" }).trim();
}
function capturePane(name) {
  try { return execSync(`${TMUX} capture-pane -t ${name} -p -e`, { encoding: "utf8" }); }
  catch { return null; }
}
function ensureTmux(name) {
  try { tmuxCmd("has-session", "-t", name); return false; }
  catch { tmuxCmd("new-session", "-d", "-s", name, "-x", "220", "-y", "50"); return true; }
}
function startPolling(name, ws) {
  let last = "";
  const poll = () => {
    if (!terminalSessions.has(name)) return;
    const content = capturePane(name);
    if (content === null) {
      if (ws.readyState === ws.OPEN)
        ws.send(JSON.stringify({ type: "screen", sessionId: name, data: "\r\n[Session ended]\r\n" }));
      terminalSessions.delete(name);
      return;
    }
    if (content !== last) {
      if (ws.readyState === ws.OPEN)
        ws.send(JSON.stringify({ type: "screen", sessionId: name, data: content }));
      last = content;
    }
    terminalSessions.get(name).timer = setTimeout(poll, 150);
  };
  poll();
}

// ─── WebSocket server ─────────────────────────────────────────────────────────

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, "http://localhost");
  if (url.searchParams.get("key") !== API_KEY) {
    ws.send(JSON.stringify({ type: "error", message: "Unauthorized" }));
    ws.close(1008, "Unauthorized");
    return;
  }

  const send = (obj) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj)); };
  console.log(`[${new Date().toISOString()}] Client connected`);

  ws.on("message", async (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch {
      send({ type: "error", message: "Invalid JSON" }); return;
    }
    console.log(`[msg] ${msg.type} session=${msg.sessionId || "-"}`);

    switch (msg.type) {

      // ── Ping ──
      case "ping": send({ type: "pong" }); break;

      // ── Agent chat ──────────────────────────────────────────────────────────
      case "agent_chat": {
        const { sessionId, content } = msg;
        if (!agentSessions.has(sessionId)) agentSessions.set(sessionId, []);
        const history = agentSessions.get(sessionId);
        history.push({ role: "user", content });

        try {
          let fullResponse = "";
          const response = await runAgent(
            [...history],
            (chunk) => {
              fullResponse += chunk;
              send({ type: "agent_chunk", sessionId, content: chunk });
            },
            (toolName, toolArgs) => {
              send({ type: "tool_call", sessionId, tool: toolName, args: toolArgs });
            }
          );
          history.push({ role: "assistant", content: response });
          send({ type: "agent_done", sessionId });
        } catch (err) {
          console.error("Agent error:", err.message);
          send({ type: "agent_error", sessionId, message: err.message });
        }
        break;
      }

      case "new_agent_session": {
        const sessionId = msg.sessionId || crypto.randomUUID();
        agentSessions.set(sessionId, []);
        send({ type: "agent_session_created", sessionId });
        break;
      }

      case "clear_agent_session":
        agentSessions.set(msg.sessionId, []);
        send({ type: "agent_session_cleared", sessionId: msg.sessionId });
        break;

      // ── Terminal (tmux) ─────────────────────────────────────────────────────
      case "new_session": {
        const name = msg.tmuxSession || "mobile";
        const created = ensureTmux(name);
        terminalSessions.set(name, { ws, timer: null });
        startPolling(name, ws);
        send({ type: "session_created", sessionId: name, created });
        break;
      }

      case "input": {
        const sid = msg.sessionId || "mobile";
        if (!terminalSessions.has(sid)) {
          ensureTmux(sid);
          terminalSessions.set(sid, { ws, timer: null });
          startPolling(sid, ws);
        }
        const data = msg.data || "";
        try {
          if (data === "\u0003") tmuxCmd("send-keys", "-t", sid, "C-c");
          else if (data === "\t") tmuxCmd("send-keys", "-t", sid, "Tab");
          else {
            const text = data.replace(/[\r\n]+$/, "");
            const hasNl = data !== text;
            if (text) { const esc = text.replace(/'/g, "'\\''"); tmuxCmd("send-keys", "-t", sid, `'${esc}'`); }
            if (hasNl) tmuxCmd("send-keys", "-t", sid, "Enter");
          }
        } catch (e) { send({ type: "error", message: e.message }); }
        break;
      }

      case "close_session": {
        const s = terminalSessions.get(msg.sessionId);
        if (s) { clearTimeout(s.timer); terminalSessions.delete(msg.sessionId); }
        break;
      }

      default:
        send({ type: "error", message: `Unknown type: ${msg.type}` });
    }
  });

  ws.on("close", () => {
    for (const [id, s] of terminalSessions) {
      if (s.ws === ws) { clearTimeout(s.timer); terminalSessions.delete(id); }
    }
    console.log(`[${new Date().toISOString()}] Client disconnected`);
  });
});

app.get("/health", (req, res) => {
  res.json({ status: "ok", model: MODEL, agentSessions: agentSessions.size, terminalSessions: terminalSessions.size, uptime: process.uptime() });
});

const PORT = parseInt(process.env.PORT || "3003", 10);
server.listen(PORT, () => {
  console.log(`\n🚀 Copilot CLI Server on port ${PORT}`);
  console.log(`   Model: ${MODEL}  |  Work dir: ${WORK_DIR}`);
  console.log(`   Health: http://localhost:${PORT}/health\n`);
});
