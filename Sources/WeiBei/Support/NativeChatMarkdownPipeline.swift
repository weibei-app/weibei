import Foundation
import WeiBeiCore

/// One worker and one replaceable pending snapshot. A completed result is published
/// before draining pending input, so continuous streaming cannot starve display.
@MainActor
final class NativeChatMarkdownPipeline {
    struct Snapshot: Equatable, Sendable {
        var markdown: String
        var messageID: UUID?
        var toggledCallouts: Set<Int> = []
        var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.markdown.utf16.elementsEqual(rhs.markdown.utf16) && lhs.messageID == rhs.messageID
                && lhs.toggledCallouts == rhs.toggledCallouts && lhs.interfaceLanguage == rhs.interfaceLanguage
        }
    }
    private var latest: Snapshot?
    private var pending: Snapshot?
    private var epoch = 0
    private var working = false
    private var displayed = NativeChatMarkdownDocument()
    var onApply: ((NativeChatMarkdownDocument, NativeChatMarkdownEdit) -> Void)?
    var parse: @Sendable (Snapshot) -> NativeChatMarkdownDocument = { NativeChatMarkdownParser.parse($0.markdown, toggledCallouts: $0.toggledCallouts, interfaceLanguage: $0.interfaceLanguage) }

    func submit(_ snapshot: Snapshot) {
        guard latest != snapshot else { return }
        if let latest, latest.messageID != snapshot.messageID || latest.toggledCallouts != snapshot.toggledCallouts || latest.interfaceLanguage != snapshot.interfaceLanguage || !snapshot.markdown.utf16.starts(with: latest.markdown.utf16) { epoch += 1 }
        latest = snapshot
        pending = snapshot
        drain()
    }

    func invalidate() { epoch += 1; pending = nil; latest = nil; onApply = nil }

    private func drain() {
        guard !working, let input = pending else { return }
        pending = nil; working = true
        let generation = epoch, baseline = displayed, parse = parse
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                let document = parse(input)
                return (document, NativeChatMarkdownEdit.between(baseline, document))
            }.value
            guard let self else { return }
            self.working = false
            if self.epoch == generation {
                self.displayed = result.0
                self.onApply?(result.0, result.1)
            }
            self.drain()
        }
    }
}
