import SwiftUI
import MosaicKit

extension Color {
    /// Creates a color from a hex string like "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        } else {
            r = 0.04; g = 0.52; b = 1.0 // fallback blue
        }
        self.init(red: r, green: g, blue: b)
    }
}

/// Curated folder color/icon choices (PRD §4.1 名称 + 图标/颜色).
enum FolderPalette {
    static let colors: [String] = [
        "#0A84FF", "#FF375F", "#FF9F0A", "#30D158",
        "#5E5CE6", "#64D2FF", "#FF6482", "#BF5AF2", "#8E8E93"
    ]
    static let icons: [String] = [
        "folder.fill", "tray.full.fill", "book.fill", "graduationcap.fill",
        "briefcase.fill", "lightbulb.fill", "airplane", "heart.fill",
        "cart.fill", "star.fill", "doc.text.fill", "calendar"
    ]
}

extension BlockKind {
    var iconName: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo.fill"
        case .audio: return "waveform"
        case .file: return "doc.fill"
        case .link: return "link"
        }
    }

    var label: String {
        switch self {
        case .text: return "文字"
        case .image: return "图片"
        case .audio: return "录音"
        case .file: return "文档"
        case .link: return "链接"
        }
    }
}

enum Format {
    /// Relative "last modified" string (PRD §4.4 最后修改时间).
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Reusable empty-state with a call to action (PRD §4.1 空状态引导).
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
