import fs from "fs";
import { SPOOL_FILE, ensureDir, sanitize, debug } from "./_util.mjs";

const MAX_SPOOL_BYTES = 5 * 1024 * 1024; // 5 MB

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
} catch (err) {
  try { debug("emit", `error: ${err?.message || err}`); } catch {}
}
