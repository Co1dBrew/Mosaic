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

    // Kimi K2.x models require temperature == 1; moonshot-v1 models keep the configured value.
    let k2 = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.cn/v1", model: "kimi-k2.6", apiKey: "k", supportsVision: true, useJSONMode: true, temperature: 0.2)
    r.expectEqual(k2.temperature, 1.0, "kimi-k2.x forces temperature 1.0")
    let mv = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", apiKey: "k", supportsVision: false, useJSONMode: true, temperature: 0.2)
    r.expectEqual(mv.temperature, 0.2, "moonshot-v1 keeps configured temperature")

    // CN region base URL builds correctly
    r.expectEqual(mv.chatCompletionsURL?.absoluteString, "https://api.moonshot.cn/v1/chat/completions")

    // Validation
    let noKey = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "m", apiKey: "  ", supportsVision: true, useJSONMode: true)
    r.expectEqual(noKey.validationError, .missingAPIKey)
    let noModel = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "", apiKey: "k", supportsVision: true, useJSONMode: true)
    r.expectEqual(noModel.validationError, .missingModel)
    let noURL = ProviderConfig(provider: .custom, baseURL: "   ", model: "m", apiKey: "k", supportsVision: false, useJSONMode: false)
    r.expectEqual(noURL.validationError, .invalidBaseURL)
    r.expectNil(kimi.validationError, "valid config has no error")
}
