import fs from "fs";
import os from "os";
import path from "path";

export const INC_OS_DIR = path.join(os.homedir(), ".incubator-os");
export const AUTH_FILE = path.join(INC_OS_DIR, "auth.json");
export const SPOOL_FILE = path.join(INC_OS_DIR, "spool.ndjson");
export const DEBUG_LOG = path.join(INC_OS_DIR, "debug.log");
export const UPDATE_THROTTLE = path.join(INC_OS_DIR, "last-update-check");

export const DEFAULT_API_BASE = "https://incubator-os.com";

export function ensureDir() {
  try {
    fs.mkdirSync(INC_OS_DIR, { recursive: true });
  } catch {}
}

export function readAuth() {
  try {
    return JSON.parse(fs.readFileSync(AUTH_FILE, "utf8"));
  } catch {
    return null;
  }
}

export function apiBase(auth) {
  return auth?.api_base || DEFAULT_API_BASE;
}

export function debug(prefix, message) {
  try {
    ensureDir();
    const line = `[${new Date().toISOString()}] [${prefix}] ${message}\n`;
    fs.appendFileSync(DEBUG_LOG, line, "utf8");
  } catch {}
}

export function truncateDebugLog(maxBytes = 256 * 1024) {
  try {
    const stat = fs.statSync(DEBUG_LOG);
    if (stat.size <= maxBytes) return;
    const data = fs.readFileSync(DEBUG_LOG, "utf8");
    const keep = data.slice(Math.floor(data.length / 2));
    fs.writeFileSync(DEBUG_LOG, keep, "utf8");
  } catch {}
}

// Allowlist-based sanitization. Constructs a NEW object; never forwards raw input.
export function sanitize(toolName, toolInput) {
  const ts = Date.now();
  if (toolName === "Skill") {
    let skill =
      toolInput?.skill ??
      toolInput?.skill_name ??
      toolInput?.name ??
      toolInput?.skillName ??
      null;
    // Claude Code passes the bare skill name (e.g., "update"); qualify it.
    if (skill && typeof skill === "string" && !skill.includes(":")) {
      skill = `inc-os:${skill}`;
    }
    if (!skill) {
      try {
        const dbgKeys = Object.keys(toolInput || {}).slice(0, 10).join(",");
        debug("sanitize", `Skill tool_input keys (no skill name found): [${dbgKeys}]`);
      } catch {}
    }
    return { event: "skill.run", ts, skill_name: skill };
  }
  const event = { event: "tool_use", ts, tool_name: toolName };
  if (toolName === "Bash") {
    const cmd = String(toolInput?.command ?? "").trim().split(/\s+/)[0];
    if (cmd) event.cmd = cmd;
  } else if (toolName === "Read" || toolName === "Edit" || toolName === "Write") {
    const filePath = String(toolInput?.file_path ?? "");
    if (filePath) event.file = path.basename(filePath);
  }
  return event;
}
