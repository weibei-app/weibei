import AppKit
import SwiftMath
import SwiftUI
import WeiBeiCore

@MainActor
final class NativeChatTextAttachment: NSTextAttachment {
    typealias VisualizationView = (String, CGFloat, @escaping (CGFloat) -> Void) -> NSView?
    typealias ImageLoader = (String, @escaping (Data?) -> Void) -> Void
    private(set) var descriptor: NativeChatAttachmentDescriptor
    private(set) var fontSize: CGFloat
    private(set) var isDark: Bool
    private(set) var interfaceLanguage: WeiBeiInterfaceLanguage
    private var appearanceMode = WeiBeiNativePalette.current
    private let providers = NSHashTable<NativeChatAttachmentProvider>.weakObjects()
    let onOpenURL: (URL) -> Void
    let onSizeChange: () -> Void
    let visualizationView: VisualizationView?
    let imageLoader: ImageLoader?

    init(descriptor: NativeChatAttachmentDescriptor, fontSize: CGFloat, isDark: Bool,
         onOpenURL: @escaping (URL) -> Void, onSizeChange: @escaping () -> Void,
         visualizationView: VisualizationView? = nil, imageLoader: ImageLoader? = nil,
         interfaceLanguage: WeiBeiInterfaceLanguage = .chinese) {
        self.descriptor = descriptor
        self.fontSize = fontSize
        self.isDark = isDark
        self.interfaceLanguage = interfaceLanguage
        self.onOpenURL = onOpenURL
        self.onSizeChange = onSizeChange
        self.visualizationView = visualizationView
        self.imageLoader = imageLoader
        super.init(data: nil, ofType: "com.weibei.chat-attachment")
        allowsTextAttachmentView = true
    }
    required init?(coder: NSCoder) { nil }

    func update(fontSize: CGFloat, isDark: Bool, interfaceLanguage: WeiBeiInterfaceLanguage? = nil) {
        update(descriptor: descriptor, fontSize: fontSize, isDark: isDark, interfaceLanguage: interfaceLanguage)
    }

    func update(descriptor: NativeChatAttachmentDescriptor) {
        update(descriptor: descriptor, fontSize: fontSize, isDark: isDark)
    }

    func update(descriptor: NativeChatAttachmentDescriptor, fontSize: CGFloat, isDark: Bool,
                interfaceLanguage: WeiBeiInterfaceLanguage? = nil) {
        let language = interfaceLanguage ?? self.interfaceLanguage
        guard language != self.interfaceLanguage || self.descriptor != descriptor || self.fontSize != fontSize || self.isDark != isDark || appearanceMode != WeiBeiNativePalette.current else { return }
        appearanceMode = WeiBeiNativePalette.current
        self.interfaceLanguage = language
        let old = self.descriptor
        self.descriptor = descriptor
        self.fontSize = fontSize
        self.isDark = isDark
        for provider in providers.allObjects {
            (provider.view as? NativeChatAttachmentView)?.update(from: old)
        }
        onSizeChange()
    }

    var readableText: String {
        switch descriptor {
        case let .math(latex, _): return latex
        case let .code(source, _): return source
        case let .table(headers, rows, _): return ([headers] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
        case let .image(source, alt): return alt.isEmpty ? source : "\(alt) (\(source))"
        case let .visualization(id): return id
        }
    }

    override func viewProvider(for parentView: NSView?, location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = NativeChatAttachmentProvider(textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location)
        provider.tracksTextAttachmentViewBounds = true
        providers.add(provider)
        return provider
    }
}

@MainActor
private final class NativeChatAttachmentProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? NativeChatTextAttachment else { return }
        view = NativeChatAttachmentView(attachment)
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
        textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        if view == nil { loadView() }
        guard let content = view as? NativeChatAttachmentView else { return .zero }
        let width = max(1, textContainer.map { $0.size.width - 2 * $0.lineFragmentPadding } ?? proposedLineFragment.width)
        let size = content.size(for: width)
        let inline = content.isInlineMath
        let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: content.attachment.fontSize)
        return CGRect(x: 0, y: inline ? (font.xHeight - size.height) / 2 : 0, width: size.width, height: size.height)
    }
}

