import SwiftUI

/// Recording UI: start / pause / resume / stop / cancel with live timer and
/// waveform (PRD §4.3.2).
struct AudioRecorderSheet: View {
    let onComplete: (AudioRecorderService.Recording) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recorder = AudioRecorderService()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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
            .task {
                do { try await recorder.start() }
                catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法开始录音" }
            }
            .interactiveDismissDisabled(recorder.isActive)
        }
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
