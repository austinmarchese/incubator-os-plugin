---
name: inc-os:improve-system
description: "Improve your system. Improves skills from iteration, captures experiences, reviews session history for knowledge, audits for rot, and sets up foundation content. Routes automatically based on context."
---

# /inc-os:improve

Make your entire system smarter based on what just happened. One skill, five modes. The model determines which mode based on conversation context, or you can specify.

## Modes

| Mode | Trigger | What it does |
|------|---------|-------------|
| **Skill** | You iterated on a skill's output | Updates the skill's process, learnings, or steps |
| **Experience** | You have a story, win, or lesson to capture | Writes a structured experience entry |
| **Session Review** | You want to extract value from recent Claude Code sessions | Reads history, pulls out transferable learnings |
| **Audit** | You want to check the system for rot | Finds stale, conflicting, duplicate, or orphaned content |
| **Foundation** | The project is missing foundational content (brand, offers, audience, etc.) | Auto-discovers foundation sub-skills and runs interviews to fill gaps |

## Instructions

### Step 0: Determine Mode

Look at the conversation context and determine which mode(s) apply:

**Skill mode** if:
- A skill or slash command was used in this conversation
- There were 3+ rounds of feedback/revision on the output
- The user corrected the skill's behavior ("no, do it this way")
- The user says "improve this skill" or "based on our back and forth"

**Experience mode** if:
- The user mentions something that happened to them (client work, a win, a mistake, a lesson)
- The user pastes a voice transcript or describes their day
- The user says "log this" or "capture this"

**Session Review mode** if:
- The user says "review my sessions" or "what did I work on"
- The user wants to extract learnings from past work they didn't capture in the moment
- It's been a while since the last review

**Audit mode** if:
- The user says "audit" or "check for rot" or "clean up"
- The user suspects something is outdated or conflicting
- It's been 2+ weeks since the last audit

**Foundation mode** if:
- The user says "set up foundation", "what's missing", "set up brand/offers/audience", or similar
- This is a new project or new onboarding session and the wiki is largely empty
- Bare invocation in a project where `.claude/skills/foundation/` exists and one or more of its declared `wiki_paths` are empty

If unclear, ask:

> "What are we improving? I can:
> 1. **Improve a skill** based on our back-and-forth
> 2. **Capture an experience** (story, win, lesson)
> 3. **Review recent sessions** for missed learnings
> 4. **Audit the system** for stale or conflicting content
> 5. **Set up foundation** (brand, offers, audience, or whatever the project declares)
>
> Or describe what you're thinking and I'll figure it out."

Multiple modes can run in one invocation if relevant.

---

### Mode 1: Skill Improvement

#### Step 1: Identify the skill

From conversation context, determine which skill was used. If ambiguous, ask.

If user says "based on our conversation" without naming a skill, infer from context which skill(s) are relevant.

#### Step 2: Extract learnings

