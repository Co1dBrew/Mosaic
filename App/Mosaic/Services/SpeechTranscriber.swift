import Foundation
import Speech

/// On-device speech-to-text using the Speech framework (PRD §4.3.2 / §6.1).
/// `requiresOnDeviceRecognition = true` guarantees audio is never uploaded.
final class SpeechTranscriber {

    enum TranscriberError: LocalizedError {
        case notAuthorized
        case onDeviceUnavailable
        case recognizerUnavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "未获得语音识别权限,请在系统设置中开启。"
            case .onDeviceUnavailable: return "当前语言不支持离线识别,已跳过转写(为保护隐私不上传音频)。"
            case .recognizerUnavailable: return "语音识别暂不可用,请稍后重试。"
            case let .failed(msg): return "转写失败:\(msg)"
            }
        }
    }

    private let mediaStore: MediaStore
    private let preferredLocales: [Locale]

    init(mediaStore: MediaStore = .shared, preferredLocales: [Locale]? = nil) {
        self.mediaStore = mediaStore
        self.preferredLocales = preferredLocales ?? [
            Locale.current,
            Locale(identifier: "zh-CN"),
            Locale(identifier: "en-US")
        ]
    }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Picks the first available recognizer that supports on-device recognition.
    private func makeRecognizer() -> SFSpeechRecognizer? {
        for locale in preferredLocales {
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }

    /// Transcribes a recorded audio file. Throws a typed error on failure so the
    /// UI can show an actionable message while still saving the recording.
    func transcribe(relativePath: String) async throws -> String {
        guard await Self.requestAuthorization() else { throw TranscriberError.notAuthorized }
        guard let recognizer = makeRecognizer() else { throw TranscriberError.onDeviceUnavailable }

        let url = mediaStore.absoluteURL(for: relativePath)
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        // The result handler may fire multiple times; guard the continuation so
        // it resumes exactly once, synchronized in case callbacks ever overlap.
        let box = ResumeBox()
        return try await withCheckedThrowingContinuation { continuation in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if box.claim() { continuation.resume(throwing: TranscriberError.failed(error.localizedDescription)) }
                    return
                }
                guard let result, result.isFinal else { return }
                if box.claim() { continuation.resume(returning: result.bestTranscription.formattedString) }
            }
            box.retain(task) // keep the task alive until it finishes
        }
    }

    /// Thread-safe single-shot guard that also retains the recognition task.
    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private var task: SFSpeechRecognitionTask?

        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if resumed { return false }
            resumed = true
            return true
        }

        func retain(_ task: SFSpeechRecognitionTask) {
            lock.lock(); self.task = task; lock.unlock()
        }
    }
}
