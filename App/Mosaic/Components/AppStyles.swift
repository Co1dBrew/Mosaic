import SwiftUI

// MARK: - Design tokens

/// Consistent spacing scale — avoids magic numbers across views.
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum AppRadius {
    static let chip: CGFloat = 8
    static let button: CGFloat = 12
    static let card: CGFloat = 14
}

enum AppMetrics {
    /// Apple HIG minimum tappable size.
    static let minTapTarget: CGFloat = 44
}

// MARK: - Button styles (all center their label and meet the 44pt tap target)

/// Filled, high-emphasis action. Full width by default so the label is always
/// horizontally centered; vertically centered via the min-height frame.
struct PrimaryActionButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: AppMetrics.minTapTarget)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Tinted, medium-emphasis action.
struct SecondaryActionButtonStyle: ButtonStyle {
    var fullWidth: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: AppMetrics.minTapTarget)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.28 : 0.14))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Tinted destructive action.
struct DestructiveActionButtonStyle: ButtonStyle {
    var fullWidth: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: AppMetrics.minTapTarget)
            .background(Color.red.opacity(configuration.isPressed ? 0.28 : 0.14))
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: - Convenience action buttons (the unified components to use everywhere)

struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var fullWidth: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) { label }
            .buttonStyle(PrimaryActionButtonStyle(fullWidth: fullWidth))
    }
    @ViewBuilder private var label: some View {
        if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
    }
}

struct SecondaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var fullWidth: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { label }
            .buttonStyle(SecondaryActionButtonStyle(fullWidth: fullWidth))
    }
    @ViewBuilder private var label: some View {
        if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
    }
}

struct DestructiveActionButton: View {
    let title: String
    var systemImage: String? = nil
    var fullWidth: Bool = false
    let action: () -> Void
    var body: some View {
        Button(role: .destructive, action: action) { label }
            .buttonStyle(DestructiveActionButtonStyle(fullWidth: fullWidth))
    }
    @ViewBuilder private var label: some View {
        if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
    }
}

// MARK: - Card container

struct AppCardStyle: ViewModifier {
    var background: Color = Color(.secondarySystemGroupedBackground)
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.md)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

extension View {
    func appCard(background: Color = Color(.secondarySystemGroupedBackground)) -> some View {
        modifier(AppCardStyle(background: background))
    }

    /// Small uppercase-ish section label used inside cards (e.g. 初始总结/更新记录).
    func appSectionLabel() -> some View {
        self.font(.caption).bold().foregroundStyle(.secondary)
    }
}
