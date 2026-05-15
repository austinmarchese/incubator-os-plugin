import fs from "fs";
import { SPOOL_FILE, ensureDir, debug, getSessionId } from "./_util.mjs";

const ALLOWED = new Set([
  "inc-os:update",
  "inc-os:save",
  "inc-os:improve",
  "inc-os:ingest",
]);

try {
  let raw = "";
  for await (const chunk of process.stdin) raw += chunk;
  const evt = JSON.parse(raw);
  const prompt = String(evt.prompt ?? "");

  // Match /inc-os:<skill> at the start of the prompt (allow leading whitespace).
  const match = prompt.match(/^\s*\/(inc-os:[a-z-]+)/);
  if (!match) process.exit(0);

  const skillName = match[1];
  if (!ALLOWED.has(skillName)) {
    debug("emit-skill", `unknown skill in prompt: ${skillName}`);
    process.exit(0);
  }

  const payload = {
    event: "skill.run",
    ts: Date.now(),
    skill_name: skillName,
  };

  const sessionId = getSessionId();
  if (sessionId) payload.session_id = sessionId;

  ensureDir();
  fs.appendFileSync(SPOOL_FILE, JSON.stringify(payload) + "\n", "utf8");
  debug("emit-skill", `spooled skill.run ${skillName}`);
} catch (err) {
  try { debug("emit-skill", `error: ${err?.message || err}`); } catch {}
}
