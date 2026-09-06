import AppKit
import SwiftUI
import WeiBeiCore
import XCTest
@testable import WeiBei

final class NativeChatMarkdownTests: XCTestCase {
    // Continuous input must publish the already completed answer, then the latest snapshot.
    @MainActor func testPendingInputDoesNotStarveDisplay() async {
        let pipeline = NativeChatMarkdownPipeline()
        let started = expectation(description: "first parse started")
        let applied = expectation(description: "both snapshots displayed")
        applied.expectedFulfillmentCount = 2
        let gate = DispatchSemaphore(value: 0)
        let first = "中文 **回答** 和 $x^2$"
        let final = first + "\n\n最后一句。"
        pipeline.parse = { snapshot in
            if snapshot.markdown == first { started.fulfill(); gate.wait() }
            return NativeChatMarkdownParser.parse(snapshot.markdown)
        }
        var observed: [String] = []
        var visible = ""
        pipeline.onApply = { document, edit in
            let updated = NSMutableString(string: visible)
            updated.replaceCharacters(in: edit.range, with: edit.replacement.map(\.text).joined())
            visible = updated as String
            XCTAssertEqual(visible, document.text)
            observed.append(document.text)
            applied.fulfill()
        }
        let identity = UUID()
        pipeline.submit(.init(markdown: first, messageID: identity))
        await fulfillment(of: [started], timeout: 3)
        pipeline.submit(.init(markdown: first + "\n\n最后", messageID: identity))
        pipeline.submit(.init(markdown: final, messageID: identity))
        gate.signal()
        await fulfillment(of: [applied], timeout: 3)
        XCTAssertEqual(observed, [NativeChatMarkdownParser.parse(first).text, NativeChatMarkdownParser.parse(final).text])
    }

    // Rich syntax remains rich, while the same syntax inside code stays literal.
    func testRichContentAndCodeRemainDistinct() {
        let source = """
        # 标题
        中文 **重点**，[[笔记|别名]]，![[嵌入笔记]]，==标注==，^[补充]，$x^2$。

        **结尾。**继续，已有**“引用”**后文，**范围更广 **，后文。

        来源：资料名

        ```swift
        let value = "$x$ and [[literal]] **结尾。**继续"
        ```

        | 左 | 右 |
        | :--- | ---: |
        | **粗体** | $y$ |

        > [!note]- 标题
        > 收起的内容
        """
        let document = NativeChatMarkdownParser.parse(source)
        XCTAssertTrue(document.runs.contains { $0.style.bold && $0.text == "重点" })
        for text in ["结尾。", "“引用”", "范围更广"] {
            XCTAssertTrue(document.runs.contains { $0.style.bold && $0.text == text }, "Missing bold span: \(text); parsed: \(document.runs.filter { $0.style.bold }.map(\.text))")
        }
        XCTAssertTrue(document.runs.contains { $0.style.link?.hasPrefix("weibei-note:") == true })
        XCTAssertTrue(document.runs.contains { $0.text == "嵌入笔记" && $0.style.link?.hasPrefix("weibei-note:") == true })
        XCTAssertTrue(document.runs.contains { $0.text == "来源：资料名" && $0.style.link?.hasPrefix("weibei-source:") == true })
        XCTAssertTrue(document.runs.contains { $0.attachment == .math(latex: "x^2", display: false) })
        XCTAssertTrue(document.runs.contains {
            if case let .code(source, _) = $0.attachment { return source.contains("$x$ and [[literal]] **结尾。**继续") }
            return false
        })
        XCTAssertTrue(document.runs.contains {
            if case let .table(headers, rows, alignments) = $0.attachment {
                return headers.count == 2 && rows.count == 1 && alignments == ["left", "right"]
            }
            return false
        })
        XCTAssertFalse(document.text.contains("收起的内容"))
        XCTAssertTrue(NativeChatMarkdownParser.parse(source, toggledCallouts: [0]).text.contains("收起的内容"))
        XCTAssertEqual(NativeChatMarkdownParser.parse("普通\n换行").text, "普通 换行")
        XCTAssertTrue(NativeChatMarkdownParser.parse("[[|]]").runs.isEmpty)
        let before = NativeChatMarkdownParser.parse("中文🙂尾部")
        let after = NativeChatMarkdownParser.parse("中文🙂新增尾部")
        let edit = NativeChatMarkdownEdit.between(before, after)
        let applied = NSMutableString(string: before.text)
        applied.replaceCharacters(in: edit.range, with: edit.replacement.map(\.text).joined())
        XCTAssertEqual(applied as String, after.text)
        XCTAssertEqual(edit.mapSelection(NSRange(location: 0, length: 4)), NSRange(location: 0, length: 4))

        // Canonically equivalent characters can have different NSTextStorage lengths.
        let displayed = NSMutableString(string: "é")
        var previous = NativeChatMarkdownParser.parse(displayed as String)
        for source in ["e\u{301}x", "e\u{301}xy"] {
            let next = NativeChatMarkdownParser.parse(source)
            let change = NativeChatMarkdownEdit.between(previous, next)
            displayed.replaceCharacters(in: change.range, with: change.replacement.map(\.text).joined())
            XCTAssertTrue((displayed as String).utf16.elementsEqual(next.text.utf16))
            previous = next
        }
        XCTAssertNotEqual(NativeChatMarkdownPipeline.Snapshot(markdown: "é", messageID: nil),
                          NativeChatMarkdownPipeline.Snapshot(markdown: "e\u{301}", messageID: nil))
        let unresolved = NativeChatMarkdownParser.parse("[a][r]\n\nTARGET")
        let resolved = NativeChatMarkdownParser.parse("[a][r]\n\nTARGET\n\n[r]: https://example.com\n\nmore")
        let selection = (unresolved.text as NSString).range(of: "TARGET")
        let mapped = NativeChatMarkdownEdit.between(unresolved, resolved).mapSelection(selection)
        XCTAssertEqual((resolved.text as NSString).substring(with: mapped), "TARGET")
    }

