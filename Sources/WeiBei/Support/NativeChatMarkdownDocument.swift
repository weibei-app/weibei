import Foundation
import Markdown
import WeiBeiCore

enum NativeChatAttachmentDescriptor: Hashable, Sendable {
    case math(latex: String, display: Bool)
    case code(source: String, language: String?)
    case table(headers: [String], rows: [[String]], alignments: [String])
    case image(source: String, alt: String)
    case visualization(id: String)

    func sameKind(as other: Self) -> Bool {
        switch (self, other) {
        case (.math, .math), (.code, .code), (.table, .table), (.image, .image), (.visualization, .visualization): return true
        default: return false
        }
    }
}

struct NativeChatMarkdownStyle: Equatable, Sendable {
    var heading = 0
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var highlight = false
    var footnote = false
    var quote = 0
    var callout: String?
    var indent = 0
    var link: String?
}

struct NativeChatMarkdownRun: Equatable, Sendable {
    var text: String
    var style = NativeChatMarkdownStyle()
    var attachment: NativeChatAttachmentDescriptor?
    var utf16Count: Int { text.utf16.count }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text.utf16.elementsEqual(rhs.text.utf16) && lhs.style == rhs.style && lhs.attachment == rhs.attachment
    }
}

struct NativeChatMarkdownDocument: Equatable, Sendable {
    var runs: [NativeChatMarkdownRun] = []
    var text: String { runs.map(\.text).joined() }
    var utf16Count: Int { runs.reduce(0) { $0 + $1.utf16Count } }
}

/// The background compares value data; AppKit only receives the changed span.
struct NativeChatMarkdownEdit: Sendable {
    var range: NSRange
    var replacement: [NativeChatMarkdownRun]
    private var removedOffsets: [Int]
    private var insertedOffsets: [Int]

    static func between(_ old: NativeChatMarkdownDocument, _ new: NativeChatMarkdownDocument) -> Self {
        var prefix = 0
        while prefix < min(old.runs.count, new.runs.count), old.runs[prefix] == new.runs[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.runs.count, new.runs.count) - prefix,
              old.runs[old.runs.count - 1 - suffix] == new.runs[new.runs.count - 1 - suffix] { suffix += 1 }
        var location = old.runs.prefix(prefix).reduce(0) { $0 + $1.utf16Count }
        var removed = Array(old.runs[prefix..<(old.runs.count - suffix)])
        var inserted = Array(new.runs[prefix..<(new.runs.count - suffix)])
        // A growing paragraph keeps its existing characters and attributes.
        if let a = removed.first, let b = inserted.first, a.style == b.style, a.attachment == nil, b.attachment == nil {
            let shared = zip(a.text, b.text).prefix { $0.unicodeScalars.elementsEqual($1.unicodeScalars) }.map(\.0)
            let count = String(shared).utf16.count
            location += count
            removed[0].text = String(a.text.dropFirst(shared.count))
            inserted[0].text = String(b.text.dropFirst(shared.count))
        }
        if let a = removed.last, let b = inserted.last, a.style == b.style, a.attachment == nil, b.attachment == nil {
            let shared = zip(a.text.reversed(), b.text.reversed()).prefix { $0.unicodeScalars.elementsEqual($1.unicodeScalars) }.count
            removed[removed.count - 1].text = String(a.text.dropLast(shared))
            inserted[inserted.count - 1].text = String(b.text.dropLast(shared))
        }
        let oldUnits = Array(removed.map(\.text).joined().utf16)
        let newUnits = Array(inserted.map(\.text).joined().utf16)
        var removals: [Int] = [], insertions: [Int] = []
        if !oldUnits.isEmpty && !newUnits.isEmpty && oldUnits != newUnits {
            for change in newUnits.difference(from: oldUnits) {
                switch change {
                case let .remove(offset, _, _): removals.append(offset)
                case let .insert(offset, _, _): insertions.append(offset)
                }
            }
        }
        return Self(range: NSRange(location: location, length: oldUnits.count), replacement: inserted.filter { !$0.text.isEmpty },
                    removedOffsets: removals.sorted(), insertedOffsets: insertions.sorted())
    }

