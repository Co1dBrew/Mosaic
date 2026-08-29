# Mosaic — Retrieval Architecture

> Goal 1 · Week 1 (Runtime Foundation) · Week 2 (Chunking · Corpus · Vector Index)
> · Week 3 (Keyword / Vector / Hybrid · RRF · Excerpt · Retrieval Lab)
> Status: **all three landed and verified**; Eval / Golden Set start Week 4.
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

# 9. Week 2 — Chunking, corpus, vector index

## 9.1 Chunk pipeline

```
Block ──▶ resolveText(block, ocrOverlay) ──▶ split(strategy) ──▶ [NoteChunk]
                                                                   id = noteID/blockID/index
                                                                   charStart / charEnd
                                                                   contentHash (of the block)
                                                                   strategy identity
```

Three strategies, comparable in the Retrieval Lab:

| Strategy | Behaviour |
|---|---|
| `.block` | one chunk per block — the baseline everything else is measured against |
| `.fixed(maxChars, overlap)` | cuts at `maxChars`, preferring a sentence boundary within the last quarter of the window, carrying `overlap` characters forward |
| `.sentence(maxChars)` | groups whole sentences; never cuts mid-sentence; an over-long sentence becomes its own chunk rather than being dropped |

`charStart` / `charEnd` exist so a future match can be mapped back to a position for
Matched Excerpt windowing. Without them a hit in chunk 3 of 7 could only be located
by re-searching the block.

**Overlap matters for recall, not tidiness.** A sentence spanning a cut is present in
both neighbours, so it is findable from either side. Without overlap, the sentences
that straddle boundaries are exactly the ones that go missing.

## 9.2 The five corpus sources

| Block kind | Retrieval source | Text |
|---|---|---|
| text | `.text` | body |
| audio | `.transcript` | transcript |
| image | `.ocr` | **caption + OCR**, newline-joined |
| file | `.extracted` | extracted document text |
| link | `.link` | title — description — URL |

Image blocks combine caption and OCR because the caption often carries intent the
OCR cannot (「答辩时间表」 over a photo of a grid of numbers).

## 9.3 IG-1 closed — Image OCR

`VisionImageTextExtractor` (app target, `VNRecognizeTextRequest`, `.accurate`,
`zh-Hans` / `zh-Hant` / `en-US`), running off the main actor. The protocol lives in
MosaicKit, the implementation in the app — the same seam shape as `EmbeddingProvider`,
because Vision is not available to the toolchain that runs `mosaic-checks`.

Verified against Vision itself: `testVisionOCRFeedsChunkPipelineAndHash` renders a
PNG containing known text, runs the real extractor, and asserts the word comes back.

**Handwriting is deliberately unsupported.** Vision's handwritten-Chinese quality is
poor enough that indexing its output would inject noise, and noise in the index is
worse than a missing source: it produces confident wrong matches instead of no match.
Recognitions below 0.3 confidence are discarded for the same reason.

## 9.4 OCR is derived data

Stored in the derived store as `ImageTextExtractionEntity`, **not on `Block`**.

`Block.transcript` and `Block.extractedText` are already derived-but-stored-on-core —
because both are user-visible and user-editable (PRD §4.3.2 lets the user correct a
transcript). OCR is neither. Putting a machine artefact into the note schema would
push it into CloudKit sync for zero user-facing benefit.

It is keyed by the *block* content hash, and the image asset ref is already inside
that hash — so replacing the image automatically invalidates the stored OCR.

## 9.5 Chunk-granular embedding lifecycle

One block → N chunks → N vectors. Consequences:

- **`EmbeddingJobKey` gained `chunkIndex`.** Without it, two chunks of the same
  block share a key and the coordinator deduplicates the second away — silently
  indexing only part of a long block.
- **Orphans are now chunk-level.** A block shrinking from 7 chunks to 3 leaves 4
  orphan vectors that would otherwise stay searchable forever, returning text the
  note no longer contains.
- **Strategy identity is stored on every record.** Switching chunk strategy
  invalidates the index exactly the way switching model does.

## 9.6 Vector index — exact brute force

`InMemoryVectorStore`: exhaustive cosine, sorted by similarity then `chunkID`.

The tie-break is not cosmetic. Without it, equal-similarity results come back in
dictionary order, which varies per process — and evaluation results that vary per
run cannot be compared across configs.

Rebuilt from the derived store at launch (`allRecords()` → `upsert`). Having no
build step means it cannot be stale relative to the records it came from.

## 9.7 Benchmark — measured

```
brute-force cosine, dim 384, topK 20, release build
chunks        P50        P95
  1000      0.39 ms     0.41 ms
  5000      2.06 ms     2.11 ms
 20000      9.83 ms    10.38 ms
SLO: P50 < 100 ms · P95 < 250 ms
```

**20k chunks uses ~10% of the P50 budget.** Linear extrapolation puts the P50 limit
near 200k chunks — far beyond a personal note corpus. **ANN is not needed for Goal 1**,
and that is now a conclusion from data rather than an assumption.

⚠️ **The debug build reports 1200 ms at 20k — 122× slower for the same code.**
Swift numeric loops without optimisation say nothing about shipping performance. The
benchmark therefore asserts the SLO only in release builds and labels debug output
as unrepresentative. This nearly produced the wrong architectural decision: the first
measurement looked like proof that brute force could not meet the SLO.

## 9.8 Index state machine

Five states — `ready` · `building(progress)` · `rebuilding(pending)` ·
`stale(pending)` · `failed(reason)` — mapping directly onto the designed
`RetrievalCapability` in `design/SEARCH_CONTRACT.md` §4.1. One vocabulary, not two.

State is **derived from facts** (`IndexStateMachine.derive`), never assigned. A
settable field drifts: some path forgets to clear `building` and the UI spins
forever. As a pure function of (total, pending, running, failure) it cannot get
stuck — a stale failure with no pending work resolves to `ready` on its own.

`allowsKeywordRetrieval` is a **constant `true`**, so no future state can
accidentally disable keyword search. Progressive Enhancement expressed as code
rather than as a habit.

---

# 10. Week 2 decisions

### D-RT-009 · Job identity gained `chunkIndex`

Two chunks of one block would otherwise share a key and be deduplicated into one —
silently indexing only part of a long block. Dedup is only safe when the key
distinguishes everything that should run separately.

### D-RT-010 · OCR is derived data, not a `Block` field

See §9.4. Keyed by block content hash, so a replaced image invalidates it for free.

### D-RT-011 · OCR is printed zh/en only; handwriting unsupported

Noise in the index is worse than a missing source — it produces confident wrong
matches. Same reasoning for the 0.3 confidence floor.

### D-RT-012 · Exact brute force; ANN deferred until measurement demands it

An approximate index can only be evaluated against an exact baseline, so the exact
one has to exist first. §9.7 says the budget is not close. ANN would be scope
expansion.

### D-RT-013 · Index state is derived, and keyword retrieval is unconditional

See §9.8.

### D-RT-014 · Chunk overlap is a recall feature

Sentences straddling a cut are exactly the ones that would otherwise be lost.

### D-RT-015 · SLO assertions only in optimised builds

A debug measurement of a numeric loop is not evidence about shipping behaviour.
Asserting on it would have blocked a correct design (§9.7).

---

# 11. Week 3 —— 三路检索 · RRF · Excerpt · Lab

## 11.1 IG-2 关闭

`SearchMatcher.matches(...) -> Bool` 丢掉了三样东西，而这三样正好是 Goal 1 全部需要的：

| 丢掉的 | 谁需要它 |
|---|---|
| 命中位置 | Matched Excerpt 开窗 + 对比式高亮 |
| 归属哪个 block | Search Result → Note 的 scroll anchor |
| 分数 | 排名 + 与 vector 路做 RRF |

新增 `TextMatcher.locate` / `KeywordHit`，返回字符区间 + `BlockRef` + 分数。
**既有 `matches()` 原样保留** —— 它是线上搜索的唯一调用点，语义一个字没改。

偏移一律按 **Character** 计，不按 UTF-8 字节：中文一个字占 3 字节，按字节做高亮会切碎汉字。
归一化（大小写 / 变音符 / 全角半角）必须保持字符数不变，否则偏移错位；代码里有断言兜底。

## 11.2 分词口径：按空白切分 + 子串定位

**刻意不引入词典分词，也不做 CJK 二元组。** 三个理由：

- 中文子串匹配天然可用 —— 「延期」在「延期毕业」里就是子串，不需要词典。
- 二元组会让 `SEARCH_CONTRACT` §2.6 的前提失效：一句自然语言 query
  **应该** keyword 零命中、全部交给语义路，这正是 24 屏要展示的产品状态。
  二元组会让它蒙对几条，把一个清晰的状态变成一团糊。
- 与既有 `matches()` 语义完全一致，线上搜索行为不变。

代价是承认的：keyword 路对长句无能为力。那本来就是 vector 路的职责。

## 11.3 Keyword 打分

```
score = Σ_token  min(tf, 3) / sqrt(chunkLength)  ×  sourceWeight
```

- **`min(tf, 3)`** 词频截断 —— 同一个词出现 20 次通常只是列表或模板，不比 3 次更相关。
- **`/ sqrt(len)`** 长度归一 —— 不归一则长 chunk 天然占优，短而精准的一句会被埋掉。
- **`sourceWeight`** 出处权重（text 1.00 → ocr 0.85），**差距刻意压得很小**，
  因为目前没有数据支持更大的差距。这是 Week 4 Eval 的第一批调参对象。

**不做 BM25**：IDF 需要稳定的语料统计，而个人笔记库既小又一直在变，
IDF 会随每次编辑抖动，使评测不可复现。等 Golden Set 证明排序不够用了再引入。

## 11.4 RRF

```
score(d) = Σ_路  1 / (k + rank_路(d))          k = 60
```

选它而不是加权分数相加，理由只有一个但足够硬：**两路的分数不可比。**
keyword 是 TF 归一分，vector 是余弦相似度，量纲和分布都不一样。加权相加的权重
就是在拿两把不同刻度的尺子拼长度 —— 调出来的值只对当前这批数据成立。

RRF 只用名次，绕开整个可比性问题。代价是丢掉强度信息，换来稳定与可解释。

**单路缺失 = 不贡献分数，而不是罚分。** 所以只被 vector 命中的结果仍然能进最终榜 ——
这正是 24 屏纯语义结果能出现的原因。

`k=60` 是文献常用默认值，作用是压平头部差距。**是 tuning value，不是产品结论。**

## 11.5 RetrievalService —— 三路排名同时返回

三种 mode 走**同一条管线**，只是跳过其中一路 —— 而不是三份各自的实现。
三份实现意味着三处可以各自跑偏，而 Compare Modes 比较的恰恰是它们的差异，
那样比出来的可能是实现差异而不是策略差异。

`RetrievalResult` 同时携带 `keywordRank` / `vectorRank` / `fusedRank` / `similarity`
/ `matchedRanges`，产出 `K #3 · V #7 → #2` 这一行 —— `DECISION_LOG.md` D-UI-DEV-007
对检索层提的硬要求。

**Progressive Enhancement 在检索层就生效**：`indexState` 不允许 vector 时自动降级为
纯 keyword，并在 trace 上标 `isStale`。不依赖 UI 记得处理。

## 11.6 ExcerptBuilder —— W1–W7

纯函数，逐条实现 `SEARCH_CONTRACT` §2.3 的七条规则与 §2.7 的四级 fallback 链。
做成纯函数的唯一理由：每条规则都能单独写一个用例。

一个容易漏的点：**W7 折叠空白必须先做，并把命中区间一起搬移**。
否则后面所有偏移都是对着原文算的，而展示的是折叠后的文本 —— 高亮会整体错位。
测试里专门有一条 `前面\n\n延期\n\n后面` 覆盖它。

## 11.7 Retrieval Lab（D2 / D3 / D4）

全原生控件：`Form` + `Picker` ×5 + `List`。唯一的自定义视图是结果卡片，内部只有文本。

- **Compare 是第四个 Mode 状态**，不是独立页面（D-UI-DEV-007）：一次检索就能拿到三路排名。
- **高亮用 `AttributedString.foregroundColor`**，与 Figma 的 per-range fill 一一对应 ——
  §2.4 之所以选前景对比而不是背景色块，就是为了这个。
- **Trace 页把常见结论直接写出来**（候选为 0 → 问题在检索层；embedding 占比过高 → 先看 provider），
  省掉「盯着数字猜」的一步。禁止 waterfall chart。

Developer Mode 入口已接进「设置 › 高级」，**默认 OFF，关闭时整行不出现**。

---

# 12. What Week 3 does **not** include

No keyword retrieval rework (`IG-2` still open) · no RRF or hybrid fusion · no
Retrieval Lab UI · no Eval · no Golden Set · no Release Gate · no Semantic Search
integration into production search · no ANN · no real embedding model
(`MockEmbeddingProvider` still stands in — the seam is proven, the model is Week 3).

Week 2 gives the foundation something real to compute over. Week 3 gives it modes to
compare and a Lab to explain them.

---

# 13. Technical debt — current

