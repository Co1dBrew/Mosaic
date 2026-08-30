import Foundation
import SwiftData

/// Builds the SwiftData `ModelContainer`, optionally backed by CloudKit private
/// database sync (PRD §4.10 / §7.1). Falls back to a local store if CloudKit
/// setup fails (e.g. missing entitlement or no signed-in iCloud account), so the
/// app still works offline.
enum ModelContainerFactory {
    static let schema = Schema([
        Folder.self,
        Card.self,
        Block.self,
        AISummaryEntity.self,
        UpdateLogEntity.self
    ])

    /// 这个**构建**有没有 CloudKit 能力。
    ///
    /// 单一来源是 Info.plist 的 `MosaicCloudKitEnabled`，由 `project.yml` 一处
    /// 控制，与 `Mosaic.entitlements` 必须一起改 —— 分开写迟早会漂移，而漂移的
    /// 后果是 UI 说在同步、数据其实只在本机。
    ///
    /// 现在是 **NO**：仓库里的 entitlements 是空的 `<dict/>`，没有 iCloud 容器。
    /// 拿到付费开发者账号并建好容器之后，改 `project.yml` 里那一个 `YES`。
    static var buildSupportsCloudKit: Bool {
        // 构建设置注入进 Info.plist 的是**字符串** `"NO"` / `"YES"`，不是布尔。
        // `as? Bool` 对字符串一律失败 —— 只写那一种的话，把开关改成 YES 之后
        // 这里仍然返回 false，而且没有任何报错。两种形态都认。
        let raw = Bundle.main.object(forInfoDictionaryKey: "MosaicCloudKitEnabled")
        if let flag = raw as? Bool { return flag }
        if let text = raw as? String {
            return ["YES", "yes", "true", "TRUE", "1"].contains(text)
        }
        return false
    }

    /// 建出来的容器，**以及它实际上是不是 CloudKit 支撑的**。
    ///
    /// 老签名只返回 `ModelContainer`，于是「申请了 CloudKit 但退回了本地」这件事
    /// 在调用方那里不可见 —— 设置页只能去读用户的偏好，然后显示一个与事实无关的
    /// 「已开启」。把事实带出来，UI 才有可能说实话。
    struct NoteStore {
        let container: ModelContainer
        let isCloudKitBacked: Bool
    }

    // MARK: UI 测试的存储隔离

    /// UI 测试用的独立 store 目录。
    ///
    /// **不用 in-memory**：Core Flow 2 要验证「重启后内容还在」，而 in-memory
    /// 一退出就没了，那条用例会变成永远通过。所以给一个真实的磁盘 store，
    /// 只是路径与用户数据分开，并且可以在启动时按需清空。
    static let uiTestStoreName = "MosaicUITest"

    static var isUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test")
    }

    /// `--ui-test-reset` 时把测试 store 删掉，保证每条用例从空状态开始。
    /// 不传这个参数的重启会保留数据 —— Core Flow 2 就靠它。
    private static func resetUITestStoreIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-test-reset") else { return }
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        for suffix in ["store", "store-shm", "store-wal"] {
            for name in [uiTestStoreName, "\(uiTestStoreName)Derived"] {
                try? fm.removeItem(at: support.appendingPathComponent("\(name).\(suffix)"))
            }
        }
    }

    static func makeNoteStore(cloudKitRequested: Bool, inMemory: Bool = false) -> NoteStore {
        if isUITest {
            resetUITestStoreIfRequested()
            let config = ModelConfiguration(uiTestStoreName, schema: schema,
                                            isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return NoteStore(container: container, isCloudKitBacked: false)
            }
        }
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // In-memory must succeed; a failure here is a programmer error.
            return NoteStore(container: try! ModelContainer(for: schema, configurations: [config]),
                             isCloudKitBacked: false)
        }

        if cloudKitRequested {
            let primary = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                             cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: [primary]) {
                return NoteStore(container: container, isCloudKitBacked: true)
            }
        }

        // Fall back to a purely local store.
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
            return NoteStore(container: container, isCloudKitBacked: false)
        }

        // Last resort: in-memory, so the app launches instead of crashing.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return NoteStore(container: try! ModelContainer(for: schema, configurations: [memory]),
                         isCloudKitBacked: false)
    }

    /// Preview / 测试用的便捷入口。生产路径走 `makeNoteStore` —— 它带着事实。
    static func make(cloudKitEnabled: Bool, inMemory: Bool = false) -> ModelContainer {
        makeNoteStore(cloudKitRequested: cloudKitEnabled, inMemory: inMemory).container
    }

    // MARK: Derived retrieval data

    /// Derived data lives in its **own schema and its own store file**, separate
    /// from user notes.
    ///
    /// - "Delete all derived data" becomes "delete one file" and cannot touch a
    ///   note, because notes are not in that file.
    /// - Never CloudKit-backed: embeddings are device-local, large, and cheap to
    ///   rebuild. Syncing them would spend the user's quota on regenerable bytes.
    static let derivedSchema = Schema([
        EmbeddingRecordEntity.self,
        ImageTextExtractionEntity.self
    ])

    static func makeDerived(inMemory: Bool = false) -> ModelContainer {
        if isUITest {
            let config = ModelConfiguration("\(uiTestStoreName)Derived", schema: derivedSchema,
                                            isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: derivedSchema, configurations: [config]) {
                return container
            }
        }
        if inMemory {
            let config = ModelConfiguration(schema: derivedSchema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: derivedSchema, configurations: [config])
        }
        let config = ModelConfiguration(
            "MosaicDerived",
            schema: derivedSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: derivedSchema, configurations: [config]) {
            return container
        }
        // Derived data is rebuildable, so an in-memory fallback loses nothing
        // permanent — the next scan simply re-queues everything.
        let memory = ModelConfiguration(schema: derivedSchema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: derivedSchema, configurations: [memory])
    }
}
