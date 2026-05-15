import { execSync } from "child_process";
import path from "path";
import os from "os";
import { readAuth, debug } from "./_util.mjs";

try {
  const auth = readAuth();
  if (!auth?.token) process.exit(0);

  const cwd = process.cwd();
  const workspaceBase = path.join(os.homedir(), "incubator");
  if (!cwd.startsWith(workspaceBase)) {
    process.exit(0);
  }

  // Find the repo root by walking up until we hit a .git dir
  let dir = cwd;
  let foundRepo = false;
  for (let i = 0; i < 8; i++) {
    try {
      execSync("git rev-parse --git-dir", { cwd: dir, stdio: "ignore" });
      foundRepo = true;
      break;
    } catch {
      const parent = path.dirname(dir);
      if (parent === dir || !parent.startsWith(workspaceBase)) break;
      dir = parent;
    }
  }
  if (!foundRepo) process.exit(0);

  // Verify this is the expected workspace repo (origin must match auth.json.repo_url).
  if (auth.repo_url) {
    let originUrl = "";
    try {
      originUrl = execSync("git remote get-url origin", { cwd: dir }).toString().trim();
    } catch {
      process.exit(0);
    }
    // Compare ignoring trailing .git
    const normalize = (u) => u.replace(/\.git$/, "");
    if (normalize(originUrl) !== normalize(auth.repo_url)) {
      debug("check-behind", `origin ${originUrl} does not match expected ${auth.repo_url}, skipping`);
      process.exit(0);
    }
  }

  try {
    execSync("git fetch origin main --quiet", { cwd: dir, stdio: "ignore", timeout: 8000 });
  } catch {
    debug("check-behind", "fetch failed (offline?)");
    process.exit(0);
  }

  let behind = 0;
  try {
    behind = parseInt(
      execSync("git rev-list --count HEAD..origin/main", { cwd: dir }).toString().trim(),
      10,
    );
  } catch {
    process.exit(0);
  }

  if (behind > 0) {
    const message = {
      systemMessage: `${behind} commit${behind === 1 ? "" : "s"} behind origin/main. Run /inc-os:update to sync.`,
    };
    process.stdout.write(JSON.stringify(message));
    debug("check-behind", `${behind} commits behind`);
  }
} catch (err) {
  try { debug("check-behind", `error: ${err?.message || err}`); } catch {}
}