| ID | Status |
|---|---|
| **TD-1** `SummaryService` has no stale protection | **Open.** Pre-existing. Now has three working consumers of `AIJobCoordinator` + `StaleGuard` to copy from |
| ~~TD-2 / IG-1~~ no OCR pipeline | **Closed in Week 2** (§9.3) |
| ~~TD-3 / IG-2~~ `SearchMatcher` returns `Bool` | **Closed in Week 3** (§11.1) |
| **TD-4** queued-job cancellation can leak a waiter | **Open.** Bounded and harmless at current depth |
| ~~TD-5~~ real embedding model | **Closed.** `NLEmbeddingProvider`（Apple `NaturalLanguage`，zh-Hans 640 维，离线）。拿不到时**不退回 mock** |
| **TD-6** vector index is memory-only | **Open.** Rebuilt from the derived store at launch; fine at 20k chunks |
| ~~TD-7~~ 生产搜索仍走旧路径 | **Closed（§16）。** `SearchView` 走 `RetrievalService` 的隐式 Hybrid：Matched Excerpt + 对比式高亮 + 状态条 + 两级触发。~~落点行为（5.10）仍未做~~ → **落点已补齐（§17.3）** |
| **TD-10** 向量检索没有相关性下限 | **状态：Improved / Calibratable，但未 production-resolved。** `bge-m3` 的余弦有了真实解释力（v3 实测：正例 top1 中位数 0.700 / 负例中位数 0.531），但**没有安全的单一阈值**：完美分离间隙 **−0.169**；最佳阈值 0.595 能挡掉 19/20 负例，代价是**丢掉 7/67 正例**（10.4% 的正确答案被静默丢弃）。⚠️ v2 上曾测得「0.54 挡 9/10 且不误伤」，那是小负例集的假象，**v3 推翻了它**。`similarity >= 0.54` **禁止**写成 production requirement。要继续研究必须先有更大的 hard-negative 集 |
| **TD-11** 余弦受文本长度支配 —— **provider-specific，非系统性解决** | **状态：Resolved for `bge-m3`，未 resolved for `NLEmbedding`。** 云端实测长度效应 0.0886 / 相关性效应 0.4142（**相关性赢 4.7 倍**），与本地完全反转。**不得写成「系统永久解决 length bias」** —— 换 provider 就要重测。本地实测（§18.3）：同一段文字拉长 16 倍，余弦下降 0.0496；而相关 / 无关文本在同一长度上只差 0.0115 —— **长度效应是相关性效应的 4.3 倍**，且存在「无关但更短」压过「相关但更长」的情形。直接后果：长笔记天然吃亏（§18.2 的长文用例三种切分全败）· TD-10 的阈值不能只看余弦 · 切到相近长度是**可比性**要求而不只是 recall 特性。**没有实现长度归一化**（无 Golden Set 支撑的模型层改动属范围扩张）；`RetrievalWeek6Checks.checkCosineLengthBias` 钉住现象 |
| ~~既有缺陷~~ 文本块不换行 | **Closed（§17.4）。** `RichMarkdownEditor` 缺 `sizeThatFits`，长文本横向铺出屏幕。它挡着 5.10 的验收（高亮几何无法成立），所以在本轮修掉，模拟器实拍确认 |
| ~~TD-8~~ App 侧没有索引服务 | **Closed（§15）。** `IndexingService` 接上了扫描 → 嵌入 → 校验落盘 → 内存索引这条线 |
| **TD-9** iOS 上没有 zh-Hans 句向量模型 | **实测可用性矩阵**（iPhone Air · iOS 26 模拟器，`NLEmbeddingAvailabilityTests`）：`zh-Hans ❌` · `zh-Hant ❌` · `ja ❌` · **`en ✅ 512 维`**。同样的代码在 macOS 上拿得到 zh-Hans（640 维），Golden Set 实测就跑在它之上。**2026-08-13 本机 App 确认**：Developer Mode 显示 Embedding Provider「不可用」，文案「本机没有可用的本地句向量模型，语义检索不可用；关键词搜索不受影响。」—— 与模拟器一致，**不是模拟器特例**。iOS 上只有 keyword 路可用。**不拿英文模型顶替**：换语言就是换向量空间，中文笔记配英文模型排出来的顺序没有意义。中文语义必须另找模型来源（云端 embedding / 自带模型） |

---

# 14. Week 4 —— 评测面（D5 / D6 / D9）

内核（`EvalRunner` / 口径 / `RegressionSet`）见 `design/GOAL1_BACKLOG.md` 4.1–4.5。
这一节只记 UI 接上真实数据时**新做的工程判断**。

## 14.1 Golden / Regression 数据集不放 derived store

Derived store 的契约是「删掉全部内容不丢任何东西，因为都能重建」（§2）。
Golden Set **不满足**这个契约：「这条 query 应该找到哪篇笔记」是人工判断，
删了要靠人重标一遍。把不可重建的数据放进一个明确标着「可以随时清空」的 store，
迟早会被一次 `deleteAll()` 抹掉。

所以它是 Application Support 下的一个 JSON 文件（`EvalDatasetStore`）：
`EvalCase` 本来就 `Codable`，形状还会随 Week 5/6 变，没必要先上 schema。

**没有种子数据。** 用例引用的是**本机**笔记的 UUID，跨设备预置的用例只会全都
dangling。所以 Golden 用例必须在设备上标，期望笔记从真实笔记里挑而不是手输 id。
`EvalDataset.danglingCases` 把引用了已删笔记的用例标出来 —— 它们必然失败，
但原因不是检索质量。

## 14.2 评测自己建索引，不用生产索引

`RetrievalEvalViewModel.index(for:config:)` 为本次评测建一份**独立的内存索引**，
按 (语料指纹 + chunk 策略 + embeddingVersion) 缓存，**不落盘、不覆盖生产索引**。

理由是 chunk 策略：生产索引是用某一套策略建的，换策略后 chunkID 全变，vector 路
命中的 chunk 在当前语料里找不到、被静默丢弃 —— 表现是「换了策略语义突然变差」，
而真正原因是索引对不上。Week 6 的 6.2（chunk 策略对比实验）需要这一层才成立。

建索引的耗时**不计入 P50 / P95** —— 那两个数只统计检索本身（与 PRD 的 SLO 同口径）。

## 14.3 baseline 必须跑 current 那一批用例

D6 的 delta 只有在两次跑批的用例集相同时才有意义。

**这是在模拟器上实跑 Flow B 时抓到的缺陷**：D9 的 `Add to Regression Set` 会当场
把 `Golden + Regression` 的用例数 +1，此时点 Run Baseline，baseline 跑的是 3 条、
current 是 2 条，表格里 `Recall@5 0.500 → 0.333` 看起来像配置变差了，实际上是分母变了。

修法：current 跑批时记下用例快照，baseline 跑同一批；重跑 current 会作废旧 baseline；
再加一条 `isComparable`（用例数不等就不出 delta）兜底。
`RetrievalWeek4Tests.testBaselineRunsTheSameCaseSetAsCurrent` 守着它。

## 14.4 `RetrievalService` 的 provider 变成可选

本机没有句向量模型时，vector 路整条跳过、keyword 路照常 —— 与 `IndexState` 的降级
走**同一个出口**，不是第二套逻辑。这样 keyword 评测在没有模型的设备上仍然可跑
（TD-9 之后这不是假设，是模拟器上的现状）。

顺带修掉一处既有的不一致：`DeveloperModeView` 原先在 provider 为 nil 时给 Lab 塞了
一个 `MockEmbeddingProvider()`，与 TD-5 的「不退回 mock」结论相反 —— 伪向量会让 Lab
排出一份看起来正常、实则无意义的顺序。现在传 nil。

## 14.5 Week 4 **不**包含

没有 Release Gate、没有 `GateThresholds`、没有 Promote、没有 `RetrievalConfig` 版本化
（D5/D6 的 `version` 是由可调项拼出来的字符串，不是版本记录）——
那些都是 Week 5。Eval 只讲 trade-off，**不下 PASS / FAIL**。

---

# 15. TD-8 关闭 —— 生产索引服务

`App/Mosaic/Retrieval/IndexingService.swift`。在它之前，Week 1–3 的每一块都单独测过，
但**没有人把它们接起来**：derived store 只有测试在写，所以真机上索引永远是空的，
Retrieval Lab 的 vector 路一直什么都搜不到。

```
笔记内容 ──▶ OCR（图片块，derived）
         ──▶ DerivedWorkScanner.plan   ← 与已存记录比对：pending / orphan
         ──▶ AIJobCoordinator          ← 并发上限 2 · 按 contentHash 去重 · 重试
         ──▶ provider.embed            ← off-main
         ──▶ DerivedDataStore.commit   ← StaleGuard 校验，同步 @MainActor 临界区
         ──▶ InMemoryVectorStore       ← 只有被接受的记录才进内存索引
```

## 15.1 三条不变量

1. **内存索引只装落盘成功的向量。** `commitBatch` 逐条校验，被 `StaleGuard` 拒掉的那条
   **不能**进内存索引 —— 否则磁盘上没有的过期向量会继续参与线上检索，
   等于把 §4 要防的 bug 换个地方重演。`testRejectedEmbeddingNeverEntersTheMemoryIndex`
   构造「嵌入进行中改内容」来守它。
2. **orphan 先删再写。** 块被删、被清空、或从 N 个 chunk 缩到更少时，旧 chunk 必须
   立刻同时从两处消失。留到下一轮意味着搜到一段已经不存在的文本。
3. **不靠取消保证正确性。** 编辑期间新的扫描不断进来，旧任务照跑完；
   去重靠 `EmbeddingJobKey`（含 contentHash），正确性靠写入路径的校验（§4）。

## 15.2 触发点

| 时机 | 入口 | 行为 |
|---|---|---|
| 启动 | `MosaicApp` → `RetrievalEnvironment.startIndexing()` | 先 `loadPersistedIndex()` 再 `indexAll()`。**顺序不能反** —— 先扫描会把「已存好、只是还没加载」的 chunk 判成 pending，于是每次冷启动重嵌全库 |
| 编辑 | `CardEditorView.commitNow()` → `noteDidChange(noteID)` | 保存**之后**才通知（索引读的是 SwiftData 里的权威内容）；服务内部合并 + 防抖 600ms，因为自动保存在一次输入里会触发很多次 |
| 删除笔记 | `CardListView.delete` → `noteWasDeleted(noteID)` | 删 embedding + OCR + 内存索引条目。否则搜索会命中一篇点进去是空的笔记 |
| 手动 | Developer Mode → `Rescan Now` | 全库增量扫描 |

重启不恢复队列，而是重新推导要做什么（§6）—— 这条在这里第一次真的被用上。

## 15.3 一套策略，不是可选项

索引口径由 `IndexingService.config`（默认 `RetrievalConfig.production`）单点决定。
生产索引只能有**一套** chunk 策略：两套策略的记录混在一个 store 里，chunkID 对不上，
vector 命中会被静默丢弃。同一个理由下，Retrieval Lab 在选了与索引不同的策略时会
显式提示 —— 那种情况下 vector 路命中变少**不是语义变差，是索引对不上**。

## 15.4 仍然没做

生产搜索还没接上（TD-7 / Week 5.5）：`SearchView` 依旧走 `SearchMatcher.matches`。
这一节只保证「索引是真的存在且是新的」，用它的还只有 Developer Tools。

---

# 16. TD-7 关闭 —— 生产搜索接入 Hybrid

`App/Mosaic/Features/Search/`（`SearchViewModel` + 重写的 `SearchView`）
+ `Sources/MosaicKit/Search/SearchPresentation.swift`。

上游是 `design/SEARCH_CONTRACT.md`（**RE-FROZEN**），不是本文件 —— 这里只记实现侧的判断。

## 16.1 两个正交维度，不是八个扁平状态

`QueryPhase`（idle / searching / ready / noResults）驱动结果区，
`RetrievalCapability`（full / indexBuilding / indexRebuilding / semanticUnavailable / offline）
驱动状态条，两者独立演进（契约 §4.1）。铺平成一个八值枚举会立刻产生
「索引建立中但同时在检索」这种无法回答的组合。

`IndexState`（工程侧五态）到 `RetrievalCapability`（用户侧五态）只有**一处**映射：
`RetrievalCapability.derive(indexState:semanticProviderAvailable:)`。

**顺手删掉了 `IndexState.capability`** —— 它只看索引状态，会在「本机根本没有句向量模型」
的空库上报出 `full`，那是一句假话。现在调用方必须一并回答 provider 在不在。

## 16.2 两级触发

| 通道 | 触发 | 防抖（初值） | 门控 |
|---|---|---|---|
| keyword | 每次输入变化 | 150ms | 无 |
| semantic | 输入停顿 | 400ms | CJK ≥2 字 / 拉丁 ≥3 字符 |

长度门控是 `SemanticGate`（内核，纯函数）。混合 query 按主语言判定，
**CJK 严格过半**才用宽阈值 —— 打平时用更严的那套，否则「a延」这种两字符噪声
也会触发一次嵌入。

防抖的存在理由是**省 embedding 成本与避免抖动，不是掩盖延迟**：本地检索的 SLO
比人的输入停顿还快，所以调参方向是尽量小（契约 §1.2 的注）。

## 16.3 chunk → 一行一笔记

`SearchPresentation.rows` 按 §2.5 收敛：每篇笔记只取**融合得分最高**的那个 chunk。
契约里的第 2–4 条并列规则（覆盖 term 数 → block order → offset）在当前融合实现下
**不可达** —— `fusedRank` 是全序。**没有写那三个分支**：一段永远跑不到的代码
比缺失更糟，它看起来像实现了。

anchor 由检索层给出（transcript 命中 → `.transcript`，其余 → `.block`），
UI 不猜。落点行为本身（scroll + 临时高亮）是 5.10，**本轮没做**。

## 16.4 标题与标签：不进语料，但必须仍然搜得到

契约 §2.8 把 Title / Tag 定为 **lexical signals**，它们不参与嵌入。
但如果只把检索结果摆出来，「按标题找笔记」这个既有行为会**静默消失**。

所以 `appendingLexicalMatches` 把只靠标题 / 标签命中的笔记补在内容命中**之后**：
它们没有可比的融合分数，硬塞进榜单中间等于发明一套相关性。
excerpt 走 fallback 第 2 级（笔记开头），无高亮（§2.4「标题不高亮」）。

## 16.5 AI 摘要退出检索语料

Correction 4 明确：**AI Summary 不是 Goal 1 检索语料。** 旧实现的 haystack 里包含
`baseTitle / baseOneLiner / baseSummary / topics / keyPoints / updateLogs`，
接入之后这些**不再参与匹配**。

