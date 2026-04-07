require("dotenv").config();
const express = require("express");
const http = require("http");
const { WebSocketServer } = require("ws");
const { execSync, execFileSync, exec } = require("child_process");
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
const AGENT_API_URL =
  process.env.COPILOT_API_URL ||
  "https://models.inference.ai.azure.com/chat/completions";
const TMUX = process.env.TMUX_BIN || "/opt/homebrew/bin/tmux";
const WORK_DIR = process.env.WORK_DIR || os.homedir();
const DEFAULT_START_COMMAND = process.env.DEFAULT_START_COMMAND || "";

if (!API_KEY || API_KEY === "change_me_to_a_strong_random_secret") {
  console.error("❌  API_KEY not set in .env");
  process.exit(1);
}
if (!GITHUB_TOKEN) {
  console.error("❌  GITHUB_TOKEN not set in .env");
  process.exit(1);
}

// ─── Security helpers ─────────────────────────────────────────────────────────

/** Resolve a path and ensure it stays within WORK_DIR (prevents path traversal). */
function safePath(userPath) {
  const resolved = path.resolve(WORK_DIR, userPath);
  const normalizedWork = path.resolve(WORK_DIR) + path.sep;
  const normalizedResolved = path.resolve(resolved);
  if (
    normalizedResolved !== path.resolve(WORK_DIR) &&
    !normalizedResolved.startsWith(normalizedWork)
  ) {
    throw new Error(`Path traversal blocked: ${userPath}`);
  }
  return normalizedResolved;
}

/** Extract API key from header (preferred) or query param (legacy). */
function extractApiKey(req) {
  return (
    req.headers["x-api-key"] ||
    new URL(req.url, "http://localhost").searchParams.get("key")
  );
}

/** Simple in-memory rate limiter per IP. */
const rateLimitMap = new Map();
function rateLimit(ip, maxPerMinute = 60) {
  const now = Date.now();
  const entry = rateLimitMap.get(ip) || { count: 0, resetAt: now + 60000 };
  if (now > entry.resetAt) {
    entry.count = 0;
    entry.resetAt = now + 60000;
  }
  entry.count++;
  rateLimitMap.set(ip, entry);
  return entry.count > maxPerMinute;
}

/** Build a sanitised env for the bash tool (strips secrets). */
function cleanEnvForBash(cwd) {
  const env = { ...process.env, TERM: "xterm-256color" };
  delete env.GITHUB_TOKEN;
  delete env.API_KEY;
  delete env.GH_TOKEN;
  return env;
}

// ─── Tool definitions ─────────────────────────────────────────────────────────

