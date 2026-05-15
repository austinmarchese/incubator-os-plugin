---
name: inc-os:update-system
description: "Update your system. Pull latest changes from main and summarize what's new. Syncs skills, knowledge, frameworks, and shared Claude Code settings so your system stays current."
---

# /inc-os:update-system

Sync this project's local checkout with `origin/main` and give a briefing on what's new — not just "files updated" but "here's what changed and what it means for how you work."

## When to use

- Triggered by the SessionStart alert ("This project is N commits behind origin/main").
- Manually when you know work has landed that you want to pull.
- Before starting a new session of meaningful work.

## Instructions

### Step 1: Check current state

Run in parallel:
- `git -C "$CLAUDE_PROJECT_DIR" fetch origin main --quiet`
- `git -C "$CLAUDE_PROJECT_DIR" status --short`
- `git -C "$CLAUDE_PROJECT_DIR" rev-list --count HEAD..origin/main`
- `git -C "$CLAUDE_PROJECT_DIR" rev-list --count origin/main..HEAD`

Interpret:
- Behind = 0 and no local changes → tell the user they're up to date, stop.
- Behind > 0 → proceed.
- Ahead > 0 → mention it; local has unpushed commits. Fine, rebase will handle.
- Dirty working tree → note it; `--autostash` will handle.

### Step 2: Preview what's changing

Before pulling, show what's about to land:

```
git log HEAD..origin/main --oneline
git diff --stat HEAD..origin/main
```

Group the changed files by area and summarize:

| Area | Path prefix | What to call it |
|------|-------------|-----------------|
| Skills | `.claude/skills/` | New/updated slash commands |
| Wiki | `wiki/` | New frameworks, brand-voice, offers, audience, advisor profiles, templates |
| Clients | `clients/` | Per-client folders (confidential) |
| Website | `app/`, `public/` | **Auto-deploys on push to main** |
| Settings | `.claude/settings.json` | **Claude Code settings (hooks, permissions)** |
| Scripts | `scripts/` | Bootstrap, status checks, ingest utilities |
| Root docs | `CLAUDE.md`, `README.md` | Instructions |

**Critical check:** if `.claude/settings.json` changed, flag it explicitly. New hooks/permissions will prompt the user to re-approve on next session (Claude Code security behavior). Tell them this is expected.

### Step 3: Pull

```
git -C "$CLAUDE_PROJECT_DIR" pull --rebase --autostash origin main
```

If the pull fails (merge conflict or rebase conflict), stop and show the output. Do **not** attempt to resolve conflicts automatically. Give the user:
- The files in conflict (`git status`)
- Suggested next step: resolve manually, then `git rebase --continue` or `git rebase --abort`

If the conflict touches anything inside `clients/` (per-client work), be extra careful — flag it explicitly so the user doesn't accidentally lose engagement notes.

### Step 4: Briefing

After a successful pull, deliver a structured briefing. Don't just list files — explain what's new in human terms.

Template:

```
Updated to latest main (N commits).

What's new:

SKILLS
  • /inc-os:new-skill-name — one-line purpose
  • /inc-os:existing-skill — what changed (e.g., "added new mode", "reworded prompt")

WIKI
  • wiki/frameworks/X/Y.md — what it teaches
  • wiki/consultants/new-person.md — new advisor profile
  • wiki/offers/{name}.md — offer added or rewritten

WEBSITE
  • app/... or public/... — note that pushes auto-deploy on merge to main

SETTINGS
  • .claude/settings.json changed. You may be prompted to re-approve
    hooks/permissions on next session — expected.

What this means for you:
  <1-3 sentences on what's worth knowing. e.g., "Use /inc-os:new-skill-name
  instead of manually doing X", or "The /inc-os:improve-system skill now
  auto-discovers any advisor file added under wiki/consultants/.">

```

Skim the contents of new/changed skill files (just the front-matter `description` + first section) to write meaningful one-liners. Do not just echo filenames.

### Step 5: Cleanup check

Quickly verify:
- Any new skills listed in CLAUDE.md? (If CLAUDE.md mentions a skill that doesn't exist locally, something's wrong.)
- Any gitignored patterns that might now be catching files the user cares about?

Only flag if there's a real issue. Otherwise end with the briefing.

## What this skill does NOT do

- Does not push local commits. That's the user's call.
- Does not resolve merge conflicts automatically.
- Does not modify local settings (`settings.local.json` stays personal).
- Does not run `/inc-os:improve-system` or any other skill as a side effect.

## Common edge cases

- **Offline / no network:** `git fetch` fails. Tell the user they appear offline and to retry later.
- **Detached HEAD or non-main branch:** warn the user and stop. They may be mid-experiment.
- **Large diff (50+ files):** don't dump the full list. Group by area and give counts per area, then highlight the most impactful changes (new skills, settings changes).
- **First run after cloning:** the user will see the SessionStart prompt asking to approve hooks from `.claude/settings.json`. That's normal.
