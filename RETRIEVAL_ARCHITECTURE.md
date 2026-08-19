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

## 21.3 Metric A —— keyword 快通道（真机 release）

| chunks | P50 | P95 |
|---|---:|---:|
| 1 000 | 3.67 ms | 4.75 ms |
| 5 000 | 18.07 ms | 24.95 ms |
| 10 000 | 35.46 ms | 45.97 ms |
| **20 000** | **73.88 ms** | **97.87 ms** |

**全部在 SLO（P50<100 / P95<250）内**，有断言守着。

## 21.4 Metric B-local —— 本地 hybrid 端到端（真机 release）

本地 query 嵌入（`nl-zh-Hans-r1`，640 维）：**P50 6.21 ms / P95 7.99 ms** —— 很便宜。

余弦检索规模曲线（dim 384，纯数学）：

| chunks | P50 | P95 | 内存 |
|---|---:|---:|---:|
| 1 000 | 0.64 ms | 0.70 ms | 1.5 MB |
| 5 000 | 1.64 ms | 1.93 ms | 7.3 MB |
| 10 000 | 2.85 ms | 3.16 ms | 14.6 MB |
| 20 000 | **5.45 ms** | **5.86 ms** | 29.3 MB |

端到端 hybrid（keyword + 本地嵌入 + 余弦 + RRF）：

| chunks | P50 | P95 |
|---|---:|---:|
| 1 000 | 8.20 ms | 9.62 ms |
| 5 000 | 24.96 ms | 31.17 ms |
| **20 000** | **92.53 ms** | **119.30 ms** |

**20k chunks 的真机 P95 = 119 ms，在 250 ms 预算内。** Mac release 是 79.5 ms，
真机约慢 1.5 倍 —— 与预期一致，D-RT-012（不上 ANN）在真机上仍然成立。

## 21.5 反直觉发现：瓶颈是 keyword 路，不是向量路

20k chunks 上：**keyword 97.87 ms vs 余弦检索 5.86 ms —— 差 17 倍。**

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