    // A real offscreen text view must lay out rich content, keep its objects, and copy readable content.
    @MainActor func testNativeRichAnswerSurvivesResizeAndCompletion() async throws {
        _ = NSApplication.shared
        let textView = NativeChatTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 560, height: 900)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        let window = NSWindow(contentRect: textView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        defer { window.close() }
        let coordinator = NativeChatMarkdownView.Coordinator()
        coordinator.view = textView
        textView.delegate = coordinator
        let pixel = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l2cAAAAASUVORK5CYII="))
        coordinator.imageLoader = { _, completion in completion(pixel) }
        let codeSource = "    let answer = 42 // 中文🙂 <tag>&\n\n"
        let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let highlighted = NSMutableAttributedString(string: codeSource, attributes: [.font: codeFont])
        let tokens = try await NativeChatCodeHighlighter.shared.tokens(codeSource, language: "swift")
        NativeChatCodeHighlighter.apply(tokens, to: highlighted, font: codeFont, isDark: false)
        XCTAssertEqual(highlighted.string, codeSource)
        XCTAssertEqual(tokens.reduce(0) { $0 + $1.range.length }, codeSource.utf16.count)
        XCTAssertNotEqual(highlighted.attribute(.foregroundColor, at: (codeSource as NSString).range(of: "let").location, effectiveRange: nil) as? NSColor, WeiBeiNativePalette.ink())
        let source = """
        一段足够在窄窗口换行的中文回答，保留数学 $x^2$ 与正常的文字选择。

        ```swift
        \(codeSource)```

        | 项目 | 内容 |
        | --- | --- |
        | **公式** | $y$ |

        ![示意图](test-image.png)
        """
        let initial = expectation(description: "native answer applied")
        let completed = expectation(description: "completion applied to same view")
        var applications = 0
        coordinator.pipeline.onApply = { document, edit in
            coordinator.apply(document, edit: edit)
            applications += 1
            if applications == 1 { initial.fulfill() } else { completed.fulfill() }
        }
        defer { coordinator.pipeline.invalidate() }
        let messageID = UUID()
        coordinator.submit(markdown: source, messageID: messageID)
        await fulfillment(of: [initial], timeout: 5)
        let manager = try XCTUnwrap(textView.textLayoutManager)
        let storage = try XCTUnwrap(textView.textStorage)
        let firstHeight = coordinator.measuredHeight()
        XCTAssertTrue(firstHeight.isFinite && firstHeight > 0)
        textView.layoutSubtreeIfNeeded()
        func checkCodeAttachmentSize() {
            var checked = false
            manager.enumerateTextLayoutFragments(from: manager.textContentManager?.documentRange.location, options: [.ensuresLayout]) { fragment in
                for provider in fragment.textAttachmentViewProviders {
                    guard let attachment = provider.textAttachment as? NativeChatTextAttachment,
                          case .code = attachment.descriptor else { continue }
                    checked = true
                    let frame = fragment.frameForTextAttachment(at: provider.location)
                    XCTAssertEqual(frame.width, textView.frame.width, accuracy: 0.5)
                    XCTAssertGreaterThan(frame.height, CGFloat(codeSource.components(separatedBy: "\n").count) * coordinator.fontSize)
                    XCTAssertEqual(provider.view?.frame.size, frame.size)
                }
                return true
            }
            XCTAssertTrue(checked)
        }
        checkCodeAttachmentSize()
        var originalAttachments: [NativeChatTextAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? NativeChatTextAttachment { originalAttachments.append(attachment) }
        }
        XCTAssertEqual(originalAttachments.count, 4)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.setFrameSize(NSSize(width: 300, height: firstHeight))
        let narrowHeight = coordinator.measuredHeight()
        XCTAssertTrue(narrowHeight.isFinite && narrowHeight >= firstHeight)
        textView.layoutSubtreeIfNeeded()
        checkCodeAttachmentSize()
        coordinator.submit(markdown: source + "\n\n回答结束。", messageID: messageID)
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertTrue(coordinator.view === textView)
        XCTAssertTrue(textView.textLayoutManager === manager)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 4))
        var finalAttachments: [NativeChatTextAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? NativeChatTextAttachment { finalAttachments.append(attachment) }
        }
        XCTAssertEqual(finalAttachments.count, originalAttachments.count)
        XCTAssertTrue(zip(originalAttachments, finalAttachments).allSatisfy { $0 === $1 })
        textView.selectAll(nil)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(textView.writeSelection(to: pasteboard, type: .string))
        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("x^2") && copied.contains(codeSource) && copied.contains("示意图"))
        XCTAssertFalse(copied.contains("\u{fffc}"))
        XCTAssertFalse(window.isVisible)
    }


    // Completing an answer with no available note actions must not insert an empty footer.
    @MainActor func testCompletionKeepsActualMessageHeightWithoutNoteActions() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let source = "生成结束时，正文和阅读位置应保持不变。"
        var message = AgentMessage(role: .assistant, text: source, source: nil, completionState: .generating)
        store.messages = [message]
        XCTAssertNil(store.selectionContext)
        XCTAssertFalse(store.canReplaceNoteSelection)
        func bubble(_ value: AgentMessage) -> some View {
            AgentBubble(message: value,
                        liveStreamingText: value.completionState == .generating ? source : nil,
                        isStreaming: value.completionState == .generating)
                .environmentObject(store)
                .frame(width: 560)
        }
        let host = NSHostingView(rootView: bubble(message))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func nativeText(in view: NSView) -> NativeChatTextView? {
            if let text = view as? NativeChatTextView { return text }
            return view.subviews.lazy.compactMap { nativeText(in: $0) }.first
        }
        func settledHeight() async throws -> CGFloat {
            var previous: CGFloat = -1
            for _ in 0..<100 {
                try await Task.sleep(nanoseconds: 20_000_000)
                host.layoutSubtreeIfNeeded()
                let height = host.fittingSize.height
                if nativeText(in: host)?.string == source, abs(height - previous) < 0.1 { return height }
                previous = height
            }
            XCTFail("native message did not finish layout")
            return host.fittingSize.height
        }
        let before = try await settledHeight()
        let textView = try XCTUnwrap(nativeText(in: host))
        message.completionState = .completed
        store.messages = [message]
        host.rootView = bubble(message)
        let after = try await settledHeight()
        XCTAssertEqual(after, before, accuracy: 0.5)
        XCTAssertTrue(nativeText(in: host) === textView)
        XCTAssertFalse(window.isVisible)
    }

}
