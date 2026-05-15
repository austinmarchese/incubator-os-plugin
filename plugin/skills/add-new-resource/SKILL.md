---
name: inc-os:add-new-resource
description: Add a new resource to your system. Takes a raw source (article, transcript, notes, YouTube URL, or attachment) and routes it to the right place — wiki/ for stable knowledge, clients/{slug}/ for client-specific material — then summarizes and cross-references.
---

# /inc-os:add-new-resource

Take an article, transcript, notes file, URL, attachment, or YouTube video and route it into the right home in this repo. Then add a `## Summary` block, extract key entities, and cross-reference with `[[wikilinks]]` where useful.

## Where things go

Two zones:

- `wiki/` — stable, slow-evolving knowledge (frameworks, brand voice, offers, audience, advisor profiles, process templates). **Not client-identifying.**
- `clients/{slug}/` — confidential per-client material (intake, Hogan PDFs, stakeholder interviews, reports, session notes).

**Default rule:**
- About or for a specific client → `clients/{slug}/`.
- General knowledge (framework article, advisor talk, succession research) → `wiki/`.
- Unclear → ask.

## Process

### Step 1: Identify the source

User can provide:
- A **file path** (existing file in the repo)
- A **URL** (article, podcast page)
- A **YouTube URL** (youtube.com/watch, youtu.be, /shorts) → go to **Step 1a**
- **Pasted raw text**
- An **attachment** (PDF, doc, transcript)

If none provided, ask:
> "What should I ingest? Paste a URL, YouTube link, file path, or raw text — or drop an attachment."

#### Step 1a: YouTube pipeline

When the input is a YouTube URL:

1. **Precondition check.** Verify the script's dependencies are installed before invoking it:
   ```bash
   python3 -c "import youtube_transcript_api" 2>/dev/null && command -v yt-dlp >/dev/null
   ```
   If this fails, tell the user the YouTube pipeline is not set up and run (or instruct them to run):
   ```bash
   bash scripts/setup.sh
   ```
   `/inc-os:update-system` will install both `yt-dlp` and `youtube-transcript-api`. Then continue.

2. Fetch the transcript and metadata:
   ```bash
   python3 scripts/fetch_youtube_transcript.py \
     --video-url "[URL]" \
     --output /tmp/yt-transcript.md
   ```
   The script prints a JSON line on stdout: `{video_id, title, channel, channel_url, output, word_count}`. Use those to populate the summary block in Step 4.

3. If the script fails (no transcript, network error), tell the user, ask whether to fall back to fetching the page (title + description only via WebFetch), or abort.

4. Continue to Step 2 with the transcript file as the source. The transcript will likely move from `/tmp/` to its final home in Step 2.

### Step 2: Decide where it belongs

Ask the user where this should live unless it is obvious from context:

> "Where does this belong?
> 1. A specific client → `clients/{slug}/...`
> 2. General knowledge → `wiki/...`
>
> I can suggest a path once I see what it is."

Pick the sub-folder:

| Source type | Wiki destination | Client destination |
|-------------|------------------|--------------------|
| Framework / methodology article | `wiki/frameworks/{topic}/sources/` | n/a |
| Voice / writing sample | `wiki/brand-voice/samples/` | `clients/{slug}/voice-samples/` |
| Advisor talk / transcript / interview | `wiki/consultants/sources/{advisor-slug}/` | n/a |
| Process / playbook | `wiki/processes/sources/` | n/a |
| Intake materials | n/a | `clients/{slug}/discovery/` |
| Stakeholder interview | n/a | `clients/{slug}/stakeholders/` |
| Hogan 360 PDF | n/a | `clients/{slug}/discovery/` |
| Session notes | n/a | `clients/{slug}/sessions/YYYY-MM-DD.md` |

