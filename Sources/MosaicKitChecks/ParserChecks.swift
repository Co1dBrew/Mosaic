import Foundation
import MosaicKit

func runParserChecks(_ r: CheckRunner) {
    r.suite("AIResponseParser — JSON extraction")

    r.expectEqual(AIResponseParser.extractJSONObject(from: #"{"a":1}"#), #"{"a":1}"#)

    let fenced = "```json\n{\"a\":1}\n```"
    r.expectEqual(AIResponseParser.extractJSONObject(from: fenced), #"{"a":1}"#)

    let bareFence = "```\n{\"a\":1}\n```"
    r.expectEqual(AIResponseParser.extractJSONObject(from: bareFence), #"{"a":1}"#)

    let prose = "好的,这是结果:\n{\"a\":1}\n希望有帮助"
    r.expectEqual(AIResponseParser.extractJSONObject(from: prose), #"{"a":1}"#)

    let nested = #"{"a":{"b":2},"c":3}"#
    r.expectEqual(AIResponseParser.extractJSONObject(from: nested), nested)

    // Braces inside string values must not break balancing.
    let braceInString = #"{"a":"text with } brace","b":1}"#
    r.expectEqual(AIResponseParser.extractJSONObject(from: braceInString), braceInString)

    // Escaped quote inside string.
    let escaped = #"{"a":"he said \"hi\" }","b":2}"#
    r.expectEqual(AIResponseParser.extractJSONObject(from: escaped), escaped)

    r.expectNil(AIResponseParser.extractJSONObject(from: "no json here"))
    r.expectNil(AIResponseParser.extractJSONObject(from: #"{"a":1"#), "unbalanced returns nil")
    r.expectNil(AIResponseParser.extractJSONObject(from: ""))

    r.suite("AIResponseParser — Chat envelope")

    let normal = #"{"choices":[{"message":{"content":"{\"title\":\"x\"}"}}]}"#.data(using: .utf8)!
    r.expectEqual(try? AIResponseParser.messageContent(from: normal), #"{"title":"x"}"#)

    // content as array of parts
    let arrayContent = #"{"choices":[{"message":{"content":[{"type":"text","text":"he"},{"type":"text","text":"llo"}]}}]}"#.data(using: .utf8)!
    r.expectEqual(try? AIResponseParser.messageContent(from: arrayContent), "hello")

    // API error envelope
    let apiErr = #"{"error":{"message":"bad key","type":"auth"}}"#.data(using: .utf8)!
    r.expectThrows(AIError.requestFailed(message: "bad key")) {
        _ = try AIResponseParser.messageContent(from: apiErr)
    }

    // Empty choices
    let empty = #"{"choices":[]}"#.data(using: .utf8)!
    var threw = false
    do { _ = try AIResponseParser.messageContent(from: empty) } catch { threw = true }
    r.expect(threw, "empty choices throws")

    r.suite("AIResponseParser — typed payloads")

    let baseJSON = """
    {"title":"周三评审","one_liner":"概述","type":"会议记录","topics":["a","b"],"key_points":["p1","p2"],"summary":"整体总结内容"}
    """
    if let dto = try? AIResponseParser.parseBaseSummary(fromMessage: baseJSON) {
        r.expectEqual(dto.title, "周三评审")
        r.expectEqual(dto.topics, ["a", "b"])
        r.expectEqual(dto.keyPoints.count, 2)
    } else {
        r.expect(false, "valid base summary should parse")
    }

    // Fenced base summary
    let fencedBase = "```json\n" + baseJSON + "\n```"
    r.expectNotNil(try? AIResponseParser.parseBaseSummary(fromMessage: fencedBase))

    // Missing fields default; topics as single string tolerated
    let partial = #"{"title":"只有标题","topics":"单个主题"}"#
    if let dto = try? AIResponseParser.parseBaseSummary(fromMessage: partial) {
        r.expectEqual(dto.title, "只有标题")
        r.expectEqual(dto.topics, ["单个主题"], "single string coerced to array")
        r.expectEqual(dto.summary, "", "missing field defaults to empty")
    } else {
        r.expect(false, "partial base summary should still parse")
    }

    // null arrays tolerated
    let nulls = #"{"title":"t","one_liner":"o","summary":"s","topics":null,"key_points":null}"#
    r.expectNotNil(try? AIResponseParser.parseBaseSummary(fromMessage: nulls))

    // Completely empty object -> invalidJSON
    r.expectThrows(AIError.invalidJSON(raw: "{}")) {
        _ = try AIResponseParser.parseBaseSummary(fromMessage: "{}")
    }

    // Update payload
    let upd = #"{"update_one_liner":"改了排期","changes":["新增 A","删除 B"]}"#
    if let dto = try? AIResponseParser.parseUpdateSummary(fromMessage: upd) {
        r.expectEqual(dto.updateOneLiner, "改了排期")
        r.expectEqual(dto.changes.count, 2)
    } else {
        r.expect(false, "valid update summary should parse")
    }
}
