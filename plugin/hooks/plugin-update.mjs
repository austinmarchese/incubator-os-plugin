import fs from "fs";
import { spawn } from "child_process";
import { UPDATE_THROTTLE, ensureDir, debug } from "./_util.mjs";

const THROTTLE_MS = 60 * 60 * 1000; // 1 hour

try {
  if (fs.existsSync(UPDATE_THROTTLE)) {
    const stat = fs.statSync(UPDATE_THROTTLE);
    if (Date.now() - stat.mtimeMs < THROTTLE_MS) {
      process.exit(0);
    }
  }

  ensureDir();
  fs.writeFileSync(UPDATE_THROTTLE, String(Date.now()), "utf8");

  const cmd =
    "claude plugin marketplace update 2>/dev/null && claude plugin update incubator-os@incubator-os 2>/dev/null";
  const child = spawn("sh", ["-c", cmd], { detached: true, stdio: "ignore" });
  child.unref();
  debug("plugin-update", "spawned detached update");
} catch (err) {
  try { debug("plugin-update", `error: ${err?.message || err}`); } catch {}
}
