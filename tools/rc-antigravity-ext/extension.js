const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const vscode = require("vscode");

const MAX_BODY_BYTES = 1024 * 1024;

let server = null;
let serverPort = 0;
let regFilePath = null;
let lastFocusedAt = 1;
let exitHandlerRegistered = false;

function getStateDir() {
  const xdgState = (process.env.XDG_STATE_HOME || "").trim();
  const base = xdgState || path.join(os.homedir(), ".local", "state");
  return path.join(base, "rc-antigravity");
}

function getWorkspaceFolders() {
  const folders = vscode.workspace.workspaceFolders || [];
  return folders
    .map((f) => (f && f.uri && f.uri.fsPath ? String(f.uri.fsPath) : ""))
    .filter(Boolean);
}

function getWorkspaceName() {
  if (typeof vscode.workspace.name === "string" && vscode.workspace.name.trim()) {
    return vscode.workspace.name.trim();
  }
  const folders = getWorkspaceFolders();
  if (folders.length > 0) {
    return path.basename(folders[0]) || folders[0];
  }
  return "Antigravity IDE";
}

function writeRegistration() {
  if (!serverPort) return;
  try {
    const dir = getStateDir();
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    try {
      fs.chmodSync(dir, 0o700);
    } catch (_) {}
    if (!regFilePath) {
      regFilePath = path.join(dir, `window-${process.pid}.json`);
    }
    const payload = {
      url: `http://127.0.0.1:${serverPort}`,
      host: "127.0.0.1",
      port: serverPort,
      pid: process.pid,
      workspaceName: getWorkspaceName(),
      workspaceFolders: getWorkspaceFolders(),
      windowFocused: !!(vscode.window.state && vscode.window.state.focused),
      lastFocusedAt,
    };
    const tmpPath = `${regFilePath}.tmp.${process.pid}`;
    fs.writeFileSync(tmpPath, JSON.stringify(payload, null, 2), { mode: 0o600 });
    fs.renameSync(tmpPath, regFilePath);
  } catch (_) {}
}

function removeRegistration() {
  if (!regFilePath) return;
  try {
    fs.unlinkSync(regFilePath);
  } catch (_) {}
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getCascadeFocusState() {
  if (vscode.Cascade && typeof vscode.Cascade.getFocusState === "function") {
    try {
      const state = await vscode.Cascade.getFocusState();
      return {
        isVisible: !!(state && state.isVisible),
        isFocused: !!(state && state.isFocused),
      };
    } catch (_) {}
  }
  return { isVisible: false, isFocused: false };
}

async function openAndFocusAgentChatOnce() {
  if (vscode.Cascade && typeof vscode.Cascade.openPanel === "function") {
    try {
      await vscode.Cascade.openPanel();
    } catch (_) {}
  }
  try {
    await vscode.commands.executeCommand("antigravity.panel.focus");
  } catch (_) {}

  let focused = false;
  try {
    await vscode.commands.executeCommand("antigravity.toggleChatFocus", "focus");
    focused = true;
  } catch (_) {}

  if (!focused) {
    try {
      await vscode.commands.executeCommand("antigravity.addContext", []);
      focused = true;
    } catch (_) {}
  }
  return focused;
}

async function focusAndVerifyAgentChat(timeoutMs = 1500) {
  let commandFocused = await openAndFocusAgentChatOnce();
  await sleep(120);

  const deadline = Date.now() + timeoutMs;
  let attempt = 0;
  let state = await getCascadeFocusState();
  while (Date.now() < deadline) {
    // Cascade.getFocusState().isFocused checks the outer workbench DOM and returns false
    // for the Agent webview iframe, so accept a successful webview focus command once visible.
    if (commandFocused && (state.isVisible || state.isFocused)) {
      await sleep(80);
      return { isVisible: true, isFocused: true };
    }
    if (state.isVisible && state.isFocused) {
      await sleep(80);
      return { isVisible: true, isFocused: true };
    }
    attempt += 1;
    if (attempt % 3 === 0 || !commandFocused) {
      const ok = await openAndFocusAgentChatOnce();
      if (ok) {
        commandFocused = true;
      }
    }
    await sleep(100);
    state = await getCascadeFocusState();
  }

  if (commandFocused) {
    await sleep(80);
    return { isVisible: true, isFocused: true };
  }
  return {
    isVisible: !!state.isVisible,
    isFocused: !!state.isFocused,
  };
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        reject(new Error("Request body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8").trim();
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(new Error(`Invalid JSON body: ${err.message}`));
      }
    });
    req.on("error", (err) => reject(err));
  });
}

