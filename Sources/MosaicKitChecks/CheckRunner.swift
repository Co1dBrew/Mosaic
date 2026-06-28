import Foundation

/// A minimal assertion harness standing in for XCTest/Swift Testing, which are
/// unavailable in the Command Line Tools toolchain. Records pass/fail counts and
/// exits non-zero on any failure so it works as a CI gate.
final class CheckRunner {
    private(set) var passed = 0
    private(set) var failed = 0
    private var failures: [String] = []

    func suite(_ name: String) {
        print("\n▶ \(name)")
    }

    func expect(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
        if condition {
            passed += 1
        } else {
            failed += 1
            let msg = "  ✗ \(message)  [\(file):\(line)]"
            failures.append(msg)
            print(msg)
        }
    }

    func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #fileID, line: Int = #line) {
        expect(a == b, message.isEmpty ? "expected \(a) == \(b)" : "\(message) (got \(a), want \(b))", file: file, line: line)
    }

    func expectNil<T>(_ value: T?, _ message: String = "", file: String = #fileID, line: Int = #line) {
        expect(value == nil, message.isEmpty ? "expected nil, got \(String(describing: value))" : message, file: file, line: line)
    }

    func expectNotNil<T>(_ value: T?, _ message: String = "", file: String = #fileID, line: Int = #line) {
        expect(value != nil, message.isEmpty ? "expected non-nil" : message, file: file, line: line)
    }

    func expectThrows<E: Error & Equatable>(_ expected: E, _ message: String = "", file: String = #fileID, line: Int = #line, _ body: () throws -> Void) {
        do {
            try body()
            expect(false, message.isEmpty ? "expected throw \(expected)" : message, file: file, line: line)
        } catch let error as E {
            expectEqual(error, expected, message, file: file, line: line)
        } catch {
            expect(false, "threw \(error), wanted \(expected)", file: file, line: line)
        }
    }

    func expectThrowsAsync<E: Error & Equatable>(_ expected: E, _ message: String = "", file: String = #fileID, line: Int = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            expect(false, message.isEmpty ? "expected throw \(expected)" : message, file: file, line: line)
        } catch let error as E {
            expectEqual(error, expected, message, file: file, line: line)
        } catch {
            expect(false, "threw \(error), wanted \(expected)", file: file, line: line)
        }
    }

    func finish() -> Never {
        print("\n────────────────────────────────────────")
        if failed == 0 {
            print("✅ ALL CHECKS PASSED — \(passed) assertions")
            exit(0)
        } else {
            print("❌ \(failed) FAILED, \(passed) passed")
            exit(1)
        }
    }
}
