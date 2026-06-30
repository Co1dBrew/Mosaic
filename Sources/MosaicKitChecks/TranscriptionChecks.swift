import Foundation
import MosaicKit

func runTranscriptionChecks(_ r: CheckRunner) async {
    r.suite("TranscriptionMode & Language")

    r.expect(!TranscriptionMode.localAppleSpeech.uploadsAudio, "local mode does not upload audio")
    r.expect(TranscriptionMode.cloudAPI.uploadsAudio, "cloud mode uploads audio")

    // Apple locale mapping
    r.expectEqual(TranscriptionLanguage.chinese.appleLocaleIdentifier, "zh-CN")
    r.expectEqual(TranscriptionLanguage.english.appleLocaleIdentifier, "en-US")
    r.expectNil(TranscriptionLanguage.auto.appleLocaleIdentifier, "auto -> system locale")

    // API hint mapping
    r.expectEqual(TranscriptionLanguage.chinese.apiLanguageHint, "zh")
    r.expectEqual(TranscriptionLanguage.english.apiLanguageHint, "en")
    r.expectNil(TranscriptionLanguage.auto.apiLanguageHint, "auto -> no hint")

    // Apple locale preference order
    r.expectEqual(TranscriptionLanguage.chinese.appleLocales(systemLocaleIdentifier: "ja-JP"), ["zh-CN"])
    r.expectEqual(TranscriptionLanguage.english.appleLocales(systemLocaleIdentifier: "ja-JP"), ["en-US"])
    r.expectEqual(TranscriptionLanguage.auto.appleLocales(systemLocaleIdentifier: "ja-JP"), ["ja-JP", "zh-CN", "en-US"])

    r.suite("CloudTranscriptionConfig")

    let cfg = CloudTranscriptionConfig(baseURL: "https://api.openai.com/v1", model: "whisper-1", apiKey: "k", languageHint: "zh")
    r.expectEqual(cfg.audioTranscriptionsURL?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
    let trailing = CloudTranscriptionConfig(baseURL: "https://x.test/v1/", model: "whisper-1", apiKey: "k")
    r.expectEqual(trailing.audioTranscriptionsURL?.absoluteString, "https://x.test/v1/audio/transcriptions")
    r.expectNil(cfg.validationError, "valid config")
    r.expectEqual(CloudTranscriptionConfig(baseURL: "https://x/v1", model: "m", apiKey: "  ").validationError, .missingAPIKey)
    r.expectEqual(CloudTranscriptionConfig(baseURL: "  ", model: "m", apiKey: "k").validationError, .invalidBaseURL)
    r.expectEqual(CloudTranscriptionConfig.mimeType(forFileName: "rec.m4a"), "audio/m4a")
    r.expectEqual(CloudTranscriptionConfig.mimeType(forFileName: "rec.wav"), "audio/wav")

    r.suite("CloudTranscriptionRequestBuilder")

    let audio = Data("FAKE-AUDIO-BYTES".utf8)
    if let req = try? CloudTranscriptionRequestBuilder.buildRequest(config: cfg, audioData: audio, fileName: "rec.m4a") {
        r.expectEqual(req.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        r.expectEqual(req.httpMethod, "POST")
        r.expectEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let ctype = req.value(forHTTPHeaderField: "Content-Type") ?? ""
        r.expect(ctype.hasPrefix("multipart/form-data; boundary="), "multipart content type with boundary")
        let bodyString = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        r.expect(bodyString.contains("name=\"model\""), "body has model field")
        r.expect(bodyString.contains("whisper-1"), "body has model value")
        r.expect(bodyString.contains("name=\"language\""), "body has language field")
        r.expect(bodyString.contains("zh"), "body has language hint")
        r.expect(bodyString.contains("name=\"file\"; filename=\"rec.m4a\""), "body has file part")
        r.expect(bodyString.contains("FAKE-AUDIO-BYTES"), "body embeds audio bytes")
    } else {
        r.expect(false, "request should build")
    }

    // No language hint when auto
    let autoCfg = CloudTranscriptionConfig(baseURL: "https://x/v1", model: "whisper-1", apiKey: "k", languageHint: nil)
    if let req = try? CloudTranscriptionRequestBuilder.buildRequest(config: autoCfg, audioData: audio, fileName: "a.m4a") {
        let bodyString = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        r.expect(!bodyString.contains("name=\"language\""), "no language field when auto")
    } else {
        r.expect(false, "auto request should build")
    }

    // Missing key throws
    r.expectThrows(TranscriptionError.missingAPIKey) {
        _ = try CloudTranscriptionRequestBuilder.buildRequest(
            config: CloudTranscriptionConfig(baseURL: "https://x/v1", model: "whisper-1", apiKey: ""),
            audioData: audio, fileName: "a.m4a")
    }
    // File too large
    r.expectThrows(TranscriptionError.fileTooLarge) {
        let small = CloudTranscriptionConfig(baseURL: "https://x/v1", model: "whisper-1", apiKey: "k", maxFileBytes: 4)
        _ = try CloudTranscriptionRequestBuilder.buildRequest(config: small, audioData: audio, fileName: "a.m4a")
    }

    r.suite("CloudTranscriptionParser")

    r.expectEqual(try? CloudTranscriptionParser.parseTranscript(from: Data(#"{"text":"你好世界"}"#.utf8)), "你好世界")
    var threwInvalid = false
    do { _ = try CloudTranscriptionParser.parseTranscript(from: Data("{}".utf8)) } catch { threwInvalid = true }
    r.expect(threwInvalid, "missing text -> invalidResponse")
    r.expectThrows(TranscriptionError.requestFailed(message: "bad")) {
        _ = try CloudTranscriptionParser.parseTranscript(from: Data(#"{"error":{"message":"bad"}}"#.utf8))
    }

    r.suite("URLSessionCloudTranscriber — HTTP mapping")

    let client = URLSessionCloudTranscriber(session: StubURLProtocol.session())
    let audioData = Data("AUDIO".utf8)

    StubURLProtocol.stub = .init(statusCode: 200, body: Data(#"{"text":"识别结果"}"#.utf8), error: nil)
    do {
        let text = try await client.transcribe(config: cfg, audioData: audioData, fileName: "a.m4a")
        r.expectEqual(text, "识别结果", "200 returns parsed text")
    } catch { r.expect(false, "200 should succeed: \(error)") }

    func expectMap(_ status: Int, _ expected: TranscriptionError) async {
        StubURLProtocol.stub = .init(statusCode: status, body: Data("{}".utf8), error: nil)
        await r.expectThrowsAsync(expected) {
            _ = try await client.transcribe(config: cfg, audioData: audioData, fileName: "a.m4a")
        }
    }
    await expectMap(401, .unauthorized)
    await expectMap(404, .unsupportedProvider)
    await expectMap(413, .fileTooLarge)
    await expectMap(415, .unsupportedFormat)
    await expectMap(429, .rateLimited)
    await expectMap(500, .serverError(status: 500, body: "{}"))

    StubURLProtocol.stub = .init(statusCode: 0, body: Data(), error: URLError(.notConnectedToInternet))
    await r.expectThrowsAsync(TranscriptionError.offline) {
        _ = try await client.transcribe(config: cfg, audioData: audioData, fileName: "a.m4a")
    }
    StubURLProtocol.stub = .init(statusCode: 0, body: Data(), error: URLError(.timedOut))
    await r.expectThrowsAsync(TranscriptionError.timedOut) {
        _ = try await client.transcribe(config: cfg, audioData: audioData, fileName: "a.m4a")
    }
}
