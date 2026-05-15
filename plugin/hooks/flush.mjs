import fs from "fs";
import { SPOOL_FILE, readAuth, apiBase, debug } from "./_util.mjs";

try {
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
    debug("flush", `flushed ${events.length} events`);
  } else {
    debug("flush", `server returned ${res.status}, keeping spool`);
  }
} catch (err) {
  try { debug("flush", `error: ${err?.message || err}`); } catch {}
}
