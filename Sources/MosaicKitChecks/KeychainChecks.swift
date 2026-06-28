import Foundation
import MosaicKit

func runKeychainChecks(_ r: CheckRunner) {
    r.suite("InMemoryKeychain")

    let kc = InMemoryKeychain()
    let account = KeychainAccount.apiKey(for: .kimi)
    r.expectEqual(account, "apiKey.kimi")

    r.expectNil(kc.string(for: account), "empty to start")
    try? kc.setString("sk-123", for: account)
    r.expectEqual(kc.string(for: account), "sk-123", "stores value")
    try? kc.setString("sk-456", for: account)
    r.expectEqual(kc.string(for: account), "sk-456", "overwrites value")
    try? kc.setString(nil, for: account)
    r.expectNil(kc.string(for: account), "nil clears value")
    try? kc.setString("x", for: account)
    try? kc.remove(account: account)
    r.expectNil(kc.string(for: account), "remove clears value")

    // Per-provider isolation
    try? kc.setString("k1", for: KeychainAccount.apiKey(for: .kimi))
    try? kc.setString("k2", for: KeychainAccount.apiKey(for: .deepseek))
    r.expectEqual(kc.string(for: KeychainAccount.apiKey(for: .kimi)), "k1")
    r.expectEqual(kc.string(for: KeychainAccount.apiKey(for: .deepseek)), "k2")
}
