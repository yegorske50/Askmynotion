# Warren Build Spec — "AskMyNotion" (FINAL · Laptop Profile)

> Paste the body of this file into Warren as the task prompt for a single `claude-code` run pointed
> at an empty repo. It is a complete product + engineering spec; the agent should not stop to ask
> questions — make reasonable calls, document them in `PROMPT_NOTES.md`, and ship a working tree.
>
> **Target environment (non-negotiable constraint):** runs on a **MacBook Air, 8GB RAM, no GPU**,
> single user, **$0 budget**. Every choice below is optimized for that. Do **not** introduce
> Postgres, Redis, Celery, a separate Node server at runtime, heavyweight local models, or any
> auth/user system. Keep peak RAM under ~2GB.

---

## 1. Product Summary

Build **AskMyNotion**: a local single-user tool. Point it at a Notion page; it ingests the page text
**and** follows Instagram video links on the page, transcribes their speech (any language), and makes
everything ask-able. Answers cite their sources inline (`[1][2]`), list **all** supporting sources
when several apply, give **timestamps** for video sources, work across languages (English / Hindi /
Telugu sources), and answer in the user's question language. If the answer isn't in the sources, the
app says so instead of inventing one.

Pipeline: **Ingest** Notion (recursive) + collect Instagram links → **Fetch & transcribe** each reel
(original language + English translation, timestamped) → **Index** (chunk → embed → SQLite vector +
keyword) → **Ask** (hybrid retrieve → answer with citations, streamed).

---

## 2. Architecture & Stack — "Laptop Profile" (build exactly this; deviate only on a hard blocker, note it in `PROMPT_NOTES.md`)

**One Python process does almost everything.** A FastAPI app serves the JSON API *and* the prebuilt
static frontend. A second lightweight worker process handles long-running ingestion. No DB server,
no Redis, no Celery, no runtime Node.

| Concern | Choice | Notes |
|---|---|---|
| Backend + web server | **Python 3.11 + FastAPI + Uvicorn** | Serves API and the static SPA from one process |
| Frontend | **Vite + React + TypeScript + Tailwind**, **prebuilt to static `dist/`** and served by FastAPI | Build happens in Warren's cloud sandbox and is committed; the Mac needs **no Node at runtime** |
| DB + vectors + keyword | **SQLite** + **`sqlite-vec`** (vector search) + **FTS5** (keyword/BM25) | Single file, zero server processes; ideal for 8GB |
| Migrations | plain SQL migrations run on startup (idempotent) | No Alembic/Postgres needed |
| Background jobs | **one worker process** + a `jobs` / per-source `status` table for **resumable** ingest | Survives restart; no Redis/Celery |
| Job progress → UI | **SSE** endpoint reading job/status rows | Live progress bar |
| Embeddings | **`intfloat/multilingual-e5-small`** (~470MB, 384-dim) via `sentence-transformers`, local | Handles en/hi/te; light enough for 8GB |
| Reranker | **none by default**; optional cheap **LLM-rerank** of top ~15 via MiniMax (env toggle) | Heavy local rerankers don't fit 8GB |
| Transcription (ASR) | **Groq free Whisper `whisper-large-v3`** (default); **local `faster-whisper small` int8** offline fallback | Groq free tier = 2,000 transcriptions/day, ~228× real-time, best Hindi/Telugu quality, ~0 RAM on the Mac |
| Answer LLM | **MiniMax** (model from `MINIMAX_MODEL` env, default `[SET-ME e.g. M2.7]`) | User already uses MiniMax; behind provider interface |
| Translation (→ English) | Whisper `translate` task **or** a MiniMax call | Per-segment English alongside original |
| Video fetch | **`yt-dlp` + `ffmpeg`** (audio-only extraction) | Public reels only; graceful failure |
| Auth | **none** (single user). Optional single `APP_PASSWORD` env gate | No NextAuth, no users table |

**Provider abstraction (required).** In `app/providers/` define Python ABCs selected by env var:
`LLMProvider` (MiniMax default), `EmbeddingProvider` (e5-small default), `TranscriptionProvider`
(Groq default, faster-whisper fallback), `VideoProvider` (yt-dlp default; Apify/RapidAPI stubs for
later), `NotionSource` (token default, public-link reader). Nothing downstream imports a vendor SDK
directly — only the interface. This is what lets the user later swap to heavier/hosted pieces without
a rewrite.

Repo layout (single Python app + a frontend that compiles to static assets):