这是契约要求的行为变更，不是回归 —— 但它对用户可见：以前靠摘要里的措辞能搜到的
笔记，现在只能靠正文 / 转写 / OCR / 文档 / 链接 / 标题 / 标签搜到。
空态文案已同步（不再写「与 AI 摘要」）。

## 16.6 in-flight 任务不该给 ViewModel 续命

两条通道的防抖任务都 `[weak self]`，并在 `onDisappear` 取消。
**这是测试逼出来的**：用例结束后挂在防抖里的任务会在容器释放之后继续跑，
去主上下文做一次全库切分，直接把测试进程 trap 掉。
生产里容器是 App 级的所以不会崩，但「屏已经没了还查一次」同样没有意义。

## 16.7 仍然没做

- **5.10 Result → Note 落点**：anchor 已经随结果返回，但进入笔记后仍停在顶部，
  没有 scroll-to-block、没有 2.0s + 0.4s 的临时高亮。
- **`.searching` 时搜索框尾部的 ProgressView**（契约 §4.3）：`.searchable` 不提供
  尾部配件槽位。I5 的实质要求（不使用覆盖结果的 spinner、结果保持可读可点）已满足，
  差的是那 20pt 的指示器。要补就得自建搜索框组件。
- **TD-10 相关性下限**（见 §13 表）。

---

# 17. Week 5 —— Release Gate 与落点（5.1–5.4 · 5.9 · 5.10）

内核：`Sources/MosaicKit/Retrieval/RetrievalConfigRegistry.swift` ·
`Sources/MosaicKit/Eval/ReleaseGate.swift` · `Sources/MosaicKit/Search/SearchLanding.swift`
App：`App/Mosaic/DeveloperTools/ReleaseStore.swift` · `ReleaseGateView(Model).swift` ·
`RetrievalConfigView.swift` · `App/Mosaic/Features/Editor/SearchLandingController.swift`

## 17.1 「生产配置只能经 Promote 更换」是结构性的，不是纪律

`RetrievalConfigRegistry` 里**没有任何 API 能改生产记录的参数**：
`duplicate` 只能派生 draft，`setCandidate` 拒绝生产记录，`remove` 拒绝生产与候选。
换掉生产配置的唯一入口是 `promote(id:decision:)`，而它要求：

1. 目标必须是 **candidate**；
2. `decision.isPass`；
3. `decision.configVersion == 记录的 version`。

第 3 条拦的是**「改完参数没重跑评测就上线」**：那种情况下判定还是绿的，
但它判的是上一套配置。UI 上的置灰只是呈现 —— 只有 UI 层拦截的话，
第二个调用点出现的那天就绕过去了。

`ReleaseGateViewModel.promote()` 在成功后调用 `IndexingService.applyConfig(_:)`：
换了 chunk 策略就重建索引。不做这一步的话，Promote 只是改了一行 JSON，
线上跑的还是旧策略（§15.3 的同一条理由）。

## 17.2 判定就是 `allSatisfy`

四项检查，任一 FAIL 即阻断，**不加权、不算总分**（D-UI-DEV-008）。
`ReleaseGate.evaluate` 里那一行 `checks.allSatisfy(\.passed)` 是整个模块的产品主张。

两处**不能默认放行**的边界：

- **没有 baseline** → 质量类两项判失败，`detail` 明确写「还没跑 baseline」而不是
  「质量下降」。补救动作完全不同：一个是去跑 baseline，一个是去调配置。
- **两次跑批用例数不同** → 同上。这是 §14.3 在 D6 上抓到的缺陷在 Gate 上的对应物。

`stale` 只有三态里的一种，没有第四态：「没跑过评测」和「评测早于当前配置」的
补救动作一样，多一个状态只会多一处文案分叉。

**TD-9 的一个直接后果**：生产配置是 hybrid，而没有句向量模型的机器（当前的模拟器）
**根本无法验证一套 hybrid 配置** —— 那里的 Gate 会一直 STALE。这是对的，不是 Gate 坏了。

## 17.3 落点：几何与时序是常量与纯函数，不是散落的字面量

契约 §3.3 / §3.4 给的是具体数字（0.15s / 2.0s / 0.4s / 0.2s · 8pt / 12pt / 88pt / 50%）。
它们放在内核 `SearchLanding` 里，**每一条都有断言**；散落在 View 里的字面量
没有办法证明「实现符合契约」，只能靠人去比对文档。

`.top` 落点的锚点是**反解出来的**，不是拍的：SwiftUI 的
`scrollTo(_:anchor:)` 把目标视图与可视区的**同一个比例点**对齐，于是
`offset = origin + y·H_view − y·H_viewport`。要让 block 顶部落在距顶 88pt 处，
需要 `y = topInset / (H_viewport − H_view)`。block 比可视区还高时无解（分母 ≤ 0），
那时顶部对齐（`y = 0`）是能给出的最好结果。

执行顺序（`SearchLandingController`）：
`展开转写 → 等一帧 layout → 无动画滚动 → +0.15s 高亮 → 保持 2.0s → 0.4s 淡出`。
用户滚动 / 点击 / 开始编辑 → **0.2s 淡出**，幂等（手势会连续触发很多次）。

## 17.4 顺带修掉的既有缺陷：文本块不换行

`RichMarkdownEditor` 是 `UIViewRepresentable` 包 `UITextView`，此前只设了纵向
抗压缩优先级，没有实现 `sizeThatFits`。SwiftUI 于是用它的固有尺寸 ——
即「整行不换行」的宽度 —— 一段长文本会横向铺出屏幕两侧。

这是既有缺陷（来自 p1-rich-text），但它**挡着 5.10 的验收**：块比屏幕还宽时，
临时高亮的 8pt 外扩与 12pt 圆角全被挤出屏幕，看起来是一条通栏色块，
契约 §3.3 的几何在这种行上根本无法成立。修法是实现 `sizeThatFits`：
按父视图给的宽度算高度。**模拟器实拍验证：修复前一行铺出屏幕，修复后两行正常换行，
高亮呈现为带圆角的外扩矩形。**

## 17.5 Week 5 仍然没做

- **Golden Set 规模**：内核里那份是 7 条 query / 8 篇笔记，改一条数字就跳 0.14。
  Release Gate 的阈值建立在这种样本上没有意义（规模由 PRD v1.0 决定）。
- **真机 SLO**：5.9 的数字全部来自 Mac。见 §18。
- **`.searching` 的尾部 ProgressView**（同 §16.7）。

---

# 18. Week 6 —— 实测数字（6.1–6.6）

> ⚠️ **以下全部是 Mac 上 `swift run -c release mosaic-checks` 的实测值。**
> iPhone 真机数字一定不同，**真机复测仍是待验证项**。
> 复现命令：`swift run -c release mosaic-checks`

## 18.1 SLO 与规模曲线（5.9 / 6.3）

端到端 hybrid 检索（keyword + vector + RRF + 排名，**不含 UI**），dim 384：

| chunks | P50 | P95 |
|---|---|---|
| 1 000 | 3.59 ms | 3.77 ms |
| 5 000 | 18.23 ms | 19.33 ms |
| 20 000 | 75.85 ms | 79.54 ms |

**结论：20k chunks 仍在 SLO（P50<100 / P95<250）内 → Goal 1 不需要 ANN**，
D-RT-012 的结论在端到端复测后仍成立。

⚠️ 同一份代码 **debug 构建 5 000 chunks 是 333 ms**（release 的 18 倍）。
SLO 断言只在 release 生效（D-RT-015）。

## 18.1a Hybrid vs Keyword Baseline（6.1a）—— PRD 的核心主张

同一批用例 · 同一份语料 · 同一套 chunk 策略，只换 `mode`
（8 篇笔记 / 7 条 query · 真实 `NLEmbedding` · release）：

| Mode | Recall@1 | Recall@3 | Recall@5 | MRR | P50 | P95 |
|---|---|---|---|---|---|---|
| **keyword（baseline）** | 0.286 | 0.286 | 0.286 | 0.286 | 0.04 ms | 0.07 ms |
| vector | 0.571 | 0.714 | 0.714 | 0.639 | 3.94 ms | 7.49 ms |
| **hybrid** | 0.571 | 0.714 | 0.714 | 0.639 | 4.33 ms | 6.96 ms |

Hybrid vs keyword baseline：**Recall@5 +150%（绝对 +0.429）· MRR +123.8%（绝对 +0.354）**，
代价是 P95 从 0.07ms 涨到 6.96ms（多一次 query embedding）—— 仍在 250ms 预算的 3% 以内。

> ⚠️ **这不是产品结论。** n=7，**一条用例翻面 = 0.143 的跳动**，
> 而 keyword baseline 只有 2/7 命中，分母极小会把相对提升放大。
> 它证明的是「管线通了、方向对了」，不是「语义检索提升 150%」。
> 真正的结论要等 Golden Set 扩到 PRD v1.0 规定的规模。
>
> 另一个必须说明的点：**这批 query 是刻意按「字面几乎不重合」构造的**
> （见 `EvalChecks.goldenSet` 的注释），本来就对 keyword 不利。
> 一份按真实使用分布抽样的 Golden Set 上，keyword baseline 会明显更高。

**hybrid 与 vector 在这批用例上完全相同** —— keyword 路能命中的 2 条，vector 路也都命中了，
RRF 没有改变笔记级的顺序。这说明**当前语料规模下融合还没有产生独立价值**，
它的价值要在 keyword 独有命中出现时才体现（Compare Modes 的 unique hit 分组就是看这个）。

## 18.2 Chunk 策略对比（6.2）

语料 11 篇（8 篇短笔记 + 3 篇长笔记，答案埋在中段）· 10 条 query · 真实 `NLEmbedding`：

| 策略 | chunks | Recall@1 | Recall@3 | Recall@5 | MRR |
|---|---|---|---|---|---|
| block | 11 | 0.400 | 0.500 | 0.500 | 0.466 |
| fixed(240/40) | 26 | 0.400 | 0.500 | 0.500 | 0.446 |
| sentence(240) | 25 | 0.400 | 0.500 | 0.500 | 0.460 |

**这张表的结论不是「三种策略一样好」，而是「换切分解决不了这批用例」**：
三种策略下**长文用例 3/3 全部失败**。追因见下一节。

> 第一版实验用的是原来的 8 篇短笔记，三种策略切出的 chunk 数完全相同，
> 三行数字自然也完全相同 —— 那种表格看起来像结论，实际什么都没测到。
> 现在有一条断言守着「三种策略必须切出不同的 chunk 数」。

## 18.3 TD-11（新）—— `NLEmbedding` 的余弦受文本长度支配

把同一段文字重复 n 次拉长，与同一条 query 的余弦：

| 重复次数 | 相关文本 cos | 无关文本 cos | 相关文本字数 |
|---|---|---|---|
| 1 | 0.9263 | 0.9248 | 32 |
| 2 | 0.9058 | 0.9173 | 64 |
| 4 | 0.8898 | 0.8972 | 128 |
| 8 | 0.8812 | 0.8815 | 256 |
| 16 | 0.8767 | 0.8730 | 512 |

**长度效应 0.0496，相关性效应（最大）0.0115 —— 相差 4.3 倍。**
而且在 n=2/4 上，**无关但更短**的文本余弦高于**相关但更长**的文本。

三个后果：

1. **长笔记天然吃亏。** 这解释了 18.2 里换切分也救不回来的那三条用例：
   对手是 13 个字的「面馆」笔记，它靠短就赢了。
2. **TD-10 的相关性下限不能只看余弦。** 早先已知「余弦绝对值没有解释力」
   （相关 0.944 / 无关 0.917），现在知道了原因：它被长度混淆了。
   任何 `similarity > x` 的阈值都会变成一个**隐蔽的长度过滤器**。
3. **切分到相近长度不只是 recall 特性，也是可比性要求**（D-RT-014 的补充）。

**没有实现任何长度归一化** —— 那是一次没有 Golden Set 支撑的模型层改动，属于范围扩张。
`RetrievalWeek6Checks.checkCosineLengthBias` 把现象钉住，换模型时它会立刻告诉你变没变。

## 18.4 Local vs Cloud（6.1）

| Provider | Recall@1 | Recall@3 | Recall@5 | MRR | P50 | 建索引 |
|---|---|---|---|---|---|---|
| local · nl-zh-Hans-r1 | 0.571 | 0.714 | 0.714 | 0.639 | 3.71 ms | 63 ms |
| mock（伪向量，反例） | 0.286 | 0.429 | 0.571 | 0.430 | 0.04 ms | 0 ms |
| **cloud** | **待验证** | | | | | |

mock 那一臂的意义不是「本地更强」，而是**伪向量不能当对照组**：
拿它做基线会让任何配置都看起来在进步。

**Cloud 臂待验证** —— 需要真实凭据。跑法：

```bash
MOSAIC_LIVE_EMBEDDING_BASE=https://api.example.com/v1 \
MOSAIC_LIVE_EMBEDDING_KEY=sk-... \
MOSAIC_LIVE_EMBEDDING_MODEL=text-embedding-3-small \
MOSAIC_LIVE_EMBEDDING_DIM=1536 \
swift run -c release mosaic-checks
```

**成本一项同样待验证**：它由服务端计费口径决定，本地测不出来。

## 18.5 Staleness 实验（6.4）

构造「改内容不重建索引」：

- 改一个字 → `contentHash` 变 → chunk 身份变；
- 用新语料查旧索引：过期向量指向的 chunkID 在当前语料里找不到，**被丢弃**，
  旧文本不会作为结果返回；
- `StaleGuard.decide` 在写入路径上拒收基于旧 hash 的结果（即使 provider 忽略取消、
  把旧内容的向量算完了）；
- **`stale` 状态仍然允许向量路** —— 部分现行的索引比没有索引有用，
  每条命中都要经 chunkID 还原，还原不到就丢弃。整条降级只发生在
  `building` / `failed`（无法推进）。

## 18.6 Regression 长跑（6.5）

一次完整闭环，全部由断言守着：

