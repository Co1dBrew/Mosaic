import Foundation
import MosaicKit

/// Orchestrates speech-to-text across the two modes (PRD §4.3.2 + upgrade):
/// - `.localAppleSpeech` → `SpeechTranscriber` (on-device, audio never leaves the
///   device), with locales chosen from the user's language preference.
/// - `.cloudAPI` → `CloudTranscriber` (uploads audio to a third-party STT service);
///   requires explicit audio-upload consent.
///
/// Model mutations happen on the caller (main actor); audio file reads and the
/// network request run off the main thread.
@MainActor
final class TranscriptionService {
    private let settings: SettingsStore
    private let cloud: CloudTranscriber
    private let mediaStore: MediaStore

    init(settings: SettingsStore,
         cloud: CloudTranscriber = URLSessionCloudTranscriber(),
         mediaStore: MediaStore = .shared) {
        self.settings = settings
        self.cloud = cloud
        self.mediaStore = mediaStore
    }

    var mode: TranscriptionMode { settings.transcriptionMode }

    /// True when the next transcription would upload audio but consent hasn't been
    /// granted yet — the UI must show the audio-upload notice first.
    var needsAudioUploadConsent: Bool {
        settings.transcriptionMode == .cloudAPI && !settings.hasAcceptedAudioUploadNotice
    }

    func transcribe(relativePath: String) async throws -> String {
        switch settings.transcriptionMode {
        case .localAppleSpeech: return try await transcribeLocal(relativePath: relativePath)
        case .cloudAPI:         return try await transcribeCloud(relativePath: relativePath)
        }
    }

    // MARK: Local

    private func transcribeLocal(relativePath: String) async throws -> String {
        let ids = settings.transcriptionLanguage.appleLocales(systemLocaleIdentifier: Locale.current.identifier)
        let local = SpeechTranscriber(mediaStore: mediaStore, preferredLocales: ids.map { Locale(identifier: $0) })
        do {
            return try await local.transcribe(relativePath: relativePath)
        } catch let error as SpeechTranscriber.TranscriberError {
            switch error {
            case .notAuthorized: throw TranscriptionError.notAuthorized
            case .onDeviceUnavailable, .recognizerUnavailable: throw TranscriptionError.localUnavailable
            case let .failed(message): throw TranscriptionError.requestFailed(message: message)
            }
        }
    }

    // MARK: Cloud

    private func transcribeCloud(relativePath: String) async throws -> String {
        // Never upload audio without explicit consent.
        guard settings.hasAcceptedAudioUploadNotice else { throw TranscriptionError.consentMissing }

        let config: CloudTranscriptionConfig
        switch settings.makeCloudTranscriptionConfig() {
        case let .success(value): config = value
        case let .failure(error): throw error
        }

        let url = mediaStore.absoluteURL(for: relativePath)
        let fileName = (relativePath as NSString).lastPathComponent
        let data: Data
        do {
            data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
        } catch {
            throw TranscriptionError.audioUnreadable
        }
        return try await cloud.transcribe(config: config, audioData: data, fileName: fileName)
    }
}