const TOOLS = [
  {
    type: "function",
    function: {
      name: "bash",
      description:
        "Run any shell command on the Mac (zsh). Use for git, npm, python, compiling, etc. Prefer specific tools below when they fit.",
      parameters: {
        type: "object",
        properties: {
          command: { type: "string", description: "The shell command to run" },
          timeout: {
            type: "number",
            description: "Timeout in seconds (default 30, max 120)",
          },
          cwd: {
            type: "string",
            description: "Working directory (default: WORK_DIR)",
          },
        },
        required: ["command"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "read_file",
      description: "Read the contents of a file.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "File path (absolute or relative to WORK_DIR)",
          },
          start_line: {
            type: "number",
            description: "First line to read (1-indexed, optional)",
          },
          end_line: {
            type: "number",
            description: "Last line to read (optional)",
          },
        },
        required: ["path"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "write_file",
      description: "Create or overwrite a file.",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path" },
          content: { type: "string", description: "Full file content" },
        },
        required: ["path", "content"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_dir",
      description: "List files and directories at a path.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Directory path (default: WORK_DIR)",
          },
          recursive: {
            type: "boolean",
            description: "List recursively (default false)",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "find_files",
      description: "Search for files by name pattern using glob.",
      parameters: {
        type: "object",
        properties: {
          pattern: {
            type: "string",
            description: "Glob pattern, e.g. '**/*.swift' or 'src/*.js'",
          },
          cwd: {
            type: "string",
            description: "Directory to search in (default: WORK_DIR)",
          },
        },
        required: ["pattern"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_in_files",
      description:
        "Search for text/regex inside files (like grep). Returns matching lines with file and line number.",
      parameters: {
        type: "object",
        properties: {
          pattern: {
            type: "string",
            description: "Search pattern (regex supported)",
          },
          path: {
            type: "string",
            description: "File or directory to search in (default: WORK_DIR)",
          },
          file_glob: {
            type: "string",
            description: "Filter files by glob, e.g. '*.js'",
          },
          case_sensitive: {
            type: "boolean",
            description: "Case sensitive (default true)",
          },
        },
        required: ["pattern"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "github",
      description:
        "Run GitHub CLI (gh) commands: list issues/PRs, view repos, create PRs, check workflow runs, etc.",
      parameters: {
        type: "object",
        properties: {
          args: {
            type: "string",
            description:
              "Arguments to pass to gh, e.g. 'issue list', 'pr create --title ...",
          },
        },
        required: ["args"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "web_search",
      description:
        "Search the web and return top results. Use for docs, error messages, latest versions, etc.",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
          max_results: {
            type: "number",
            description: "Max results to return (default 5)",
          },
        },
        required: ["query"],
      },
    },
  },
];

// ─── Tool execution ───────────────────────────────────────────────────────────

function executeTool(name, args) {
  try {
    const cwd = args.cwd ? path.resolve(WORK_DIR, args.cwd) : WORK_DIR;
    switch (name) {
      case "bash": {
        const timeout = Math.min(args.timeout || 30, 120) * 1000;
        try {
          const output = execSync(args.command, {
            encoding: "utf8",
            timeout,
            cwd,
            env: cleanEnvForBash(cwd),
          });
          return output.trim() || "(no output)";
        } catch (e) {
          return `Exit ${e.status || 1}:\n${(e.stdout || "").trim()}\n${(e.stderr || e.message).trim()}`.trim();
        }
      }

      case "read_file": {
        const filePath = safePath(args.path);
        const content = fs.readFileSync(filePath, "utf8");
        if (args.start_line || args.end_line) {
          const lines = content.split("\n");
          const start = (args.start_line || 1) - 1;
          const end = args.end_line || lines.length;
          return lines
            .slice(start, end)
            .map((l, i) => `${start + i + 1}: ${l}`)
            .join("\n");
        }
        return content;
      }

      case "write_file": {
        const filePath = safePath(args.path);
        fs.mkdirSync(path.dirname(filePath), { recursive: true });
        fs.writeFileSync(filePath, args.content, "utf8");
        return `✅ Written to ${filePath} (${args.content.length} chars)`;
      }

      case "list_dir": {
        const dirPath = safePath(args.path || ".");
        if (args.recursive) {
          return execFileSync("find", [dirPath, "-maxdepth", "4"], {
            encoding: "utf8",
          })
            .split("\n")
            .sort()
            .join("\n")
            .trim();
        }
        const entries = fs.readdirSync(dirPath, { withFileTypes: true });
        return entries
          .map((e) => (e.isDirectory() ? `📁 ${e.name}/` : `📄 ${e.name}`))
          .join("\n");
      }

      case "find_files": {
        const searchDir = safePath(args.cwd || ".");
        const pattern = String(args.pattern).replace(
          /[^a-zA-Z0-9_.*?\[\]-]/g,
          "",
        ); // sanitise glob
        try {
          const result = execFileSync(
            "find",
            [searchDir, "-name", pattern, "-maxdepth", "10"],
            { encoding: "utf8", timeout: 15000 },
          );
          return (
            result.split("\n").filter(Boolean).slice(0, 50).join("\n") ||
            "No files found"
          );
        } catch {
          return "No files found";
        }
      }

      case "search_in_files": {
        const searchPath = safePath(args.path || ".");
        const grepArgs = ["-r", "-n"];
        if (args.case_sensitive === false) grepArgs.push("-i");
        if (args.file_glob) grepArgs.push(`--include=${args.file_glob}`);
        grepArgs.push("--", String(args.pattern), searchPath);
        try {
          const result = execFileSync("grep", grepArgs, {
            encoding: "utf8",
            timeout: 15000,
          });
          return (
            result.split("\n").filter(Boolean).slice(0, 50).join("\n") ||
            "No matches"
          );
        } catch {
          return "No matches";
        }
      }

      case "github": {
        try {
          const ghArgs = String(args.args).split(/\s+/);
          return execFileSync("gh", ghArgs, {
            encoding: "utf8",
            timeout: 30000,
            cwd: WORK_DIR,
            env: { ...process.env, GH_TOKEN: GITHUB_TOKEN },
          }).trim();
        } catch (e) {
          return `gh error: ${(e.stderr || e.message).trim()}`;
        }
      }

      case "web_search": {
        const max = args.max_results || 5;
        const encoded = encodeURIComponent(args.query);
        try {
          // DuckDuckGo instant answer API (no key needed)
          const ddg = execSync(
            `curl -s "https://api.duckduckgo.com/?q=${encoded}&format=json&no_redirect=1&no_html=1&skip_disambig=1"`,
            { encoding: "utf8", timeout: 10000 },
          );
          const data = JSON.parse(ddg);
          const results = [];
          if (data.AbstractText)
            results.push(
              `📌 ${data.AbstractText}\n   Source: ${data.AbstractURL}`,
            );
          (data.RelatedTopics || []).slice(0, max - 1).forEach((t) => {
            if (t.Text)
              results.push(
                `• ${t.Text}${t.FirstURL ? `\n  ${t.FirstURL}` : ""}`,
              );
          });
          return results.length
            ? results.join("\n\n")
            : `No instant answer. Try: https://duckduckgo.com/?q=${encoded}`;
        } catch (e) {
          return `Search failed: ${e.message}`;
        }
      }

      default:
        return `Unknown tool: ${name}`;
    }
  } catch (e) {
    return `Error: ${e.message}`;
  }
}

// ─── Agent loop ───────────────────────────────────────────────────────────────

async function runAgent(
  history,
  onChunk,
  onToolCall,
  onToolStart,
  onToolComplete,
) {
  // Build rich system context
  let gitContext = "";
  try {
    const log = execFileSync(
      "git",
      ["-C", WORK_DIR, "log", "--oneline", "-3"],
      { encoding: "utf8", timeout: 3000 },
    ).trim();
    const status = execFileSync("git", ["-C", WORK_DIR, "status", "--short"], {
      encoding: "utf8",
      timeout: 3000,
    }).trim();
    gitContext = [log, status].filter(Boolean).join("\n");
  } catch {}

  const messages = [
    {
      role: "system",
      content: [
        `You are GitHub Copilot CLI, a powerful AI developer assistant running on the user's Mac.`,
        ``,
        `## Environment`,
        `- Hostname: ${os.hostname()}`,
        `- User: ${os.userInfo().username}`,
        `- OS: macOS ${os.release()}`,
        `- Working directory: ${WORK_DIR}`,
        `- Shell: zsh`,
        gitContext ? `- Git context:\n${gitContext}` : "",
        ``,
        `## Capabilities`,
        `You have tools to: run shell commands, read/write files, search files, run GitHub CLI commands, and search the web.`,
        `Use @workspace to focus on the current project, @terminal to run commands, @github for GitHub operations.`,
        ``,
        `## Guidelines`,
        `- Be concise but thorough. Show command output when relevant.`,
        `- For code changes, read the file first, then write the full updated content.`,
        `- Use web_search for docs, error messages, or anything requiring up-to-date info.`,
        `- Chain tools naturally: search → read → edit → verify.`,
      ]
        .filter(Boolean)
        .join("\n"),
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
      body: JSON.stringify({
        model: MODEL,
        messages,
        tools: TOOLS,
        stream: true,
      }),
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
              if (!toolCalls[idx])
                toolCalls[idx] = { id: "", name: "", arguments: "" };
              if (tc.id) toolCalls[idx].id = tc.id;
              if (tc.function?.name) toolCalls[idx].name = tc.function.name;
              if (tc.function?.arguments)
                toolCalls[idx].arguments += tc.function.arguments;
            }
          }
        } catch {
          /* skip malformed */
        }
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
      tool_calls: toolCallList.map((tc) => ({
        id: tc.id,
        type: "function",
        function: { name: tc.name, arguments: tc.arguments },
      })),
    });

    for (const tc of toolCallList) {
      let args;
      try {
        args = JSON.parse(tc.arguments);
      } catch {
        args = {};
      }

      const toolStartTime = Date.now();
      onToolCall(tc.name, args);
      if (onToolStart) onToolStart(tc.name, args, tc.id);
      const result = executeTool(tc.name, args);
      const elapsed = Date.now() - toolStartTime;
      if (onToolComplete) onToolComplete(tc.name, elapsed);

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

const agentSessions = new Map(); // sessionId -> { history, status, currentTool, startedAt, lastActivityAt }
const terminalSessions = new Map(); // tmuxSession -> { ws, timer }

// ─── Tmux helpers ─────────────────────────────────────────────────────────────

const PARENT = "copilot-mobile"; // all windows live inside this tmux session

function tmuxCmd(...args) {
  return execFileSync(TMUX, args, {
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

// target string for a named window: "copilot-mobile:windowname"
function target(name) {
  return `${PARENT}:${name}`;
}

function capturePane(name) {
  try {
    return execFileSync(
      TMUX,
      ["capture-pane", "-t", target(name), "-p", "-e", "-S", "-500"],
      { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
    );
  } catch {
    return null;
  }
}

function ensureParentSession() {
  try {
    tmuxCmd("has-session", "-t", PARENT);
    return false;
  } catch {
    tmuxCmd("new-session", "-d", "-s", PARENT, "-x", "220", "-y", "50");
    return true; // newly created
  }
}

function openTerminalAttached(preferred) {
  const scriptPath = "/tmp/copilot-mobile-attach.sh";
  fs.writeFileSync(
    scriptPath,
    `#!/bin/bash\nexec ${TMUX} attach -t ${PARENT}\n`,
    { mode: 0o755 },
  );
  try {
    const lsinfo = execSync("lsappinfo list 2>/dev/null", { encoding: "utf8" });
    const frontmostMatch = lsinfo.match(
      /"([^"]+)"\s+ASN:[^:]+:\s*\(in front\)/,
    );
    const frontmost = frontmostMatch ? frontmostMatch[1] : "";
    const isRunning = (name) => lsinfo.includes(`"${name}" ASN:`);

    console.log(
      `[terminal] Frontmost: "${frontmost}", Preferred: "${preferred || "none"}"`,
    );

    const tryOpen = (appName) =>
      execSync(`open -a "${appName}" "${scriptPath}"`);
    const TERMINALS = ["Warp", "Ghostty", "kitty", "iTerm2", "Terminal"];

    // If preferred is set and is installed/running, use it
    if (preferred && (isRunning(preferred) || TERMINALS.includes(preferred))) {
      try {
        tryOpen(preferred);
        return;
      } catch {}
    }
    // Try frontmost if it's a terminal
    if (TERMINALS.includes(frontmost)) {
      try {
        tryOpen(frontmost);
        return;
      } catch {}
    }
    // Try any running terminal in default order
    const running = TERMINALS.find((t) => isRunning(t));
    if (running) {
      tryOpen(running);
      return;
    }
    execSync(`open -a "Terminal" "${scriptPath}"`);
  } catch (e) {
    console.warn("Could not auto-open terminal:", e.message);
  }
}

function ensureTmux(name, cwd, preferred, startCommand) {
  const parentCreated = ensureParentSession();
  if (parentCreated) openTerminalAttached(preferred);
  try {
    tmuxCmd("select-window", "-t", target(name));
    return false;
  } catch {
    const resolvedCwd = cwd
      ? cwd.replace(/^~/, process.env.HOME)
      : process.env.HOME;
    tmuxCmd("new-window", "-t", PARENT, "-n", name, "-c", resolvedCwd);
    if (startCommand) {
      // Small delay to let shell initialize before sending command
      setTimeout(() => {
        try {
          tmuxCmd("send-keys", "-t", target(name), startCommand, "Enter");
        } catch {}
      }, 800);
    }
    return true;
  }
}
function startPolling(name, ws) {
  let last = "";
  let lastChangeAt = Date.now();

  const getStatus = () => {
    const age = Date.now() - lastChangeAt;
    if (age < 3000) return "running"; // changed in last 3s
    if (age < 60000) return "idle"; // changed in last minute
    return "stale"; // no activity > 1 min
  };

  const poll = () => {
    if (!terminalSessions.has(name)) return;
    const content = capturePane(name);
    if (content === null) {
      if (ws.readyState === ws.OPEN)
        ws.send(
          JSON.stringify({
            type: "screen",
            sessionId: name,
            data: "\r\n[Session ended]\r\n",
            status: "ended",
          }),
        );
      terminalSessions.delete(name);
      return;
    }
    const status = getStatus();
    if (content !== last) {
      lastChangeAt = Date.now();
      if (ws.readyState === ws.OPEN)
        ws.send(
          JSON.stringify({
            type: "screen",
            sessionId: name,
            data: content,
            status: "running",
          }),
        );
      last = content;
    } else if (terminalSessions.get(name)?.lastStatus !== status) {
      // Status changed even though content didn't — notify
      if (ws.readyState === ws.OPEN)
        ws.send(JSON.stringify({ type: "status", sessionId: name, status }));
    }
    if (terminalSessions.has(name))
      terminalSessions.get(name).lastStatus = status;
    terminalSessions.get(name).timer = setTimeout(poll, 150);
  };
  poll();
}

// ─── WebSocket server ─────────────────────────────────────────────────────────

wss.on("connection", (ws, req) => {
  const clientIp = req.socket.remoteAddress || "unknown";
  if (rateLimit(clientIp, 120)) {
    ws.send(JSON.stringify({ type: "error", message: "Rate limited" }));
    ws.close(1008, "Rate limited");
    return;
  }
  if (extractApiKey(req) !== API_KEY) {
    ws.send(JSON.stringify({ type: "error", message: "Unauthorized" }));
    ws.close(1008, "Unauthorized");
    return;
  }

  const send = (obj) => {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
  };
  console.log(`[${new Date().toISOString()}] Client connected`);

  ws.on("message", async (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      send({ type: "error", message: "Invalid JSON" });
      return;
    }
    console.log(`[msg] ${msg.type} session=${msg.sessionId || "-"}`);

    switch (msg.type) {
      // ── Ping ──
      case "ping":
        send({ type: "pong" });
        break;

      // ── Agent chat ──────────────────────────────────────────────────────────
      case "agent_chat": {
        const { sessionId, content } = msg;
        if (!agentSessions.has(sessionId)) {
          agentSessions.set(sessionId, {
            history: [],
            status: "idle",
            currentTool: null,
            startedAt: null,
            lastActivityAt: null,
          });
        }
        const session = agentSessions.get(sessionId);
        session.history.push({ role: "user", content });
        session.status = "thinking";
        session.startedAt = Date.now();
        session.lastActivityAt = Date.now();
        send({
          type: "agent_status",
          sessionId,
          status: "thinking",
          startedAt: session.startedAt,
        });

        try {
          let fullResponse = "";
          const response = await runAgent(
            [...session.history],
            (chunk) => {
              fullResponse += chunk;
              send({ type: "agent_chunk", sessionId, content: chunk });
            },
            (toolName, toolArgs) => {
              send({
                type: "tool_call",
                sessionId,
                tool: toolName,
                args: toolArgs,
              });
            },
            (toolName, toolArgs, toolId) => {
              session.status = "running_tool";
              session.currentTool = {
                name: toolName,
                args: toolArgs,
                startedAt: Date.now(),
              };
              session.lastActivityAt = Date.now();
              send({
                type: "agent_status",
                sessionId,
                status: "running_tool",
                tool: toolName,
                args: toolArgs,
              });
              send({
                type: "tool_start",
                sessionId,
                tool: toolName,
                args: toolArgs,
                toolId,
              });
            },
            (toolName, elapsed) => {
              session.status = "thinking";
              session.currentTool = null;
              session.lastActivityAt = Date.now();
              send({
                type: "tool_complete",
                sessionId,
                tool: toolName,
                elapsed,
              });
            },
          );
          session.history.push({ role: "assistant", content: response });
          session.status = "idle";
          session.currentTool = null;
          session.lastActivityAt = Date.now();
          send({ type: "agent_done", sessionId });
          send({ type: "agent_status", sessionId, status: "idle" });
        } catch (err) {
          console.error("Agent error:", err.message);
          session.status = "idle";
          session.currentTool = null;
          session.lastActivityAt = Date.now();
          send({ type: "agent_error", sessionId, message: err.message });
          send({ type: "agent_status", sessionId, status: "idle" });
        }
        break;
      }

      case "new_agent_session": {
        const sessionId = msg.sessionId || crypto.randomUUID();
        agentSessions.set(sessionId, {
          history: [],
          status: "idle",
          currentTool: null,
          startedAt: null,
          lastActivityAt: null,
        });
        send({ type: "agent_session_created", sessionId });
        break;
      }

      case "clear_agent_session": {
        if (agentSessions.has(msg.sessionId)) {
          agentSessions.get(msg.sessionId).history = [];
        } else {
          agentSessions.set(msg.sessionId, {
            history: [],
            status: "idle",
            currentTool: null,
            startedAt: null,
            lastActivityAt: null,
          });
        }
        send({ type: "agent_session_cleared", sessionId: msg.sessionId });
        break;
      }

      // ── Terminal (tmux) ─────────────────────────────────────────────────────
      case "new_session": {
        const name = msg.tmuxSession || msg.sessionId || "mobile";
        const workDir = msg.workDir || null;
        const preferred = msg.preferredTerminal || null;
        const startCommand = msg.startCommand || DEFAULT_START_COMMAND || null;
        const existing = terminalSessions.get(name);
        if (existing) clearTimeout(existing.timer);
        const created = ensureTmux(name, workDir, preferred, startCommand);
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
          if (data === "\u0003") tmuxCmd("send-keys", "-t", target(sid), "C-c");
          else if (data === "\t")
            tmuxCmd("send-keys", "-t", target(sid), "Tab");
          else {
            const text = data.replace(/[\r\n]+$/, "");
            const hasNl = data !== text;
            if (text) {
              const esc = text.replace(/'/g, "'\\''");
              tmuxCmd("send-keys", "-t", target(sid), `'${esc}'`);
            }
            if (hasNl) tmuxCmd("send-keys", "-t", target(sid), "Enter");
          }
        } catch (e) {
          send({ type: "error", message: e.message });
        }
        break;
      }

      case "close_session": {
        const s = terminalSessions.get(msg.sessionId);
        if (s) {
          clearTimeout(s.timer);
          terminalSessions.delete(msg.sessionId);
        }
        break;
      }

      default:
        send({ type: "error", message: `Unknown type: ${msg.type}` });
    }
  });

  ws.on("close", () => {
    for (const [id, s] of terminalSessions) {
      if (s.ws === ws) {
        clearTimeout(s.timer);
        terminalSessions.delete(id);
      }
    }
    console.log(`[${new Date().toISOString()}] Client disconnected`);
  });
});

app.get("/api/agent-sessions", (req, res) => {
  if (extractApiKey(req) !== API_KEY)
    return res.status(401).json({ error: "Unauthorized" });
  const sessions = Array.from(agentSessions.entries()).map(([id, s]) => ({
    sessionId: id,
    status: s.status || "idle",
    currentTool: s.currentTool || null,
    messageCount: (s.history || s).length,
    startedAt: s.startedAt || null,
    lastActivityAt: s.lastActivityAt || null,
  }));
  res.json({ sessions });
});

app.get("/api/terminals", (req, res) => {
  if (extractApiKey(req) !== API_KEY)
    return res.status(401).json({ error: "Unauthorized" });
  const KNOWN = [
    { name: "Warp", bundle: "Warp.app" },
    { name: "Ghostty", bundle: "Ghostty.app" },
    { name: "kitty", bundle: "kitty.app" },
    { name: "iTerm2", bundle: "iTerm.app" },
    { name: "Terminal", bundle: "Terminal.app" },
  ];
  const isInstalled = (bundle) => {
    const paths = [
      `/Applications/${bundle}`,
      `/System/Applications/${bundle}`,
      `/System/Applications/Utilities/${bundle}`,
    ];
    return paths.some((p) => {
      try {
        fs.accessSync(p);
        return true;
      } catch {
        return false;
      }
    });
  };
  const terminals = KNOWN.filter((t) => isInstalled(t.bundle)).map(
    (t) => t.name,
  );
  res.json({ terminals });
});

app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    model: MODEL,
    agentSessions: agentSessions.size,
    terminalSessions: terminalSessions.size,
    uptime: process.uptime(),
  });
});

const PORT = parseInt(process.env.PORT || "3003", 10);
server.listen(PORT, () => {
  console.log(`\n🚀 Copilot CLI Server on port ${PORT}`);
  console.log(`   Model: ${MODEL}  |  Work dir: ${WORK_DIR}`);
  console.log(`   Health: http://localhost:${PORT}/health\n`);

  // Auto-create default "copilot" session on startup
  if (DEFAULT_START_COMMAND) {
    try {
      ensureTmux("copilot", WORK_DIR, null, DEFAULT_START_COMMAND);
      console.log(
        `   Auto-started session "copilot" with: ${DEFAULT_START_COMMAND}`,
      );
    } catch (e) {
      console.warn("   Could not auto-start session:", e.message);
    }
  }
});