    func mapSelection(_ selection: NSRange) -> NSRange {
        let newLength = replacement.reduce(0) { $0 + $1.utf16Count }
        func position(_ offset: Int, afterInsertion: Bool) -> Int {
            if offset < range.location { return offset }
            if offset > NSMaxRange(range) { return offset + newLength - range.length }
            if range.length == 0 { return range.location + (afterInsertion ? newLength : 0) }
            if newLength == 0 { return range.location }
            let local = offset - range.location
            var mapped = local - removedOffsets.prefix { $0 < local }.count
            for insertion in insertedOffsets {
                guard insertion < mapped || (insertion == mapped && afterInsertion) else { break }
                mapped += 1
            }
            return range.location + mapped
        }
        let start = position(selection.location, afterInsertion: selection.length > 0)
        return NSRange(location: start, length: max(0, position(NSMaxRange(selection), afterInsertion: false) - start))
    }
}

enum NativeChatMarkdownParser {
    static func parse(_ source: String, toggledCallouts: Set<Int> = [], interfaceLanguage: WeiBeiInterfaceLanguage = .chinese) -> NativeChatMarkdownDocument {
        var parser = Builder(toggledCallouts: toggledCallouts, interfaceLanguage: interfaceLanguage)
        let prepared = parser.prepare(source)
        parser.visit(Document(parsing: prepared), style: .init())
        while parser.runs.last?.text == "\n" { parser.runs.removeLast() }
        return NativeChatMarkdownDocument(runs: parser.runs)
    }

