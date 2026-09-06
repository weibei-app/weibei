import Foundation

/// Session-scoped first-frame height seeds for finalized agent Markdown rows.
/// The bucket never proves measurement success at the current exact width.
enum AgentFinalizedMarkdownHeightCache {
    static let capacity = 256
    private static let lock = NSLock()
    private static var values: [String: CGFloat] = [:]
    private static var recentlyUsed: [String] = []

    static func height(for key: String) -> CGFloat? {
        lock.lock(); defer { lock.unlock() }
        guard let height = values[key] else { return nil }
        touchLocked(key)
        return height
    }

    static func store(_ height: CGFloat, for key: String) {
        // Called only after the real message row is measured. Store the
        // raw measured value, including legitimate <=44pt short block content;
        // the synthetic 44pt SwiftUI loading frame never reaches this method.
        guard height.isFinite, height > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if let existing = values[key], abs(existing - height) < 2 {
            touchLocked(key)
            return
        }
        values[key] = height
        touchLocked(key)
        evictLocked()
    }

    static func cacheKey(messageID: UUID?, text: String, widthBucket: Int, wideTypography: Bool, textScale: CGFloat = 1) -> String {
        let id = messageID?.uuidString ?? "anon"
        let content = text.hashValue
        let tier = wideTypography ? "wide" : "compact"
        return "\(id):\(content):w\(widthBucket):\(tier):s\(textScale)"
    }

    static func widthBucket(_ width: CGFloat) -> Int {
        max(Int((width / 24.0).rounded(.down)) * 24, 0)
    }

    static func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        values.removeAll()
        recentlyUsed.removeAll()
    }

    static var storedKeyCountForTesting: Int {
        lock.lock(); defer { lock.unlock() }
        return values.count
    }

    private static func touchLocked(_ key: String) {
        recentlyUsed.removeAll { $0 == key }
        recentlyUsed.append(key)
    }

    private static func evictLocked() {
        while recentlyUsed.count > capacity {
            let stale = recentlyUsed.removeFirst()
            values.removeValue(forKey: stale)
        }
    }
}
