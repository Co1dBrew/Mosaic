import Foundation
import MosaicKit

private func bodyJSON(_ request: URLRequest) -> [String: Any]? {
    guard let data = request.httpBody,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return obj
}

func runRequestBuilderChecks(_ r: CheckRunner) {
    r.suite("AIRequestBuilder — base summary")

    let visionConfig = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "kimi-k2.6", apiKey: "secret", supportsVision: true, useJSONMode: true, temperature: 0.2)
    let images = [AIImage(base64: "QUJD", mimeType: "image/jpeg")]

    guard let req = try? AIRequestBuilder.baseSummaryRequest(config: visionConfig, aggregatedText: "内容", images: images) else {
        r.expect(false, "base request should build"); return
    }
    r.expectEqual(req.url?.absoluteString, "https://api.moonshot.ai/v1/chat/completions")
    r.expectEqual(req.httpMethod, "POST")
    r.expectEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    r.expectEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

    if let body = bodyJSON(req) {
        r.expectEqual(body["model"] as? String, "kimi-k2.6")
        r.expectEqual(body["max_tokens"] as? Int, 1024)
        r.expectNotNil(body["response_format"], "json mode -> response_format present")
        let messages = body["messages"] as? [[String: Any]]
        r.expectEqual(messages?.count, 2)
        r.expectEqual(messages?[0]["role"] as? String, "system")
        r.expectEqual(messages?[1]["role"] as? String, "user")
        // Vision: user content is an array including an image_url part
        if let parts = messages?[1]["content"] as? [[String: Any]] {
            let hasImage = parts.contains { ($0["type"] as? String) == "image_url" }
            r.expect(hasImage, "vision request includes image_url part")
            let hasText = parts.contains { ($0["type"] as? String) == "text" }
            r.expect(hasText, "vision request includes text part")
        } else {
            r.expect(false, "vision user content should be an array")
        }
    } else {
        r.expect(false, "body should decode")
    }

    r.suite("AIRequestBuilder — vision degradation & json mode off")

    let noVision = ProviderConfig(provider: .deepseek, baseURL: "https://api.deepseek.com/v1", model: "deepseek-v4-flash", apiKey: "k", supportsVision: false, useJSONMode: false)
    if let req2 = try? AIRequestBuilder.baseSummaryRequest(config: noVision, aggregatedText: "内容", images: images),
       let body = bodyJSON(req2) {
        r.expectNil(body["response_format"], "json mode off -> no response_format")
        let messages = body["messages"] as? [[String: Any]]
        // No vision: content is a plain string
        r.expectNotNil(messages?[1]["content"] as? String, "non-vision user content is a string")
    } else {
        r.expect(false, "non-vision request should build")
    }

    r.suite("AIRequestBuilder — update & test connection")

    if let upd = try? AIRequestBuilder.updateSummaryRequest(config: visionConfig, previousSummaryText: "旧总结", changeSetText: "变更", images: []),
       let body = bodyJSON(upd) {
        r.expectEqual(body["max_tokens"] as? Int, 512, "update uses 512 max tokens")
    } else {
        r.expect(false, "update request should build")
    }

    if let test = try? AIRequestBuilder.testConnectionRequest(config: visionConfig),
       let body = bodyJSON(test) {
        r.expectEqual(body["max_tokens"] as? Int, 1, "test connection uses minimal tokens")
        r.expectNil(body["response_format"], "test connection does not force json mode")
    } else {
        r.expect(false, "test request should build")
    }

    r.suite("AIRequestBuilder — validation")
    let bad = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "m", apiKey: "", supportsVision: true, useJSONMode: true)
    r.expectThrows(AIError.missingAPIKey) {
        _ = try AIRequestBuilder.baseSummaryRequest(config: bad, aggregatedText: "x", images: [])
    }
}