```
评测出现失败用例 → 人工归因 missingData → Add to Regression Set
→ 下一次评测自动带上（8 条：7 golden + 1 regression）
→ 候选配置 keyword-only：Recall@5 0.250（baseline hybrid 0.625）· Regression 0/1
→ Gate: PROMOTION BLOCKED（Recall@5 / MRR / Regression 三项同时阻断）
→ registry.promote 抛错，生产配置没有被换成 keyword-only
```

## 18.7 无障碍（6.6）

结果行合成**一个**可聚焦元素，朗读顺序由 `SearchPresentation.accessibilityLabel`
给定：**标题 → 来源 → 命中片段 → 文件夹 → 时间**。

不合并的话，来源图标会被读成一个没有标签的元素，而且一行要划五次。
高亮区间**不进入朗读**（对比式前景高亮是视觉手段，读出「命中」只会打断句子）；
纯文本命中**没有**来源标签（它是默认形态，读出「文字」只是噪声）。
用户侧禁用词表（契约 §1.1.1）在朗读文本上同样有断言守着。

> **VoiceOver / Dynamic Type 的真机主观验证仍是待验证项** ——
> 自动化断言证明的是朗读**内容与顺序**，不是朗读体验。


---

# 19. 语种路由与云端隐私闸门（TD-9 的落地）

`Sources/MosaicKit/Retrieval/{ScriptDetection,EmbeddingRouter}.swift` ·
`App/Mosaic/Retrieval/ProductionEmbedding.swift`

## 19.1 一个索引只有一个向量空间，所以路由是整库级的

中文 640 维、英文 512 维、云端通常 1536 维 —— 混进同一个 store 做余弦没有意义。
所以 `EmbeddingRouter` 输出的是**整库一条路线**，不是按块切换。优先级：

```
本机中文模型 → 本机中文（离线）
库里有汉字 + 无本机中文 → 云端（需同意）
纯英文 → 本机英文（离线）
以上都没有 → 不可用，keyword 照常
```

**本机优先于云端，与同意与否无关** —— 能离线做的事不该上传。

## 19.2 云端那一路必须先拿到明确同意

云端 embedding 把**整库**笔记发到第三方，而且发生在启动后的后台索引里。
这比「用户主动点一次、生成一篇摘要」重得多，**不能靠「已经配了 API Key」推定授权**
（摘要与录音上传各自都有明确同意，这里没有理由例外）。

闸门做在**两层**，而且都不是「调用方记得检查」：

1. `EmbeddingRouter.choose(..., cloudConsentGranted:)` —— **默认 `false`**。
   没同意时返回 `.cloudNeedsConsent`，不是 `.cloud`。
2. `ProductionEmbedding.decide` 在这个状态下**连 provider 都不构造**
   （构造会把 API Key 拷进请求对象）。provider 为 nil → 检索层没有东西可用 →
   **一个请求都发不出去**。

`SettingsStore.makeCloudEmbeddingProvider()` 里也有同一道闸门 —— 它是唯一构造云端
provider 的地方，闸门放在这里而不是调用方，是因为「每个新调用点都要记得检查」
那种约定迟早会漏。

**`.cloudNeedsConsent` 与 `.unavailable` 是两个状态**，因为下一步动作完全不同：
一个是「问用户要不要开」，一个是「去设置里配」。合并成一个，UI 就只能给一句
什么都没说的「不可用」。

同意入口有两处：搜索状态条（此时按钮文案是**「开启」而不是「重试」**——
「重试」会让人以为是网络问题，而实际上是我们在等他授权）与设置里的开关（可撤销）。

## 19.3 路线解析**不在编辑热路径上**

「库里有没有汉字」是 O(全库) 的：**实测 200 篇 × 5 块约 26 ms，且全程在 main actor**。
放进 `commitNow()` 就等于每次自动保存卡 26ms，并随库线性增长。

现在的规则：

| 时机 | 行为 |
|---|---|
| 启动 / 手动 Rescan / 设置变更 | 全库扫描，允许切换路线并重建索引 |
| 一次编辑 | **只看被改的那一篇**，而且**只升不降** |

「只升不降」的理由：判断「是不是最后一篇中文笔记被清空了」需要全库扫描，
而降级不紧急（英文库用着云端只是浪费，不是错）。这同时避免了打字时路线来回翻。

**路线该变时也不自动变**：`desiredRoute` 只是标记出来，由用户显式确认。
换向量空间 = 清空索引 + 全库重嵌，还可能是付费云端调用 ——
在用户打字打到一半时替他做这个决定是不合适的。

---

# 20. Synthetic Golden v2：解除共线与双语边界证据

`synthetic-human-v1` 把 source、language、length 绑在一起，overall 指标无法归因。
2026-08-18 重做为 `synthetic-human-v2`：60 篇、五类 source 各 12 篇且每类中英 6/6，
54 条正例（35 in-scope / 19 cross-language）、10 条 no-result、6 篇跨五类来源的长文、
34 篇不作为 expected 的干扰项。完整方法和 release 数字见 `HUMANLIKE_GOLDEN_SET.md`。

## 20.1 Eval 的主指标与边界指标分离

`EvalCase` 现在记录 `queryLanguage`、`expectedLanguage`、`scope` 和 `expectation`。
`EvalRunner` 同时产出：

- `inScopeMetrics`：仅 in-scope 正例，供 Eval Compare 与 Release Gate 使用；
- `crossLanguageMetrics`：已知边界，只作诊断；
- `metrics`：全部正例的 overall 参考值，并承载负例指标；
- `noResultAccuracy` / `falsePositiveRate`：负例单独口径，暂不进 Gate。

旧落盘数据没有语言字段时迁移为 in-scope，以维持升级前行为。新建 Golden Case 时由
编辑器显式收集 query / expected language，scope 由两者是否一致确定。

Release Gate 的 Recall@5、MRR、P95 与 Regression Pass Rate 均只读取 in-scope 正例；
断言构造了“overall 很差但 in-scope 变好”的用例，确认 cross-language 不会阻断发布。

## 20.2 双语 persona 推翻了“整库一个本地向量空间足够”的假设

Mac release、真实 Apple `NLEmbedding`、默认切分：

| Mode | Group | Recall@5 | MRR |
|---|---|---:|---:|
| Keyword | in-scope / cross | 0.457 / 0.105 | 0.457 / 0.105 |
| Vector | in-scope / cross | 0.343 / 0.158 | 0.226 / 0.145 |
| Hybrid | in-scope / cross | **0.600 / 0.211** | **0.494 / 0.171** |

这不是“跨语言再调一点参数”的证据，而是 §19 整库单向量空间的产品边界。当前生产实现
保持不变，不在没有产品选择时擅自改成另一套架构。待决方案只有三类：

1. 云端多语言模型：一个空间覆盖中英；需要明确同意、成本与隐私表述；
2. 中英双索引：两个 provider / store，各取 Top-K 后融合；需要重定索引和融合契约；
3. 明确不支持跨语言语义：保留 keyword 兜底，并把边界写进产品承诺。

在选择前，cross-language 永远单独报告，不进入 Gate。

## 20.3 TD-10 已有负例实证

10 条 no-result query 在 release 跑批中：Keyword 空结果 10/10；Vector 与 Hybrid
误召回 10/10。当前正确口径严格是 `results.isEmpty`，因为还没有相关性下限。

这证明 `.noResults` 在语义路可用时几乎不可达，但**仍不据此拍一个余弦阈值**：§18.3
已经证明余弦被长度显著混淆。负例指标先观察，相关性下限与 Gate 阈值等真实 Golden Set、
模型路线和 PRD 精确要求齐备后再定。

---

# 21. D-AI-003 —— 云端优先的语义路，与分层 SLO

上游决策：`design/DECISION_LOG.md` **D-AI-003**。完整实验：`EMBEDDING_EXPERIMENT.md`。

## 21.1 能力层级，不是「换默认模型」

```
Query
 ├── Keyword Retrieval ──────────────────▶ Fast Result（永远可用）
 └── Semantic Retrieval
       ├── Cloud multilingual embedding   ← 已配置 + 已授权
       └── Local embedding fallback       ← 本机模型覆盖当前语料语种
                 ↓
            Vector Results ──▶ RRF ──▶ Hybrid Result Upgrade
```

`EmbeddingRouter.choose` 是唯一的路由入口，顺序是 **Cloud → Local → Keyword**。
两条容易写错的规矩：

1. **未授权时优先降级到本地，而不是弹窗打扰。** 只有本地也顶不上（语料语种与本机模型
   对不上，即 iPhone 上的现状）才返回 `.cloudNeedsConsent` 去请求授权。
2. **云端失败不能变成搜索失败。** 401 / 429 / 5xx / offline / timeout / malformed /
   dimension mismatch / count mismatch 全部注入过，keyword 路每次都照常返回结果
   （`CloudEmbeddingResilienceChecks`）。

**为什么翻转了 v2 的「本地优先」**：v2 的理由是「能离线做的事不该上传」。v3 的实测把它
推翻了 —— 同一批 114 条 query，本地 Hybrid 的 in-scope R@1 是 0.269、cross-language R@5
是 0.128；云端分别是 0.866 和 0.936。差距大到「省一次上传」换不回来。
**但授权仍是硬前置**，所以省下的那次上传由用户自己决定，不由默认值决定。

## 21.2 SLO 不再是一个数字

PRD 原来的 **Local Retrieval SLO（P50 < 100 ms · P95 < 250 ms）保留不变**，
它现在是三层里的一层，而不是全部。

| | 定义 | 负责通道 | 目标 | 当前实测（Mac release） |
|---|---|---|---|---|
| **Metric A** Time to First Useful Result | query 稳定 → 第一批可交互结果出现 | keyword / local 快通道 | **P50 < 100 ms · P95 < 250 ms**（沿用 PRD） | keyword P50 **1.33 ms** / P95 **1.91 ms** ✅ |
| **Metric B** Time to Semantic Refinement | query 稳定 → 语义完成并升级 Hybrid 排序 | cloud（或 local）慢通道 | **单独记录，不套用 A 的预算** | cloud-hybrid P50 **710 ms** / P95 **894 ms** |
| **Metric C** Search Availability | 语义 provider timeout / offline / failed / rate limited 时，keyword 是否仍工作 | 全链路 | **Semantic failure ≠ Search failure** | 六种失败形态注入，keyword 100% 可用 ✅ |

三条纪律：

- **Metric B 不许被偷偷排除在性能评测之外。** 它是用户真实等到的时间，必须报。
- **Metric B 也不许污染 Local Retrieval SLO。** 一次网络往返和一次本机余弦不是同一件事，
  混在一个数里两边都失去意义。
- **Release Gate 仍然只用一个 P95 门槛（250 ms）**，所以云端候选**当前判定为 BLOCKED**。
  要放行必须由产品显式决定 Gate 用哪一层的 P95 —— 而不是把数字悄悄换掉。

## 21.3 云端越慢，stale 保护越重要

```
Note v12 → 云端请求发出 → 用户编辑 → Note v13 → 1.3 s 后 v12 的响应才回来
        → contentHash 不符 → DISCARD
```

**不因为云端慢就改用取消来保证正确性。** 取消是协作式的（§4），而云端延迟把竞态窗口
从毫秒级拉到秒级，反而让写入路径的 `contentHash` / `embeddingVersion` 校验更关键。
额外一条：从本地切到云端之后，本地那一批迟到结果也进不来 —— `embeddingVersion` 不符。

## 21.4 RRF 保留，但不是因为 PRD 写了它

实测（114 条逐条对比）：Cloud Vector vs Cloud Hybrid **1 胜 0 负 113 平**。
`bge-m3` 自己就把 `CS5330` / `Mask R-CNN RoIAlign` / `VNB3K21099` / `CF259A` 全部排到第 1 ——
**「Hybrid 用来保护 exact code」这个假设被证伪了。**

保留 RRF 的三条理由都是实测的：从不变差（成本 1.33 ms）· 对本地 fallback 决定性
（R@1 0.079 → 0.193）· keyword 是唯一有 no-result 能力的一路（100% vs 0%）。

---

# 21. 真机基准（Metric A / Metric B-local）与 TD-9 的推翻

`App/MosaicBench/DeviceLatencyBenchmarkTests.swift` · `Sources/MosaicKit/Eval/RunEnvironment.swift`

## 21.1 TD-9 是模拟器的现象，不是 iOS 的现象

**实测环境**：iPhone Air（`iPhone18,4`）· iOS 27.0 · **release 构建** · thermalState `nominal` ·
低电量模式关闭。

| 语言 | 模拟器（iOS 26.5） | **真机（iOS 27.0）** | macOS |
|---|---|---|---|
| `zh-Hans` | ❌ | **✅ 640 维** | ✅ 640 维 |
| `en` | ✅ 512 维 | **✅ 512 维** | ✅ |

**TD-9 关闭。** 此前「iOS 上没有中文句向量模型」的结论来自模拟器 —— 模拟器不附带
`linguisticdata` 的模型资源。这是一次**测量环境被当成产品事实**的错误，代价是它连续
几轮参与了「必须上云端」的论证。

> ⚠️ 一处未排除的混淆：真机是 iOS 27.0，模拟器是 26.5。所以无法区分
> 「模拟器从来不带模型」与「iOS 27 才加上」。**产品上不重要**（真机可用就是可用），
> 但如果要支持 iOS 26 真机，需要单独在那个版本上复测。
>
> 反过来这也说明：**模拟器上看到的 `semanticUnavailable` 降级是真的**，
> 开发时遇到不是 bug。

## 21.2 为什么基准是独立 target 而不是 XCTest 里的一条用例

`MosaicTests` 里的用例需要 `@testable import Mosaic`，而 `@testable` 要求
`ENABLE_TESTABILITY`，**Release 下默认关闭**。为了让它编译而打开 testability 会改变
符号可见性与优化行为 —— 那就污染了性能数字本身。

