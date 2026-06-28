import Foundation
import MosaicKit

/// Optional live end-to-end check against a real provider, exercising the actual
/// URLSessionAIClient → network → AIResponseParser path. Runs ONLY when the env
/// vars are set, so no secret is ever stored in source:
///   MOSAIC_LIVE_KEY=<api-key> \
///   MOSAIC_LIVE_BASEURL=https://api.moonshot.cn/v1 \
///   MOSAIC_LIVE_MODEL=moonshot-v1-8k-vision-preview \
///   swift run mosaic-checks
func runLiveChecks(_ r: CheckRunner) async {
    let env = ProcessInfo.processInfo.environment
    guard let key = env["MOSAIC_LIVE_KEY"], !key.isEmpty else {
        print("\n▶ Live provider check — skipped (set MOSAIC_LIVE_KEY to run)")
        return
    }
    r.suite("Live provider check (real network)")

    let baseURL = env["MOSAIC_LIVE_BASEURL"] ?? "https://api.moonshot.cn/v1"
    let model = env["MOSAIC_LIVE_MODEL"] ?? "moonshot-v1-8k-vision-preview"
    let providerRaw = env["MOSAIC_LIVE_PROVIDER"] ?? "kimi"
    let provider = AIProvider(rawValue: providerRaw) ?? .kimi

    let config = ProviderConfig(
        provider: provider,
        baseURL: baseURL,
        model: model,
        apiKey: key,
        supportsVision: false,
        useJSONMode: true,
        temperature: 0.2
    )
    let client = URLSessionAIClient()

    // 1) Test connection
    do {
        try await client.testConnection(config: config)
        r.expect(true, "testConnection succeeded")
    } catch {
        r.expect(false, "testConnection failed: \(error)")
    }

    // 2) Base summary, real parse
    let text = "今天开了产品评审会,确定下周三上线新版本,新增三位负责人分工。"
    do {
        let dto = try await client.generateBaseSummary(config: config, aggregatedText: text, images: [])
        r.expect(!dto.title.isEmpty, "base summary returned a non-empty title: \(dto.title)")
        r.expect(!dto.summary.isEmpty, "base summary returned a non-empty summary")
        print("   ↳ title: \(dto.title)")
        print("   ↳ one_liner: \(dto.oneLiner)")
        print("   ↳ type: \(dto.type)  topics: \(dto.topics)")
        print("   ↳ summary: \(dto.summary)")
    } catch {
        r.expect(false, "generateBaseSummary failed: \(error)")
    }
}
