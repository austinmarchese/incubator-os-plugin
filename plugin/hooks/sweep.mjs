import fs from "fs";
import os from "os";
import path from "path";
import { fileURLToPath } from "url";
import { SPOOL_FILE, readAuth, apiBase, debug, truncateDebugLog } from "./_util.mjs";

const CLAUDE_MD = path.join(os.homedir(), ".claude", "CLAUDE.md");
const BLOCK_START = "<!-- incubator-os-start -->";
const BLOCK_END = "<!-- incubator-os-end -->";

function pluginRoot() {
  if (process.env.CLAUDE_PLUGIN_ROOT) return process.env.CLAUDE_PLUGIN_ROOT;
  // Fallback: hooks/sweep.mjs is two levels under plugin root
  const here = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(here, "..");
}

function syncClaudeMdBlock() {
  try {
    const blockFile = path.join(pluginRoot(), "claude-md-block.txt");
    if (!fs.existsSync(blockFile)) return;
    const canonical = fs.readFileSync(blockFile, "utf8").trim();

    let existing = "";
    try {
      existing = fs.readFileSync(CLAUDE_MD, "utf8");
    } catch {
      // File doesn't exist; create parent + empty file path
    }
    fs.mkdirSync(path.dirname(CLAUDE_MD), { recursive: true });

    // Strip existing block (if any) via regex spanning the markers
    const stripped = existing.replace(
      new RegExp(`\\n*${BLOCK_START}[\\s\\S]*?${BLOCK_END}\\n*`, "g"),
      "\n",
    );

    const next = stripped.trimEnd() + "\n\n" + canonical + "\n";

    if (next === existing) {
      debug("sweep", "CLAUDE.md block already up to date");
      return;
    }

    const tmp = `${CLAUDE_MD}.tmp`;
    fs.writeFileSync(tmp, next, "utf8");
    fs.renameSync(tmp, CLAUDE_MD);
    debug("sweep", "CLAUDE.md block synced");
  } catch (err) {
    debug("sweep", `claude-md sync error: ${err?.message || err}`);
  }
}

try {
  truncateDebugLog();
  syncClaudeMdBlock();

  const auth = readAuth();
  if (!auth?.token) process.exit(0);

  let data;
  try {
    data = fs.readFileSync(SPOOL_FILE, "utf8").trim();
  } catch {
    process.exit(0);
  }
  if (!data) process.exit(0);

  const events = data
    .split("\n")
    .filter(Boolean)
    .map((line) => { try { return JSON.parse(line); } catch { return null; } })
    .filter(Boolean);

  if (events.length === 0) {
    fs.writeFileSync(SPOOL_FILE, "", "utf8");
    process.exit(0);
  }

  const res = await fetch(`${apiBase(auth)}/api/incubator-os/ingest`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${auth.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ events }),
    signal: AbortSignal.timeout(10000),
  });

  if (res.ok) {
    fs.writeFileSync(SPOOL_FILE, "", "utf8");
    debug("sweep", `swept ${events.length} orphaned events`);
  } else {
    debug("sweep", `server returned ${res.status}, keeping spool`);
  }
} catch (err) {
  try { debug("sweep", `error: ${err?.message || err}`); } catch {}
}