所以拆出 `MosaicBench` target + 独立 scheme，它**只依赖内核**，不用 `@testable`。
`RunEnvironment` 也因此从 App 层移进内核（`ReleaseGate` 本来就要读它）。

模拟器上自动 `XCTSkip`，不靠调用方记得加环境变量 —— 模拟器跑在 Mac 的 CPU 上，
它的数字既不是 Mac 也不是 iPhone。

> **本节数字已于 2026-08-19 全部重测。** 口径变了两处：取样量 20 → **25**
> （20 样本时「P95」等于 max，见 §23.5）、每档之间**等热状态回 `nominal`** 再测。
> 6 轮跑批，报区间。旧的点值已作废，理由与新旧对照见 §23.6。

## 21.3 Metric A —— keyword 快通道（真机 release · **生产路径** · 25 样本 · nominal）

> 2026-08-20 再次换口径：以前直接调 `KeywordRetriever.retrieve`，
> 于是 `NormalizedTextCache`（§24.3）落地后它一点没变快 —— 因为**它测的不是产品路径**。
> 缓存装在 `RetrievalService` 上，用户走的也是 service。Metric A 是对用户的承诺，
> 就必须在用户实际走的那条路上测。**冷热分开报**：语料变化后的第一次查询要付全价。

| chunks | 冷 P50 | 冷 P95 | 热 P50 | 热 P95 | 热/冷 |
|---|---:|---:|---:|---:|---:|
| 1 000 | 4.61 – 4.63 ms | 9.77 – 12.96 ms | 1.54 – 1.57 ms | 2.59 – 2.60 ms | 2.9–3.0× |
| 5 000 | 16.98 – 17.31 ms | 24.31 – 24.35 ms | 7.18 – 7.37 ms | 12.21 – 12.51 ms | 2.4× |
| 10 000 | 34.18 – 34.34 ms | 44.13 – 44.33 ms | 14.77 – 14.93 ms | 24.83 – 27.38 ms | 2.3× |
| **20 000** | **70.64 – 71.37 ms** | **94.92 – 101.06 ms** | **30.66 – 31.20 ms** | **52.52 – 52.56 ms** | **2.3×** |

**冷热都在 SLO（P50<100 / P95<250）内**，断言两组都查 ——
「第一次搜索慢一倍」不是可以豁免的情形，那恰恰是用户最先遇到的一次。

**产品意义**：热 P50 从 ~71 ms 降到 ~31 ms，P50 预算的余量从 1.4× 变成 **3.2×**。
按线性外推，P50 破 100 ms 的规模从约 **28k** 推到约 **65k** —— 这直接回答了
「keyword 慢会不会威胁 fast path → semantic refinement 架构」：**现在不会了**。

> ⚠️ §21.3 之前记录的「20k P50 68.72–73.32 / P95 89.23–98.51」是**裸 retriever、无缓存**
> 的数字，对应现在的「冷」那一列。它没有错，但它不是用户走的那条路。

## 21.4 Metric B-local —— 本地 hybrid 端到端（真机 release · 25 样本 · nominal · 6 轮）

余弦检索规模曲线（dim 384，纯数学）：

| chunks | P50 | P95 | 内存 |
|---|---:|---:|---:|
| 1 000 | 0.65 – 0.67 ms | 0.69 – 0.74 ms | 1.5 MB |
| 5 000 | 1.64 – 1.65 ms | 1.92 – 1.96 ms | 7.3 MB |
| 10 000 | 2.85 – 2.89 ms | 3.15 – 3.21 ms | 14.6 MB |
| 20 000 | **5.41 – 5.61 ms** | **5.86 – 6.15 ms** | 29.3 MB |

端到端 hybrid（keyword + 本地嵌入 + 余弦 + RRF）—— **§24.3 缓存落地后**：

| chunks | P50 | P95 | max | 缓存前 P50 / P95 |
|---|---:|---:|---:|---|
| 1 000 | 6.32 ms | 9.16 ms | 11.47 ms | 14.88–15.28 / 17.29–17.73 |
| 5 000 | 13.72 ms | 19.26 ms | 19.31 ms | 30.00–32.10 / 36.42–41.01 |
| **20 000** | **45.69 ms** | **66.07 ms** | 66.32 ms | 93.81–97.56 / 119.39–128.33 |

**20k 上 P95 从 ~124 ms 降到 66.07 ms（1.9×）** —— hybrid 里含 keyword 那一路，
所以 §24.3 的收益直接传导过来。250 ms 预算的余量从 2× 变成 **3.8×**。

**方差收下来了。** 20k 的 P50 从旧口径的 92.53–113.03（±22%）收到 93.81–97.56（**±4%**），
P95 从 119.30–143.23（+20%）收到 119.39–128.33（**+7.5%**）。
**并且现在的 P95 是真百分位**（第 24/25 位），旧的那个是 20 个样本里的最差一个。

**最坏 P95 = 128.33 ms，仍在 250 ms 预算内** —— 所以「不上 ANN」和 D-AI-003
「本地 hybrid 在 SLO 内所以本地必须保留」两个结论都成立，且比之前站得更稳。

本地 query 嵌入（`nl-zh-Hans-r1`，640 维）：**P50 4.29 – 4.40 ms /
P95 10.22 – 12.51 ms**（25 样本，测前等回 nominal）。

⚠️ **L2a 这个数字第三次变了，而机制始终没查清。** 历史读数：6.21 → 11.1 → 4.3。
最后这次跨越发生在 §24.3 缓存落地前后，**L2a 自身的代码一行没动**：

| | L2a P50 | 轮次 |
|---|---:|---|
| 旧口径（6 样本） | 6.21 ms | 1 |
| 25 样本 · 缓存前 | 11.08 – 11.27 ms | 6 |
| 25 样本 · **缓存后** | **4.29 – 4.40 ms** | 3（隔离 / test3+test4 / 全套，三种都一样） |

排除掉的解释：热状态（测前都等回 nominal）、取样量（后两组相同）、
「前面跑了什么」（隔离跑与全套跑给出同一个值）。

**结论只能是：L2a 从来就不是一个独立数字** —— 它会被同进程里别处的改动影响，
而这次是被 §24.3 影响的。**不编机制。** 它不改变任何结论（L2a 是 Metric B-local
的一个分量，而 Metric B-local 20k 只有 45.69/66.07 ms，远在 SLO 内）。
P1 #14 由「未解释的差异」改记为「**这个指标本身不可独立引用**」。

Mac release 同口径是 79.5 ms，真机约慢 1.2–1.3 倍。

## 21.5 反直觉发现：瓶颈是 keyword 路，不是向量路

20k chunks 上：**keyword P95 89.23–98.51 ms vs 余弦检索 5.86–6.15 ms —— 差 14.5–16.8 倍。**

> 2026-08-20 更新：§24.3 的缓存把这个差距压到 **8.5–9 倍**（热 P95 52.52 vs 余弦 5.88）。
> 瓶颈仍在词法路，但已经不再威胁 fast path 架构 —— 见 §21.3 的产品意义一段。

余弦是 384 次乘加，编译器能向量化；而子串匹配走的是 Swift `String`
（Unicode 正确、按 grapheme cluster），在 20k × 约 100 字符上逐 token 定位要贵得多。

**产品含义**：想改善「用户多久看到第一批结果」，要优化的是**词法路**（例如倒排索引），
不是向量路。这条也进一步支持 D-RT-012 —— ANN 优化的正是那个已经只占 6% 的部分。

## 21.6 这次基准**没有**测什么

- **云端语义（L3 网络 / L4 总计）**：不在真机基准里。云端 query embedding 的耗时
  主要由地理位置决定（实测 US→China P95 1317 ms），混进「检索延迟」会得到一个
  换服务商就作废的数字。它要带 `providerRegion` 标签单独测。
- **质量**：本基准的向量是确定性填充值，只测延迟，不测 Recall。

---

# 22. SLO 分层 · 弃答策略 · 性能 Gate policy

## 22.1 为什么单一 Retrieval SLO 不再成立

原 PRD 的 `P50 < 100ms / P95 < 250ms` 是**一个**数字，它同时被拿去判 keyword 快通道
和云端语义 —— 而后者含一次跨洲网络往返。**实测那次往返占总耗时的 99.80%**
（网络 P50 383.5 ms / P95 1192.7 ms，解析+归一化 P50 0.76 ms）。
一个数字判两件量级差 400 倍的事，判出来的结论没有意义。

拆成三层（`MeasuredLatencyLayer`）：

| 层 | 测什么 | 地理相关 | policy 中的处置 |
|---|---|---|---|
| **Metric A** `firstResult` | keyword / 本地快通道 | ❌ | **阻断**，P50<100 / P95<250 |
| **Metric B-local** `semanticLocal` | 本地嵌入 + 余弦 + RRF | ❌ | **阻断**，P95<250 |
| **Metric B-cloud** `semanticCloud` | 含一次网络往返 | ✅ **完全是** | **记录但不判定**（`nil` 预算） |

**一次跑批只测一层。** 三层预算不同，混在一个 `p95Ms` 里判定必然出错，所以
`RunEnvironment.measuredLayer` 声明这批数字属于哪一层，Gate 据此取对应预算。

Metric B-cloud 之所以「记录不判定」：progressive enhancement 下 keyword 快通道
已经承担了「用户多久看到东西」这个承诺，云端只是就地升级。**这个取舍显式写在
policy 里，而不是藏在代码分支里。**

## 22.2 测量环境是判定的前置条件，不是脚注

`PerformanceGatePolicy` 要求 `release` 构建 + `physicalDevice`，并检查热状态与
低电量模式。任一条不满足 → **STALE，不是 FAIL**。

理由：「这批数字没有资格参与判定」与「性能不达标」是两件事，**补救动作也不同** ——
一个是换台机器重测，一个是去优化代码。判成 FAIL 会让人去优化一份本来就不该
拿来判定的数字。

`requiredProviderRegion` 同理：同一份 policy 在 `cn-shanghai` 与 `us-east` 下
不该给出同一个判决。

### 重跑 Gate 的实际结果

用 v3 上的真实跑批（本地 hybrid vs keyword baseline）：

```
perf-v2（要求真机）  → STALE：「这批数字来自 mac，判定要求 physicalDevice」
perf-v1（允许 Mac）  → PASS
```

**同一份数字，两个 policy，两个判决。** perf-v2 的 STALE 才是诚实的那个 ——
它拦住了「拿 Mac 的性能数字发布」这条路。这不是失败，是 Gate 在正常工作。

## 22.3 弃答策略（TD-10）：三态，四信号，且**校准失败**

`AbstentionPolicy` / `AbstentionJudge`。三态而非二元：

- `confident` → 正常显示
- `uncertain` → **照常显示** + 契约 §2.6 已有的那行说明（只改文案，不改可见性）
- `abstain` → 走契约 §4.5 的 `.noResults` 三套分叉文案

四个信号，全部可从一次 `RetrievalOutcome` 算出：绝对下限 `top1` · **`top1−top2`
（主力，理论上不受长度偏置影响）** · `top1/mean(rest)` · 有无字面命中。

### 校准结果：三个信号全部重叠，没有可发布的阈值

在 v3 上（in-scope 正例 67 / 负例 20），约束是**正例零损失**：

| provider | 信号 | 完美分离间隙 | 零损失时挡掉负例 | 到最近负例的余量 |
|---|---|---:|---:|---:|
| 本地 `nl-zh-Hans-r1` | 绝对下限 | −0.4557 | 0/20 | — |
| 本地 | **margin** | −0.0130 | **0/20** | — |
| 本地 | 比值 | −0.0219 | 0/20 | — |
| 云端 `bge-m3` | 绝对下限 | −0.1689 | 2/20 | 0.0088 ⚠️ |
| 云端 | **margin** | −0.0661 | **6/20** | 0.0002 ⚠️ |
| 云端 | 比值 | −0.1517 | 2/20 | 0.0054 ⚠️ |

**两个必须记住的结论：**

1. **「margin 不受长度偏置影响所以更可靠」这个假设在本地模型上完全错了。**
   本地正例 margin 中位数 0.0032、负例中位数 **0.0032** —— 一模一样。
   `NLEmbedding` 的余弦全挤在 0.93 附近，绝对值和相对差值都没有信号。
2. **云端上 margin 确实是最好的信号**（6/20 vs 绝对值 2/20，3 倍），
   方向性假设成立；但余量 0.0002，**不可发布**。

> ⚠️ 这**推翻了上一轮在 v2 上的乐观读数**（当时「阈值 0.54 挡掉 9/10 负例」）。
> 原因是 v3 更难：负例 10→20、语料 60→150 篇，正例最低相似度从 0.541 掉到 0.4413。
> 按纪律接受新数据，不维护旧结论。

因此 `AbstentionPolicy.neverAbstains` 是**默认值**，产品行为与接入前逐位一致。
TD-10 状态：**Improved / Calibratable，not production-resolved。**

---

# 23. 云端凭据恢复后的一轮：Gate 断言过期、成本口径落地

> 2026-08-19。新 API key 到位，云端两路第一次在**当前代码**上跑起来。

## 23.1 缺凭据把三条断言藏了起来

上一轮记录的「全绿 1268 断言」是**在没有云端凭据的情况下**跑出来的。
`RetrievalProviderBenchmark` 的 Gate 那一段包在 `if let candidate = metric("cloud-hybrid", …)`
里 —— 没有 key，云端臂不存在，这一段**整段不执行**。

key 一插上，立刻 **3 FAILED / 1275 passed**：

```
✗ Gate 四项检查全部产出
✗ 云端 P95 超 250ms 预算 → Gate 阻断
✗ cloud-hybrid 当前不能进生产：质量三项全过，P95 一项否决
```

三条都是 §22 的分层 SLO 落地（`37ac9de`）之后就已经过期的旧口径，只是没人看见。

