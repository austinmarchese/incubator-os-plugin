import fs from "fs";
import path from "path";
import { spawn } from "child_process";
import { fileURLToPath } from "url";
import { SPOOL_FILE, INC_OS_DIR, ensureDir, sanitize, debug } from "./_util.mjs";

const MAX_SPOOL_BYTES = 5 * 1024 * 1024; // 5 MB
const FLUSH_THROTTLE_MS = 30 * 1000;
const FLUSH_THROTTLE_FILE = `${INC_OS_DIR}/last-flush-spawn`;
const FLUSH_LINE_THRESHOLD = 10;
const FLUSH_AGE_THRESHOLD_MS = 60 * 1000;

function trimSpoolIfOversize() {
  try {
    const stat = fs.statSync(SPOOL_FILE);
    if (stat.size <= MAX_SPOOL_BYTES) return;
    const data = fs.readFileSync(SPOOL_FILE, "utf8");
    const lines = data.split("\n");
    // Drop oldest half
    const keep = lines.slice(Math.floor(lines.length / 2)).join("\n");
    fs.writeFileSync(SPOOL_FILE, keep, "utf8");
    debug("emit", `spool trimmed to ${keep.length} bytes (was ${stat.size})`);
  } catch {}
}

function shouldFlush() {
  try {
    // Throttle: don't spawn flush more than once per 30s
    if (fs.existsSync(FLUSH_THROTTLE_FILE)) {
      const stat = fs.statSync(FLUSH_THROTTLE_FILE);
      if (Date.now() - stat.mtimeMs < FLUSH_THROTTLE_MS) return false;
    }

    const data = fs.readFileSync(SPOOL_FILE, "utf8");
    const lines = data.split("\n").filter(Boolean);

    if (lines.length >= FLUSH_LINE_THRESHOLD) return true;

    // Check oldest event age
    if (lines.length > 0) {
      try {
        const first = JSON.parse(lines[0]);
        if (first.ts && (Date.now() - first.ts) >= FLUSH_AGE_THRESHOLD_MS) return true;
      } catch {}
    }
  } catch {}
  return false;
}

function spawnFlush() {
  try {
    ensureDir();
    fs.writeFileSync(FLUSH_THROTTLE_FILE, String(Date.now()), "utf8");
    const __dirname = path.dirname(fileURLToPath(import.meta.url));
    const flushScript = path.join(__dirname, "flush.mjs");
    const child = spawn("node", [flushScript], { detached: true, stdio: "ignore" });
    child.unref();
    debug("emit", "spawned detached flush");
  } catch (err) {
    debug("emit", `flush spawn error: ${err?.message || err}`);
  }
}

try {
  let raw = "";
  for await (const chunk of process.stdin) raw += chunk;
  const evt = JSON.parse(raw);

  const toolName = evt.tool_name || evt.toolName || "";
  if (!toolName) {
    debug("emit", "no tool name in payload");
    process.exit(0);
  }

  const payload = sanitize(toolName, evt.tool_input || evt.toolInput || {});

  ensureDir();
  trimSpoolIfOversize();
  fs.appendFileSync(SPOOL_FILE, JSON.stringify(payload) + "\n", "utf8");
  debug("emit", `spooled ${payload.event} ${payload.tool_name || payload.skill_name || ""}`);

  if (shouldFlush()) {
    spawnFlush();
  }
} catch (err) {
  try { debug("emit", `error: ${err?.message || err}`); } catch {}
}
