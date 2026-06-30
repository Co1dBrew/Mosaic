import SwiftUI
import UIKit

/// Audio block: playback with scrubbing + transcript view/edit (PRD §4.3.2).
struct AudioBlockView: View {
    @Bindable var block: Block
    let player: AudioPlayerService
    let isTranscribing: Bool
    var transcriptionError: String? = nil
    let onEdit: () -> Void
    let onRetranscribe: () -> Void

    @State private var showTranscript = false

    private var isCurrent: Bool { player.loadedPath == block.audioRelativePath }
    private var progress: Double {
        guard isCurrent, player.duration > 0 else { return 0 }
        return player.currentTime / player.duration
    }
    private var displayDuration: TimeInterval {
        isCurrent && player.duration > 0 ? player.duration : block.durationSec
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    player.toggle(relativePath: block.audioRelativePath)
                } label: {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: AppMetrics.minTapTarget, height: AppMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCurrent && player.isPlaying ? "暂停" : "播放")

                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        WaveformView(samples: block.waveformSamples, progress: progress)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard isCurrent, displayDuration > 0, geo.size.width > 0 else { return }
                                        let fraction = max(0, min(1, value.location.x / geo.size.width))
                                        player.seek(to: fraction * displayDuration)
                                    }
                            )
                    }
                    .frame(height: 28)
                    HStack {
                        Text(Format.duration(isCurrent ? player.currentTime : 0))
                        Spacer()
                        Text(Format.duration(displayDuration))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            // Transcription status (visible without expanding).
            if isTranscribing {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("转写中…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let transcriptionError {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Label(transcriptionError, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    SecondaryActionButton(title: "重试", systemImage: "arrow.clockwise") { onRetranscribe() }
                }
            }

            DisclosureGroup(isExpanded: $showTranscript) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    TextField("转写文字(可编辑)", text: $block.transcript, axis: .vertical)
                        .font(.caption)
                        .lineLimit(1...10)
                        .onChange(of: block.transcript) { _, _ in onEdit() }
                    SecondaryActionButton(title: "重新转写", systemImage: "arrow.clockwise") { onRetranscribe() }
                        .disabled(isTranscribing)
                }
                .padding(.top, AppSpacing.xs)
            } label: {
                Label(block.transcript.isEmpty ? "转写稿(空)" : "转写稿", systemImage: "text.quote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.md)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }
}

/// Minimal static waveform rendering from stored amplitude samples.
struct WaveformView: View {
    let samples: [Double]
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let bars = downsample(to: max(1, Int(geo.size.width / 4)))
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                    let fraction = bars.isEmpty ? 0 : Double(index) / Double(bars.count)
                    Capsule()
                        .fill(fraction <= progress ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 2, height: max(2, CGFloat(value) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func downsample(to count: Int) -> [Double] {
        guard !samples.isEmpty, count > 0 else { return Array(repeating: 0.1, count: max(1, count)) }
        if samples.count <= count { return samples }
        let bucket = Double(samples.count) / Double(count)
        return (0..<count).map { i in
            let start = Int(Double(i) * bucket)
            let end = min(samples.count, Int(Double(i + 1) * bucket))
            let slice = samples[start..<max(start + 1, end)]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }
}
