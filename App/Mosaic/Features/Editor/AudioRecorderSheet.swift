import SwiftUI
import MosaicKit

/// Recording UI: start / pause / resume / stop / cancel with live timer and
/// waveform (PRD §4.3.2).
struct AudioRecorderSheet: View {
    let onComplete: (AudioRecorderService.Recording) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recorder = AudioRecorderService()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            // Stage G：权限被拒时给的是**可操作的界面**，不是一句「无法开始录音」。
            // `permissionDenied` 这个状态一直存在，但此前 UI 从来没有消费它。
            if recorder.permissionDenied {
                PermissionDeniedView(kind: .microphone,
                                     status: recorder.microphonePermission,
                                     onRequest: { Task { await retryAfterPermissionChange() } },
                                     onCancel: { dismiss() })
                    .navigationTitle("录音")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                recordingBody
            }
        }
    }

    private var recordingBody: some View {
            VStack(spacing: 28) {
                Spacer()

                Text(Format.duration(recorder.elapsed))
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()

                WaveformView(samples: recorder.waveform, progress: 1)
                    .frame(height: 60)
                    .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Spacer()

                HStack(spacing: 40) {
                    Button(role: .destructive) {
                        recorder.cancel(); dismiss()
                    } label: {
                        Label("取消", systemImage: "xmark").labelStyle(.iconOnly).font(.title2)
                    }
                    .frame(width: 60, height: 60)

                    mainButton

                    Button {
                        if let recording = recorder.stop() { onComplete(recording) }
                        dismiss()
                    } label: {
                        Label("完成", systemImage: "checkmark").labelStyle(.iconOnly).font(.title2)
                    }
                    .frame(width: 60, height: 60)
                    .disabled(!recorder.isActive)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("录音")
            .navigationBarTitleDisplayMode(.inline)
            .task { await startRecording() }
            .interactiveDismissDisabled(recorder.isActive)
    }

    private func startRecording() async {
        errorMessage = nil
        do { try await recorder.start() }
        catch AudioRecorderService.RecorderError.permissionDenied {
            // 权限被拒**不是**一条错误消息 —— 它有专门的界面（上面那一支）。
            // 走到这里只需要让状态刷新一次。
            recorder.refreshPermissionState()
        }
        catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法开始录音" }
    }

    /// 用户从系统设置回来（或第一次点「允许访问」）之后重试。
    private func retryAfterPermissionChange() async {
        recorder.refreshPermissionState()
        guard !recorder.permissionDenied else { return }
        await startRecording()
    }

    @ViewBuilder private var mainButton: some View {
        if recorder.isRecording {
            Button { recorder.pause() } label: {
                Image(systemName: "pause.fill").font(.system(size: 32)).foregroundStyle(.white)
                    .frame(width: 80, height: 80).background(Color.red).clipShape(Circle())
            }
        } else if recorder.isPaused {
            Button { recorder.resume() } label: {
                Image(systemName: "mic.fill").font(.system(size: 32)).foregroundStyle(.white)
                    .frame(width: 80, height: 80).background(Color.accentColor).clipShape(Circle())
            }
        } else {
            ProgressView().frame(width: 80, height: 80)
        }
    }
}
