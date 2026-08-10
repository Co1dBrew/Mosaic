# Mosaic — Retrieval Architecture

> Goal 1 · Week 1 · Runtime Foundation
> Status: **foundation landed and verified**; retrieval itself starts Week 2.
> Upstream: *Mosaic AI Retrieval Quality Platform PRD v1.0*
> Design: [`design/SEARCH_CONTRACT.md`](design/SEARCH_CONTRACT.md) · [`design/DEVTOOLS.md`](design/DEVTOOLS.md)

---

# 1. Existing Architecture Map

Established by reading the code, not by assumption.

## 1.1 Card → Blocks → Edit → Persist

```
CardEditorView  (@MainActor, SwiftUI)
   │  user types / inserts / reorders / deletes
   │
   ├─ scheduleAutosave()      800 ms debounce, cancels the previous Task
   │     └─ commitNow()
   ├─ moveBlocks/deleteBlocks → commitNow() immediately (no debounce)
   │
   └─ commitNow()
        card.touch()                    // updatedAt = now; folder.touch()
        modelContext.save()             // SwiftData main context
```

- `Card` `@Model`: `id: UUID` (assigned in `init`), `blocks: [Block]?`
  (`@Relationship(deleteRule: .cascade)`), `summary: AISummaryEntity?`.
- `Block` `@Model`: `id: UUID` **and a separate `order: Int`**. One flat model
  carries the payload for all five kinds — text / image / audio / file / link.
- Reorder rewrites `order` only; ids are never touched.
- `Block.toContent()` adapts the `@Model` into `CardBlockContent`, the
  platform-agnostic value type. **MosaicKit never sees SwiftData** — that boundary
  already existed and Week 1 preserves it.

## 1.2 Summary → Provider → Background task → Persist

```
SummaryStickerView / CardEditorView.handleExit()
   │
   └─ Task { @MainActor in summaryService.generateUpdateSummary(card:force:) }
          │
          ▼
   SummaryService  (@MainActor)
      let blocks = card.blockContents()          ← snapshot captured BEFORE await
      let diff   = SnapshotDiffer.diff(current:snapshot:)
      let images = await loadImages(...)         ← Task.detached, off-main
      let dto    = await client.generate…(…)     ← network, suspension point
      ── resume ──
      summary.applyBase(dto) / append UpdateLogEntity
      summary.snapshot = SummarySnapshot.make(from: blocks)   ← uses the PRE-await capture
      card.modelContext?.save()
```

Change detection already exists and is sound: `ContentHasher` builds a canonical
per-kind string and SHA-256s it; `SummarySnapshot` stores `blockID → descriptor`;
`SnapshotDiffer` yields added / modified / deleted.

**What does not exist:** job identity, deduplication, a concurrency limit,
cancellation, and — critically — **any validation that the content is still current
when the result is written**. See §8 (Technical debt).

## 1.3 Concurrency today

Everything AI-related is `@MainActor`. The only off-main work is image compression
(`Task.detached` in `loadImages`). No `ModelContext` crosses an actor boundary.
Simple, and it means Week 1 introduced the *first* real cross-actor derived-write
path — which is exactly why it needed a spike.

## 1.4 Search today

`SearchMatcher.matches(query:haystack:tags:) -> Bool`. Substring AND over a
flattened haystack. No offsets, no block attribution, no score. (`IG-2`.)

---

# 2. Core Data vs Derived Data

| | Core user data | Derived data |
|---|---|---|
| **What** | `Card` · `Block` · `Folder` · `Tag` | `NoteChunk` · `EmbeddingRecord` · `RetrievalTrace` |
| **Authored by** | the user | computation |
| **If lost** | **unacceptable** | rebuild in seconds |
| **Store** | `default.store` | **`MosaicDerived.store` — separate file** |
| **CloudKit** | synced | **never** |
| **Schema** | `ModelContainerFactory.schema` | `ModelContainerFactory.derivedSchema` |
| **Link direction** | — | → core, **by id string only** |

> **Deleting all derived data must never lose a single user note.**

That rule is enforced structurally, not by discipline: derived records live in a
different `ModelContainer` with a different store file, and reference notes by
`noteID` / `blockID` strings rather than SwiftData relationships. There is no
cascade rule that can propagate from derived data into user content, and
"delete everything derived" is a file removal.

`Card` / `Block` / `Folder` schema is **unchanged**. Goal 1 required zero
destructive migration and got it.

---

# 3. The pipeline

