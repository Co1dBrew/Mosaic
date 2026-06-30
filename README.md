# 万象记 / Mosaic

An iOS multimedia note app. Each note card mixes **text, images, audio, documents, and links**; the app generates an AI **base summary** of the whole card and, after edits, **incremental update summaries** that describe only what changed. Built with SwiftUI + SwiftData, prepared for CloudKit sync. See [`prd.md`](prd.md) for the full product spec.

## Architecture

The codebase is split into two layers so the bug-prone logic can be unit-tested even without Xcode:

```
Mosaic/
├── Package.swift                 # MosaicKit (library) + mosaic-checks (test runner)
├── Sources/MosaicKit/            # PURE Swift core — no SwiftData, no UIKit
│   ├── Provider/                 # AIProvider, ProviderConfig (URL/temperature/validation)
│   ├── AI/                       # Prompts, DTOs, request builder, response parser, AIClient, errors
│   ├── Aggregation/              # CardContent value types, content aggregator (+ truncation)
│   ├── Diff/                     # ContentHasher, SummarySnapshot, SnapshotDiffer (change detection)
│   └── Security/                 # KeychainService (+ in-memory variant)
├── Sources/MosaicKitChecks/      # Runnable test suite (assertion harness) — `swift run mosaic-checks`
└── App/
    ├── project.yml               # XcodeGen spec (generates Mosaic.xcodeproj)
    └── Mosaic/
        ├── App/                  # MosaicApp, RootView, ModelContainerFactory (SwiftData+CloudKit)
        ├── Persistence/          # @Model: Folder, Card, Block, AISummaryEntity, UpdateLogEntity
        ├── Services/             # MediaStore, AudioRecorder/Player, SpeechTranscriber,
        │                         #   ImagePipeline, DocumentImporter, SummaryService
        ├── Settings/             # SettingsStore (UserDefaults + Keychain), SettingsView
        ├── Features/             # Folders / Cards (collapsed bar + summary sticker) / Editor (blocks)
        └── Components/           # Design system, UIKit bridges, flow layout
```

**Boundary:** `MosaicKit` never imports SwiftData or UIKit. The app adapts its SwiftData `Block` models into `MosaicKit.CardBlockContent` value types (`Block.toContent()`), so all hashing/diffing/aggregation/AI logic is platform-agnostic and testable.

## Building & running

### Core logic (works with just the Swift toolchain / Command Line Tools)

```bash
swift build                 # builds MosaicKit
swift run mosaic-checks     # runs the core test suite (exits non-zero on failure)
```

`mosaic-checks` is the unit-test suite (117+ assertions covering provider config, JSON parsing robustness, defensive DTO decoding, content hashing, snapshot diff, aggregation/truncation, request building incl. vision on/off, full HTTP/transport error mapping via a stubbed URLSession, and Keychain logic). It is used in place of XCTest/Swift Testing, which are **not** bundled with the Command Line Tools toolchain.

### iOS app (requires full Xcode)

```bash
brew install xcodegen        # if needed
cd App && xcodegen generate  # regenerates Mosaic.xcodeproj from project.yml
open App/Mosaic.xcodeproj
```

Then set your signing team and an iCloud container identifier, and run on a device/simulator.

## Configuration

1. **Settings → AI 服务商**: choose Kimi / DeepSeek / Custom.
2. Enter your **API Key** (stored in the Keychain only) and, for Custom, a Base URL + model name.
3. Tap **测试连接** to verify.
4. On first summary generation you'll see a one-time **privacy notice** before any content is sent.

