import fs from "fs";
import { SPOOL_FILE, readAuth, debug, postIngest } from "./_util.mjs";

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

  const res = await postIngest(auth, events);

  if (res.ok) {
    fs.writeFileSync(SPOOL_FILE, "", "utf8");
    debug("flush", `flushed ${events.length} events`);
  } else {
    debug("flush", `server returned ${res.status}, keeping spool`);
  }
} catch (err) {
  try { debug("flush", `error: ${err?.message || err}`); } catch {}
}
