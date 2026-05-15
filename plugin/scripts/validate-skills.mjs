#!/usr/bin/env node
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SKILLS_DIR = path.join(__dirname, "..", "skills");

// Mirror of INC_OS_SKILL_NAMES from src/lib/inc-os-skills.ts
const ALLOWED = new Set(["inc-os:update", "inc-os:save", "inc-os:improve-system", "inc-os:ingest"]);

const errors = [];
const seenNames = new Set();

if (!fs.existsSync(SKILLS_DIR)) {
  console.error(`Skills directory missing: ${SKILLS_DIR}`);
  process.exit(1);
}

for (const entry of fs.readdirSync(SKILLS_DIR, { withFileTypes: true })) {
  if (!entry.isDirectory()) continue;
  const folder = entry.name;
  const skillFile = path.join(SKILLS_DIR, folder, "SKILL.md");
  if (!fs.existsSync(skillFile)) {
    errors.push(`${folder}: missing SKILL.md`);
    continue;
  }
  const content = fs.readFileSync(skillFile, "utf8");
  const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
  if (!frontmatterMatch) {
    errors.push(`${folder}: missing YAML frontmatter`);
    continue;
  }
  const fm = frontmatterMatch[1];
  const nameMatch = fm.match(/^name:\s*(.+?)\s*$/m);
  const descMatch = fm.match(/^description:\s*(.+?)\s*$/m);
  if (!nameMatch || !nameMatch[1].trim()) {
    errors.push(`${folder}: frontmatter missing 'name'`);
    continue;
  }
  if (!descMatch || !descMatch[1].trim()) {
    errors.push(`${folder}: frontmatter missing 'description'`);
  }
  const name = nameMatch[1].trim().replace(/^["']|["']$/g, "");
  const expectedName = `inc-os:${folder}`;
  if (name !== expectedName) {
    errors.push(`${folder}: frontmatter name '${name}' must be '${expectedName}'`);
  }
  if (!ALLOWED.has(name)) {
    errors.push(`${folder}: '${name}' not in SKILL_NAMES allowlist`);
  }
  if (seenNames.has(name)) {
    errors.push(`${folder}: duplicate name '${name}'`);
  }
  seenNames.add(name);
}

if (errors.length > 0) {
  console.error("Skill validation FAILED:");
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}

console.log(`✓ All ${seenNames.size} skills valid.`);