```
Note edit  (@MainActor)
   │
   ▼
Content snapshot            Block.toContent() → CardBlockContent   (value type)
   │
   ▼
Hash                        AIContentHash.forBlock(...)            (SHA-256, canonical string)
   │
   ▼
Job identity                EmbeddingJobKey(noteID, blockID, contentHash, embeddingVersion)
   │
   ▼
Queue                       AIJobCoordinator   dedup · concurrency limit · retry · cancel
   │
   ▼
Provider          off-main  EmbeddingProvider.embed(text)
   │
   ▼
Result envelope             DerivedResult(key:payload:)   ← carries the identity it came from
   │
   ▼
Stale validation @MainActor StaleGuard.decide(result:context:)     ← the correctness gate
   │
   ▼
Derived persistence         EmbeddingRecordEntity in the derived store
```

Everything expensive happens off the main actor. Only the final, already computed,
validated write hops back.

---

# 4. Stale protection

The rule:

> A derived result may be persisted **only if** the content it was computed from is
> still the current content.

Implemented as `StaleGuard.decide`, checked at the persistence boundary, in this
order: note exists → block exists → embedding version matches → content hash
matches.

## Why cancellation is not the mechanism

`Task.cancel()` is an **optimisation**. It saves work when it happens to land. It is
not a correctness guarantee, because:

1. Cancellation is cooperative. A provider that never checks `Task.isCancelled` —
   a synchronous C library, a `URLSession` that already has the bytes, a vendor SDK
   — runs to completion and returns a result.
2. It races completion. The job can finish *before* the cancel is observed and then
   resume after the edit landed.
3. A retry can outlive the edit that should have invalidated it.
4. Nothing cancels across a process restart.

In every one of those cases a stale result is sitting there ready to be written. So
the check is based on **data** (`contentHash`), at a place that **cannot be
bypassed** (the write path), rather than on control flow.

Both properties are tested, including a provider that deliberately ignores
cancellation (`MockEmbeddingProvider(ignoresCancellation: true)`).

---

# 5. SwiftData concurrency model

## The finding

Authoritative note content lives in SwiftData's **main context**, and every user
edit runs on `@MainActor`. Stale protection requires that no edit interleave
between *"read current hash"* and *"write derived record"*.

If validation runs on a background actor, there is necessarily an `await` between
the read and the write — and `await` is precisely where a `@MainActor` edit can run.
The window is small, which makes it worse: it would fail rarely and
non-reproducibly.

## The resolution

The validated write is a **synchronous `@MainActor` critical section**
(`DerivedDataStore.commit`): read context → decide → write, with no suspension
point in between. Since edits are also `@MainActor`, they cannot interleave.

```
off-main:  embed(text)                 ← the expensive part
   hop  ─▶ @MainActor {
             read current hash         ┐  no await between these three
             StaleGuard.decide(...)    │
             write derived record      ┘
           }
```

## Why not `@ModelActor`

A background `@ModelActor` is right when the data being validated *and* written both
live inside it. Here they do not — the truth about content lives in the main
context. Mirroring the hash into the derived store would put both together, but the
mirror would lag behind edits, and a stale mirror means accepting a stale result:
the exact bug being prevented.

If derived writes ever become a main-thread cost, the fix is **batching** (validate
and write N records in one hop), not moving validation off-main.

## Verified

`App/MosaicTests/RetrievalFoundationTests.swift`, 7 tests, real SwiftData contexts on
a real simulator — not pseudo-code, not a mock of SwiftData.

---

# 6. Restart & recovery

**No job queue is persisted.** On launch, Mosaic recomputes what needs doing by
comparing current content against stored embeddings (`DerivedWorkScanner.plan`) and
re-queues.

| Requirement | How it holds |
|---|---|
| No permanent "running" mark | "running" is never persisted, so a kill cannot leave it stuck |
| No infinite re-execution | the scan is a pure function of (blocks, records); a completed block produces no work item |
| No stale write | writes only happen after `StaleGuard` accepts |
| No index corruption | an interrupted job has written nothing, so there is nothing to roll back |

The desired state is already on disk. A persisted queue would be a **second source
of truth** that can disagree with the first — and when they disagree, the queue is
always the one that is wrong.

Goal: *restart is safe*. Not: *restart resumes the exact instruction pointer*.
Re-running an embedding costs one API call; corrupting the index costs correctness.

---

# 7. Decision Log

### D-RT-001 · Derived data lives in its own store, separate from notes

Separate `ModelContainer`, separate store file, no CloudKit, no SwiftData
relationship back to `Card`/`Block`.

*Why:* "derived data is deletable" has to be structural. If embeddings sat in the
note schema, a bad cascade rule or a botched migration could take user notes with
them. Different file ⇒ that is not expressible. Also keeps regenerable bytes out of
the user's iCloud quota, and leaves `Card`/`Block` schema untouched.

### D-RT-002 · Cancellation cannot replace hash validation