    private struct Builder {
        var runs: [NativeChatMarkdownRun] = []
        var tokens: [NativeChatMarkdownRun] = []
        var tokenSources: [String] = []
        var toggledCallouts: Set<Int> = []
        var calloutIndex = 0
        var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
        private static let sourceReference = try! NSRegularExpression(pattern: #"(?:^|[\s`])((?:来源：|Source:)[^`\n]+)"#)
        // Match the editor's emphasis boundary rules for Chinese punctuation.
        private static let emphasisRules: [(NSRegularExpression, String)] = [
            (#"([\p{L}\p{N}])(\*\*|__)(?=\p{P})"#, "$1 $2"),
            (#"(^|[\s\p{P}])(\*\*|__)([^\s*_\n][^*_\n]*\p{P})\2(?=[^\s\p{P}])"#, "$1$2$3$2 "),
            (#"(^|[\s\p{P}])(\*\*|__)([^\s*_\n](?:[^*_\n]*?\S)?)[ \t]+\2(?=\S)"#, "$1$2$3$2")
        ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

        private func normalizeEmphasis(_ source: String) -> String {
            Self.emphasisRules.reduce(source) { text, rule in
                rule.0.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count), withTemplate: rule.1)
            }
        }
        mutating func append(_ text: String, _ style: NativeChatMarkdownStyle, attachment: NativeChatAttachmentDescriptor? = nil) {
            guard !text.isEmpty else { return }
            runs.append(.init(text: text, style: style, attachment: attachment))
        }
        mutating func appendText(_ text: String, _ style: NativeChatMarkdownStyle) {
            let source = text as NSString
            var cursor = 0
            for match in Self.sourceReference.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                let range = match.range(at: 1)
                append(source.substring(with: NSRange(location: cursor, length: range.location - cursor)), style)
                let reference = source.substring(with: range)
                var linked = style
                linked.link = "weibei-source:" + (reference.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reference)
                append(reference, linked)
                cursor = NSMaxRange(range)
            }
            append(source.substring(from: cursor), style)
        }
        mutating func attachment(_ descriptor: NativeChatAttachmentDescriptor, _ style: NativeChatMarkdownStyle) {
            append("\u{fffc}", style, attachment: descriptor)
        }
        mutating func newline() { if !runs.isEmpty && runs.last?.text != "\n" { append("\n", .init()) } }

        mutating func visit(_ node: any Markup, style: NativeChatMarkdownStyle) {
            var s = style
            switch node {
            case let text as Markdown.Text: appendText(text.string, s)
            case is SoftBreak: append(" ", s)
            case is LineBreak: append("\n", s)
            case let code as InlineCode: s.code = true; append(code.code, s)
            case is Strong: s.bold = true; children(node, s)
            case is Emphasis: s.italic = true; children(node, s)
            case is Strikethrough: s.strike = true; children(node, s)
            case let heading as Heading:
                newline(); s.heading = heading.level; children(node, s); newline()
            case let link as Markdown.Link:
                if let destination = link.destination, destination.hasPrefix("weibei-native-token:"),
                   let index = Int(destination.dropFirst("weibei-native-token:".count)), tokens.indices.contains(index) {
                    var token = tokens[index]
                    token.style.heading = s.heading; token.style.quote = s.quote; token.style.indent = s.indent
                    token.style.callout = s.callout; token.style.strike = s.strike
                    if token.style.link == nil { token.style.link = s.link }
                    token.style.bold = token.style.bold || s.bold; token.style.italic = token.style.italic || s.italic
                    if !token.text.isEmpty { runs.append(token) }
                } else { s.link = link.destination; children(node, s) }
            case let image as Markdown.Image:
                let src = image.source ?? ""
                if src.hasPrefix("weibei-visualization:") { attachment(.visualization(id: String(src.dropFirst("weibei-visualization:".count))), s) }
                else { attachment(.image(source: src, alt: image.plainText), s) }
            case let code as CodeBlock:
                newline(); attachment(.code(source: code.code, language: code.language), s); newline()
            case let table as Markdown.Table:
                newline()
                let headers = Array(table.head.cells.map { $0.children.map { $0.format() }.joined() }).map { restoreExtensions($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                let rows = Array(table.body.rows.map { row in Array(row.cells.map { $0.children.map { $0.format() }.joined() }) }).map { row in row.map { restoreExtensions($0).trimmingCharacters(in: .whitespacesAndNewlines) } }
                let alignments = table.columnAlignments.map { alignment in
                    switch alignment { case .left: return "left"; case .center: return "center"; case .right: return "right"; default: return "left" }
                }
                attachment(.table(headers: headers, rows: rows, alignments: alignments), s); newline()
            case let quote as BlockQuote:
                newline(); s.quote += 1
                if !callout(quote, style: s) { children(node, s) }
                newline()
            case let list as OrderedList:
                newline()
                for (index, item) in list.listItems.enumerated() { listItem(item, marker: "\(list.startIndex + UInt(index)).", style: s) }
            case let list as UnorderedList:
                newline()
                for item in list.listItems { listItem(item, marker: "•", style: s) }
            case is ThematicBreak: newline(); append("────────────────", s); newline()
            case is Paragraph:
                children(node, s); newline()
            case let html as InlineHTML: append(html.rawHTML, s)
            case let html as HTMLBlock: append(html.rawHTML, s); newline()
            default: children(node, s)
            }
        }
        mutating func children(_ node: any Markup, _ style: NativeChatMarkdownStyle) { for child in node.children { visit(child, style: style) } }
        mutating func listItem(_ item: ListItem, marker: String, style: NativeChatMarkdownStyle) {
            var s = style; s.indent += 1
            let bullet = item.checkbox.map { $0 == .checked ? "☑" : "☐" } ?? marker
            append("\(bullet)\t", s); children(item, s); newline()
        }

        func restoreExtensions(_ value: String) -> String {
            var restored = value
            for (index, source) in tokenSources.enumerated() {
                restored = restored.replacingOccurrences(of: "[扩展](weibei-native-token:\(index))", with: source)
            }
            return restored
        }

        mutating func callout(_ quote: BlockQuote, style: NativeChatMarkdownStyle) -> Bool {
            guard let paragraph = quote.child(at: 0) as? Paragraph else { return false }
            let first = paragraph.children.prefix { !($0 is SoftBreak) && !($0 is LineBreak) }
                .compactMap { ($0 as? any PlainTextConvertibleMarkup)?.plainText }.joined()
            guard !first.isEmpty,
                  let regex = try? NSRegularExpression(pattern: #"^\[!([A-Za-z][A-Za-z0-9_-]*)\]([+-]?)(?:[ \t]+(.+))?$"#),
                  let match = regex.firstMatch(in: String(first), range: NSRange(location: 0, length: String(first).utf16.count)) else { return false }
            let header = String(first) as NSString
            let kind = header.substring(with: match.range(at: 1)).lowercased()
            let fold = header.substring(with: match.range(at: 2))
            let labels = ["note": "札记", "tip": "提示", "important": "重点", "warning": "留心", "caution": "谨慎", "summary": "提要", "abstract": "摘要", "quote": "引文", "question": "问题", "example": "例子", "info": "信息", "success": "可行", "failure": "失败", "danger": "风险", "bug": "问题", "todo": "待办"]
            let defaultTitle = interfaceLanguage.text(labels[kind] ?? kind, kind.prefix(1).uppercased() + kind.dropFirst())
            let title = match.range(at: 3).location == NSNotFound ? defaultTitle : header.substring(with: match.range(at: 3))
            let id = calloutIndex; calloutIndex += 1
            let collapsed = (fold == "-") != toggledCallouts.contains(id)
            var s = style; s.callout = kind; s.bold = true
            if !fold.isEmpty { s.link = "weibei-callout:\(id)" }
            append((fold.isEmpty ? "" : (collapsed ? "▸ " : "▾ ")) + title, s); newline()
            guard !collapsed else { return true }
            s.bold = style.bold; s.link = style.link
            var passedHeader = false
            for child in paragraph.children {
                if !passedHeader {
                    if child is SoftBreak || child is LineBreak { passedHeader = true }
                } else { visit(child, style: s) }
            }
            newline()
            for child in quote.children.dropFirst() { visit(child, style: s) }
            return true
        }

        /// Only the extensions absent from CommonMark are tokenized. Code remains untouched.
        mutating func prepare(_ source: String) -> String {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var lineOffsets = [0]
            for line in lines { lineOffsets.append(lineOffsets.last! + line.utf16.count + 1) }
            func offset(_ location: SourceLocation) -> Int {
                let line = lines[min(location.line - 1, lines.count - 1)]
                let bytes = line.utf8.prefix(max(0, location.column - 1))
                return lineOffsets[min(location.line - 1, lines.count - 1)] + String(decoding: bytes, as: UTF8.self).utf16.count
            }
            var protected: [NSRange] = []
            func protect(_ node: any Markup) {
                if node is CodeBlock || node is InlineCode, let range = node.range {
                    protected.append(NSRange(location: offset(range.lowerBound), length: offset(range.upperBound) - offset(range.lowerBound)))
                } else { for child in node.children { protect(child) } }
            }
            protect(Document(parsing: source))
            let original = source as NSString
            var normalized = "", previousEnd = 0
            var normalizedCodeRanges: [NSRange] = []
            for range in protected.sorted(by: { $0.location < $1.location }) {
                normalized += normalizeEmphasis(original.substring(with: NSRange(location: previousEnd, length: range.location - previousEnd)))
                normalizedCodeRanges.append(NSRange(location: normalized.utf16.count, length: range.length))
                normalized += original.substring(with: range)
                previousEnd = NSMaxRange(range)
            }
            normalized += normalizeEmphasis(original.substring(from: previousEnd))
            protected = normalizedCodeRanges
            let pattern = #"(?s)(?<!\\)\$\$(.+?)\$\$|(?<!\\)\\\[(.+?)\\\]|(?<!\\)\\\((.+?)\\\)|(?<!\\)\$(?!\s)([^$\n]+?)\$(?!\d)|(?<!\\)(!?)\[\[([^\]\n]+)\]\]|(?<!\\)==([^=\n]+)==|(?<!\\)\^\[([^\]\n]+)\]|(?m:^[ \t]*\[[ \t]*\n?([^\]]*?\\[A-Za-z]+[^\]]*?)\][ \t]*$)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return normalized }
            let ns = normalized as NSString
            var output = "", cursor = 0
            for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let raw = ns.substring(with: match.range)
                func capture(_ index: Int) -> String? { match.range(at: index).location == NSNotFound ? nil : ns.substring(with: match.range(at: index)) }
                var token = NativeChatMarkdownRun(text: "")
                if protected.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { output += raw; cursor = NSMaxRange(match.range); continue }
                if let math = capture(1) ?? capture(2) ?? capture(3) ?? capture(4) ?? capture(9) {
                    token.text = "\u{fffc}"; token.attachment = .math(latex: AgentChatKaTeXMarkdown.prepare(math.trimmingCharacters(in: .whitespacesAndNewlines)), display: capture(1) != nil || capture(2) != nil || capture(9) != nil)
                } else if let wiki = capture(6) {
                    let parts = wiki.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                    let target = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let label = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : target
                    if capture(5) == "!", target.range(of: #"\.(png|jpe?g|gif|webp|svg|heic)(?:[?#].*)?$"#, options: .regularExpression) != nil {
                        token.text = "\u{fffc}"; token.attachment = .image(source: target, alt: label)
                    } else {
                        token.text = label; token.style.link = "weibei-note:" + (target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target)
                    }
                } else if let highlight = capture(7) { token.text = highlight; token.style.highlight = true }
                else if let footnote = capture(8) { token.text = footnote; token.style.footnote = true }
                output += "[扩展](weibei-native-token:\(tokens.count))"; tokens.append(token); tokenSources.append(raw)
                cursor = NSMaxRange(match.range)
            }
            output += ns.substring(from: cursor)
            return output
        }
    }
}
