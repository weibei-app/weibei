import Foundation

/// Normalizes formula delimiters and common model output for Markdown renderers.
enum AgentChatKaTeXMarkdown {
    private static let singleLineDisplayMath = try? NSRegularExpression(
        pattern: #"^[ \t]*\$\$([^$\n]+)\$\$[ \t]*$"#,
        options: [.anchorsMatchLines]
    )
    private static let bracketMultiLineMath = try? NSRegularExpression(
        pattern: #"\[\s*\n([\s\S]*?\\[A-Za-z]+[\s\S]*?)\n\s*\]"#
    )
    private static let bracketSingleLineMath = try? NSRegularExpression(
        pattern: #"(?m)^\[\s*([^\n\]]*?\\[A-Za-z]+[^\n\]]*?)\]\s*$"#
    )
    private static let hatSpacedArgument = try? NSRegularExpression(pattern: #"\\hat\s+([A-Za-z\\]+)"#)
    private static let hatGluedArgument = try? NSRegularExpression(pattern: #"\\hat(?!\{)(\\[A-Za-z]+|[A-Za-z])"#)

    static func prepare(_ raw: String) -> String {
        var text = raw
        text = convertBracketDisplayMath(in: text)
        text = expandSingleLineDisplayMath(in: text)
        text = fixHatArguments(in: text)
        return text
    }

    /// `$$x$$` on one line parses as INLINE math (micromark math flow needs the
    /// fences on their own lines), so block formulas stayed left-aligned at
    /// text size. Models emit the one-line form constantly — expand it so the
    /// editor produces a real math_block and the displayMode upgrade applies.
    static func expandSingleLineDisplayMath(in text: String) -> String {
        #if DEBUG
        assert(displayMathExpansionSelfCheckPassed, "single-line $$ expansion self-check failed")
        #endif
        guard text.contains("$$") else { return text }
        return expandSingleLineDisplayMathUnchecked(text)
    }

    #if DEBUG
    private static let displayMathExpansionSelfCheckPassed: Bool = {
        let expanded = expandSingleLineDisplayMathUnchecked("前文\n\n$$a + b$$\n\n后文 $c$ 与 $$d$$ 行内混排")
        return expanded.contains("$$\na + b\n$$")
            && expanded.contains("与 $$d$$ 行内混排")
    }()
    #endif

    private static func expandSingleLineDisplayMathUnchecked(_ text: String) -> String {
        guard let pattern = singleLineDisplayMath else { return text }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        for match in pattern.matches(in: text, range: fullRange).reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }
            let content = String(text[contentRange]).trimmingCharacters(in: .whitespaces)
            result.replaceSubrange(matchRange, with: "$$\n\(content)\n$$")
        }
        return result
    }

    /// Standalone `[ ... \cmd ... ]` (single- or multi-line) → `$$...$$`.
    /// Citations like `[材料：…]` are stripped before this runs.
    private static func convertBracketDisplayMath(in text: String) -> String {
        var result = text
        if let multi = bracketMultiLineMath {
            result = replaceMatches(in: result, regex: multi) { match in
                "$$\n\(match)\n$$"
            }
        }
        if let single = bracketSingleLineMath {
            result = replaceMatches(in: result, regex: single) { match in
                "$$\(match)$$"
            }
        }
        return result
    }

    /// `\hat\beta` / `\hat y` → `\hat{\beta}` / `\hat{y}` (KaTeX-friendly).
    private static func fixHatArguments(in text: String) -> String {
        var result = text
        if let spaced = hatSpacedArgument {
            result = replaceMatches(in: result, regex: spaced) { match in
                "\\hat{\(match)}"
            }
        }
        if let glued = hatGluedArgument {
            result = replaceMatches(in: result, regex: glued) { match in
                "\\hat{\(match)}"
            }
        }
        return result
    }

    private static func replaceMatches(
        in text: String,
        regex: NSRegularExpression,
        transform: (String) -> String
    ) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return text }
        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let full = Range(match.range, in: output),
                  let capture = Range(match.range(at: 1), in: output) else { continue }
            let inner = String(output[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
            output.replaceSubrange(full, with: transform(inner))
        }
        return output
    }
}