**教训：条件执行的断言 = 条件存在的回归保护。** 「全绿」这句话必须带上
「在什么条件下」—— 一个因为缺环境变量而整段跳过的检查，不会让套件变红，
但也**没有在保护任何东西**。以后凡是要凭据的分支，报结果时都要写明它跑没跑。

## 23.2 修正后的口径：现在挡住云端的**不是延迟**

旧断言说的是 perf-v1 的结论：一个 250 ms 判所有层，云端语义被延迟一票否决。
perf-v2 之后两件事同时变了：

| | perf-v1 | **perf-v2（现行）** |
|---|---|---|
| 云端语义延迟 | 阻断项（P95 ≤ 250 ms） | **Metric B-cloud：记录但不判定** |
| Mac 上跑的数字 | 允许进 Gate | **不予受理 → STALE** |

同一份 v3 云端数字，两种 policy 下的实际判定（都是跑出来的，不是手算）：

```
perf-v2 · mac/release/semanticCloud/cn-shanghai → STALE
          · 这批数字来自 mac，判定要求 physicalDevice
perf-v1 · 同一份数字                              → PROMOTION BLOCKED
          ✅ Recall@5 1.000 ≥ 0.418
          ✅ MRR 0.938 ≥ 0.331
          ❌ Metric B · Semantic P50 628ms · P95 1485ms  要求 P95 ≤ 250ms
          ✅ Regression 100%（回归集为空）
```

**判定更严了，不是更松了**：以前 Mac 数字还能进 Gate 挨一顿判，现在直接不予受理。
perf-v1 那一路保留下来做对照，因为 D-UI-DEV-008（「质量再好也不能靠加权换放行」）
是在那个口径下被证明的，换 policy 不等于那件事没发生过。

**所以现在挡住 cloud-hybrid 上线的是两件事，都不是延迟：**

1. **没有一份有资格参与判定的测量** —— 要真机 release 上的云端跑批
2. **评测集仍是 synthetic** —— 见 `HUMANLIKE_GOLDEN_SET.md`

## 23.3 成本一项：换单位才测得出来

backlog 6.1 的「成本」栏长期是空的，登记的理由是「本地测不出来」。
真正缺的不是能力，是**单位**：本地那一路的代价是设备时间与电，云端那一路的代价是
token 和钱，两者没有共同单位，合成一个「成本分」只会得到一个谁也不信的数字。

做法是并排摆、各标口径，并且把 token 从**外推**改成**实测** ——
`CloudEmbeddingProvider.parseUsage` 读服务端回报的 `usage.prompt_tokens`。

同一份 v3 语料（186 chunks / 25 310 字符），Mac：

| | Local `nl-zh-Hans-r1` | Cloud `bge-m3` |
|---|---:|---:|
| 建索引 | 3 038 – 3 596 ms | 4 517 – 64 227 ms |
| 单 chunk | 16.3 – 19.3 ms | 24.3 – **345.3** ms |
| `prompt_tokens` | — | **9 720**（五次跑批**每次都一样**，跨 3 把 key） |

区间来自 5 次跑批（4 次 release + 1 次 debug），跨 3 把不同的 API key。云端那一段**与构建配置无关**
（花的是 HTTP 往返）；本地那一段的 debug/release 差异是噪声，
本地嵌入耗时由 `NLEmbedding` 这个系统框架决定。

**这张表里唯一稳定的数字是 token。** 单 chunk 耗时五次跑批差 14 倍 ——
云端建索引是**网络量**，不是算力量。因此：

- **引用成本引 token**，引墙上时间等于引当天的网速
- 实测换算率 **0.38 token/字符 ≈ 2.6 字符/token**，此前外推用的 3.7 偏低，
  旧的「20k ≈ 814k token」因此偏小，按实测应为 **≈ 1.05M**（仍是 *estimated*）
- 单 chunk 耗时的底数波动 10 倍，**20k 的索引耗时不外推** —— 外推没有意义

`parseUsage` 返回 optional 且**不参与向量解析的成败**：usage 字段缺失或改名，
不该让一批已经拿到的向量作废；返回 `nil` 而不是 0，因为 0 会把成本算成免费。

## 23.4 这一轮**没有**改变的结论

- 五路质量数字与 `DECISION_LOG.md` D-AI-003 记录的**逐位一致** —— 前后 3 把不同的 key、
  5 次跑批，一位都没变。服务端 embedding 是确定性的，所以质量可复现、延迟不可
- 负例：keyword no-result accuracy **100%**，四个向量臂全是 **0%**，TD-10 仍未解决
- `EmbeddingRouter` 仍是云端优先 + 同意闸门默认关闭，产品可见行为**没有变化**

## 23.5 真机云端基准（`MosaicBench.test5`）与凭据怎么上设备

P1 的「真机上跑一次云端臂」需要的不是一条命令，是一条测试 ——
`MosaicBench` 原有 5 条全在测本机算力，**没有一条碰云端**。

`test5_metricB_cloudSemantic` 补上这一层。三个设计取舍：

1. **规模曲线只跑最大档。** 网络往返与索引规模无关，1k 和 20k 的 query 嵌入
   是同一个 HTTP 请求 —— 跑四档只是把同一个数字花四份钱测四次。
   所以 L3（网络/解析分段）不分档单测，L4（端到端）只在 20k 上跑。
2. **不断延迟。** perf-v2 对 Metric B-cloud 是「记录但不判定」，
   在测试里加一条 `XCTAssertLessThan(p95, …)` 等于绕过 policy 偷偷改判定口径。
   断的是**这批数字有没有资格被引用**：`PerformanceGatePolicy.v2.disqualification`
   必须为 nil、region 必须记下来、以及「耗时由网络主导」这个结构性主张。
3. **没凭据 skip，有凭据打不通 fail。** 两者补救动作不同：前者是「本轮不测云端」，
   后者是「你以为你在测，其实没测」。后者若也判 skip，跑批会绿着结束而一个数字都没采到。

### 凭据怎么进设备上的测试进程

**`TEST_RUNNER_` 前缀那套对 app-hosted 单元测试无效** —— 本项目实测：

```
xcodebuild test … TEST_RUNNER_MOSAIC_LIVE_EMBEDDING_KEY=<key> …
→ 测试进程里可见的 MOSAIC_* 变量：（一个都没有）
```

它只对 UI test 的 runner app 生效。设备上的测试进程读不到 Mac 的 shell 环境，
也读不到 Mac 的文件，所以凭据只能**进 bundle**：
`App/MosaicBench/CloudCredentials.json`（gitignored）。

**但它不能进 `sources`。** 试过了：工程一旦在文件存在时 `xcodegen generate` 过，
删掉文件就构建不了 ——

```
error: …/CloudCredentials.json: No such file or directory (in target 'MosaicBench')
```

而这个文件恰恰是「跑完就该删」的东西，那个报错会把人引到完全错误的方向。
所以改成 `project.yml` 里的 `postBuildScripts` **可选拷贝**：有就带上、没有就删掉旧的，
**两种情况都构建成功，且都不需要重新 `xcodegen generate`**。

一句话规矩：**凭据的「有无」不该改变工程结构，只该改变测量结果的「测到没测到」。**

### 结果（3 轮 × 25 样本 · iPhone18,4 / iOS 27.0.0 / Release / nominal / `cn-shanghai`）

| 层 | P50 | P95 | max |
|---|---:|---:|---:|
| L3 网络往返 | 420.5 – 442.9 ms | 629.2 – **1075.3** ms | — |
| L3 解析 + 归一化 | 0.48 – 0.53 ms | 0.51 – 1.21 ms | — |
| L4 端到端（20k chunks） | 575.6 – 637.0 ms | 681.7 – **1480.7** ms | 868 – **7623** ms |

网络占 **99.87–99.89%**（Mac 侧 99.80%，一致）。25 次 query 嵌入 = 149 prompt_tokens，三轮一致。

**P50 可复现，尾部不可复现。** P50 三轮 ±5%，而 max 从 868 跳到 7623 ms（**8.8 倍**）。
偶发的七秒是真的，这正是 keyword 先出结果不是锦上添花而是必需的理由。

### 顺手挖出来的：**取样量 ≤ 20 时「P95」就是 max**

`percentiles` 取 `s[min(count-1, Int(count*0.95))]`。`count = 20` 时
`Int(19.0) = 19 = count-1` —— 下标落在最后一位。所以：

| test | 取样量 | 它的「P95」 |
|---|---:|---|
| `test2` Metric A | 25 | 第 24/25 位，**真百分位** |
| `test3` L2b | 25 | 第 24/25 位，**真百分位** |
| `test4` L2a 本地嵌入 | 6 | **max** |
| `test4` L2 Metric B-local | 20 | **max** |
| `test5` L3 / L4（已改） | 25 | 第 24/25 位，**真百分位** |

`test5` 先用 10 样本跑过一轮，打印出的 P95 与 max 逐位相同，直接证实了这一点，
随后改成 25。

⚠️ **这意味着当时已记录的 Metric B-local「P95 119.30 / 143.23 ms」也是单次最差请求，
不是百分位** —— 它是那个「两次跑批 +20%」的一部分成因。

当时没有顺手改 `test4`（那会变更已经写进文档的基准口径，backlog P1 #7 明确登记为
需要单独决定）。**后来经确认已经改了并全部重测 —— 见 §23.6。**

### 仍然没到的地方：这不等于 cloud-hybrid 可以进 Gate

现在有了一份合格的**延迟**测量，但 Gate 判定读的是**同一次 `EvalRun`** 里的
recall / MRR / p95 —— 而质量数字来自 Mac 侧的 `mosaic-checks`。
把「Mac 上的质量」和「真机上的延迟」拼进一次判定，正是本项目一直在防的那种事。

**要让 cloud-hybrid 真正有资格进 Gate，得让 golden set 的 eval 整体跑在真机上**
（fixture + `EvalRunner` 上设备），不是只补延迟这一项。

## 23.6 真机基准重测：新旧对照，与一处查不清的差异

P1 #7（降低方差）与 #13（P95 退化成 max）本来就是同一件事，一起做掉。
改了两处口径：**取样量 20 → 25**、**每档之间等热状态回 `nominal`**（有 45 s 上限，
等不回来就如实标注，不假装）。跑 6 轮。

| 层（20k） | 旧记录（20 样本 · P95=max · 2 轮） | **新（25 样本 · nominal · 6 轮）** |
|---|---|---|
| Metric A P50 / P95 | 73.88 / 97.87 ms | 68.72–73.32 / 89.23–98.51 ms |
| L2b 余弦 P50 / P95 | 5.45 / 5.86 ms | 5.41–5.61 / 5.86–6.15 ms |
| **Metric B-local P50 / P95** | **92.53–113.03 / 119.30–143.23 ms** | **93.81–97.56 / 119.39–128.33 ms** |
| L2a 本地嵌入 P50 / P95 | 6.21 / 7.99 ms | **11.11–11.19 / 15.75–16.24 ms** |

### 收获

1. **方差确实收下来了**：Metric B-local 20k 的 P50 从 ±22% 收到 **±4%**，
   P95 从 +20% 收到 **+7.5%**。主要功劳是每档之间等热状态，不是取样量。
2. **承重结论更稳了**：最坏 P95 128.33 ms，远在 250 ms 内，且现在是真百分位。
   D-AI-003「本地 hybrid 在 SLO 内，所以本地必须保留」不受影响。
3. **Metric A 与 L2b 本来就对**（它们一直是 25 样本），重测只是补上区间。

### 反直觉：**放凉会让 P95 变差**

L2a 在「不等热状态」时是 P95 11.63–12.28 ms，加了 `coolUntilNominal` 之后变成
**15.75–16.24 ms**。P50 两组都是 11.1 ms，纹丝不动。

即：**放凉降低的是 P50 的跨轮方差，代价是 P95 多了一段冷启动。**
所以「等热状态回 nominal」不是一个无成本的稳定化手段 —— 它换掉的是尾部。
要报 P95 就必须一起说明是哪一种取法。

### 一处查不清的差异：L2a 的 6.21 ms 复现不了

新值 6 轮 P50 全部落在 **11.08–11.27 ms（±1%）**，旧记录是 6.21 ms —— 差 1.8 倍。

**试过的解释都不成立：**

- 「是热的」→ 加了 `coolUntilNominal` 之后 P50 一点没动（11.11–11.19）
- 「是取样量」→ 新旧都在跑同一组 6 条 query，只是新的每条跑 4–5 次。
  若有缓存，重复应当更**快**，不是更慢
- 「是构建配置」→ 两次都是 release

**没有查清就不编机制。** 这里的处理是：采用新值（6 轮 ±1%，可复现），
把旧值标为作废，并记下差异未解释。

它不改变任何结论：L2a 是 Metric B-local 的一个分量，而总量仍在 SLO 内 ——
11 ms 的本地嵌入相对 94–98 ms 的端到端仍然是「很便宜」。

## 23.7 Golden Set eval 搬上真机：判定链路闭合，并暴露一个 Gate 盲区

`test2`–`test5` 测的全是延迟，质量数字一直来自 Mac 侧的 `mosaic-checks`。
而 `ReleaseGate.evaluate` 读的是**同一个 `EvalRun`** 里的 recall / MRR / p95 ——
把「Mac 上的质量」和「真机上的延迟」拼进一次判定，正是这个项目一直在防的事。
`test6_goldenSetEvalOnDevice` 把 `EvalRunner` 整个搬上设备，补掉最后这一块。

### fixture 怎么共用：类型搬家，数据不复制

`HumanLikeGoldenFixture`（140 行，含五类语料到 `CardBlockContent` 的映射与
`ChunkPipeline` 调用）原来整个住在 `MosaicKitChecks` —— 那是 Mac 侧的可执行 target，
bench target 用不到。两条显而易见的路都不好：

| 做法 | 问题 |
|---|---|
| 把解析逻辑复制进 bench target | 两份会漂移，而「真机与 Mac 跑同一个评测集」是数字可比的前提 |
| 把 100 KB fixture JSON 放进 `MosaicKit` | 它会跟着产品 app 一起发出去 |