```
askmynotion/
  app/
    main.py            # FastAPI: API routes + serves /assets + index.html from web/dist
    worker.py          # resumable ingestion loop (poll jobs table)
    providers/         # llm, embedding, transcription, video, notion ABCs + impls
    ingest/            # notion fetch + recursion, link extraction, chunker, instagram pipeline
    rag/               # hybrid retrieval (vec + FTS5 + RRF), answer prompt, citation builder
    db/                # sqlite connection, schema.sql, migrations, sqlite-vec + FTS5 setup
    models.py          # pydantic schemas
  web/                 # Vite + React source; `npm run build` -> web/dist (committed)
  scripts/
    seed_demo.py       # seeded demo corpus (1 notion page + 3 mock reels w/ fixture transcripts)
  tests/
  .env.example
  README.md
  PROMPT_NOTES.md
  Makefile             # make install / make dev / make ingest / make test
```

Run model: `make dev` starts FastAPI (serving the prebuilt UI) **and** the worker. No Docker
required (offer an optional `docker-compose.yml` but the default path is bare `python`/`uv`).

---

## 3. Functional Requirements

### 3.1 Notion access (single user; private pages → token primary)

- **Primary: internal integration token.** User sets `NOTION_TOKEN`; app uses the official Notion SDK
  to fetch a page and **recursively** its child pages/blocks. **Cap recursion at 3 levels** (configurable
  `NOTION_MAX_DEPTH=3`). Report any child pages skipped (not shared with the integration) rather than
  failing.
- **Bonus: public "share to web" link.** If the user pastes a public URL instead of using a token,
  read the public page and extract the block tree. Best-effort.
- Collect **every URL** in the page (rich-text link annotations, bookmark blocks, embed blocks, bare
  URLs). Route Instagram URLs to §3.2.
- Store each text block with `block_id`, type, plain text, and a deep link
  (`https://www.notion.so/...#<block_id>`).
- **Incremental re-sync:** persist `last_edited_time` per page; on re-sync reprocess only changed/new
  blocks and newly added links; dedupe reels by canonical URL; delete orphan chunks.

### 3.2 Instagram pipeline (public reels only; the fragile part — build defensively)

Detect `instagram.com/(p|reel|reels|tv)/<id>`. For each unique reel:

1. **Fetch** via `VideoProvider` (default `yt-dlp`, audio-only when possible), **with retry +
   exponential backoff and a polite delay between reels** (Instagram rate-limits; 100+ reels in one
   page is expected). Apify/RapidAPI provider left as an env-selectable stub for later.
2. **Extract audio** with `ffmpeg` → 16kHz mono wav.
3. **Transcribe** via `TranscriptionProvider` (Groq default), requiring **timestamped segments** +
   detected language. Produce, per segment, **original-language text + English translation**.
4. **Caption fallback:** if audio transcription is empty/fails but the public post has a caption,
   store the caption as the transcript (often the real signal for text-on-screen reels).
5. **Graceful failure:** private / removed / region-locked / login-walled / rate-limited → mark the
   source `unavailable` with a reason, show it in the UI with a **retry** action and a **manual
   transcript paste** box, and **continue the job** (never crash the whole ingest).
6. **Cache** transcripts keyed by canonical media URL so re-syncs and duplicate links are free.
7. **ToS note** in README: best-effort, public content only, respect Instagram's Terms and law; a
   config flag disables fetching entirely.

> Reality check to encode in the UX: with 100+ reels, expect a meaningful minority to fail fetching.
> Transcription itself is fast/free via Groq; the bottleneck and failure source is Instagram fetching.

### 3.3 RAG pipeline

- **Chunking** (~500 tokens, ~80 overlap, never split mid-sentence): Notion text per block (merge
  tiny adjacent blocks); tables as one chunk; transcripts chunked on ≥2s silence boundaries with
  `[start,end]` attached to every chunk.
- **Embeddings:** `multilingual-e5-small` on the **original** text (multilingual → cross-lingual
  retrieval works); store the English translation for the answer-LLM context + UI snippet. Use the
  model's required `query:` / `passage:` prefixes.
- **Storage:** `sqlite-vec` virtual table for vectors + FTS5 table for keyword search.
- **Retrieval:** top-50 vector (cosine) **fused with** FTS5 keyword results via **Reciprocal Rank
  Fusion** (`k=60`) → take top-~10. Optional MiniMax LLM-rerank of the top-15 behind an env toggle.

### 3.4 Q&A behavior (`app/rag/prompts.py`)

