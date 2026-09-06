import AppKit
import SwiftUI
import WeiBeiCore

/// Ordered content uses native attachments in the same document while text is paced.
enum AgentNativeMessageContent {
    static func markdown(text: String, blocks: [AgentMessageContentBlock]) -> String {
        guard blocks.contains(where: { if case .text = $0 { return false }; return true }) else { return text }
        let hasText = blocks.contains { if case .text = $0 { return true }; return false }
        var remaining = text.count
        var result = hasText ? "" : text
        for (index, block) in blocks.enumerated() {
            switch block {
            case let .text(value):
                let count = min(remaining, value.count)
                result += value.prefix(count)
                remaining -= count
                if count < value.count { return result }
            case let .visualization(value):
                result += marker(value.id)
            case .unavailable:
                result += marker("unavailable-\(index)")
            }
        }
        // Text can advance between the existing throttled block publications.
        if hasText, remaining > 0 { result += text.suffix(remaining) }
        return result
    }

    private static func marker(_ id: String) -> String {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return "\n\n![图示](weibei-visualization:\(encoded))\n\n"
    }
}

struct AgentNativeContentAttachment: View {
    @EnvironmentObject private var store: WorkspaceStore
    let messageID: UUID
    let identifier: String
    let initialBlocks: [AgentMessageContentBlock]
    let onHeight: (CGFloat) -> Void

    private var blocks: [AgentMessageContentBlock] {
        store.messages.first(where: { $0.id == messageID })?.contentBlocks ?? initialBlocks
    }

    var body: some View {
        Group {
            if let visualization = blocks.compactMap({ block -> AgentVisualization? in
                if case let .visualization(value) = block, value.id == identifier { return value }
                return nil
            }).first {
                AgentVisualizationView(messageID: messageID, visualization: visualization)
            } else if identifier.hasPrefix("unavailable-"),
                      let index = Int(identifier.dropFirst("unavailable-".count)),
                      blocks.indices.contains(index),
                      case let .unavailable(type, rawJSON) = blocks[index] {
                UnavailableAgentContentBlockView(type: type, rawJSON: rawJSON)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { onHeight(geometry.size.height) }
                    .onChange(of: geometry.size.height) { _, height in onHeight(height) }
            }
        }
    }
}
