import SwiftUI

/// A measured distant row keeps the document's height while its native view is released.
struct AgentMessagePlaceholderRow: View {
    var height: CGFloat

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: max(height, 1))
            .accessibilityHidden(true)
    }
}

/// Preserve the current row height until the same answer is mounted again nearby.
struct AgentMessageViewportGatedRow<Content: View>: View {
    var isPlaceholder: Bool
    var placeholderHeight: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isPlaceholder, let placeholderHeight, placeholderHeight > 0 {
            AgentMessagePlaceholderRow(height: placeholderHeight)
        } else {
            content()
        }
    }
}