- Answer in the **user's question language**. Every non-trivial claim ends with `[n]`. If sources
  disagree, show both with separate citations. **If the answer isn't in the sources, say "I couldn't
  find this in your Notion page"** and suggest what to ingest — never hallucinate.
- Video answers include the timestamp inline: "She explains it at [1] (00:42–01:08)".
- **Stream** the answer (SSE). After it, a **Sources panel** lists, numbered to match `[n]`:
  - Notion: page title, breadcrumb, highlighted snippet, "Open in Notion" deep link.
  - Reel: creator handle if known, the matched transcript snippet (original + a "Show English"
    toggle), language badge, and a link to the reel showing the timestamp.
  - "Copy citation" (Markdown / plain).

### 3.5 Ingestion UX

- Submit token+page (or public URL) → create an `ingestion_jobs` row → worker processes it, writing
  per-source status rows → UI shows a live bar via SSE: "Fetched 14/30 blocks · Transcribed 22/108
  reels · Indexed 6,140 chunks", with a per-reel status list (queued → fetching → transcribing →
  done / failed+reason) and retry buttons.
- Resumable: if the process restarts mid-ingest, the worker picks up unfinished sources from the
  status table. "Force full re-ingest" button.

### 3.6 Scope (single workspace, light history)

- **One workspace** (one Notion root). No workspace switcher, no multi-tenant isolation needed.
- **Light chat history:** persist conversations + messages so the user can scroll past Q&As; no pin /
  rename / export, no usage dashboard, no transcription budgets.

---

## 4. Non-Functional Requirements

- **Runs on 8GB RAM, no GPU; peak < ~2GB.** Only one of {embedding model, local-whisper-fallback}
  loaded at a time. Default ASR is Groq (remote) so the Mac stays light during ingest.
- **Streaming** answers (SSE), first token fast.
- **Self-contained:** `make install && make dev` brings it up with only Python + ffmpeg installed.
- **Privacy:** the Notion token and any cached media stay local; the only outbound calls are Groq
  (ASR) + MiniMax (answers). A README note explains exactly which data leaves the machine and how to
  switch ASR to the local `faster-whisper` fallback for fully-offline operation.
- **Observability:** `structlog` logs; `/health` returns DB + model-load + worker-alive status.
- **Validation:** all inputs validated with Pydantic and length-limited.

---

## 5. Data Model (SQLite — `app/db/schema.sql`)

- `workspace(id, name, notion_page_id, notion_page_url, mode, notion_last_edited_time, created_at)` — single row.
- `notion_pages(id, workspace_id, notion_page_id, parent_page_id, title, url, depth, last_edited_time, last_ingested_at, status, error)`
- `notion_blocks(id, notion_page_id, block_id, type, text, deep_link, created_at)`
- `videos(id, workspace_id, source_url, canonical_url, author, status, error, created_at)` — status: queued|fetching|transcribing|done|unavailable
- `video_transcripts(id, video_id, language, full_text_original, full_text_en, segments_json, source)` — segments: `[{start,end,text_original,text_en,language}]`; source: whisper|caption|manual
- `chunks(id, workspace_id, source_type, source_id, block_id, video_id, text_original, text_en, language, start_sec, end_sec, deep_link, created_at)` — `source_type`: notion_block|video_transcript|caption
- **`chunks_vec`** — `sqlite-vec` virtual table (chunk_id ↔ 384-dim embedding)
- **`chunks_fts`** — FTS5 over `text_original`/`text_en`
- `ingestion_jobs(id, workspace_id, status, total_blocks, done_blocks, total_videos, done_videos, indexed_chunks, current_step, error, started_at, finished_at)`
- `conversations(id, title, created_at)` · `messages(id, conversation_id, role, content, citations_json, model, created_at)`
- `media_cache(canonical_url PRIMARY KEY, transcript_json, created_at)`

---

## 6. API Surface (FastAPI; JSON; SSE where noted)

```
POST /api/workspace            set/replace Notion source (token+page_id | public url)
GET  /api/workspace            current config + counts
POST /api/ingest               enqueue ingest -> {jobId}
POST /api/resync               incremental re-ingest
GET  /api/ingest/status        SSE: job + per-source progress
GET  /api/sources              list pages + reels with statuses (+ per-reel retry target)
POST /api/sources/{id}/retry   re-fetch/re-transcribe one reel
POST /api/sources/{id}/transcript  manual transcript paste for a failed reel
DELETE /api/sources/{id}       drop a source + its chunks
POST /api/conversations/{id}/messages   SSE streaming chat {content, answerLanguage?} -> {answer, sources[]}
GET  /api/conversations        list   ·   GET /api/conversations/{id}   detail
GET  /health
```

