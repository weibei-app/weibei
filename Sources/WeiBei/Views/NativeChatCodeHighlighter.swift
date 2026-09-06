import AppKit
import JavaScriptCore

/// Reuses the pinned Highlight.js grammars without Foundation's HTML importer.
actor NativeChatCodeHighlighter {
    static let shared = NativeChatCodeHighlighter()
    struct Token: Sendable {
        let range: NSRange
        let scopes: [String]
    }
    enum Failure: Error { case missingResource, invalidTokens, javascript(String) }
    private var tokenize: JSValue?

    func tokens(_ source: String, language: String?) throws -> [Token] {
        try Task.checkCancellation()
        if tokenize == nil {
            guard let script = WeiBeiResources.bundle.url(forResource: "highlight.min", withExtension: "js"),
                  let context = JSContext() else { throw Failure.missingResource }
            context.evaluateScript(try String(contentsOf: script, encoding: .utf8))
            if let error = context.exception { throw Failure.javascript(error.toString()) }
            // The pinned Highlight.js 11.9 emitter already walks nested scopes and
            // embedded languages. Only convert its text leaves to UTF-16 ranges.
            tokenize = context.evaluateScript("""
            (function(source, language) {
                const result = language ? hljs.highlight(source, { language, ignoreIllegals: true }) : hljs.highlightAuto(source);
                const tokens = [], scopes = result.language ? ["language:" + result.language] : [];
                let offset = 0, original = '';
                result._emitter.walk({
                    openNode(node) { if (node.scope) scopes.push(node.scope); },
                    closeNode(node) { if (node.scope) scopes.pop(); },
                    addText(text) {
                        tokens.push([offset, text.length, scopes.slice()]);
                        offset += text.length;
                        original += text;
                    }
                });
                if (original !== source) throw new Error('Highlight token text differs from source');
                return tokens;
            })
            """)
        }
        guard let tokenize else { throw Failure.invalidTokens }
        tokenize.context.exception = nil
        let result = tokenize.call(withArguments: [source, language ?? ""])
        if let error = tokenize.context.exception { throw Failure.javascript(error.toString()) }
        guard let rows = result?.toArray() as? [[Any]] else { throw Failure.invalidTokens }
        let sourceLength = source.utf16.count
        return try rows.map { row in
            guard row.count == 3, let location = row[0] as? Int, let length = row[1] as? Int,
                  let scopes = row[2] as? [String], location >= 0, length >= 0,
                  location + length <= sourceLength else { throw Failure.invalidTokens }
            return Token(range: NSRange(location: location, length: length), scopes: scopes)
        }
    }

    @MainActor static func apply(_ tokens: [Token], to storage: NSMutableAttributedString,
                                 font: NSFont, isDark: Bool) {
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes([.font: font, .foregroundColor: WeiBeiNativePalette.ink()],
                              range: NSRange(location: 0, length: storage.length))
        for token in tokens {
            var attributes: [NSAttributedString.Key: Any] = [:]
            var traits: NSFontTraitMask = []
            for scope in token.scopes {
                if let hex = color(scope, ancestors: token.scopes, isDark: isDark) {
                    attributes[.foregroundColor] = NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
                        green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
                }
                if scope == "strong" || scope == "doctag" { traits.insert(.boldFontMask) }
                if scope == "emphasis" || scope == "formula" { traits.insert(.italicFontMask) }
            }
            if !traits.isEmpty { attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits) }
            storage.addAttributes(attributes, range: token.range)
        }
    }

    // Exact token colors from the existing HighlightSwift Xcode light/dark themes.
    private static func color(_ scope: String, ancestors: [String], isDark: Bool) -> UInt32? {
        let base = scope.split(separator: ".").first.map(String.init) ?? scope
        if base == "meta", ancestors.contains("language:xml") { return isDark ? 0x6c7986 : 0xc0c0c0 }
        if base == "title", ancestors.contains("class") || scope.hasPrefix("title.class") { return isDark ? 0xd0a8ff : 0x5c2699 }
        switch base {
        case "comment", "quote": return isDark ? 0x6c7986 : 0x007400
        case "attribute", "keyword", "literal", "name", "selector-tag", "tag": return isDark ? 0xfc5fa3 : 0xaa0d91
        case "template-variable", "variable": return isDark ? 0xfc5fa3 : 0x3f6e74
        case "code", "string", "meta-string": return isDark ? 0xfc6a5d : 0xc41a16
        case "link", "regexp": return isDark ? 0x5482ff : 0x0e0eff
        case "bullet", "number", "symbol", "title": return isDark ? 0x41a1c0 : 0x1c00cf
        case "meta", "section": return isDark ? 0xfc5fa3 : 0x643820
        case "built_in", "builtin-name", "params", "type": return isDark ? 0xd0a8ff : 0x5c2699
        case "attr": return isDark ? 0xbf8555 : 0x836c28
        case "subst": return isDark ? 0xffffff : 0x000000
        case "selector-class", "selector-id": return 0x9b703f
        default: return nil
        }
    }
}
