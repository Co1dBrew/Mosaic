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

    static func make(cloudKitEnabled: Bool, inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // In-memory must succeed; a failure here is a programmer error.
            return try! ModelContainer(for: schema, configurations: [config])
        }

        let primary = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitEnabled ? .automatic : .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [primary]) {
            return container
        }

        // Fall back to a purely local store.
        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
            return container
        }

        // Last resort: in-memory, so the app launches instead of crashing.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memory])
    }
}