function sendJson(res, statusCode, obj) {
  const raw = JSON.stringify(obj);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(raw, "utf8"),
  });
  res.end(raw);
}

async function handleRequest(req, res) {
  const urlPath = (req.url || "/").split("?")[0];

  if (req.method === "GET" && urlPath === "/info") {
    sendJson(res, 200, {
      ok: true,
      pid: process.pid,
      port: serverPort,
      workspaceName: getWorkspaceName(),
      workspaceFolders: getWorkspaceFolders(),
      windowFocused: !!(vscode.window.state && vscode.window.state.focused),
      lastFocusedAt,
    });
    return;
  }

  if (req.method === "POST" && urlPath === "/prepare") {
    const focus = await focusAndVerifyAgentChat(1500);
    if (!focus.isFocused) {
      sendJson(res, 200, {
        ok: false,
        error: "Antigravity Agent chat input did not gain focus",
        isVisible: focus.isVisible,
        isFocused: false,
      });
      return;
    }
    sendJson(res, 200, {
      ok: true,
      isVisible: true,
      isFocused: true,
      workspaceName: getWorkspaceName(),
      workspaceFolders: getWorkspaceFolders(),
    });
    return;
  }

  if (req.method === "POST" && urlPath === "/populate") {
    let body;
    try {
      body = await readJsonBody(req);
    } catch (err) {
      sendJson(res, 400, { ok: false, error: err.message || "Invalid JSON body" });
      return;
    }
    await focusAndVerifyAgentChat(1000);
    const cleanText = typeof body.text === "string" ? body.text.trim() : "";
    if (cleanText.length > 0) {
      try {
        await vscode.commands.executeCommand("antigravity.addContext", [cleanText]);
        try {
          await vscode.commands.executeCommand("antigravity.toggleChatFocus", "focus");
        } catch (_) {}
      } catch (err) {
        sendJson(res, 500, {
          ok: false,
          error: (err && err.message) || "Failed to execute antigravity.addContext",
        });
        return;
      }
    }
    await sleep(120);

    let sent = false;
    if (body.autoSend === true) {
      try {
        await vscode.commands.executeCommand("antigravity.triggerSend");
        sent = true;
      } catch (_) {
        sent = false;
      }
    }

    sendJson(res, 200, {
      ok: true,
      isVisible: true,
      isFocused: true,
      sent,
      workspaceName: getWorkspaceName(),
    });
    return;
  }

  sendJson(res, 404, { ok: false, error: "Not found" });
}

function startBridgeServer() {
  return new Promise((resolve, reject) => {
    const srv = http.createServer((req, res) => {
      handleRequest(req, res).catch((err) => {
        if (!res.headersSent) {
          sendJson(res, 500, {
            ok: false,
            error: (err && err.message) || "Internal bridge error",
          });
        } else {
          try {
            res.end();
          } catch (_) {}
        }
      });
    });
    srv.on("error", (err) => reject(err));
    srv.listen(0, "127.0.0.1", () => {
      const addr = srv.address();
      server = srv;
      serverPort = addr && typeof addr === "object" ? addr.port : 0;
      writeRegistration();
      resolve();
    });
  });
}

async function activate(context) {
  lastFocusedAt = vscode.window.state && vscode.window.state.focused ? Date.now() : 1;

  if (!exitHandlerRegistered) {
    exitHandlerRegistered = true;
    process.on("exit", removeRegistration);
  }

  context.subscriptions.push(
    vscode.window.onDidChangeWindowState((state) => {
      if (state && state.focused) {
        lastFocusedAt = Date.now();
      }
      writeRegistration();
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      writeRegistration();
    }),
    vscode.commands.registerCommand("rcAntigravityBridge.focusChat", async () => {
      return focusAndVerifyAgentChat(1800);
    }),
    vscode.window.registerUriHandler({
      async handleUri() {
        await focusAndVerifyAgentChat(1800);
      },
    }),
    {
      dispose() {
        deactivate();
      },
    }
  );

  await startBridgeServer();
}

function deactivate() {
  removeRegistration();
  if (server) {
    try {
      server.close();
    } catch (_) {}
    server = null;
    serverPort = 0;
  }
}

module.exports = {
  activate,
  deactivate,
};
