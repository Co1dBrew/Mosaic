import Foundation
import MosaicKit

func runClientChecks(_ r: CheckRunner) async {
    r.suite("URLSessionAIClient — guards (no network)")

    let client = URLSessionAIClient(session: StubURLProtocol.session())
    let config = ProviderConfig(provider: .kimi, baseURL: "https://api.moonshot.ai/v1", model: "kimi-k2.6", apiKey: "k", supportsVision: true, useJSONMode: true)

    await r.expectThrowsAsync(AIError.emptyContent) {
        _ = try await client.generateBaseSummary(config: config, aggregatedText: "   ", images: [])
    }
    await r.expectThrowsAsync(AIError.changeTooSmall) {
        _ = try await client.generateUpdateSummary(config: config, previousSummaryText: "old", changeSetText: "  ", images: [])
    }

    r.suite("URLSessionAIClient — success")

    let baseContent = #"{\"title\":\"标题\",\"one_liner\":\"概述\",\"type\":\"会议记录\",\"topics\":[\"a\"],\"key_points\":[\"k\"],\"summary\":\"总结\"}"#
    StubURLProtocol.stub = .init(statusCode: 200, body: #"{"choices":[{"message":{"content":"\#(baseContent)"}}]}"#.data(using: .utf8)!, error: nil)
    do {
        let dto = try await client.generateBaseSummary(config: config, aggregatedText: "内容", images: [])
        r.expectEqual(dto.title, "标题")
        r.expectEqual(dto.type, "会议记录")
    } catch {
        r.expect(false, "200 valid base summary should parse, got \(error)")
    }
    // Outgoing request body carried the right model
    if let body = StubURLProtocol.lastRequestBody,
       let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
        r.expectEqual(obj["model"] as? String, "kimi-k2.6", "request body carried model")
    } else {
        r.expect(false, "captured request body should decode")
    }

    r.suite("URLSessionAIClient — HTTP error mapping")

    StubURLProtocol.stub = .init(statusCode: 401, body: Data("{}".utf8), error: nil)
    await r.expectThrowsAsync(AIError.unauthorized) {
        _ = try await client.generateBaseSummary(config: config, aggregatedText: "内容", images: [])
    }

    StubURLProtocol.stub = .init(statusCode: 429, body: Data("{}".utf8), error: nil)
    await r.expectThrowsAsync(AIError.rateLimited) {
        _ = try await client.generateBaseSummary(config: config, aggregatedText: "内容", images: [])
    }

    StubURLProtocol.stub = .init(statusCode: 500, body: #"{"error":{"message":"boom"}}"#.data(using: .utf8)!, error: nil)
    await r.expectThrowsAsync(AIError.serverError(status: 500, body: "boom")) {
        _ = try await client.generateBaseSummary(config: config, aggregatedText: "内容", images: [])
    }

    r.suite("URLSessionAIClient — transport error mapping")

    StubURLProtocol.stub = .init(statusCode: 0, body: Data(), error: URLError(.notConnectedToInternet))
    await r.expectThrowsAsync(AIError.offline) {
        _ = try await client.generateBaseSummary(config: config, aggregatedText: "内容", images: [])
    }

    StubURLProtocol.stub = .init(statusCode: 0, body: Data(), error: URLError(.timedOut))
    await r.expectThrowsAsync(AIError.timedOut) {
        _ = try await client.generateBaseSummary(config: config, aggregatedText: "内容", images: [])
    }

    r.suite("URLSessionAIClient — invalid JSON content")

    StubURLProtocol.stub = .init(statusCode: 200, body: #"{"choices":[{"message":{"content":"this is not json"}}]}"#.data(using: .utf8)!, error: nil)
    do {
        _ = try await client.generateBaseSummary(config: config, aggregatedText: "内容", images: [])
        r.expect(false, "non-JSON content should throw")
    } catch let e as AIError {
        if case .invalidJSON = e { r.expect(true, "invalid JSON mapped") }
        else { r.expect(false, "expected invalidJSON, got \(e)") }
    } catch {
        r.expect(false, "expected AIError, got \(error)")
    }

    r.suite("URLSessionAIClient — test connection")
    StubURLProtocol.stub = .init(statusCode: 200, body: #"{"choices":[{"message":{"content":"pong"}}]}"#.data(using: .utf8)!, error: nil)
    do {
        try await client.testConnection(config: config)
        r.expect(true, "200 test connection succeeds")
    } catch {
        r.expect(false, "test connection should succeed on 200, got \(error)")
    }
    StubURLProtocol.stub = .init(statusCode: 401, body: Data("{}".utf8), error: nil)
    await r.expectThrowsAsync(AIError.unauthorized) {
        try await client.testConnection(config: config)
    }
}