@MainActor
private final class NativeChatAttachmentView: NSView, NSTextViewDelegate {
    let attachment: NativeChatTextAttachment
    private let scroll = NativeChatHorizontalScrollView()
    private let document = NativeChatFlippedView()
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let caption = NSTextField(labelWithString: "")
    private var math: MTMathUILabel?
    private var code: NSTextView?
    private var mermaid: NSHostingView<NativeChatMermaidPreview>?
    private var mermaidHeight: CGFloat = 44
    private var cells: [[NSTextView]] = []
    private var columnWidths: [CGFloat] = []
    private var tableHeight: CGFloat?
    private var picture: NSImageView?
    private var external: NSView?
    private var externalHeight: CGFloat = 160
    private var naturalSize = NSSize(width: 1, height: 1)
    private var imageTaskStarted = false
    private var highlightTask: Task<Void, Never>?
    override var isFlipped: Bool { true }
    var isInlineMath: Bool {
        if case .math(_, false) = attachment.descriptor { return true }
        return false
    }

    private var isMermaid: Bool {
        if case let .code(_, language) = attachment.descriptor { return language?.lowercased() == "mermaid" }
        return false
    }

    init(_ attachment: NativeChatTextAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        appearance = NSAppearance(named: attachment.isDark ? .darkAqua : .aqua)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)
        copyButton.target = self
        copyButton.action = #selector(copyContent)
        copyButton.bezelStyle = .inline
        copyButton.font = .systemFont(ofSize: 11)
        addSubview(copyButton)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = WeiBeiNativePalette.secondaryInk()
        addSubview(caption)
        setAccessibilityLabel(attachment.readableText)
        configure()
        applyColors()
    }
    required init?(coder: NSCoder) { nil }
    deinit { highlightTask?.cancel() }

    func update(from previous: NativeChatAttachmentDescriptor) {
        appearance = NSAppearance(named: attachment.isDark ? .darkAqua : .aqua)
        setAccessibilityLabel(attachment.readableText)
        highlightTask?.cancel()
        if isMermaid, let mermaid, case let .code(source, _) = attachment.descriptor {
            caption.stringValue = attachment.interfaceLanguage.text("流程图 · Mermaid", "Mermaid diagram")
            mermaid.rootView = mermaidPreview(source)
        } else if !isMermaid, case let .code(oldSource, _) = previous,
           case let .code(source, language) = attachment.descriptor, let code, let storage = code.textStorage {
            let edit = NativeChatMarkdownEdit.between(
                .init(runs: [.init(text: oldSource)]), .init(runs: [.init(text: source)]))
            let selection = edit.mapSelection(code.selectedRange())
            storage.replaceCharacters(in: edit.range, with: edit.replacement.map(\.text).joined())
            storage.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: attachment.fontSize - 1, weight: .regular),
                                   .foregroundColor: WeiBeiNativePalette.ink()], range: NSRange(location: 0, length: storage.length))
            code.setSelectedRange(selection)
            caption.stringValue = language ?? attachment.interfaceLanguage.text("代码", "Code")
            naturalSize = storage.size()
            naturalSize.height = CGFloat(source.components(separatedBy: "\n").count) * ceil(attachment.fontSize * 1.4)
            highlightTask = Task { [weak self] in await self?.highlight(source, language: language) }
        } else {
            document.subviews.forEach { $0.removeFromSuperview() }
            math = nil
            code = nil
            mermaid = nil
            cells = []
            columnWidths = []
            tableHeight = nil
            picture = nil
            external = nil
            imageTaskStarted = false
            copyButton.isHidden = false
            caption.isHidden = false
            configure()
        }
        applyColors()
        needsLayout = true
    }

    private func applyColors() {
        copyButton.title = attachment.interfaceLanguage.text("复制", "Copy")
        caption.textColor = WeiBeiNativePalette.secondaryInk()
        wantsLayer = true
        if case .code = attachment.descriptor { layer?.backgroundColor = WeiBeiNativePalette.codePaper().cgColor }
        else { layer?.backgroundColor = NSColor.clear.cgColor }
    }

    private func configure() {
        switch attachment.descriptor {
        case let .math(latex, display):
            let label = MTMathUILabel()
            let font = MTFontManager().latinModernFont(withSize: attachment.fontSize)
            font?.fallbackFont = NSFont.systemFont(ofSize: attachment.fontSize)
            label.font = font
            label.latex = latex
            label.labelMode = display ? .display : .text
            label.textColor = WeiBeiNativePalette.ink()
            label.displayErrorInline = true
            math = label
            naturalSize = label.intrinsicContentSize
            document.addSubview(label)
            copyButton.isHidden = !display
            caption.isHidden = true
        case let .code(source, language):
            if isMermaid {
                caption.stringValue = attachment.interfaceLanguage.text("流程图 · Mermaid", "Mermaid diagram")
                let host = NSHostingView(rootView: mermaidPreview(source))
                host.sizingOptions = []
                mermaid = host
                document.addSubview(host)
                break
            }
            caption.stringValue = language ?? attachment.interfaceLanguage.text("代码", "Code")
            let text = makeText(NSAttributedString(string: source, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: attachment.fontSize - 1, weight: .regular),
                .foregroundColor: WeiBeiNativePalette.ink()]))
            code = text
            document.addSubview(text)
            naturalSize = text.textStorage!.size()
            naturalSize.height = CGFloat(source.components(separatedBy: "\n").count) * ceil(attachment.fontSize * 1.4)
            // Tokenize with the existing grammars off the main thread; the source remains selectable.
            highlightTask = Task { [weak self] in
                guard let self else { return }
                await self.highlight(source, language: language)
            }
        case let .table(headers, rows, alignments):
            caption.stringValue = attachment.interfaceLanguage.text("表格", "Table")
            let contents = [headers] + rows
            let count = contents.map(\.count).max() ?? 0
            columnWidths = Array(repeating: 96, count: count)
            for (rowIndex, row) in contents.enumerated() {
                var views: [NSTextView] = []
                for index in 0..<count {
                    let source = index < row.count ? row[index] : ""
                    weak var cellView: NSTextView?
                    let value = NativeChatInlineAttributedString(source, fontSize: attachment.fontSize,
                        isDark: attachment.isDark, onOpenURL: attachment.onOpenURL,
                        onSizeChange: { [weak self] in
                            if let manager = cellView?.textLayoutManager,
                               let range = manager.textContentManager?.documentRange {
                                manager.invalidateLayout(for: range)
                            }
                            self?.tableHeight = nil
                            self?.attachment.onSizeChange()
                        }, imageLoader: attachment.imageLoader, interfaceLanguage: attachment.interfaceLanguage)
                    let mutable = NSMutableAttributedString(attributedString: value)
                    let paragraph = NSMutableParagraphStyle()
                    if index < alignments.count {
                        paragraph.alignment = alignments[index] == "center" ? .center : alignments[index] == "right" ? .right : .left
                    }
                    mutable.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length))
                    if rowIndex == 0 {
                        mutable.addAttribute(.backgroundColor, value: WeiBeiNativePalette.codePaper(), range: NSRange(location: 0, length: mutable.length))
                    }
                    let cell = makeText(mutable)
                    cellView = cell
                    document.addSubview(cell)
                    views.append(cell)
                    columnWidths[index] = min(320, max(columnWidths[index], ceil(value.size().width) + 24))
                }
                cells.append(views)
            }
        case let .image(_, alt):
            caption.stringValue = alt
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.setAccessibilityLabel(alt)
            imageView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openImage)))
            picture = imageView
            document.addSubview(imageView)
            naturalSize = NSSize(width: 240, height: 60)
        case .visualization:
            copyButton.isHidden = true
            caption.isHidden = true
        }
    }

    private func mermaidPreview(_ source: String) -> NativeChatMermaidPreview {
        NativeChatMermaidPreview(source: source, appearanceMode: WeiBeiNativePalette.current,
            interfaceLanguage: attachment.interfaceLanguage,
            textScale: attachment.fontSize / 14,
            onHeight: { [weak self] height in
                guard let self, height.isFinite, height > 0 else { return }
                let measured = max(44, ceil(height))
                guard abs(measured - self.mermaidHeight) > 0.5 else { return }
                self.mermaidHeight = measured
                self.attachment.onSizeChange()
            }, onFailure: { [weak self] in
                guard let self else { return }
                self.caption.stringValue = self.attachment.interfaceLanguage.text("流程图未能加载", "Could not load diagram")
            })
    }

    private func highlight(_ source: String, language: String?) async {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let tokens = try await NativeChatCodeHighlighter.shared.tokens(source, language: language)
            guard !Task.isCancelled, let storage = code?.textStorage else { return }
            NativeChatCodeHighlighter.apply(tokens, to: storage,
                font: .monospacedSystemFont(ofSize: attachment.fontSize - 1, weight: .regular),
                isDark: attachment.isDark)
        } catch {
            caption.toolTip = attachment.interfaceLanguage.text("此代码语言无法高亮：", "Could not highlight this language: ") + error.localizedDescription
        }
    }

    private func makeText(_ value: NSAttributedString) -> NSTextView {
        let text = NativeChatTextView(usingTextLayoutManager: true)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textStorage?.setAttributedString(value)
        text.delegate = self
        return text
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { attachment.onOpenURL(url); return true }
        if let string = link as? String, let url = URL(string: string) { attachment.onOpenURL(url); return true }
        return false
    }

    func size(for width: CGFloat) -> NSSize {
        let chrome: CGFloat = isInlineMath ? 0 : 28
        switch attachment.descriptor {
        case .math:
            return NSSize(width: isInlineMath ? min(width, ceil(naturalSize.width)) : width,
                          height: ceil(naturalSize.height) + chrome + (naturalSize.width > width ? 12 : 0))
        case .code:
            return NSSize(width: width, height: mermaid == nil ? ceil(naturalSize.height) + chrome + 24 : mermaidHeight + chrome)
        case .table:
            let height = layoutTable()
            return NSSize(width: width, height: height + chrome + 16)
        case let .image(source, _):
            if !imageTaskStarted {
                imageTaskStarted = true
                attachment.imageLoader?(source) { [weak self] data in
                    guard let self, case let .image(currentSource, _) = self.attachment.descriptor,
                          currentSource == source else { return }
                    guard let data, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
                        self.caption.stringValue = self.attachment.interfaceLanguage.text("图片未能加载", "Could not load image") + " · " + self.attachment.readableText
                        return
                    }
                    self.picture?.image = image
                    self.naturalSize = image.size
                    self.attachment.onSizeChange()
                }
            }
            let shownWidth = min(width, naturalSize.width)
            return NSSize(width: width, height: ceil(shownWidth * naturalSize.height / naturalSize.width) + chrome)
        case let .visualization(id):
            if external == nil {
                let newView = attachment.visualizationView?(id, width) { [weak self] height in
                    guard let self, height.isFinite, height > 0, abs(height - self.externalHeight) > 0.5 else { return }
                    self.externalHeight = height
                    self.attachment.onSizeChange()
                }
                if newView !== external {
                    external?.removeFromSuperview()
                    external = newView
                    if let newView { document.addSubview(newView) }
                }
            }
            return NSSize(width: width, height: externalHeight)
        }
    }

    private func layoutTable() -> CGFloat {
        if let tableHeight { return tableHeight }
        var y: CGFloat = 0
        for row in cells {
            var rowHeight: CGFloat = attachment.fontSize * 1.5 + 16
            for (index, cell) in row.enumerated() {
                let width = columnWidths[index] - 24
                cell.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
                if let manager = cell.textLayoutManager, let range = manager.textContentManager?.documentRange {
                    // Only this cell is laid out, once per cell content/attachment size.
                    // Its view attachments participate in the same native layout.
                    manager.ensureLayout(for: range)
                    rowHeight = max(rowHeight, ceil(manager.usageBoundsForTextContainer.height) + 16)
                }
            }
            var x: CGFloat = 0
            for (index, cell) in row.enumerated() {
                cell.frame = NSRect(x: x + 12, y: y + 8, width: columnWidths[index] - 24, height: rowHeight - 16)
                x += columnWidths[index]
            }
            y += rowHeight
        }
        tableHeight = y
        return y
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInlineMath ? nil : super.hitTest(point)
    }

    override func layout() {
        super.layout()
        let chrome: CGFloat = isInlineMath ? 0 : 28
        copyButton.frame = NSRect(x: max(0, bounds.width - 44), y: 3, width: 40, height: 22)
        caption.frame = NSRect(x: 8, y: 5, width: max(0, bounds.width - 60), height: 20)
        scroll.frame = NSRect(x: 0, y: chrome, width: bounds.width, height: max(1, bounds.height - chrome))
        var documentWidth = bounds.width
        if math != nil || code != nil { documentWidth = max(bounds.width, ceil(naturalSize.width) + (code == nil ? 0 : 24)) }
        if !cells.isEmpty { documentWidth = max(bounds.width, columnWidths.reduce(0, +)) }
        document.frame = NSRect(x: 0, y: 0, width: documentWidth, height: max(1, bounds.height - chrome))
        math?.frame = NSRect(x: max(0, (documentWidth - naturalSize.width) / 2), y: 0, width: naturalSize.width, height: naturalSize.height)
        code?.frame = NSRect(x: 12, y: 8, width: max(1, documentWidth - 24), height: naturalSize.height)
        code?.textContainer?.containerSize = NSSize(width: max(1, documentWidth - 24), height: .greatestFiniteMagnitude)
        picture?.frame = document.bounds
        external?.frame = document.bounds
        mermaid?.frame = document.bounds
    }

    @objc private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(attachment.readableText, forType: .string)
    }
    @objc private func openImage() {
        if case let .image(source, _) = attachment.descriptor, let url = URL(string: source) { attachment.onOpenURL(url) }
    }
}

