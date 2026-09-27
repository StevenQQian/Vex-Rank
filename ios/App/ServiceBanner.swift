import SwiftUI
import VEXRankKit

/// The strip above the tab bar that carries whatever the service has to say:
/// that a newer build exists, or a note for readers.
///
/// It sits in a `safeAreaInset` rather than inside a screen so it survives
/// navigation - a reader who is three pushes deep into an event should still
/// see it, and no individual screen should have to know it exists.
@available(iOS 17.0, *)
struct ServiceBanner: View {
    @Environment(\.vexTheme) private var theme
    @Environment(\.openURL) private var openURL
    let store: AppConfigStore

    var body: some View {
        if let update = store.pendingUpdate {
            banner(
                icon: store.updateStatus == .required ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill",
                title: store.updateStatus == .required ? "Update required" : "Update available",
                detail: update.notes ?? update.version.map { "Version \($0) is ready to install." },
                action: update.link.map { link in ("Get it", { openURL(link) }) },
                // A required update is the one thing here that does not go
                // away on its own.
                dismiss: store.updateStatus == .required ? nil : { store.dismissUpdate() }
            )
        } else if let note = store.pendingAnnouncement {
            banner(
                icon: "megaphone.fill",
                title: note.title,
                detail: note.body,
                action: note.link.map { link in ("Open", { openURL(link) }) },
                dismiss: { store.dismissAnnouncement(note.id) }
            )
        }
    }

    private func banner(icon: String,
                        title: String,
                        detail: String?,
                        action: (label: String, run: () -> Void)?,
                        dismiss: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(theme.accent)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // Notes come from the service and can be any length.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action {
                Button(action.label, action: action.run)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            }

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.accent.opacity(0.35)))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

@available(iOS 17.0, *)
extension View {
    /// Puts the banner above the tab bar.
    ///
    /// It goes on each tab's `NavigationStack` rather than once on the
    /// `TabView`, because an inset on the `TabView` is laid out against the
    /// window and draws across the tab bar - the labels end up behind it.
    func serviceBanner(_ store: AppConfigStore) -> some View {
        safeAreaInset(edge: .bottom) {
            ServiceBanner(store: store)
                .animation(.snappy, value: store.pendingUpdate)
        }
    }
}