所以拆开：**类型与解析** → `MosaicKit.GoldenSetFixture`，`decode(_:)` 只接受 `Data`
**不碰 `Bundle`**；**数据仍只有一份 JSON**，`project.yml` 直接引用
`../Sources/MosaicKitChecks/Fixtures/HumanLikeGoldenSet.json`，bench 不放副本。
Mac 侧 13 处调用点一行没改（留了 `typealias` + `load()` 扩展）。

### 结果：第一次完全出自真机的 Gate 判定

iPhone18,4 · iOS 27.0.0 · Release · nominal · 150 notes / 186 chunks / 114 正例 / 20 负例：

| arm | R@1 | R@3 | R@5 | MRR | P50 | P95 | no-result |
|---|---:|---:|---:|---:|---:|---:|---:|
| keyword | 0.343 | 0.343 | 0.343 | 0.343 | 0.99 ms | 2.28 ms | **100%** |
| local-hybrid | 0.269 | 0.373 | 0.418 | 0.341 | 13.56 ms | 15.98 ms | 0% |
| cloud-hybrid | **0.866** | 1.000 | 1.000 | **0.938** | 511.15 ms | 614.43 ms | 0% |

```
Gate（candidate local-hybrid · baseline keyword · layer semanticLocal）      → PASS
Gate（candidate cloud-hybrid · baseline local-hybrid · layer semanticCloud） → PASS
  ✅ Recall@5 1.000 ≥ 0.418
  ✅ MRR 0.938 ≥ 0.331
  ✅ Metric B · Semantic P50 511 ms · P95 614 ms   要求「记录，不判定」
  ✅ Regression 100%（回归集为空）
```

**质量数字与 Mac 侧逐位相同** —— 本地 `nl-zh-Hans-r1` 和云端 `bge-m3` 在 iPhone 上
给出和 macOS 完全一致的检索结果。所以「真机 vs Mac」的差别只在延迟，不在质量。

### 修掉一处自己造的软对照

第一版给所有 candidate 都配 keyword 当 baseline，于是 cloud-hybrid 的 Recall@5
检查变成「1.000 ≥ 0.343」——**一关等于没设**。那是 D-UI-DEV-008 想拦的失败形态
换了身衣服：不是加权放行，是**挑一个软的对照**放行。

改成按「谁会被它替掉」配：`local-hybrid` 对 keyword（语义路上线前的现状），
`cloud-hybrid` 对 `local-hybrid`（现在生产在跑的隐式 Hybrid）。

### ⚠️ 暴露的 Gate 盲区：**R@1 根本没进 Gate**

`HUMANLIKE_GOLDEN_SET.md` 明写「**主判定指标改为 R@1 / MRR**，R@5 降级为 safety-net」。
但 `ReleaseGate` 里 **`recallAt1` 出现 0 次** —— 它检查的恰恰是被降级的 R@5。

这一跑正好把后果摆出来了。local-hybrid vs keyword（真机 in-scope）：

| 指标 | keyword | local-hybrid | 相对变化 | Gate |
|---|---:|---:|---:|---|
| **R@1** | 0.343 | **0.269** | **−21.6%** | **不看** |
| R@5 | 0.343 | 0.418 | +21.9% | 看，通过 |
| MRR | 0.343 | 0.341 | −0.6% | 靠 0.010 容差通过 |

**本地语义路在这个集上「找得更多、排得更差」**：R@5 涨了 21.9%，而第一名的命中率
掉了 21.6%。Gate 说 PASS，因为它看的那一项涨了，而真正掉下去的那一项它不看。

这不是「Gate 坏了」，是**判定口径与文档写的主指标脱节**。修它等于改发布标准，
属于 P0 #2（PRD 的四项 Gate 阈值定值）的范围，**没擅自动**。
已登记 backlog P1 #15。

### PASS 不等于可以上线

评测集是 synthetic。`test6` 证明的是**判定链路在真机上闭合了** ——
质量与延迟出自同一次跑批、同一份环境元数据、`disqualification` 为 nil。
它不是「检索质量达到了发布标准」。正式结论要等真实笔记上的人工标注（P0 #1/#3）。

断言也是照这个边界写的：只断言**判定成立**（不是 STALE、四项都产出、环境合格），
**不断言 status 等于 PASS** —— 那等于把评测结论钉进断言，数据一变用例就红，
而那时候该改的是结论，不是用例。

---

# 24. R@1 进 Gate（P1 #15）· keyword 路的真实瓶颈（P1 #9）

## 24.1 R@1 与 R@5 合成一行，而不是加第五行

§23.7 发现 Gate 查的是被降级的 R@5，主指标 R@1 **根本没进判定**。补上它有个版式冲突：
`DEVTOOLS.md` §4.7 规定判定区是**四行**，还有一条断言守着。

解法沿用已有先例：**R@1 与 R@5 合成一行**，就像 P50/P95 合成一行那样 ——
它俩是同一条 recall 曲线上的两个点，拆开是改版式而不是多给信息。
`GateCheck.Kind.recallAt5` → `.recall`，**任一不过即阻断**，不做加权。

```
✅ Recall @1/@5   R@1 0.866 · R@5 1.000    要求 R@1 ≥ 0.269 · R@5 ≥ 0.418
❌ Recall @1/@5   R@1 0.269 · R@5 0.418    要求 R@1 ≥ 0.343 · R@5 ≥ 0.343
   ↳ R@1 低于 baseline —— **主指标**倒退：第一名的命中率下降。
     注意 R@5 仍然达标，即「找得更多、排得更差」
```

**失败原因必须点明是哪一个点掉了。** 一行装两项的代价就是这个：只说「Recall 不过」，
看的人会去查 R@5 —— 而 R@5 是涨的。

`recallAt1MinDelta` 默认 **0**（零容差）。为什么不像 MRR 那样留 0.010：
MRR 的容差是给配置之间的名次抖动留的，而 R@1 现在是**主指标** ——
给主指标留容差、却让 safety-net 零容差，是反过来的。
⚠️ 粒度提醒：in-scope 67 条时一条用例翻面 = 0.0149，零容差意味着**一条都不能掉**。
这是**初值**，PRD 定值时要一起决定（P0 #2）。

### 后果：local-hybrid 从 PASS 变 BLOCKED

真机实测 local-hybrid R@1 0.269 vs keyword 0.343。加上 R@1 之后它**过不了自己的 Gate**。
这是有意的：Gate 本来就该拦住「找得更多、排得更差」。
连带影响是 **cloud-hybrid 的 baseline 本身不达标** —— 这件事要一起记着。

> ⚠️ 上面这个翻转是**按已测数字算出来的**，真机复跑时手机离线，**尚未实测确认**。

## 24.2 keyword 慢 14.5–16.8 倍，但不是因为「没有倒排索引」

直觉答案是上倒排索引。先分段测了一遍（`KeywordLatencyBreakdown`，Mac release）：

| chunks | tokenize | **normalize** | scan | score+sort | 合计 | normalize 占比 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 000 | 0.009 | **3.534** | 1.339 | 0.308 | 5.189 | **68.1%** |
| 5 000 | 0.022 | **18.028** | 6.746 | 1.635 | 26.430 | **68.2%** |
| 20 000 | 0.032 | **72.556** | 26.750 | 6.652 | 105.990 | **68.5%** |

**68.5% 花在 normalize，而它与 query 无关** —— `Array(normalizedForOffsets(chunk.text))`
只取决于 chunk 自身，每次查询都在重算同一个东西。占比在三档上稳定，说明它是结构性的。

### 为什么倒排索引是错的答案

本项目的匹配是**纯子串**、**没有分词器**：「解约」必须能命中「提前解约」。
token 倒排做不到这件事 —— 中文没有空格，「提前解约」会是一个 token。
要保子串语义得上 **n-gram 索引**，那是一整套新的 derived 结构（内存/重建/stale 三件事都要配套）。
而先去掉那 68.5% 的重复计算**不改任何检索语义**。

### 另一个被数据否掉的方案

「改用原生 `String.range(of:options:)`，免掉字符数组分配」—— 实测**更慢**：

```
折叠 35.69 ms + Array 27.73 ms = 63.42 ms
原生查找：命中 91.47 ms · 未命中 241.83 ms
```

（这是本项目第八次直觉被实测推翻。）

## 24.3 `NormalizedTextCache`：拿内存换时间，语义逐位不变

derived、在内存、可随时重建 —— 与 `InMemoryVectorStore` 同一类。
**按 `contentHash` 自失效**：内容变了 hash 就变，缓存自动不命中，
调用方**不需要**记得清 —— 那种「记得调用」的正确性这个项目不采用。

批量 API（一次拿一整批）：逐个 chunk 走 actor 会产生 20k 次跨隔离跳转，比省下来的还贵。

| chunks | 优化前 | 优化后 | 提速 | 缓存内存 |
|---:|---:|---:|---:|---:|
| 1 000 | 6.24 ms | 2.74 ms | 2.28× | 1.3 MB |
| 5 000 | 31.33 ms | 13.94 ms | 2.25× | 6.4 MB |
| **20 000** | **126.11 ms** | **53.44 ms** | **2.36×** | **26.0 MB** |

**代价是真的**：`[Character]` 每字符 16 字节，20k 上 26 MB —— 与向量库的 29.3 MB 同量级。
要不要开、在什么规模上开，必须连着内存一起看。

### 语义不变靠的是结构，不是小心

`TextMatcher.locate(tokens:in:)` 现在**直接委托**给
`locate(tokens:inNormalized:)` —— 缓存版与非缓存版是**同一份逻辑**，
不存在「两个实现慢慢漂移」的可能。

断言在 144 条 query（golden set 正例 114 + 负例 20 + 全角/变音符/子串边界 10）上
逐条比对命中列表、分数、**以及高亮区间** —— range 尤其重要，
`SEARCH_CONTRACT.md` §2 要求高亮由检索层返回的 range 驱动，range 错了高亮就跟着错。

`normalized` 数量与 `chunks` 对不上时**忽略它就地算**：宁可慢，不可把 A 的正文当成 B 的。

## 24.4 还没做的

- **真机复测**：Mac 上 2.36×。按 Metric A 20k P95 89.23–98.51 ms 推算应落到 ~38–42 ms，
  **但这是外推，不是实测** —— 手机当时离线。接回来要跑一次。
- **n-gram 索引**：先看真机复测够不够。scan 段（20k 上 26.75 ms）是它的下一个目标，
  但它要改匹配单位，风险与这一步完全不同。

## 24.5 真机复测：#15 与 #9 的实测确认

上一节两项都是在手机离线时改完的，数字是**算出来的**。设备接回后实测确认：

### #15 · local-hybrid 确实变成 BLOCKED

```
── Gate（candidate local-hybrid · baseline keyword · layer semanticLocal）──
判定 PROMOTION BLOCKED
  ❌ Recall @1/@5  R@1 0.269 · R@5 0.418   要求 R@1 ≥ 0.343 · R@5 ≥ 0.343
  ✅ MRR 0.341                              要求 ≥ 0.333
  ✅ Metric B · Semantic P50 6 ms · P95 10 ms  要求 P95 ≤ 250 ms
  ✅ Regression 100%（回归集为空）           要求 ≥ 98%

── Gate（candidate cloud-hybrid · baseline local-hybrid · layer semanticCloud）──
判定 PASS
```

与推算一致：Recall 那一行栽在 R@1，而 R@5 是涨的。
**cloud-hybrid 仍然 PASS，但它的 baseline（local-hybrid）自己不达标** ——
这件事在 §24.1 已登记，不因为 candidate 过了就消失。

### #9 · 真机提速 2.3×，且比 Mac 预测的更有价值

Mac 上 2.36×，真机 **2.29–2.30×**（20k）—— 外推这次对了。但真机跑出来还多两件事：

1. **`test2` 一开始没测出提速** —— 它直接调 `KeywordRetriever.retrieve`，
   而缓存在 `RetrievalService` 上。**测的不是产品路径。** 已改（§21.3）。
   教训：优化落在哪一层，基准就得测哪一层；「优化无效」的第一嫌疑是基准测错了对象。
2. **冷启动是真实成本** —— 语料变化后第一次查询付全价（20k 冷 P95 101.06 ms）。
   缓存不能把它变没，只能让后续查询便宜。所以 Metric A **冷热两组都报、都断言**。

### 连带效果：Metric B-local 也快了近一倍

hybrid 里含 keyword 那一路，所以收益直接传导：20k P95 **119–128 → 66.07 ms**。
这不是单独优化出来的，是 §24.3 的副产品。

### 现在还剩多少余量

| | 20k 实测 | 预算 | 余量 | 线性外推破预算的规模 |
|---|---:|---:|---:|---:|
| Metric A 热 P50 | 31.20 ms | 100 ms | **3.2×** | ≈ 65k |
| Metric A 冷 P95 | 101.06 ms | 250 ms | 2.5× | ≈ 49k |
| Metric B-local P95 | 66.07 ms | 250 ms | **3.8×** | ≈ 76k |

**「keyword 慢会不会威胁 fast path → semantic refinement 架构」的答案：现在不会了。**
瓶颈仍在词法路（热 P95 52.52 vs 余弦 5.88，仍差 8.5–9 倍），
但它离预算的距离已经从 1.4× 拉到 3.2×，n-gram 索引因此**不再紧急**。

---

# 25. Fusion 参数实验（P1 #6）

起因是 cross-language **R@1 只有 0.681**（R@5 已 0.936）——「找得到，没排到第一」。
直觉答案是调 RRF 的 `k`。

## 25.1 先问：cross 上 fusion 有东西可融吗

五路对照里 cloud-vector 与 cloud-hybrid 的 cross 三档**完全相同**。
所以在扫 k 之前先测 keyword 的参与率：

| 组 | 有 keyword 结果的 query |
|---|---|
| in-scope | 23/67（**34.3%**） |
| **cross-language** | **4/47（8.5%）** |