Cancellation is an optimisation; `contentHash` comparison at the persistence
boundary is the correctness guarantee. Reasons in §4. Tested against a provider that
ignores cancellation.

### D-RT-003 · Job identity includes `contentHash`

`EmbeddingJobKey = noteID + blockID + contentHash + embeddingVersion`.

*Why `contentHash` specifically:* it is what makes deduplication **safe**. Dedup on
`blockID` alone would suppress the job for freshly edited content because "that block
is already running" — and the index would silently keep the old vector. With the
hash in the key, an edit produces a different key, so it cannot be deduped against
the in-flight old job. Identity and validation use the same four fields on purpose:
one concept, not two.

### D-RT-004 · Restart re-scans instead of resuming a durable queue

See §6. The desired state is derivable from data that already exists; a persisted
queue would be a second, disagreeing source of truth.

### D-RT-005 · No vector storage or retrieval in Week 1

`MockEmbeddingProvider` produces deterministic SHA-derived vectors. No cosine
search, no ANN, no RRF, no index.

*Why:* Week 1's claim is *"derived work is scheduled reliably and stale results
never win"*. Real vectors would not strengthen that claim, and a half-built index
would make the foundation harder to change. `LocalEmbeddingProvider` and
`CloudEmbeddingProvider` exist as compiled seams that fail loudly
(`.unavailable`) rather than returning plausible-looking wrong vectors.

### D-RT-006 · Metadata-only changes do not change the content hash

Excluded from the block hash: `order`, `createdAt`, `tags`, `folder`, `isPinned`,
card title.

*Why:* reordering a block or re-tagging a note must not re-embed anything. The
card-level hash **does** include order and title, so a reorder triggers a cheap
re-scan that finds zero blocks needing work. Cheap scan, zero API cost.

### D-RT-007 · Validated derived writes happen in a synchronous `@MainActor` section

See §5. Not `@ModelActor`, because the authoritative content is not in that actor.

### D-RT-008 · Traces are in-memory and unconditional

Ring buffer of 20, never persisted. Recorded even when Developer Mode is off,
because the PRD's local retrieval SLO (P50 < 100 ms / P95 < 250 ms) can only be
measured on the real user path. Writing diagnostic churn into the note store — and
therefore into CloudKit — would be the wrong trade.

---

# 8. Technical debt discovered

### TD-1 · `SummaryService` has no stale protection *(pre-existing)*

`generateBaseSummary` / `generateUpdateSummary` capture `blocks` before `await`,
then write `applyBase(...)` and `snapshot = SummarySnapshot.make(from: blocks)`
after it. There is no job identity, no dedup, and no check that the card still holds
the content the summary describes.

Today this is not silent corruption — the snapshot is captured *before* the await,
so it is conservative and later edits are still detected as pending changes. But:

- two concurrent generations (auto-on-exit racing a manual tap) are last-write-wins,
  and can pair a summary from v13 with a snapshot from v12;
- there is no dedup, so a double-tap is two paid API calls.

**Not fixed in Week 1** — changing production summary behaviour is beyond
"foundation", and doing it without the same test coverage would be trading one
unverified path for another. The foundation built here (`EmbeddingJobKey` generalised
to an AI job key, `AIJobCoordinator`, `StaleGuard`) is exactly what it needs.
**Recommended for Week 2**, as the second consumer of the same machinery.

### TD-2 · `IG-1` — no OCR pipeline

`CardBlockContent` has no OCR field. Image blocks currently contribute their
user-authored caption as a stand-in (`RetrievableText` returns `.ocr` with the
caption). PRD v1.0 lists Image OCR Text as a Goal 1 corpus source and requires
Golden Set coverage, so this is real work in Week 2 — starting from zero.

### TD-3 · `IG-2` — `SearchMatcher` returns `Bool`

No offsets, no block attribution, no score. Matched Excerpt and highlighting cannot
be built on it. Hard prerequisite for shipping Production Semantic Search.

### TD-4 · Cancellation during queue wait can leak a waiter

`AIJobCoordinator.acquireSlot()` uses `withCheckedContinuation`, which is not
cancellation-aware. A job cancelled *while queued* (not yet running) still holds its
place and resumes before completing. Bounded and harmless at Week 1 volumes — the
slot is released immediately after — but it should become
`withTaskCancellationHandler` when queue depth grows.

---

# 9. What Week 1 does **not** include

No vector storage · no cosine search · no ANN · no RRF · no chunking strategies
beyond block granularity · no Retrieval Lab · no Eval · no Golden Set · no Release
Gate · no Semantic Search integration · no production embedding index.

The foundation is deliberately inert: it schedules, validates, and persists derived
work correctly, and proves it. Week 2 gives it something real to compute.
