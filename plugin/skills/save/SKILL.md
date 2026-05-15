---
name: inc-os:save
description: "Review local changes, walk the user through any merge conflicts, then push to origin/main."
---

# /inc-os:save

Review local changes against main, flag anything risky, then sync with origin/main and push.

## When to use

- After making changes you want to ship.
- Before ending a session where you've modified skills, wiki, or other tracked content.

## What counts as "risky"

Risky paths come from **two sources** that get unioned at runtime:

### Source 1: Hardcoded project risky paths

| Area | Path patterns | Why it's risky |
|------|--------------|----------------|
| Website (auto-deploys to production) | `app/**`, `public/**` | Pushes go live on Vercel on merge to main |
| Frameworks | `wiki/frameworks/**` | Core methodology patterns |
| Proposal templates | `wiki/proposals/**` | Templates feed every client proposal |
| Report templates | `wiki/reports/**` | Templates feed every client report |
| Consultants | `wiki/consultants/**` | Changes advisor panel feedback |
| Skills | `.claude/skills/**` | Core workflows |
| Shared settings | `.claude/settings.json` | Affects Claude Code behavior |

Client folders (`clients/**`) and docs (`docs/**`) are **not risky** — they churn constantly with working data.

### Source 2: Foundation paths (auto-discovered)

Any path declared by a foundation sub-skill is automatically risky. No manual upkeep.

**How discovery works:**

1. Glob `.claude/skills/foundation/*/SKILL.md` from the project root.
2. For each match, parse the YAML frontmatter for `wiki_paths`.
3. Treat every listed path as a risky path pattern (use the path as a directory prefix glob).

If `.claude/skills/foundation/` does not exist, skip this source.

When a risky file matches a foundation path, label it in the summary as `(foundation, auto-detected)`.

Everything else is **not risky** and can be pushed without review.

## Instructions

### Step 1: Gather the diff

Run in parallel:
- `git status --short`
- `git diff HEAD` (unstaged + staged changes)
- `git log --oneline -5` (recent commits for message style)
- `git rev-list --count origin/main..HEAD` (unpushed commits)

If there are no changes (clean working tree AND no unpushed commits), tell the user there's nothing to push and stop.

### Step 2: Classify changes

Before classifying, **build the full risky-path set**:

1. Start with the hardcoded patterns from the "Source 1" table above.
2. Discover foundation paths by globbing `.claude/skills/foundation/*/SKILL.md` and extracting `wiki_paths` frontmatter. Add each to the set, tagged as `foundation`.

Then split every changed file into two buckets:

1. **Risky** - matches any path pattern in the set
2. **Safe** - everything else

Present a summary:

```
Changes to push:

SAFE (N files)
  • clients/acme/sessions/2026-05-12.md — new session log
  • docs/playbooks/intake-call.md — playbook tweak

RISKY (N files)
  • wiki/audience/icp.md — (foundation, auto-detected)
  • wiki/brand-voice/voice.md — (foundation, auto-detected)
  • wiki/frameworks/hogan-360/scoring.md — modified framework
  • .claude/skills/ingest-source/SKILL.md — changed ingest workflow
  • app/page.tsx — website change, auto-deploys on merge
```

### Step 3: Handle risky changes

If there are **no risky files**, skip to Step 4.

If there **are risky files**, for each risky file:

1. Show the diff for that file
2. Explain what changed and why it matters (e.g., "This removes the 'Johnny' persona from ICP, which means future scripts won't reference that audience segment")
3. Ask: "Keep this change, modify it, or revert it?"

Options:
- **Keep** - proceed as-is
- **Modify** - work with the user to adjust the change, then re-diff
- **Revert** - `git checkout -- <file>` to undo that specific file

After resolving all risky files, re-run `git status` to confirm the final state.

### Step 4: Commit (if needed)

If there are uncommitted changes:
- Stage all remaining files
- Write a concise commit message following the repo's style (look at recent `git log`)
- Commit

### Step 5: Pre-push sync check

Before pushing, check if origin/main has moved ahead:

```bash
git fetch origin main --quiet
BEHIND=$(git rev-list --count HEAD..origin/main)
```

**If `BEHIND` = 0**, proceed directly to Step 6.

**If `BEHIND` > 0**, origin is ahead — walk through the divergence interactively:

1. Show the user what's on origin that we don't have:
   ```bash
   git log HEAD..origin/main --oneline
   ```

2. Offer to rebase:
   > "Origin/main has N commit(s) we don't have locally. I'll rebase your local commits on top of origin/main. Want to proceed?"

3. On confirmation, run:
   ```bash
   git pull --rebase --autostash origin main
   ```

4. **If rebase succeeds cleanly**, proceed to Step 6.

5. **If rebase hits conflicts**, stop immediately. Show the conflict state:
   ```bash
   git status
   git diff --diff-filter=U
   ```
   Then walk through each conflicted file one at a time:
   - Show the conflict markers for the file
   - Explain what each side (ours vs theirs) is trying to do
   - Suggest the most likely resolution and ask: "Accept ours, accept theirs, merge manually, or skip this file for now?"
   - For accepted resolutions: `git add <file>` and move to the next conflict
   - After all conflicts are resolved: `git rebase --continue`
   - If a conflict cannot be resolved in chat (e.g., complex code merge), surface the file path, show both versions, and pause:
     > "This conflict in `<file>` needs manual resolution. Open it in your editor, fix the conflict markers, then run `git add <file> && git rebase --continue`. Let me know when you're done and I'll resume."

6. **NEVER use `git push --force` or `git push --force-with-lease`**. If the push would require a force, stop and explain why, then help the user understand what diverged.

### Step 6: Push

```bash
git push origin main
```

### Step 7: Confirm

```
Pushed to main (N commits).

Changes:
  • <grouped summary of what shipped>
```

## Edge cases

- **Push fails (auth, network):** Show the error. Suggest `git push origin main` again after checking credentials.
- **Rebase aborted by user:** Run `git rebase --abort` to restore the pre-rebase state. Nothing is lost.
- **Mixed risky + safe:** Only the risky files get interactive review. Safe files flow through automatically.
- **User wants to override all risk warnings:** That's fine. If they say "just push it" or "skip review", respect that and proceed to Step 4.

## What this skill does NOT do

- Does not pull from main without committing first. Use `/inc-os:update` for a pure sync.
- Does not run tests or builds.
- Does not force-push or rewrite history.