Answer payload: `{ answer, sources: [{ n, type, title, url, deep_link, snippet_original, snippet_en, language, start?, end? }] }`.

---

## 7. UI (prebuilt SPA served by FastAPI)

1. **Connect** — paste Notion token + page URL (or a public URL); explains the "share page with the
   integration" step inline.
2. **Ingest view** — live progress bar + per-reel status list with retry / paste-transcript actions.
3. **Chat** — streaming answers, inline `[n]` citation chips, a Sources panel (original + English
   toggle, language badge, timestamped reel links, copy-citation), and a clear "not found" state.
4. **Sources manager** — list of ingested pages + reels, language badges, delete / re-ingest.
5. Minimal settings: ASR provider (Groq / local fallback), answer-language override, LLM-rerank
   toggle, force full re-ingest, "what data leaves my machine" explainer.

---

## 8. Critical Edge Cases (handle explicitly, with tests)

- Child sub-page not shared with the integration → recursion skips it gracefully and reports it.
- Reel private / removed / geo-blocked / login-walled / rate-limited → marked `unavailable` + reason;
  job continues; retry + manual-paste available.
- Whisper mis-detects language on a short clip → show detected language; allow re-run with explicit
  language override.
- Question in a language no source is in → answer in the question's language; Sources panel shows the
  source language with the English toggle.
- Reel with no speech (music / text-on-screen) → caption fallback; if none, "no transcribable audio".
- 100+ reels → resumable worker, polite per-reel delay/backoff, partial-failure reporting; ingest can
  finish across interruptions.
- Notion page edited/deleted externally → next re-sync updates changed blocks and flags missing pages.

---

## 9. Deliverables (what the branch must contain)

1. `make install && make dev` runs the whole app on a clean Mac with only **Python 3.11 + ffmpeg**
   installed (no Node, no Docker needed at runtime). The frontend is prebuilt and committed in
   `web/dist`.
2. Complete `.env.example`: `NOTION_TOKEN`, `NOTION_PAGE_URL`, `NOTION_MAX_DEPTH`, `GROQ_API_KEY`,
   `MINIMAX_API_KEY`, `MINIMAX_MODEL`, `ASR_PROVIDER`, `EMBED_MODEL`, `ENABLE_LLM_RERANK`,
   `APP_PASSWORD` (optional), `DB_PATH`.
3. SQLite schema + `sqlite-vec` + FTS5 created/migrated idempotently on startup.
4. **Seeded demo** (`scripts/seed_demo.py`): one mock Notion page + 3 mock reels with fixture
   transcripts (incl. one Telugu and one Hindi) so a reviewer sees the full flow with **no real
   credentials**.
5. **README**: setup, the Notion "share with integration" step, how to get a free Groq key, the
   MiniMax key, a mermaid architecture diagram, "fully-offline mode" instructions (switch
   `ASR_PROVIDER=local`), "Known limitations", and "Privacy & Instagram ToS".
6. Tests green: `pytest` (unit + RAG with **mocked** Groq/MiniMax/yt-dlp providers), and a
   **golden-dataset test** — fixed questions over the fixture corpus asserting the **cited source
   ids**, covering: answer-from-transcript-with-timestamp, answer-from-Notion-block, multi-source
   listing, unanswerable → "not found", and a **cross-language** case (Telugu transcript + English
   question → correct grounded citation).
7. `PROMPT_NOTES.md` listing every ambiguous call the agent made.

---

## 10. Out of Scope (v1)

Multi-user / auth / isolation; multiple workspaces; usage dashboard + budgets; dedicated reranker
model; Postgres/Redis/Celery; YouTube/TikTok (interface ready, not implemented); private-account
reels needing login cookies; native mobile; billing.

---

## 11. If the spec is ambiguous

Make the call, document it in `PROMPT_NOTES.md`, and ship. Don't stall on a "should I ask" loop. Keep
build/lint/typecheck green at every commit. Open a PR with a summary, the required env vars, and exact
"how to run on macOS" steps.

---

### Fill-me before dispatch
- `MINIMAX_MODEL` default — set to the model you use (e.g. `M2.7` or `M3`).
- Confirm Notion pages are private (token mode). If they're public, the public-link reader is fine too.

**End of build spec. Paste into Warren and let it run.**