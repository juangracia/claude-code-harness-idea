# Wiki: schema for agents

This folder is the project's second brain. It follows Andrej Karpathy's "LLM Wiki" pattern:
https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

The LLM writes and maintains the wiki. Humans read it, add sources and ask questions.
It is a compiled, compounding artifact: knowledge is written once and kept current, not re-derived per question.

## Layers

| Layer | Path | Who writes | Rule |
|---|---|---|---|
| Raw sources | `raw/` | humans, agents saving reports | Immutable. Never edit after saving. Source of truth. |
| Wiki | `pages/`, `index.md`, `log.md` | the LLM | Summaries, entities, concepts, decisions. Always cite. |
| Schema | `AGENTS.md` (this file) | humans + LLM together | Conventions and workflows. Change it when a rule proves wrong. |

The code in this repo is also a source. Cite it, do not copy it.

## Layout

```
wiki/
  AGENTS.md          schema (this file)
  index.md           catalog of every page, read this first
  log.md             append-only history of ingests, queries, lints
  raw/               immutable sources, named YYYY-MM-DD-<slug>.md
  raw/assets/        images and attachments
  pages/entities/    one page per domain entity
  pages/concepts/    rules, flows, cross-cutting ideas
  pages/architecture/ backend, frontend, deploy
  pages/glossary.md  es/en terms
  pages/decisions.md ADR-style decision log
  pages/open-questions.md gaps, bugs, unknowns
```

## Page conventions

- File names: `kebab-case.md`. One topic per page.
- Frontmatter on every page:
  ```yaml
  ---
  type: entity | concept | architecture | glossary | decisions | open-questions | answer
  updated: YYYY-MM-DD
  sources: [raw/2026-01-15-explore-domain.md, backend/pom.xml]
  ---
  ```
- Link pages with Obsidian `[[wikilinks]]` (file name without `.md`). Every page needs at least one inbound link from `index.md` or another page.
- Cite code as `path:line` relative to the repo root (for example `backend/pom.xml:10`).
- Anything you could not check against code or a source gets the word `UNVERIFIED`.
- Short and plain. English for content. No em dashes.
- When code changes a fact, update the page and bump `updated`. Do not keep stale claims "for history"; history lives in `log.md` and git.

## Workflows

### Ingest (a new source arrives)
1. Save it under `raw/YYYY-MM-DD-<slug>.md` with frontmatter (`source`, `date`, `immutable: true`). Never edit it after that.
2. Read it. Note the takeaways in a few lines.
3. Update every affected page in `pages/` (one source often touches many pages). Create pages for new entities or concepts.
4. Check the claims against the code before writing them. Add `path:line` citations.
5. Update `index.md`.
6. Append to `log.md`.

### Query (someone asks a question)
1. Read `index.md` first, then the pages it points to.
2. Answer with citations to pages and code.
3. If the answer is reusable (a comparison, a how-to, a non-obvious finding), file it back as a page with `type: answer` and link it from `index.md`. Log it.

### Lint (periodic health check, or before a demo or release)
Look for, and fix or list in `pages/open-questions.md`:
- contradictions between pages, or between a page and the code
- stale claims (code moved, line numbers drifted)
- orphan pages (no inbound links)
- concepts mentioned in several pages with no page of their own
- missing cross-links
- `UNVERIFIED` items that can now be checked
Log the lint pass with what changed.

## log.md format

Append only. One heading per event, with this exact prefix so `grep` works:

```
## [YYYY-MM-DD] ingest | <source title>
## [YYYY-MM-DD] query | <question>
## [YYYY-MM-DD] lint | <scope>
```

Under each heading: 1 to 5 bullets with what changed (pages touched, facts added).
Last five events: `grep "^## \[" wiki/log.md | tail -5`

## What does not belong here

- Secrets, tokens, real personal data.
- Things the code or git history already says plainly (file lists, diffs). Link to them instead.
- Session chatter. Only durable knowledge.