For a YouTube transcript of an advisor (e.g., a talk by someone whose frameworks you're cloning into `wiki/consultants/`), default destination is `wiki/consultants/sources/{advisor-slug}/transcripts/`. Sources live in a sibling `sources/` tree, NOT in a folder named after the advisor at the same level as advisor `.md` files — the advisor file itself is the single `wiki/consultants/{advisor-slug}.md` per project convention, and `/inc-os:add-new-resource` only globs `wiki/consultants/*.md` so the `sources/` subfolder is correctly ignored. Move the `/tmp/` file into `wiki/consultants/sources/{advisor-slug}/transcripts/`. Create folders if missing.

Filename: lowercase kebab-case, dated when relevant (`2026-05-12-article-title.md`).

### Step 3: Fetch / save the content (non-YouTube)

- **URL:** fetch the page (WebFetch / firecrawl). Save the readable content as markdown. Capture title, author/source, date.
- **Attachment:** read and convert to markdown (use firecrawl `parse` for PDFs/docx if needed).
- **Pasted text:** save as-is.
- **Existing file:** read it; if it should move, move it to the chosen destination.

### Step 4: Add a summary block

Prepend (or insert after any title/frontmatter):

```markdown
## Summary

[2-4 sentences: what this is, the main claim, why it matters here.]

**Source type:** [article / youtube-transcript / interview / PDF / notes]
**Origin:** [URL or short attribution]
**Ingested:** YYYY-MM-DD
**Key entities:** [[Person A]], [[Concept B]]
```

If a summary already exists, leave it alone.

### Step 5: Extract entities and concepts (only when useful)

Read the source. Identify:
- **People** discussed substantively (not just name-dropped)
- **Frameworks / concepts** likely to appear in future sources

Filter hard. Three or fewer is usually right for a single source.

Tell the user:
> "Found: [N] entities, [M] concepts. Worth pages for: [list]. Create / update wiki pages for these?"

### Step 6: Update wiki pages

Only for entities/concepts the user confirms.

**If a wiki page exists** at `wiki/{section}/{slug}.md` (or `wiki/consultants/{slug}.md` for advisors):
- Add the new source under `## Sources`.
- Update facts if the new source meaningfully adds context. Don't duplicate.

**If a wiki page doesn't exist**, create one in the right section:
- Advisor → do **not** write `wiki/consultants/{slug}.md` directly from ingest. Suggest the user run the consultant-creation workflow to do the full intake. Ingest only adds the new source to the advisor file's `## Sources` section if the file already exists.
- Framework / concept → `wiki/frameworks/{topic}/{slug}.md`.

Minimal scaffold:

```markdown
# [Name]

[1-2 sentences: who/what this is and why it's tracked here.]

## Key Ideas

- [Point from the source]

## Sources

- [[path/to/source]] — [one-line note on what this source contributes]
```

### Step 7: Add wikilinks to the source file

Add `[[wikilinks]]` on the **first** mention of each entity/concept that has a wiki page. Don't link every occurrence. Don't link inside code blocks or URLs.

### Step 8: Report

```
Done.

Source saved: <path>
- Summary block added
- [N] wikilinks added

Wiki pages updated: <list>
Wiki pages created: <list>
```

## Batch mode

If the user says "ingest everything in [folder]" or supplies multiple files:
1. List the files.
2. Process each through Steps 3-7.
3. Batch wiki updates (Step 6) at the end.
4. One summary report.

## Confidentiality

Client material stays in `clients/{slug}/`. **Do not promote client-identifying text into `wiki/`**. If a client engagement surfaces a generally useful framework or pattern, anonymize before lifting it.

## Error handling

- Source path doesn't exist → "File not found at `[path]`. Check the path."
- Destination folder doesn't exist → create it.
- YouTube script fails (network, no transcript, geo-block) → tell the user the error, offer to fall back to title/description via WebFetch or abort.
- Wiki page diverges from what the new source says → flag instead of overwriting:
  > "Existing `[[X]]` page says [A]. This source says [B]. Update, keep both, or skip?"

## Setup

- `scripts/fetch_youtube_transcript.py` is a **per-repo script** that lives in the client's content workspace (not in the plugin). It requires `youtube-transcript-api` (Python) and `yt-dlp` (for title/channel metadata).

  The plugin install script (`install.sh` / `install.ps1`) installs both dependencies automatically as a best-effort step. If they are missing, run:
  ```bash
  pip install youtube-transcript-api
  brew install yt-dlp   # macOS; or: pip install yt-dlp
  ```

  If `scripts/fetch_youtube_transcript.py` is missing from your workspace (e.g., a newly provisioned repo), the YouTube pipeline will not work. In that case, tell the user: "The YouTube transcript script is not present in this workspace. Ask Austin to add `scripts/fetch_youtube_transcript.py` to your repo, or fall back to fetching the video page (title + description only) via WebFetch."

  If `yt-dlp` is missing but `youtube-transcript-api` is present, the transcript still fetches successfully; only the title and channel metadata fall back to the raw video ID.

## Learnings

(None yet. Add as the skill is used.)