Review the conversation for:
- **Corrections** ("no, not like that") that reveal missing rules or steps
- **Confirmed approaches** that worked (non-obvious choices the user approved without pushback)
- **Process friction** (steps that were skipped, reordered, or didn't apply)
- **New questions** the skill should ask upfront
- **Feedback interpretation** (e.g., "tighter" means cut filler, not rewrite sections)

#### Step 3: Read the skill and understand its structure

Read the skill's SKILL.md (or equivalent). Identify:
- Current steps and process
- Which wiki folders or files it loads
- Existing learnings (count them, check for conflicts)
- Whether learnings live in SKILL.md or in a separate file it references

#### Step 4: Find neighboring skills

Neighboring skills are skills that load the same wiki folders. When you improve one, the learning might apply to others.

**How to find neighbors:**
1. Read the target skill's context/load instructions
2. Find which knowledge paths it references
3. Search other skill files for the same path references
4. Also check agents that reference the same knowledge

Show neighbors only if the learning applies to them. Don't ask about empty matches.

#### Step 5: Propose changes

Show:
> "Here's what I'd update in **[skill-name]**:
>
> **Current state:** [X steps, Y learnings, loads Z folders]
>
> **Proposed changes:**
> - [specific change to process, learning, or step]
> - [specific change]
>
> **Neighboring skills that might need the same update:**
> - [skill-name]: [why this learning applies]
>
> Apply these?"

#### Step 6: Check for contextual rot within the skill

After proposing changes, scan the skill for:

- **Duplicate learnings**: Same advice stated differently in multiple places
- **Conflicting learnings**: "Always do X" vs "Never do X" in the same skill
- **Learning bloat**: 30+ learnings in one section (suggest grouping, promoting stable ones to process, or archiving obvious ones)
- **Stale references**: Tool names, file paths, or examples that no longer exist

If found, flag them alongside the proposed changes.

#### Step 7: Apply on approval

Update the skill file(s) and any approved neighbors. Confirm what changed.

---

### Mode 2: Experience Capture

#### Step 1: Get the experience

Either from:
- Conversation context (the user described something)
- A pasted voice transcript
- A typed description
- Claude Code session history (what was actually built)

#### Step 2: Extract structured content

From the raw input, extract:
- **Key stories**: What happened, the challenge, what was tried, what worked, the outcome. Write in first person, past tense, conversational.
- **Quotable moments**: Punchy phrases that sound natural and could go into content verbatim
- **Insights**: Transferable lessons that apply beyond this specific situation
- **Tags**: Topics covered (e.g., data-loops, client-work, delegation, tool-setup, pricing, mistakes, wins, frameworks)

#### Step 3: Find where to write

Scan the project for an experience directory:
- Check for `wiki/experiences/`, `docs/experiences/`, or similar paths
- Check CLAUDE.md for documented paths
- If nothing exists, ask where to create it.

#### Step 4: Write the entry

Write as `{path}/{YYYY-MM-DD}-{brief-slug}.md`:

```markdown
# {YYYY-MM-DD} - {Brief Descriptive Title}

## Metadata
- **Date**: YYYY-MM-DD
- **Topics**: [topic1, topic2, topic3]
- **Source**: [voice-transcript | session-history | combined | typed]

## Key Stories

### Story 1: {Story Title}
{Narrative: specific context, the challenge, what you tried, what worked, the outcome}

## Quotable Moments
> "{Direct quote that sounds natural and punchy}"

## Insights & Learnings
- {Transferable insight}
- {Another learning}

## Tags
{topic1, topic2, topic3}
```

#### Step 5: Cross-reference

Check if this experience is relevant to any active projects in the workspace. If so, mention which project and where the story might fit.

#### Step 6: Ingest into wiki

After writing all experience entries, automatically run the `/inc-os:ingest` process on each file:
- Add a `## Summary` section with source type, key entities, key concepts, and ingestion date
- Extract entities and concepts worth tracking in the wiki
- Create or update wiki pages for substantive new concepts
- Add `[[wikilinks]]` to the source file for first mentions of wiki entities
- Update `wiki/_Home.md` if any new top-level wiki sections were added

For multiple entries, batch the wiki updates at the end (one pass, not per-file). Use parallel agents when processing 3+ files to speed this up.

---

### Mode 3: Session Review

#### Step 1: Read session history

Read `~/.claude/history.jsonl` (last 500 lines or configurable). Extract:
- **Projects worked on**: Group by `project` field, using the `display` field for prompt text
- **Skills/commands used**: Prompts starting with `/`
- **Timeline**: Use `timestamp` to order the day's/week's work
- **Patterns**: creation, debugging, iteration, discovery
- **Pasted content**: Check `pastedContents` field for error messages, transcripts, or meeting notes included in prompts

Also supplement with `git log --oneline --since="2 weeks ago"` to see what was actually committed, which is often richer than the history file alone.

#### Step 2: Identify extractable learnings

Look for:
- **Skill iteration**: Sessions where a skill was invoked and then had multiple rounds of feedback (potential skill improvements)
- **Repeated patterns**: Things becoming habits across sessions (e.g., same skill cloned to multiple projects)
- **Problems solved**: Debugging sessions that could inform future work
- **Tools/approaches discovered**: New tools, APIs, or workflows figured out
- **Implicit learnings**: Repeated debugging of the same thing suggests a "gotcha" worth documenting
- **Cross-project patterns**: The same action taken in multiple projects signals a universal principle
- **System evolution**: Changes to how the system itself works (new skills, new onboarding flows, new interfaces)

#### Step 3: Present draft entries and interview

Present 2-5 draft entry summaries (title + 2-3 sentence description each). Do NOT write the full entries yet.

Then **interview the user** to dig deeper. For each entry, ask 2-3 targeted questions:

- **"Why now?"** - What triggered this specific action? Was it reactive (something broke) or proactive (building ahead)?
- **"Who benefits?"** - Is this just for you, or does it affect teammates, clients, or a future audience?
- **"What's the bigger pattern?"** - Does this connect to a broader shift in how you work? Is this a one-off or the start of something?
- **"What was the alternative?"** - What would you have done without this? What was the old way?
- **"What surprised you?"** - Anything unexpected in how it played out?

Pick the most relevant questions per entry. Don't ask all of them for every entry. The goal is to surface the insight behind the action, not just document what happened.

Continue the interview for 1-2 rounds until the entries feel rich enough to capture something transferable, not just a log of what was built.

#### Step 4: Generate full entries

After the interview, write entries using the Experience mode format (Step 2-4 from Mode 2). Each entry should include:
- Key stories enriched with interview context
- Quotable moments (pull directly from interview responses when possible)
- Insights that are transferable beyond the specific session

Generate entries for significant sessions only (2-5 entries). Skip trivial sessions.

#### Step 5: Write entries

Same path detection as Experience mode. Write each entry as a separate file.

#### Step 6: Suggest skill improvements

If the session review reveals skill iteration patterns (a skill was used with multiple rounds of feedback), offer to switch to Skill mode for those specific skills.

---

### Mode 4: System Audit

#### Step 1: Map the system

Scan for all components:
- All skill files (`.claude/skills/`, `.claude/commands/`)
- All wiki files (`wiki/`) and docs (`docs/`). Client material (`clients/`) is in scope for orphan/link checks but never for cross-project lifting.
- All agent files (`.claude/agents/`)
- CLAUDE.md and any `.claude/rules/` files

Build two maps:

**Dependency map** (what uses what):
```
skill-name -> reads: wiki/path/a/, wiki/path/b/
agent-name -> reads: wiki/path/c/
```

**Link graph** (for projects using wikilinks/Obsidian):
For each .md file, extract outgoing `[[wikilinks]]` and markdown links to local files. Build incoming/outgoing link maps.

#### Step 2: Run checks

**Check 1: Broken links (high severity)**
- Wikilinks or file references that point to files that don't exist
- Check case-insensitive and partial path matches before flagging

**Check 2: Conflicting rules (high severity)**
- Two files giving opposite guidance on the same topic
- Skill learnings that contradict each other ("always do X" vs "never do X")
- Different sources recommending opposite approaches without documenting when each applies

**Check 3: Orphaned content (medium severity)**
- Knowledge files that no skill or agent references
- Files with zero incoming AND zero outgoing links (graph orphans)
- Exclude structural files (INDEX.md, README.md, etc.)

**Check 4: Missing pages (medium severity)**
- Wikilink targets that appear in 2+ source files but have no actual page
- Concepts referenced repeatedly but never defined

**Check 5: Stale content (low severity)**
- Files not updated in 120+ days (use `git log -1 --format="%ai" -- [file]`)
- Skip inherently stable files (voice patterns, brand briefs, frameworks)

**Check 6: Coverage gaps (low severity)**
- Topics that appear in 3+ projects/experiences but have no knowledge entry
- Scan project folders and experience files for recurring themes

**Check 7: Duplicate content (low severity)**
- Multiple files covering the same ground without cross-linking
- Similar filenames in the same domain (e.g., `brand-context.md` and `brand-brief.md`)

**Check 8: Learning bloat (low severity)**
- Skills with 30+ learnings in one section
- Suggest: group related learnings, promote stable ones to process, archive obvious ones

#### Step 3: Report findings

Show a summary first:

```
SYSTEM AUDIT
============
Components: X skills, Y agents, Z wiki files
Referenced: X files used by skills/agents
Orphaned: X files
Broken links: X
Conflicts: X
Stale: X
Gaps: X

HEALTH SCORE: X/10
```

Then show each category with details, grouped by severity.

#### Step 4: Fix on approval

- **Broken links**: Find closest matching file, fix the link or offer to create a stub
- **Conflicts**: Propose a resolution that documents when each approach applies
- **Orphans**: Ask if should be deleted, connected to a skill, or kept as reference
- **Stale files**: Read the file, check if content is still accurate, propose updates
- **Gaps**: Propose a new knowledge file with a starter outline
- **Duplicates**: Read both files, propose consolidation or cross-linking
- **Bloat**: Propose grouping, promotion to process, or archiving

Never auto-delete without explicit approval.

#### Step 5: Rebuild index (if project uses one)

If the project has a wiki home file (e.g., `wiki/_Home.md`), rebuild its section index with:
- Files by domain
- Cross-references (topics covered by multiple sources)
- Dependency map (skill -> wiki paths, wiki paths -> skill)
- Unlinked wiki pages

---

### Mode 5: Foundation

Detect missing foundational content for the current project and dispatch the right interview to fill it. Generic across projects — discovers what counts as "foundation" by inspecting the project's foundation sub-skills.

#### Convention

Foundation sub-skills live at `.claude/skills/foundation/{name}/SKILL.md`. Each declares one or both completion checks via frontmatter:

**Content foundation** — declares `wiki_paths:`. Skill is "done" when every listed path contains real content (more than just `.gitkeep`).

```yaml
---
name: brand-voice
description: Interview the business owner about their brand and voice
wiki_paths:
  - wiki/brand-voice/
---
```

**System foundation** — declares `setup_check:`. Skill is "done" when the shell command exits 0.

```yaml
---
name: system-setup
description: Install required plugins
setup_check: 'grep -q "skill-creator@claude-plugins-official" "$HOME/.claude/settings.json"'
---
```

A skill can declare both if it has both content and system setup. The set of foundation sub-skills IS the project's definition of foundation. This skill does not hardcode any business-specific checks.

#### Step 1: Discover foundation sub-skills

Glob `.claude/skills/foundation/*/SKILL.md` from the project root. For each match:

1. Parse the frontmatter (`name`, `description`, and either `wiki_paths`, `setup_check`, or both).
2. Skip any file that has neither field.

If no foundation sub-skills exist, tell the user the project has no foundation declared. Offer to help create some via `/skill-creator` if appropriate. Stop.

#### Step 2: Check status of each sub-skill

For each sub-skill, evaluate completion based on what it declares:

- If `wiki_paths:` is declared: when every listed path exists AND contains non-`.gitkeep` files. (missing) when any listed path does not exist; (empty) when it exists but has no real files. Surface "(missing)" vs "(empty)" in the status table so the user can tell setup vs interview state.
- If `setup_check:` is declared: when running the command exits 0; otherwise not done.
- If both are declared: only when both pass.

Run system-foundation skills (those with `setup_check`) before content-foundation skills (those with `wiki_paths`) in the dispatch order — system prerequisites first.

#### Step 3: Report status

Present a concise table. Group system foundation first, content foundation second.

```
FOUNDATION STATUS
=================
SYSTEM
  x system-setup        (plugins not installed)

CONTENT
  + brand-voice         wiki/brand-voice/    (populated)
  x offers              wiki/offers/         (empty)
  x audience            wiki/audience/       (empty)
```

If everything is complete, say so and stop.

#### Step 4: Prompt and dispatch

If any sub-skill is empty or partial:

> "Two foundation pieces are missing: **offers** and **audience**. Want me to walk through them now? I can run both, or pick one to start."

On user confirmation, invoke the chosen sub-skill(s) directly. Each sub-skill runs its own interview and writes into its declared `wiki_paths`.

#### Step 5: Verify

After each sub-skill completes, re-run the Step 2 status check. For content-foundation skills, confirm the `wiki_paths` are populated. For system-foundation skills, re-run the `setup_check` and confirm it exits 0. If not, note what's still missing.

#### Step 6: Suggest related work

Once foundation is complete, mention that:

- `/inc-os:save` will automatically treat all foundation `wiki_paths` as sensitive (auto-discovered, no manual config).
- Other skills that need foundation context can invoke a foundation sub-skill in "read mode" to load it.

---

## Rules

- **Don't force learnings from single instances.** Only promote a pattern to a skill when it recurs 3+ times.
- **Don't auto-run without approval.** Always show what you'll change and ask first.
- **Respect the existing structure.** Write to the directories the project already uses. Don't create new structures when one exists.
- **Be honest about what you find.** If the system is clean, say so. Don't invent problems.
- **Multiple modes in one run is fine.** If you improved a skill and found an experience worth capturing, do both.
- **Keep entries useful, not comprehensive.** A good learning is transferable to future work, not just a diary entry.
- **Contradictions aren't always bad.** Sometimes two sources genuinely disagree. The resolution is documenting when to use which approach, not picking a winner.
- **Confirmed approaches matter as much as corrections.** Don't only save mistakes. If a non-obvious approach worked and was approved, that's a learning too.