private final class NativeChatFlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private func NativeChatInlineAttributedString(_ source: String, fontSize: CGFloat, isDark: Bool,
    onOpenURL: @escaping (URL) -> Void, onSizeChange: @escaping () -> Void,
    imageLoader: NativeChatTextAttachment.ImageLoader?,
    interfaceLanguage: WeiBeiInterfaceLanguage) -> NSAttributedString {
    NativeChatMarkdownAttributed.make(runs: NativeChatMarkdownParser.parse(source).runs,
        fontSize: fontSize, isDark: isDark) { descriptor in
        NativeChatTextAttachment(descriptor: descriptor, fontSize: fontSize, isDark: isDark,
            onOpenURL: onOpenURL, onSizeChange: onSizeChange, imageLoader: imageLoader, interfaceLanguage: interfaceLanguage)
    }
}

private final class NativeChatHorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || event.modifierFlags.contains(.shift) {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}

/// Only the Mermaid attachment uses the existing dedicated web renderer.
/// Updating this value preserves the hosting view and its underlying web view.
private struct NativeChatMermaidPreview: View {
    let source: String
    let appearanceMode: WeiBeiAppearanceMode
    let interfaceLanguage: WeiBeiInterfaceLanguage
    let textScale: CGFloat
    let onHeight: (CGFloat) -> Void
    let onFailure: () -> Void

    private var markdown: String {
        let longestFence = source.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longestFence + 1))
        return "\(fence)mermaid\n\(source)\n\(fence)"
    }

    var body: some View {
        MarkdownPreviewView(markdown: markdown, markdownBaseURL: nil,
            appearanceMode: appearanceMode, interfaceLanguage: interfaceLanguage, compact: true,
            preservesHeightAcrossMarkdownChanges: true,
            onRenderFailure: onFailure, onMeasuredHeight: onHeight)
            .environment(\.weiBeiTextScale, textScale)
    }
}
