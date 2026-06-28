import Foundation
import MosaicKit

func runProviderChecks(_ r: CheckRunner) {
    r.suite("Provider & ProviderConfig")

    // Defaults
    r.expectEqual(AIProvider.kimi.defaultBaseURL, "https://api.moonshot.ai/v1")
    r.expectEqual(AIProvider.deepseek.defaultBaseURL, "https://api.deepseek.com/v1")
    r.expectNil(AIProvider.custom.defaultBaseURL)
    r.expectEqual(AIProvider.kimi.temperatureMax, 1.0)
    r.expectEqual(AIProvider.deepseek.temperatureMax, 2.0)

    // URL building
    let kimi = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "kimi-k2.6", apiKey: "k", supportsVision: true, useJSONMode: true)
    r.expectEqual(kimi.chatCompletionsURL?.absoluteString, "https://api.moonshot.ai/v1/chat/completions")

    let trailing = ProviderConfig(provider: .custom, baseURL: "https://x.test/v1/", model: "m", apiKey: "k", supportsVision: false, useJSONMode: false)
    r.expectEqual(trailing.chatCompletionsURL?.absoluteString, "https://x.test/v1/chat/completions")

    let already = ProviderConfig(provider: .custom, baseURL: "https://x.test/v1/chat/completions", model: "m", apiKey: "k", supportsVision: false, useJSONMode: false)
    r.expectEqual(already.chatCompletionsURL?.absoluteString, "https://x.test/v1/chat/completions")

    // Temperature clamping
    let hot = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "m", apiKey: "k", supportsVision: true, useJSONMode: true, temperature: 1.8)
    r.expectEqual(hot.temperature, 1.0, "kimi temperature clamps to 1.0")
    let cold = ProviderConfig(provider: .deepseek, baseURL: "https://api.deepseek.com/v1", model: "m", apiKey: "k", supportsVision: false, useJSONMode: true, temperature: -3)
    r.expectEqual(cold.temperature, 0.0, "temperature clamps to >= 0")

    // Validation
    let noKey = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "m", apiKey: "  ", supportsVision: true, useJSONMode: true)
    r.expectEqual(noKey.validationError, .missingAPIKey)
    let noModel = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "", apiKey: "k", supportsVision: true, useJSONMode: true)
    r.expectEqual(noModel.validationError, .missingModel)
    let noURL = ProviderConfig(provider: .custom, baseURL: "   ", model: "m", apiKey: "k", supportsVision: false, useJSONMode: false)
    r.expectEqual(noURL.validationError, .invalidBaseURL)
    r.expectNil(kimi.validationError, "valid config has no error")
}