Model defaults (verify against providers' latest docs): Kimi `kimi-k2.6` (vision), DeepSeek `deepseek-v4-flash` / `deepseek-v4-pro` (vision off by default until verified).

## Speech-to-text: two modes (privacy)

Transcription is switchable in **Settings → 语音转写**:

- **Apple 本地转写 (default)** — `SpeechTranscriber` via the Speech framework with
  `requiresOnDeviceRecognition = true`. Runs entirely on-device; **the original
  audio never leaves the device**. Works offline. Privacy-friendly; accuracy
  depends on the on-device model.
- **API 云端转写** — `URLSessionCloudTranscriber` uploads the recorded audio file
  to an OpenAI-compatible `/audio/transcriptions` endpoint (e.g. Whisper). By
  default it reuses the AI provider's API key / base URL, with optional **STT
  Base URL** and **STT API Key** overrides so STT can use a *different* provider
  than chat. **This uploads the audio to a third party**, so the app shows a
  one-time audio-upload consent dialog before the first cloud transcription and
  refuses to upload without it. "Test connection" never uploads user audio.
  - Note: not every chat provider offers STT. **Moonshot/Kimi and DeepSeek do
    NOT currently expose `/audio/transcriptions`** (verified: 404), so for cloud
    STT point the STT Base URL/Key at an OpenAI-compatible Whisper service (e.g.
    OpenAI `whisper-1`). A 404 surfaces as "服务商不支持语音转写".

Language preference (自动 / 中文 / English) maps to the Apple locale
(`zh-CN` / `en-US` / system) or the API `language` hint (`zh` / `en` / omitted).
Either way the resulting transcript is stored on the audio block and feeds the AI
summary. Transcription orchestration lives in `TranscriptionService`; the cloud
request building/parsing is in `MosaicKit/Transcription` (unit-tested).

## Search (P1)

Global card search from the folder-list toolbar (🔍). Matching is a pure,
unit-tested `SearchMatcher` in MosaicKit (multi-term AND, case- &
diacritic-insensitive, tag-aware). The app builds a per-card "haystack" from the
title, text blocks, audio transcripts, document `extractedText`, link
URL/title/description, image captions, the AI base summary, and update logs
(`CardSearchText.haystack`). Filtering goes through a reserved `SearchScope`
(global / folder / tag / pinned) — Phase 1 uses the unconstrained (global) scope;
later filters slot in without changing call sites. The search field is debounced
(~250ms). Tags are wired into search but empty until the Tags phase adds
`Card.tags`. A DEBUG `--search-demo` launch arg seeds sample data and opens
search prefilled, for QA.

## Tags (P1)

Cards carry `tags: [String]` (defaulted — safe SwiftData lightweight migration,
CloudKit-compatible, old cards → `[]`). Normalization/de-dup is the pure,
unit-tested `TagUtilities` in MosaicKit: trims/collapses whitespace, de-dups
case- & diacritic-insensitively (so "Work" == "work"; Chinese preserved with
original casing). Edit tags as chips in the card editor; tap **把主题加为标签**
in the summary sticker to turn AI topics into tags; the folder card list shows a
tag filter bar; tags feed search (`CardSearchText.tags`). `--cards-demo` (DEBUG)
seeds tagged sample cards for QA.

## Pinning (P1)

Cards can be pinned (existing `Card.isPinned`, no schema change). Folder lists
sort **pinned first, then `updatedAt` descending** via the pure, unit-tested
`CardSorting` in MosaicKit. Toggle from the card list (leading swipe) or the
editor toolbar (📌); pinned cards show a pin badge on the collapsed bar. Toggling
pin does not change `updatedAt`, so pinned cards keep their recency order.

## Design system

Shared UI lives in `App/Mosaic/Components/AppStyles.swift`: `AppSpacing`,
`AppRadius`, `AppMetrics` (44pt min tap target), the `PrimaryActionButtonStyle` /
`SecondaryActionButtonStyle` / `DestructiveActionButtonStyle` button styles and
their `PrimaryActionButton` / `SecondaryActionButton` / `DestructiveActionButton`
wrappers, plus `appCard()`. All primary actions use these (centered labels,
≥44pt, Dynamic Type via `minimumScaleFactor`, dark-mode-safe system colors). A
DEBUG-only `--ui-gallery` launch argument renders a component gallery for QA.

## Known limitations / environment blockers

This project was built in an environment **without full Xcode** (Command Line Tools only). Consequences:

- **The iOS app target was not compiled here** — no iOS SDK / simulator available. The pure-Swift `MosaicKit` core *is* compiled and tested. The app layer was written to Apple's APIs and reviewed by static analysis; please build it in full Xcode.
- **Media-file CloudKit sync is a follow-up.** Media (audio/images/documents) is stored as files in the app sandbox (`MediaStore`); SwiftData metadata syncs via CloudKit, but binary media does not yet sync as CloudKit assets. This is the documented sequencing in PRD §10.1 and the seam is isolated in `MediaStore`.
- **CloudKit requires setup**: a real iCloud container id (replace `iCloud.com.mosaic.app` in `App/Mosaic/Mosaic.entitlements`) and a signed-in iCloud account. The container falls back to a local store if CloudKit is unavailable, so the app still runs offline.
- **Deployment target is iOS 17** (SwiftData / `@Observable` requirement), slightly above the PRD's suggested iOS 16 floor.

## PRD coverage (MVP / P0)

Folders (CRUD, color/icon, count, delete-confirm) · Cards (CRUD, sort by updatedAt, AI title fallback) · Block editor (text/image/audio/file/link, add/delete/reorder, autosave, offline) · On-device audio transcription · Image compression + vision · PDF text extraction · Link open/in-app browser · Collapsed bar + AI summary sticker (base + reverse-chron update logs) · Incremental update via block-level snapshot diff (base preserved) · Strict-JSON prompts + defensive parsing · Settings (Keychain key, test connection, auto-update toggle, privacy notice) · CloudKit-ready schema.
