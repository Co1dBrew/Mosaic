import SwiftUI
import UIKit
import MosaicKit

/// One collapsed card bar (PRD §4.4): title, one-line AI summary, content-type
/// icons, last-modified time, disclosure triangle, and unread-update dot.
struct CardRowView: View {
    let card: Card
    let isExpanded: Bool
    let onOpen: () -> Void
    let onToggleExpand: () -> Void

    private var oneLiner: String? {
        guard let s = card.summary, s.hasBase else { return nil }
        let t = s.baseOneLiner.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var unreadCount: Int {
        (card.summary?.updateLogs ?? []).filter { !$0.isRead }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if let oneLiner {
                            Text(oneLiner)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        HStack(spacing: 10) {
                            ForEach(card.presentKinds, id: \.self) { kind in
                                Image(systemName: kind.iconName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(Format.relative(card.updatedAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onToggleExpand) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                        if unreadCount > 0 {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if isExpanded {
                Divider().padding(.horizontal, 12)
                SummaryStickerView(card: card)
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}
