import Foundation
import AVFoundation
import Observation
import MosaicKit

/// Records audio to the sandbox using AVFoundation (PRD §4.3.2): start / pause /
/// resume / stop, with elapsed time and a simple waveform from metering.
@MainActor
@Observable
final class AudioRecorderService {
    enum State: Equatable { case idle, recording, paused }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var waveform: [Double] = []
    private(set) var permissionDenied = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var currentRelativePath: String?
    @ObservationIgnored private let mediaStore: MediaStore

    init(mediaStore: MediaStore = .shared) {
        self.mediaStore = mediaStore
    }

    var isRecording: Bool { state == .recording }
    var isPaused: Bool { state == .paused }
    var isActive: Bool { state != .idle }

    /// 当前的麦克风权限。**不发起请求**，只读系统的记录 ——
    /// 界面要在弹窗之前就知道该显示「允许访问」还是「去设置」。
    var microphonePermission: PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:       return .granted
        case .denied:        return .denied
        case .undetermined:  return .notDetermined
        @unknown default:    return .notDetermined
        }
    }

    /// Requests microphone permission (PRD privacy / Info.plist usage string).
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// 用户可能刚从系统设置里改过权限。重新读一次并清掉旧的拒绝标记 ——
    /// 界面停在「权限已关闭」会让人以为设置没生效。
    func refreshPermissionState() {
        permissionDenied = (microphonePermission == .denied)
    }

    func start() async throws {
        guard state == .idle else { return }
        let granted = await requestPermission()
        guard granted else { permissionDenied = true; throw RecorderError.permissionDenied }
        permissionDenied = false

        let session = AVAudioSession.sharedInstance()
        // `.allowBluetooth` 在 iOS 26 SDK 里改名为 `.allowBluetoothHFP`（同一个值）。
        // 新名字是**回溯可用**的（部署目标 iOS 17 下编译通过），所以直接用新名字，
        // 不需要 `#available` 分支 —— 留分支反而会让旧名字继续报废弃警告。
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let relative = mediaStore.makeRelativePath(kind: .audio, ext: "m4a")
        let url = mediaStore.absoluteURL(for: relative)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        self.currentRelativePath = relative
        self.elapsed = 0
        self.waveform = []
        self.state = .recording
        startMeterTimer()
    }

    func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
        meterTimer?.invalidate()
    }

    func resume() {
        guard state == .paused, let recorder else { return }
        if recorder.record() {
            state = .recording
            startMeterTimer()
        }
    }

    struct Recording {
        let relativePath: String
        let duration: TimeInterval
        let waveform: [Double]
    }

    /// Stops and finalizes the recording, returning its metadata.
    func stop() -> Recording? {
        guard let recorder, let relative = currentRelativePath else { resetSession(); return nil }
        let duration = recorder.currentTime
        recorder.stop()
        meterTimer?.invalidate()
        let result = Recording(relativePath: relative, duration: max(duration, elapsed), waveform: waveform)
        resetSession()
        return result
    }

    /// Cancels recording and deletes the partial file.
    func cancel() {
        if let relative = currentRelativePath {
            recorder?.stop()
            mediaStore.delete(relative)
        }
        meterTimer?.invalidate()
        resetSession()
    }

    private func resetSession() {
        recorder = nil
        currentRelativePath = nil
        state = .idle
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMeterTimer() {
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func tick() {
        guard let recorder, state == .recording else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        let power = Double(recorder.averagePower(forChannel: 0)) // dBFS, -160...0
        let normalized = max(0, min(1, pow(10, power / 20)))     // ~amplitude 0...1
        waveform.append(normalized)
        // Cap stored samples to keep memory bounded.
        if waveform.count > 600 { waveform.removeFirst(waveform.count - 600) }
    }

    enum RecorderError: LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "未获得麦克风权限,请在系统设置中开启。"
            case .couldNotStart: return "无法开始录音,请重试。"
            }
        }
    }
}