cross 上 **91.5% 的 query 只有一个输入**。`fuse` 退化成 vector 排序，**调 k 是空调**。

## 25.2 实测：cross-language 一动不动

| arm | 方法 | cross R@1 | cross R@5 | cross MRR |
|---|---|---:|---:|---:|
| cloud | rrf(k=1 / 5 / 10 / 30 / 60 / 100 / 200) | **0.681** | 0.936 | 0.813 |
| cloud | weighted(.3/.7) · weighted(.7/.3) | **0.681** | 0.936 | 0.813 |
| cloud | vector-only | **0.681** | 0.936 | 0.813 |

**七个 k 值 + 两个加权点 + 单臂参照，摆动 0.000。**

> **P1 #6 的答案：cross-language R@1 = 0.681 不是 fusion 能改善的。**
> 要动它得动排序信号本身（换模型 / reranker / 让 keyword 在跨语言上能出结果），
> 而那些都在 P2「明确不做」里。**这一项到此结束，不是「还没调好」。**

## 25.3 意外发现：RRF 在本地臂上**主动有害**

同一次实验的 in-scope 一栏（这不是原来要找的东西）：

| arm | 方法 | in-scope R@1 | in-scope MRR |
|---|---|---:|---:|
| — | keyword 单独 | 0.343 | 0.343 |
| local | **rrf（任意 k）** | **0.269 – 0.284** | 0.341 – 0.349 |
| local | vector 单独 | 0.104 | 0.146 |
| local | **weighted(kw .7 / v .3)** | **0.358** | 0.386 |

**RRF 把 R@1 从 keyword 单独的 0.343 压到 0.269** —— 那不是「没帮上忙」，是帮了倒忙。

机制清楚：RRF 等权。本地向量臂 R@1 只有 0.104，等权让**弱臂稀释强臂**。
这与「中英双索引反而更差」是同一个失效模式的第二次出现 ——
**往融合里加一路弱信号，不是中性的。**

## 25.4 权重曲线：有平台，不是尖峰

两个加权点不算参数实验。扫 w ∈ [0, 1]（`w·keyword + (1−w)·vector`，皆用名次倒数）：

| w | local in R@1 | cloud in R@1 |
|---:|---:|---:|
| 0.0 – 0.3 | 0.104 | 0.851 |
| 0.4 | 0.119 | 0.866 |
| 0.5 | 0.284 | 0.866 |
| **0.6 – 0.9** | **0.358** | **0.866** |
| 1.0 | 0.358（MRR 掉） | **0.388** ← 塌了 |

**两个 provider 的最优区间重叠在 w ∈ [0.6, 0.9]**，各自 5–6 个采样点宽。
平台宽说明它是结构，不是某个点碰巧好看。

两端揭示的是对称的道理：

- **local 的向量臂弱** → 压低它才好（w ≥ 0.6）
- **cloud 的向量臂强** → w = 1.0 把它清零，in-scope R@1 从 0.866 塌到 **0.388**

也就是说，**最优权重取决于哪一路更强，而两个 provider profile 相反** ——
但它们仍然共享一个可用区间，所以不需要按 provider 分别配。

## 25.5 一处文档与实现不符

`FusionMethod.weighted` 的枚举注释写着「需要两路分数可比 —— 目前**并不可比**，
保留只为在 Lab 里作为对照，不作为默认」。

但实现里是 `s += kw / Double(kr)` —— **用的是名次倒数，不是原始分数**
（方法体内部的注释也这么写：「名次的倒数当作可比的替身」）。
也就是说**那条弃用理由描述的不是它自己的实现**：它和 RRF 一样是纯名次融合，
区别只在有权重、没有 `k` 平滑。

排除它的理由因此不成立。已修正枚举注释。

## 25.6 它会把 local-hybrid 从 BLOCKED 救回来

用 keyword 作 baseline 跑真实判定（perf-v1 口径，只看 in-scope）：

```
rrf(k=1 … 200)         PROMOTION BLOCKED   R@1 0.269–0.284 · R@5 0.418
weighted(kw .3/v .7)   PROMOTION BLOCKED   R@1 0.104 · R@5 0.418
weighted(kw .7/v .3)   PASS                R@1 0.358 · R@5 0.418
vector-only            PROMOTION BLOCKED   R@1 0.104 · R@5 0.194
```

**§24.5 那个 BLOCKED 的成因是融合方式，不是本地向量模型。**

## 25.7 为什么**没有**顺手改默认值

改生产融合方式是产品决策，登记为待定（P1 #18），理由：

1. **证据只有一个 synthetic 数据集。** in-scope 67 条，`weighted(.7/.3)` 相对 RRF
   赢 **6 条用例**（0.089），但相对 **keyword 单独只赢 1 条**（0.015）。
   「RRF 等权是错的」这句站得住；「加权融合更好」这句**还不够**。
2. R@5 在所有融合方式下都不变（local 0.418 / cloud 1.000）——
   融合只改排序、不改召回集合。所以收益全部押在 R@1 这一个指标上。
3. 负例 no-result 在所有方式下都是 **0%**，TD-10 不受影响，也没被改善。

**要做这个决定，需要的是真实标注的 Golden Set（P0 #1/#3），不是再扫一遍参数。**

---

# 26. P1 收口：v4 评测集 · 融合默认值 · 分档成本 · 云端提示

## 26.1 Golden Set v4（P1 #5）：210 篇，**部分达成**

| | v3 | **v4** |
|---|---:|---:|
| Notes | 150 | **210** |
| 每类语料 | 30（15 中 / 15 英） | **42（21 中 / 21 英）** |
| 正向 query | 114 | **166**（101 in-scope / 65 cross） |
| 负例 | 20 | **30** |
| 干扰项 | 77 | **117** |

**加的不是数量，是「同构簇」** —— v3 的干扰是「同话题不同答案」，v4 更狠一层：
整篇几乎逐句对应，**只有一个数字或一个结论不同**。19 个簇，例如：

- 同一门课三次作业（周次 / 截止 / 组队规则各不同）
- 租约续租附录 30 日 **vs** 原租约 60 日 **vs** 另一处 90 日（**条款冲突，附录优先**）
- I-20 批准 / 待补材料 / 初次签发
- 墨盒 CF259A / CF259X / CF258A（型号仅一字之差且不可互换）
- 用药 500mg q8h / 875mg q12h / 家人的另一种药

新增自动保护：**每个同构簇里至多一篇能当答案**。两篇都算对的话，
排序层分不分得清都拿满分 —— 那簇就白设计了。这条守卫当场抓到 3 处违规
（I45 角色标反、两条 query 指向簇里的干扰项）。

### 结果：R@1 有区分度了，**R@5 仍然饱和**

| | v3 | **v4** | |
|---|---:|---:|---|
| cloud-hybrid in-scope **R@1** | 0.866 | **0.792** | ✅ 压下来了 |
| cloud-hybrid in-scope **R@5** | 1.000 | **1.000** | ❌ **没打破** |
| cloud-hybrid cross R@1 | 0.681 | **0.600** | ✅ |
| cloud-hybrid cross R@5 | 0.936 | **0.892** | ✅ |
| keyword in-scope R@1 | 0.343 | 0.386 | （新增 exact query 较多） |

**如实记：加固的一半目标没达成。** 同构簇让**排序**更难（R@1 −0.074），
但没让**召回**更难 —— in-scope R@5 仍是 1.000。

机制清楚：一个簇 3 篇，Top-5 有 5 个位置，**整簇装进去还有余量**。
要压 R@5 得让簇更大（6–8 篇）或让干扰跨簇分布。这是 v5 的方向，不是再加 60 篇散篇。

## 26.2 默认融合换成加权名次（P1 #18）

§25 在 v3 上发现「等权 RRF 主动有害」。v4 上**复现且更强**：

| 数据集 | in-scope R@1：RRF | 加权 w=0.7 | keyword 单独 | RRF 相对 keyword |
|---|---:|---:|---:|---:|
| v3（67 in-scope） | 0.269 | 0.358 | 0.343 | **−5 条** |
| v4（101 in-scope） | 0.287 | **0.386** | 0.386 | **−10 条** |

**默认值已从 `.rrf(k: 60)` 换成 `.weighted(keyword: 0.7, vector: 0.3)`。**

选 0.7 而不是各自最优：v4 上 cloud 最优在 w=0.5（0.802），local 最优在 w≥0.6。
选 w=0.7 **云端付 −0.010，本地拿 +0.099 —— 交换比约 10:1**，且 w ∈ [0.6, 0.9]
是宽 4 个采样点的共同平台。

**它只影响新建配置。** 已 promote 的生产配置自带各自的 `fusion` 值，
不会被默认值改动 —— 「生产配置只能经 promote 更换」这条纪律不因此松动。

仍然成立的限制：证据全部来自 synthetic。它支持「等权 RRF 是错的」，
**不支持「hybrid 比 keyword 单独更好」** —— v4 上两者 R@1 恰好都是 0.386。

## 26.3 分档索引成本（P1 #11）

**本地（Mac release · dim 640）—— 四档全部实测：**

| chunks | 建索引 | 单 chunk | 向量内存 | 归一化缓存 | 合计内存 |
|---:|---:|---:|---:|---:|---:|
| 1 000 | 11 752 ms | 11.75 ms | 2.4 MB | 1.3 MB | 3.7 MB |
| 5 000 | 58 470 ms | 11.69 ms | 12.2 MB | 6.4 MB | 18.6 MB |
| 10 000 | 117 447 ms | 11.74 ms | 24.4 MB | 12.8 MB | 37.3 MB |
| **20 000** | **235 243 ms** | **11.76 ms** | 48.8 MB | 26.0 MB | **74.9 MB** |

**完美线性**（单 chunk 耗时 1k→20k 漂移 **1.00×**）—— 所以本地这一项外推是有依据的。
两个要记住的产品数字：**20k 全量建索引 ≈ 3.9 分钟**（真机按 ~20 ms/chunk 约 **7 分钟**）；
**20k 常驻内存 74.9 MB**（向量 48.8 + 归一化缓存 26.0）。

**云端 token —— 只在 1k 上实测**（四档全跑要 ~0.8M token，而墙上时间本就不可外推）：

```
1 000 chunks / 81 780 字符 / 39 384 prompt_tokens  →  39.4 token/chunk · 0.482 token/字符
```

⚠️ **修正一个此前的说法。** 之前记的是「token/chunk 恒定 52.3」——
那是**对那一份语料**恒定（fixture 四次跑批一字不差）。换一批文本就变了
（这里 39.4 / 0.482，fixture 是 52.3 / 0.384）。
**token 随文本走，不随 chunk 数走** —— 外推必须用**该语料自己实测的换算率**，
不能借用别处的数字。

## 26.4 云端升级提示（P1 #8）

D-AI-003 的已知缺口：本地可用 + 云端已配未授权 + **双语库**时，
中文 query 搜不到英文文档，而系统**安静地**用本地跑完。用户看到的是「搜不到」，
不是「有个开关能搜到」。实测代价（v4 · 65 条跨语言）：cross R@5 本地 **0.092** → 云端 **0.892**。

### 三个设计取舍

1. **判断在内核，文案在 App。** `EmbeddingRouter.shouldOfferCloudUpgrade` 返回 `Bool`
   而不是句子 —— `SEARCH_CONTRACT.md` §1.1.1 那张禁用词表（向量 / 语义检索 / index / chunk…）
   内核既不该也没法执行。第一版内核里直接返回了中文句子且**当场违反了词表**，已改。
2. **挂在零结果，不做常驻状态条。** 状态条（§4.4）说的是「有什么坏了」，
   而这是「其实可以更好」—— 混在一起会让双语用户每次搜索都看一遍。
   零结果那一刻用户正好撞上它要解释的现象，最有用也最不打扰。
3. **不改路由。** `choose` 仍返回 `.localChinese`，**不弹 `.cloudNeedsConsent` 打断搜索**。
   路由是能力判定，提示是产品沟通，混进一个返回值会让「弹不弹窗」变成路由的副作用。

四个抑制条件缺一不可（已在用云端 / 没配 Key / 已授权 / 单语库），断言全部覆盖 ——
一句在四种情形里有三种会变成骚扰的提示，价值全在抑制条件上。

`ScriptDetection.containsLatin` **刻意不认数字与标点**：纯中文笔记里
`2026`、`CS5330` 的数字部分很常见，算成「含英文」会让提示在纯中文库上冒出来。

## 26.5 L2a 改为不可单独引用（P1 #14）

三次读数 6.21 → 11.1 → 4.3 ms，代码一行没动，机制没查清。
处理方式不是继续查，而是**让上下文跟着数字走**：`test4` 不再单独打印 L2a，
而是连同「占同批次 20k 端到端 P50 的百分比」一起打印，并断言
`L2a < 端到端`（不满足说明两者不是同一批测的）。想引绝对值，就必须把那张表一起抄走。

## 26.6 n-gram 索引：**决定不做**（P1 #17）

§24.5 之后 Metric A 热 P50 余量从 1.4× 变 **3.2×**，破预算规模从约 28k 推到约 65k。
词法路仍比向量路慢 8.5–9 倍，但那**不再是架构威胁**。

不做的三条理由：

1. **没有用户在 65k chunks 上。** 20k 是 PRD 的上限档，而热 P50 只用掉预算的 31%。
2. **它要改匹配单位。** 中文没有分词器，保子串语义得上 n-gram，
   那是一整套新的 derived 结构（内存 / 重建 / stale 三件事都要配套）。
   §24.3 那一步之所以能做，正因为它**不改语义**。
3. **下一个瓶颈不在这儿。** 真要优化，`scan` 段（20k 上 26.75 ms）之外，
   本地建索引 3.9 分钟、常驻 74.9 MB 都是更靠前的问题。

**重新打开它的条件**：PRD 把语料上限提到 40k 以上，或真机热 P50 越过 60 ms。
