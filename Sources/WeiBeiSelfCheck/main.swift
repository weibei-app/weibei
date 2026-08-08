import AppKit
import CoreText
import Darwin
import Foundation
import PDFKit
import WeiBeiCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("self-check failed: \(message)\n", stderr)
        exit(1)
    }
}

let legacyChatID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
let legacyChatCourseID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
let legacyChatData = try! JSONSerialization.data(withJSONObject: [
    "id": legacyChatID.uuidString,
    "title": "旧课程会话",
    "messages": [],
    "summary": "原有摘要",
    "courseID": legacyChatCourseID.uuidString,
    "scopeNeedsReview": false,
])
let migratedChat = try! JSONDecoder().decode(StudySession.self, from: legacyChatData)
let migratedChatJSON = try! JSONSerialization.jsonObject(
    with: JSONEncoder().encode(migratedChat)
) as! [String: Any]
expect(
    migratedChat.id == legacyChatID
        && migratedChat.summary == "原有摘要"
        && migratedChat.relatedCourseIDs == [legacyChatCourseID],
    "legacy fixed-scope Chats migrate in place to course associations"
)
expect(
    migratedChatJSON["relatedCourseIDs"] != nil
        && migratedChatJSON["courseID"] == nil
        && migratedChatJSON["scopeNeedsReview"] == nil,
    "unified Chats persist associations without the removed scope classification"
)

func importedIdentity(at url: URL) -> ImportedFileIdentity? {
    var fileStat = Darwin.stat()
    guard url.withUnsafeFileSystemRepresentation({ path in
        guard let path else { return false }
        return Darwin.lstat(path, &fileStat) == 0
    }) else { return nil }
    return ImportedFileIdentity(
        volumeID: UInt64(fileStat.st_dev),
        fileID: UInt64(fileStat.st_ino),
        birthTimeSeconds: Int64(fileStat.st_birthtimespec.tv_sec),
        birthTimeNanoseconds: Int64(fileStat.st_birthtimespec.tv_nsec)
    )
}

final class OneShotFileReplacement: @unchecked Sendable {
    private let lock = NSLock()
    private var didRun = false
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func run() {
        lock.lock()
        defer { lock.unlock() }
        guard !didRun else { return }
        didRun = true
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("verified-read-backup-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            try Data("MALICIOUS_DURING_READ".utf8).write(to: url)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: backup, to: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.moveItem(at: backup, to: url)
        }
    }
}


if ProcessInfo.processInfo.environment["WEIBEI_PI_TERMINAL_SELF_CHECK_ONLY"] == "1" {
    try await runPiTerminalRuntimeSelfChecks()
    print("WeiBei PI terminal runtime self-check passed")
    exit(0)
}

try runPiAgentSelfChecks()

expect(EmptyWorkspaceDayPeriod(hour: 5) == .morning
    && EmptyWorkspaceDayPeriod(hour: 10) == .morning
    && EmptyWorkspaceDayPeriod(hour: 11) == .midday
    && EmptyWorkspaceDayPeriod(hour: 16) == .midday
    && EmptyWorkspaceDayPeriod(hour: 17) == .evening
    && EmptyWorkspaceDayPeriod(hour: 22) == .evening
    && EmptyWorkspaceDayPeriod(hour: 23) == .lateNight
    && EmptyWorkspaceDayPeriod(hour: 4) == .lateNight, "empty workspace greeting follows morning, midday, evening, and late-night boundaries")
expect(EmptyWorkspaceDayPeriod.morning.greeting(language: .chinese).contains("早安")
    && EmptyWorkspaceDayPeriod.midday.greeting(language: .chinese).contains("午安")
    && EmptyWorkspaceDayPeriod.evening.greeting(language: .chinese).contains("晚安")
    && EmptyWorkspaceDayPeriod.lateNight.greeting(language: .chinese).contains("夜深")
    && !EmptyWorkspaceDayPeriod.morning.greeting(language: .english).isEmpty, "empty workspace greetings stay localized and non-empty")
expect(!AgentHistoryRevealPolicy.shouldRevealEarlierPage(
        distanceFromTop: 0,
        isUserScrolling: false,
        isScrollingTowardTop: true,
        hiddenMessageCount: 30,
        revealInFlight: false
    )
    && AgentHistoryRevealPolicy.shouldRevealEarlierPage(
        distanceFromTop: 0,
        isUserScrolling: true,
        isScrollingTowardTop: true,
        hiddenMessageCount: 30,
        revealInFlight: false
    )
    && !AgentHistoryRevealPolicy.shouldRevealEarlierPage(
        distanceFromTop: 0,
        isUserScrolling: true,
        isScrollingTowardTop: true,
        hiddenMessageCount: 30,
        revealInFlight: true
    )
    && !AgentHistoryRevealPolicy.shouldRevealEarlierPage(
        distanceFromTop: 0,
        isUserScrolling: true,
        isScrollingTowardTop: true,
        hiddenMessageCount: 0,
        revealInFlight: false
    )
    && !AgentHistoryRevealPolicy.shouldRevealEarlierPage(
        distanceFromTop: 0,
        isUserScrolling: true,
        isScrollingTowardTop: false,
        hiddenMessageCount: 30,
        revealInFlight: false
    )
    && AgentHistoryRevealPolicy.expandedVisibleLimit(currentLimit: 30, totalMessageCount: 95) == 60
    && AgentHistoryRevealPolicy.expandedVisibleLimit(currentLimit: 90, totalMessageCount: 95) == 95
    && !AgentHistoryRevealPolicy.shouldReleaseRevealLock(isUserScrolling: true)
    && AgentHistoryRevealPolicy.shouldReleaseRevealLock(isUserScrolling: false), "agent history paging requires an upward live-scroll gesture, expands exactly one bounded page, and keeps its re-entry lock until that gesture ends")
let historyMessageIDs = [UUID(), UUID(), UUID()]
expect(AgentHistoryRevealPolicy.appendedMessageCount(
        previousMessageIDs: Array(historyMessageIDs.prefix(2)),
        currentMessageIDs: historyMessageIDs
    ) == 1
    && AgentHistoryRevealPolicy.appendedMessageCount(
        previousMessageIDs: [],
        currentMessageIDs: historyMessageIDs
    ) == nil
    && AgentHistoryRevealPolicy.appendedMessageCount(
        previousMessageIDs: Array(historyMessageIDs.prefix(2)),
        currentMessageIDs: Array(historyMessageIDs.suffix(2))
    ) == nil, "agent history distinguishes a same-session append from initial restore or replacement")

let inspirationItems = EmptyWorkspaceInspirationCatalog.items
expect(inspirationItems.count >= 6
    && EmptyWorkspaceInspirationCatalog.validationErrors.isEmpty
    && inspirationItems.contains(where: { if case .calligraphy = $0.presentation { return true }; return false })
    && inspirationItems.contains(where: { $0.presentation == .quotation })
    && inspirationItems.contains(where: { $0.presentation == .formula }), "daily inspiration catalog contains validated calligraphy, original-language quotation, and formulas")
expect(inspirationItems.allSatisfy { item in
    !item.text.isEmpty
        && !item.credit.isEmpty
        && item.sourceURL?.scheme == "https"
        && !item.rightsLabel.isEmpty
        && item.rightsURL?.scheme == "https"
}, "every daily inspiration keeps text, author/work credit, a reliable source, and rights metadata")
var inspirationCalendar = Calendar(identifier: .gregorian)
inspirationCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let inspirationDayOne = inspirationCalendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
let inspirationDayTwo = inspirationCalendar.date(byAdding: .day, value: 1, to: inspirationDayOne)!
expect(EmptyWorkspaceInspirationCatalog.item(for: inspirationDayOne, calendar: inspirationCalendar).id
    != EmptyWorkspaceInspirationCatalog.item(for: inspirationDayTwo, calendar: inspirationCalendar).id, "daily inspiration rotates deterministically from one local day to the next")

let fontDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Fonts")
let displayFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiStele.ttf")
let monoFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiSteleMono.ttf")
CTFontManagerRegisterFontsForURL(displayFontURL as CFURL, .process, nil)
CTFontManagerRegisterFontsForURL(monoFontURL as CFURL, .process, nil)
expect(NSFont(name: "WeiBeiStele-Regular", size: 18) != nil
    && NSFont(name: "WeiBeiSteleMono-Regular", size: 13) != nil, "bundled WeiBei English fonts register under their PostScript names")
let emptyWorkspaceEntryFont = CTFontCreateWithName("WeiBeiStele-Regular" as CFString, 22, nil)
let emptyWorkspaceEntryCharacters = Array("DOCCHATNOTES".utf16)
var emptyWorkspaceEntryGlyphs = Array(repeating: CGGlyph(), count: emptyWorkspaceEntryCharacters.count)
expect(emptyWorkspaceEntryCharacters.withUnsafeBufferPointer { characters in
    emptyWorkspaceEntryGlyphs.withUnsafeMutableBufferPointer { glyphs in
        CTFontGetGlyphsForCharacters(emptyWorkspaceEntryFont, characters.baseAddress!, glyphs.baseAddress!, characters.count)
    }
} && emptyWorkspaceEntryGlyphs.allSatisfy { $0 != 0 }, "WeiBeiStele keeps every glyph required by the DOC, CHAT, and NOTES work entries")

func inspectCalligraphyAsset(_ url: URL) throws -> (width: Int, height: Int, visible: Int, transparent: Int, opaqueWhite: Int, outerInk: Int) {
    let data = try Data(contentsOf: url)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        throw NSError(domain: "WeiBeiSelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable calligraphy PNG: \(url.path)"])
    }
    var visible = 0
    var transparent = 0
    var opaqueWhite = 0
    var outerInk = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.alphaComponent > 0.05 {
                visible += 1
                if x < 2 || y < 2 || x >= bitmap.pixelsWide - 2 || y >= bitmap.pixelsHigh - 2 {
                    outerInk += 1
                }
            } else {
                transparent += 1
            }
            if color.alphaComponent > 0.95
                && color.redComponent > 0.95
                && color.greenComponent > 0.95
                && color.blueComponent > 0.95 {
                opaqueWhite += 1
            }
        }
    }
    return (bitmap.pixelsWide, bitmap.pixelsHigh, visible, transparent, opaqueWhite, outerInk)
}

let calligraphyDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Inspiration/Calligraphy", isDirectory: true)
let clearBreezeStats = try inspectCalligraphyAsset(calligraphyDirectoryURL.appendingPathComponent("lanting-clear-breeze.png"))
let universeStats = try inspectCalligraphyAsset(calligraphyDirectoryURL.appendingPathComponent("lanting-universe.png"))
expect(clearBreezeStats.width == 856 && clearBreezeStats.height == 132
    && universeStats.width == 624 && universeStats.height == 132
    && clearBreezeStats.visible > 1_000 && universeStats.visible > 1_000
    && clearBreezeStats.transparent > clearBreezeStats.visible
    && universeStats.transparent > universeStats.visible
    && clearBreezeStats.opaqueWhite == 0 && universeStats.opaqueWhite == 0
    && clearBreezeStats.outerInk == 0 && universeStats.outerInk == 0, "bundled Lanting calligraphy masks are transparent, uncropped, and free of hard white backgrounds")


expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.pdf")) == .pdf, "pdf detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.html")) == .html, "html detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.md")) == .markdown, "markdown detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.txt")) == .text, "text detection")

func makeSelectablePDF(at url: URL) {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 260)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        expect(false, "create pdf context")
        return
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSString(string: "PDF 可选文本层：利率是资金使用价格的表达。").draw(
        at: CGPoint(x: 42, y: 178),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]
    )
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    expect(data.write(to: url, atomically: true), "write selectable pdf")
}

func makeImageOnlyPDF(at url: URL) {
    let image = NSImage(size: NSSize(width: 900, height: 260))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    NSString(string: "INTEREST RATE OCR PRICE").draw(
        at: CGPoint(x: 48, y: 96),
        withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 54),
            .foregroundColor: NSColor.black
        ]
    )
    image.unlockFocus()

    let document = PDFDocument()
    guard let page = PDFPage(image: image) else {
        expect(false, "create image-only pdf page")
        return
    }
    document.insert(page, at: 0)
    expect(document.write(to: url), "write image-only pdf")
}

func makeBlankImageOnlyPDF(at url: URL) {
    let image = NSImage(size: NSSize(width: 600, height: 300))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    let document = PDFDocument()
    guard let page = PDFPage(image: image) else {
        expect(false, "create blank image-only pdf page")
        return
    }
    document.insert(page, at: 0)
    expect(document.write(to: url), "write blank image-only pdf")
}

let selectablePDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-selectable-pdf-check-\(UUID().uuidString).pdf")
makeSelectablePDF(at: selectablePDFURL)
defer { try? FileManager.default.removeItem(at: selectablePDFURL) }
let selectablePDF = PDFDocument(url: selectablePDFURL)
expect(selectablePDF?.string?.contains("利率是资金使用价格") == true, "PDFKit extracts text from selectable PDF text layer")
let pdfSelections = selectablePDF?.findString("资金使用价格", withOptions: []) ?? []
expect(pdfSelections.count == 1, "PDFKit finds selectable text in generated PDF")
if let selection = pdfSelections.first, let page = selection.pages.first {
    expect(selection.string == "资金使用价格", "PDFSelection preserves selected text")
    let selectedPDFPageIndex = selectablePDF?.index(for: page)
    expect(selectedPDFPageIndex == 0, "PDFSelection resolves selected page index")
    expect(!selection.bounds(for: page).isEmpty, "PDFSelection exposes non-empty page bounds for floating agent anchor")
    let ownerTitle = "Mishkin 教材样例，第 \((selectedPDFPageIndex ?? 0) + 1) 页"
    let context = SelectionContext(text: selection.string ?? "", source: .document, ownerTitle: ownerTitle)
    let reference = SourceReferenceTitle.parse("来源：\(context.ownerTitle)")
    expect(context.label(language: .chinese) == "文档选区：Mishkin 教材样例，第 1 页", "PDF selection context carries the selected page label into the floating agent")
    expect(reference.title == "Mishkin 教材样例" && reference.pageIndex == 0, "PDF selection reference can jump back to the selected page")
} else {
    expect(false, "PDFSelection contains page")
}

let imageOnlyPDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-image-only-pdf-check-\(UUID().uuidString).pdf")
makeImageOnlyPDF(at: imageOnlyPDFURL)
defer { try? FileManager.default.removeItem(at: imageOnlyPDFURL) }
let imageOnlyPDF = PDFDocument(url: imageOnlyPDFURL)
expect(imageOnlyPDF?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false, "image-only PDF has no native text layer")
let ocrText = imageOnlyPDF.flatMap { PDFOCRTextExtractor.text(from: $0, maxPages: 1) }?.uppercased() ?? ""
expect(ocrText.contains("INTEREST") && ocrText.contains("OCR") && ocrText.contains("PRICE"), "Vision OCR extracts text from image-only PDF pages")
let ocrPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, maxPages: 1) } ?? []
expect(ocrPages.count == 1 && ocrPages[0].lines.contains { $0.text.uppercased().contains("INTEREST") && !$0.boundingBox.isEmpty }, "Vision OCR keeps page text bounds for scanned PDF selection overlays")
let targetedOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [0]) } ?? []
expect(targetedOCRPages.count == 1 && targetedOCRPages[0].pageIndex == 0, "Vision OCR can target a specific PDF page for mixed text and scanned documents")
let outOfRangeOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [1]) } ?? []
expect(outOfRangeOCRPages.isEmpty, "targeted OCR ignores pages outside the PDF")
let blankImagePDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-blank-image-pdf-check-\(UUID().uuidString).pdf")
makeBlankImageOnlyPDF(at: blankImagePDFURL)
defer { try? FileManager.default.removeItem(at: blankImagePDFURL) }
if let blankImagePDF = PDFDocument(url: blankImagePDFURL) {
    expect(
        PDFOCRTextExtractor.pageOutcome(from: blankImagePDF, pageIndex: 0) == .empty(pageIndex: 0),
        "Vision OCR distinguishes a successfully scanned blank page from an extraction failure"
    )
} else {
    expect(false, "open blank image-only pdf")
}

func makeMixedLateOCRPDF(at url: URL) {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 720, height: 420)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        expect(false, "create mixed PDF context")
        return
    }

    for pageIndex in 0..<13 {
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        if pageIndex < 12 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSString(string: "Native text layer content for page \(pageIndex + 1) with enough characters").draw(
                at: CGPoint(x: 48, y: 210),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 24),
                    .foregroundColor: NSColor.black,
                ]
            )
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let image = NSImage(size: NSSize(width: 1_200, height: 500))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: image.size).fill()
            NSString(string: "LATEPAGE OCR TARGET").draw(
                at: CGPoint(x: 70, y: 190),
                withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 82),
                    .foregroundColor: NSColor.black,
                ]
            )
            image.unlockFocus()
            var imageRect = CGRect(origin: .zero, size: image.size)
            if let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) {
                context.draw(cgImage, in: CGRect(x: 35, y: 70, width: 650, height: 270))
            }
        }
        context.endPDFPage()
    }
    context.closePDF()
    expect(data.write(to: url, atomically: true), "write mixed late-OCR PDF")
}

let courseIndexRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-course-index-check-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: courseIndexRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: courseIndexRoot) }
let verifiedReadURL = courseIndexRoot.appendingPathComponent("verified-read.md")
try? "# 原文\n\nORIGINAL_VERIFIED_CONTENT".write(
    to: verifiedReadURL,
    atomically: true,
    encoding: .utf8
)
let verifiedReadItem = StudyItem(
    id: "verified-read",
    title: "Verified read",
    subtitle: verifiedReadURL.lastPathComponent,
    kind: .markdown,
    urlPath: verifiedReadURL.path,
    importedFileIdentity: importedIdentity(at: verifiedReadURL),
    isSample: false,
    storage: .courseOwned(ownerCourseID: UUID())
)
let verifiedReadReplacement = OneShotFileReplacement(url: verifiedReadURL)
let verifiedReadIndex = CourseDocumentSearchIndex(
    databaseURL: courseIndexRoot.appendingPathComponent("verified-read.sqlite3"),
    verifiedFileDidOpen: { verifiedReadReplacement.run() }
)
let verifiedReadResult = verifiedReadIndex.lookup(
    items: [verifiedReadItem],
    query: "ORIGINAL_VERIFIED_CONTENT MALICIOUS_DURING_READ"
)[verifiedReadItem.id]
expect(
    verifiedReadResult?.text?.contains("ORIGINAL_VERIFIED_CONTENT") == true
        && verifiedReadResult?.text?.contains("MALICIOUS_DURING_READ") == false,
    "course index reads the verified open file when its path is replaced and restored mid-read"
)
let visualSnapshotURL = courseIndexRoot.appendingPathComponent("verified-visual.png")
try? Data("ORIGINAL_VISUAL_BYTES".utf8).write(to: visualSnapshotURL)
let visualSnapshotItem = StudyItem(
    id: "verified-visual",
    title: "Verified visual",
    subtitle: visualSnapshotURL.lastPathComponent,
    kind: .text,
    urlPath: visualSnapshotURL.path,
    importedFileIdentity: importedIdentity(at: visualSnapshotURL),
    isSample: false,
    storage: .courseOwned(ownerCourseID: UUID())
)
let visualReplacement = OneShotFileReplacement(url: visualSnapshotURL)
let visualSnapshotIndex = CourseDocumentSearchIndex(
    databaseURL: courseIndexRoot.appendingPathComponent("verified-visual.sqlite3"),
    verifiedFileDidOpen: { visualReplacement.run() }
)
let visualSnapshot = visualSnapshotIndex.verifiedSnapshot(
    of: visualSnapshotItem,
    maximumBytes: 6_000_000
)
let visualSnapshotData = visualSnapshot.flatMap { try? Data(contentsOf: $0) }
expect(
    visualSnapshotData == Data("ORIGINAL_VISUAL_BYTES".utf8),
    "visual attachments copy the verified open file instead of following a replaced path"
)
if let visualSnapshot {
    try? FileManager.default.removeItem(at: visualSnapshot)
}
let mixedPDFURL = courseIndexRoot.appendingPathComponent("mixed-late-ocr.pdf")
makeMixedLateOCRPDF(at: mixedPDFURL)
let mixedPDFItem = StudyItem(
    id: "file:\(mixedPDFURL.path)",
    title: "Mixed late OCR",
    subtitle: mixedPDFURL.lastPathComponent,
    kind: .pdf,
    urlPath: mixedPDFURL.path,
    isSample: false
)
let markdownIndexURL = courseIndexRoot.appendingPathComponent("late-section.md")
let lateMarkdownToken = "PERSISTENT_LATE_INDEX_TOKEN"
try? (
    String(repeating: "ordinary material\n\n", count: 1_500)
        + "## Deep section\n"
        + lateMarkdownToken
)
    .write(to: markdownIndexURL, atomically: true, encoding: .utf8)
let markdownIndexItem = StudyItem(
    id: "file:\(markdownIndexURL.path)",
    title: "Late markdown section",
    subtitle: markdownIndexURL.lastPathComponent,
    kind: .markdown,
    urlPath: markdownIndexURL.path,
    isSample: false
)
let stableHTMLURL = courseIndexRoot.appendingPathComponent("stable-sections.html")
let stableHTMLOriginal = """
<html><body>
<h1>利率</h1><p>ORIGINAL_ALPHA_SECTION 资金价格。</p>
<h2>利率</h2><p>ORIGINAL_BETA_SECTION 购买力变化。</p>
</body></html>
"""
try? stableHTMLOriginal.write(to: stableHTMLURL, atomically: true, encoding: .utf8)
let stableHTMLItem = StudyItem(
    id: "file:\(stableHTMLURL.path)",
    title: "Stable duplicate sections",
    subtitle: stableHTMLURL.lastPathComponent,
    kind: .html,
    urlPath: stableHTMLURL.path,
    isSample: false
)
let blankPDFIndexItem = StudyItem(
    id: "file:\(blankImagePDFURL.path)",
    title: "Blank scanned page",
    subtitle: blankImagePDFURL.lastPathComponent,
    kind: .pdf,
    urlPath: blankImagePDFURL.path,
    isSample: false
)
let courseIndexDatabaseURL = courseIndexRoot.appendingPathComponent("course-search.sqlite3")
let courseIndex = CourseDocumentSearchIndex(databaseURL: courseIndexDatabaseURL)
#if DEBUG
expect(
    BoundedPDFTextExtractor.runSafetySelfCheck(),
    "bounded PDF worker passes normal execution, timeout, cancellation, memory, and output-overflow probes"
)
#endif
let boundedNativeProbe = BoundedPDFTextExtractor.pages(
    from: mixedPDFURL,
    pageIndexes: Array(0..<8),
    maximumCharactersPerPage: 128_000,
    timeout: 3.5
)
if boundedNativeProbe?[0]?.text.contains("Native text layer content for page 1") != true {
    fputs("bounded native PDF diagnostic: \(String(describing: boundedNativeProbe))\n", stderr)
}
expect(
    boundedNativeProbe?[0]?.text.contains("Native text layer content for page 1") == true,
    "bounded PDF worker returns native text for a generated multi-page PDF"
)
courseIndex.schedule([mixedPDFItem, markdownIndexItem, stableHTMLItem, blankPDFIndexItem])
var mixedIndexResult: CourseDocumentIndexResult?
var markdownIndexResult: CourseDocumentIndexResult?
var blankPDFIndexResult: CourseDocumentIndexResult?
var stableHTMLIndexResult: CourseDocumentIndexResult?
for _ in 0..<600 {
    mixedIndexResult = courseIndex.lookup(items: [mixedPDFItem], query: "LATEPAGE OCR TARGET")[mixedPDFItem.id]
    markdownIndexResult = courseIndex.lookup(items: [markdownIndexItem], query: lateMarkdownToken)[markdownIndexItem.id]
    blankPDFIndexResult = courseIndex.lookup(items: [blankPDFIndexItem], query: "blank page")[blankPDFIndexItem.id]
    stableHTMLIndexResult = courseIndex.lookup(items: [stableHTMLItem], query: "ORIGINAL_ALPHA_SECTION ORIGINAL_BETA_SECTION")[stableHTMLItem.id]
    if mixedIndexResult?.text?.uppercased().contains("LATEPAGE") == true,
       markdownIndexResult?.text?.contains(lateMarkdownToken) == true,
       stableHTMLIndexResult?.text?.contains("ORIGINAL_ALPHA_SECTION") == true,
       blankPDFIndexResult?.isTruncated == false {
        break
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
expect(
    mixedIndexResult?.isTruncated == true
        && mixedIndexResult?.text?.uppercased().contains("LATEPAGE") == true
        && mixedIndexResult?.text?.contains("第 13 页（OCR）") == true,
    "persistent course index OCRs a scanned page beyond page twelve, keeps its page location, and marks the returned excerpt partial"
)
let nativePDFIndexResult = courseIndex.lookup(
    items: [mixedPDFItem],
    query: "Native text layer content for page 1"
)[mixedPDFItem.id]
if nativePDFIndexResult?.text?.contains("Native text layer content for page 1") != true
    || nativePDFIndexResult?.text?.contains("第 1 页（OCR）") == true {
    fputs("native PDF index diagnostic: \(nativePDFIndexResult?.text ?? "<nil>")\n", stderr)
}
expect(
    nativePDFIndexResult?.text?.contains("Native text layer content for page 1") == true
        && nativePDFIndexResult?.text?.contains("第 1 页（OCR）") != true,
    "persistent course index executes the bounded worker and preserves a real native PDF text-layer result"
)
let nativePDFPageRead = courseIndex.read(
    item: mixedPDFItem,
    query: "",
    location: "第 1 页"
)
expect(
    nativePDFPageRead.text?.contains("Native text layer content for page 1") == true,
    "course host read resolves an exact indexed PDF page without exposing the SQLite schema"
)
let markdownSectionRead = courseIndex.read(
    item: markdownIndexItem,
    query: "",
    location: "Deep section"
)
expect(
    markdownSectionRead.text?.contains(lateMarkdownToken) == true
        && markdownSectionRead.text?.contains("ordinary material") != true,
    "course host read resolves an exact indexed Markdown section by its visible title"
)
let htmlSectionRead = courseIndex.read(
    item: stableHTMLItem,
    query: "",
    location: "html-heading-0"
)
expect(
    htmlSectionRead.text?.contains("ORIGINAL_ALPHA_SECTION") == true
        && htmlSectionRead.text?.contains("ORIGINAL_BETA_SECTION") != true,
    "course host read resolves an exact indexed HTML section by its stable reader location"
)
let indexedPDFCourseContext = CourseKnowledgeIndex.build(
    title: "Indexed PDF",
    sources: [
        CourseKnowledgeSource(
            id: mixedPDFItem.id,
            title: mixedPDFItem.title,
            subtitle: mixedPDFItem.subtitle,
            kind: mixedPDFItem.kind.rawValue,
            role: "material",
            text: mixedIndexResult?.text ?? "",
            isTruncated: mixedIndexResult?.isTruncated ?? true
        ),
    ],
    links: [],
    query: "LATEPAGE OCR TARGET",
    currentMaterialID: nil,
    currentNoteID: nil
)
expect(
    indexedPDFCourseContext.items.first?.headings.contains("第 13 页（OCR）") == true,
    "course search preserves confirmed OCR page locations for exact PDF jumps"
)
if blankPDFIndexResult?.isTruncated != false || blankPDFIndexResult?.text != nil {
    fputs("blank PDF index diagnostic: \(String(describing: blankPDFIndexResult))\n", stderr)
}
expect(
    blankPDFIndexResult?.isTruncated == false && blankPDFIndexResult?.text == nil,
    "persistent course index records a successfully scanned blank PDF page without retrying it forever"
)
expect(
    markdownIndexResult?.isTruncated == true
        && markdownIndexResult?.text?.contains(lateMarkdownToken) == true,
    "persistent course index finds a late text-file section without per-question rescanning and marks the excerpt partial"
)
func stableHTMLSectionIDs(in text: String) -> Set<String> {
    guard let regex = try? NSRegularExpression(pattern: #"\[(html-section-[A-Za-z0-9-]+)\]"#) else {
        return []
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return Set(regex.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    })
}
let originalStableSectionIDs = stableHTMLSectionIDs(in: stableHTMLIndexResult?.text ?? "")
let stableHTMLWithInsertedDuplicate = """
<html><body>
<h1>利率</h1><p>NEW_INSERTED_SECTION 新增解释。</p>
<h1>利率</h1><p>ORIGINAL_ALPHA_SECTION 资金价格。</p>
<h2>利率</h2><p>ORIGINAL_BETA_SECTION 购买力变化。</p>
</body></html>
"""
try? stableHTMLWithInsertedDuplicate.write(to: stableHTMLURL, atomically: true, encoding: .utf8)
let refreshedStableHTML = courseIndex.lookup(
    items: [stableHTMLItem],
    query: "NEW_INSERTED_SECTION ORIGINAL_ALPHA_SECTION ORIGINAL_BETA_SECTION"
)[stableHTMLItem.id]
let refreshedStableSectionIDs = stableHTMLSectionIDs(in: refreshedStableHTML?.text ?? "")
expect(
    originalStableSectionIDs.count == 2
        && originalStableSectionIDs.isSubset(of: refreshedStableSectionIDs)
        && refreshedStableSectionIDs.count == 3,
    "HTML section content fingerprints survive insertion of a new same-title section before existing sections"
)
let reopenedCourseIndex = CourseDocumentSearchIndex(databaseURL: courseIndexDatabaseURL)
reopenedCourseIndex.schedule([mixedPDFItem])
let reopenedResult = reopenedCourseIndex.lookup(
    items: [mixedPDFItem],
    query: "LATEPAGE OCR TARGET"
)[mixedPDFItem.id]
expect(
    reopenedResult?.isTruncated == true
        && reopenedResult?.text?.uppercased().contains("LATEPAGE") == true,
    "course full-text index survives reopening without rebuilding the PDF"
)

let splitFailureIndex = CourseDocumentSearchIndex(
    databaseURL: courseIndexRoot.appendingPathComponent("course-search-split-failure.sqlite3"),
    nativePDFTextLoader: { _, pageIndexes, _, _ in
        guard pageIndexes.count == 1, let pageIndex = pageIndexes.first else { return nil }
        let text = pageIndex < 12
            ? "SPLIT_NATIVE_LAYER_PAGE_\(pageIndex + 1) remains native after a failed batch extraction"
            : ""
        return [pageIndex: BoundedPDFTextPage(text: text, isPartial: false)]
    }
)
splitFailureIndex.schedule([mixedPDFItem])
var splitFailureResult: CourseDocumentIndexResult?
for _ in 0..<200 {
    splitFailureResult = splitFailureIndex.lookup(
        items: [mixedPDFItem],
        query: "SPLIT_NATIVE_LAYER_PAGE_1"
    )[mixedPDFItem.id]
    if splitFailureResult?.text?.contains("SPLIT_NATIVE_LAYER_PAGE_1") == true { break }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
expect(
    splitFailureResult?.text?.contains("SPLIT_NATIVE_LAYER_PAGE_1") == true
        && splitFailureResult?.text?.contains("第 1 页（OCR）") != true,
    "a failed native PDF batch is bisected to single pages instead of sending unattempted text pages to OCR"
)

let calloutSelectionText = MarkdownSelectionSanitizer.clean("""
[!quote] 选区摘录
利率是资金使用价格的表达。
""")
expect(calloutSelectionText == "选区摘录\n利率是资金使用价格的表达。", "selection sanitizer removes visible Obsidian callout control markers from rendered selections")
let quotedCalloutSelectionText = MarkdownSelectionSanitizer.clean("""
> [!warning]- 风险提示
> 普通美元 $5 不应被误伤。
""")
expect(!quotedCalloutSelectionText.contains("[!warning]")
    && quotedCalloutSelectionText.contains("风险提示")
    && quotedCalloutSelectionText.contains("$5"), "selection sanitizer handles quoted and folded callouts without damaging ordinary prose")
let readableMarkdownSelectionText = MarkdownSelectionSanitizer.clean("""
==重点==<br />
[[货币理论|理论别名]]
[[货币理论\\|表格别名]]
![曲线图|120x80](assets/curve.png)
![[assets/curve.png|180]]
~~删除线~~、`代码`、^[脚注说明]
%%内部注释%%
- [x] 已完成项
""")
let expectedReadableMarkdownSelectionText = """
重点
理论别名
表格别名
曲线图
assets/curve.png
删除线、代码、脚注说明
已完成项
"""
expect(readableMarkdownSelectionText == expectedReadableMarkdownSelectionText, "selection sanitizer turns common Markdown and Obsidian writing syntax into readable text for Agent context")
let searchableTags = MarkdownTagSearch.tags(in: """
---
tags:
  - property/rate
  - "#quoted-tag"
---

# 标题不是标签
正文标签 #finance/rate 和 #nested/tag
行内代码 `#not-tag` 不应该进入标签

```swift
let tag = "#code-tag"
```
""")
expect(searchableTags == ["#finance/rate", "#nested/tag", "#property/rate", "#quoted-tag"], "markdown tag search extracts real prose and frontmatter property tags")
expect(MarkdownTagSearch.tags(in: "---\ntags: [banking, #macro/rate]\n---\n正文") == ["#banking", "#macro/rate"], "markdown tag search reads inline frontmatter tag arrays")
expect(MarkdownTagSearch.matches(query: "finance", in: "#finance/rate")
    && MarkdownTagSearch.matches(query: "macro", in: "---\ntags: [banking, macro/rate]\n---")
    && MarkdownTagSearch.matches(query: "#nested", in: "#nested/tag")
    && !MarkdownTagSearch.matches(query: "code-tag", in: "`#code-tag`"), "markdown tag search supports library queries without indexing code")

expect(PageNavigator.previous(0) == 0, "pdf previous clamps first page")
expect(PageNavigator.next(0, pageCount: 2) == 1, "pdf next advances")
expect(PageNavigator.next(1, pageCount: 2) == 1, "pdf next clamps last page")
expect(PageNavigator.display(0, pageCount: 0) == "1 / 1", "pdf display empty")
expect(TopBarLeadingInset.value(isFullScreen: true) == 12, "fullscreen top-left controls start from the left edge")
expect(TopBarLeadingInset.value(isFullScreen: false) == 80
    && TopBarLeadingInset.value(isFullScreen: false) > TopBarLeadingInset.value(isFullScreen: true), "windowed top-left controls clear the traffic-light area")
expect(!PDFModeChipPresentation.showsLabel(isExpanded: false), "pdf mode chip hides text after collapse")
expect(PDFModeChipPresentation.showsLabel(isExpanded: true), "pdf mode chip shows text only during transient expansion")
expect(PDFModeChipPresentation.controlOpacity(isExpanded: false, isHovering: true)
    < PDFModeChipPresentation.controlOpacity(isExpanded: true, isHovering: true), "pdf mode chip fades back even when hover state lingers")
expect(ReaderSearch.cleaned("  利率\n") == "利率", "reader search trims query")
expect(ReaderSearch.firstMatch(in: "实际利率与名义利率", query: "名义")?.location == 5, "reader search finds first match")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: "money")?.location == 0, "reader search ignores case")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: " ") == nil, "reader search ignores empty query")
let pdfSourceReference = SourceReferenceTitle.parse("> 来源：Mishkin 教材样例，第 3 页")
expect(pdfSourceReference.title == "Mishkin 教材样例" && pdfSourceReference.pageIndex == 2, "source reference parses pdf page")
let htmlSourceReference = SourceReferenceTitle.parse("来源：货币金融学课程 HTML，章节：实际利率")
expect(
    htmlSourceReference.title == "货币金融学课程 HTML"
        && htmlSourceReference.pageIndex == nil
        && htmlSourceReference.sectionTitle == "实际利率"
        && htmlSourceReference.sectionLocationID == nil
        && htmlSourceReference.sectionOrdinal == nil,
    "source reference parses an exact HTML section"
)
let disambiguatedSourceReference = SourceReferenceTitle.parse("来源：重复教材，条目：7，章节标识：html-section-a1b2c3d4，章节序号：4，章节：利率")
expect(
    disambiguatedSourceReference.title == "重复教材"
        && disambiguatedSourceReference.courseItemOrdinal == 7
        && disambiguatedSourceReference.sectionLocationID == "html-section-a1b2c3d4"
        && disambiguatedSourceReference.sectionOrdinal == 4
        && disambiguatedSourceReference.sectionTitle == "利率",
    "source reference preserves the file and section ordinals needed to disambiguate duplicate titles"
)
let englishSectionReference = SourceReferenceTitle.parse("Source: Repeated Course, item: 2, section id: html-section-d4c3b2a1, section number: 5, section: Interest")
expect(
    englishSectionReference.title == "Repeated Course"
        && englishSectionReference.courseItemOrdinal == 2
        && englishSectionReference.sectionLocationID == "html-section-d4c3b2a1"
        && englishSectionReference.sectionOrdinal == 5
        && englishSectionReference.sectionTitle == "Interest",
    "source reference preserves stable HTML section ordinals in English"
)
let emphasizedSourceReference = SourceReferenceTitle.parse("来源：**Mishkin 教材样例**")
expect(emphasizedSourceReference.title == "Mishkin 教材样例", "source reference ignores whole-title Markdown emphasis")
let inlineCodeSourceReference = SourceReferenceTitle.parse("- 相关资料：`来源：Mishkin 教材样例`")
expect(inlineCodeSourceReference.title == "Mishkin 教材样例", "source reference remains actionable when PI wraps the jump in inline code")
let calloutSourceReference = SourceReferenceTitle.parse("""
> [!quote] 选区摘录
> 实际利率
>
> 来源：Mishkin 教材样例，第 12 页
""")
expect(calloutSourceReference.title == "Mishkin 教材样例" && calloutSourceReference.pageIndex == 11, "source reference parses quote callout")
expect(WikiLink.targetTitle(from: "  货币理论 | 显示名 ") == "货币理论", "wikilink alias keeps target title")
expect(WikiLink.targetTitle(from: "  货币理论 ") == "货币理论", "wikilink plain title")
expect(WikiLink.targetTitle(from: "货币理论#利率") == "货币理论", "wikilink heading target opens note title")
expect(WikiLink.targetTitle(from: "货币理论#^rate-block") == "货币理论", "wikilink block target opens note title")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论|Money]] 继续写", cursor: 6) == "货币理论", "wikilink title at cursor")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论#利率]] 继续写", cursor: 8) == "货币理论", "wikilink heading title at cursor")
expect(WikiLink.enclosingTitle(in: "没有双链", cursor: 2) == nil, "wikilink title ignores plain text")
expect(WorkspaceLayout.documentAgentNotes.hasCollapsibleRightPane, "three-pane layout can collapse right pane")
expect(WorkspaceLayout.documentNotesSplit.hasCollapsibleRightPane, "split layout can collapse right pane")
expect(!WorkspaceLayout.immersiveReading.hasCollapsibleRightPane, "immersive reading has no right pane to collapse")
expect(!WorkspaceLayout.immersiveWriting.hasCollapsibleRightPane, "immersive writing keeps one uninterrupted note canvas")
expect(WorkspaceLayout.documentAgentNotes.isDocumentThreePane
    && WorkspaceLayout.documentNotesAgent.isDocumentThreePane
    && !WorkspaceLayout.documentNotesSplit.isDocumentThreePane, "only full document layouts participate in three-pane reordering")
expect(WorkspaceLayout.documentAgentNotes.allowsRailOnlyPanes
    && WorkspaceLayout.documentNotesSplit.allowsRailOnlyPanes
    && !WorkspaceLayout.immersiveConversation.allowsRailOnlyPanes
    && !WorkspaceLayout.immersiveWriting.allowsRailOnlyPanes, "only normal multi-pane layouts can collapse content panes into rail-only mode")
expect(WorkspaceLayout.documentAgentNotes.defaultThreePaneOrder == [.reader, .agent, .notes]
    && WorkspaceLayout.documentNotesAgent.defaultThreePaneOrder == [.reader, .notes, .agent], "legacy three-pane layout presets map to pane role order")
expect(WorkspacePaneRole.normalized([.notes, .reader, .notes]) == [.notes, .reader, .agent], "pane role order normalization preserves user pane order and restores missing panes")
expect(WorkspacePaneRole.agent.focus == .agent
    && WorkspacePaneRole.reader.shortLabel(language: .chinese) == "文"
    && WorkspacePaneRole.notes.label(language: .english) == "Notes", "pane roles expose focus and localized labels")
let reorderOrder: [WorkspacePaneRole] = [.reader, .agent, .notes]
let reorderFrames: [WorkspacePaneRole: CGRect] = [
    .reader: CGRect(x: 0, y: 0, width: 320, height: 600),
    .agent: CGRect(x: 330, y: 0, width: 620, height: 600),
    .notes: CGRect(x: 960, y: 0, width: 360, height: 600)
]
expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .reader, horizontalDelta: 180) == 1, "pane reorder target follows real resized pane overlap instead of fixed thirds")
expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .notes, horizontalDelta: -420) == 1, "pane reorder target works from either edge using the current pane widths")
expect(NoteRenderMode.visibleCases == [.rich, .split, .source]
    && NoteRenderMode.preview.visibleMode == .rich
    && NoteRenderMode.source.visibleMode == .source, "note render modes keep legacy preview data readable while hiding preview from the writing controls")
expect(WorkspaceLayout.documentAgentNotes.label(language: .chinese) == "阅读-对话-笔记"
    && WorkspaceLayout.documentAgentNotes.label(language: .english) == "Reader-Chat-Notes"
    && WorkspaceLayout.documentNotesAgent.label(language: .chinese) == "阅读-笔记-对话"
    && WorkspaceLayout.documentNotesSplit.label(language: .english) == "Reader / Notes", "layout labels use localized task language instead of internal pane names")
expect(WorkspaceLayout.immersiveConversation.systemImage == "bubble.left.and.text.bubble.right" && WorkspaceLayout.immersiveWriting.systemImage == "square.and.pencil", "immersive layouts expose semantic menu icons")
func readSource(_ relativePath: String) -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}
let agentDataPathsSource = readSource("Sources/WeiBeiCore/WeiBeiAgentDataPaths.swift")
let workspaceStoreSource = readSource("Sources/WeiBei/Stores/WorkspaceStore.swift")
let workspaceModelsSource = readSource("Sources/WeiBeiCore/WorkspaceModels.swift")
let piAgentRuntimeSource = readSource("Sources/WeiBeiCore/PiAgentRuntime.swift")
let piManagementSource = readSource("Sources/WeiBeiCore/AgentResources/management-extension.ts")
let piOAuthSource = readSource("Sources/WeiBei/Support/PiOAuthService.swift")
let credentialProfilesSource = readSource("Sources/WeiBeiCore/AgentCredentialProfiles.swift")
expect(
    piManagementSource.contains("const { ModelRuntime } = await import(PI_PACKAGE)")
        && piManagementSource.contains("ModelRuntime.create")
        && piManagementSource.contains("runtime.getProviders()")
        && piManagementSource.contains("runtime.getModels()")
        && piManagementSource.contains("runtime.listCredentials()")
        && piManagementSource.contains("runtime.login(request.providerId, request.authType")
        && piManagementSource.contains("runtime.logout(request.providerId)")
        && piOAuthSource.contains("runtime.managementCatalog")
        && piOAuthSource.contains("runtime.login(")
        && piOAuthSource.contains("runtime.logout(")
        && agentDataPathsSource.contains("piAgentDirectory")
        && !agentDataPathsSource.contains("secretsDirectory")
        && !agentDataPathsSource.contains("piAuthJSON")
        && !agentDataPathsSource.contains("migrateHomePiAuthIfNeeded")
        && piAgentRuntimeSource.contains("WeiBeiAgentDataPaths.piAgentDirectory")
        && !piAgentRuntimeSource.contains("environment[providerID.environmentAPIKeyName]")
        && !workspaceModelsSource.contains("ModelListProtocol")
        && !workspaceStoreSource.contains("AgentModelListService")
        && !credentialProfilesSource.contains("KeyHelp")
        && !credentialProfilesSource.contains("environmentAPIKeyName"),
    "embedded Pi exclusively owns credentials, provider login, and model discovery"
)
// Provider console metadata stays callable and preserves its public values.
for provider in AgentProviderID.allCases {
    _ = AgentProviderConsoleLinks.loginURL(for: provider)
    _ = AgentProviderConsoleLinks.accountURL(for: provider)
    _ = AgentProviderConsoleLinks.metadata(for: provider)
}
expect(AgentProviderConsoleLinks.loginURL(for: .openai)?.absoluteString == "https://platform.openai.com/api-keys"
    && AgentProviderConsoleLinks.accountURL(for: .openai)?.absoluteString == "https://platform.openai.com/"
    && AgentProviderConsoleLinks.loginURL(for: .openaiCodex)?.absoluteString == "https://platform.openai.com/api-keys"
    && AgentProviderConsoleLinks.accountURL(for: .openaiCodex)?.absoluteString == "https://chatgpt.com/"
    && AgentProviderConsoleLinks.loginURL(for: .anthropic)?.absoluteString == "https://console.anthropic.com/settings/keys"
    && AgentProviderConsoleLinks.accountURL(for: .anthropic)?.absoluteString == "https://claude.ai/"
    && AgentProviderConsoleLinks.loginURL(for: .githubCopilot)?.absoluteString == "https://github.com/settings/copilot"
    && AgentProviderConsoleLinks.accountURL(for: .githubCopilot)?.absoluteString == "https://github.com/login"
    && AgentProviderConsoleLinks.loginURL(for: .xai)?.absoluteString == "https://console.x.ai/"
    && AgentProviderConsoleLinks.accountURL(for: .xai)?.absoluteString == "https://x.ai/"
    && AgentProviderConsoleLinks.loginURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys"
    && AgentProviderConsoleLinks.loginURL(for: .openrouter)?.absoluteString == "https://openrouter.ai/keys"
    && AgentProviderConsoleLinks.loginURL(for: .custom) == nil
    && AgentProviderConsoleLinks.loginURL(for: .llamaCpp) == nil
    && AgentProviderConsoleLinks.loginURL(for: .xiaomi) == nil
    && AgentProviderConsoleLinks.accountURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys",
    "provider console login/account URLs match the golden set")
// WP9: 行文进行中 V3 loading motion — no three-dot pulse card; hang-proof AppKit orbit.
// Deleted overlay views (drawer / corner / quiet insight / compact previews) are gone.
expect(LibraryNavigator.adjacentID(in: [], selectedID: nil, step: 1) == nil, "library navigation empty")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: nil, step: 1) == "a", "library navigation defaults first")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "b", step: 1) == "c", "library navigation next")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "a", step: -1) == "c", "library navigation wraps previous")

expect(SelectionContext(text: "文档", source: .document, ownerTitle: "资料").isNoteSelection == false, "document selection is read-only")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isNoteSelection == true, "note selection is replaceable")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isReplaceableNoteSelection, "editable note selection can be replaced")
expect(!SelectionContext(text: "预览", source: .note, ownerTitle: "资料", isEditable: false).isReplaceableNoteSelection, "preview note selection is not replaceable")
let legacySelection = try! JSONDecoder().decode(
    SelectionContext.self,
    from: Data(#"{"id":"40000000-0000-0000-0000-000000000001","text":"旧选区","source":"note","ownerTitle":"旧笔记","isEditable":true}"#.utf8)
)
expect(legacySelection.itemID == nil && legacySelection.text == "旧选区", "selection records saved before stable item IDs still reopen")
expect(SelectionAttachmentMerge.mergedText(existing: "当前笔记已经覆盖材", incoming: "开头。建议检查是否写了来源、例子和待追问。", withinSelectionGesture: true) == "当前笔记已经覆盖材开头。建议检查是否写了来源、例子和待追问。", "same-gesture selection attachment stitches split live selection fragments into one attachment")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用", incoming: "使用价格的表达", withinSelectionGesture: true) == "利率是资金使用价格的表达", "same-gesture overlapping fragments merge without duplicate overlap text")
expect(SelectionAttachmentMerge.mergedText(existing: "你们", incoming: "好", withinSelectionGesture: true) == "你们好", "same-gesture single-character live-selection fragments merge into one human selection")
expect(SelectionAttachmentMerge.mergedText(existing: "开头。建议检查是否写了来源。", incoming: "你们好", withinSelectionGesture: true) == "开头。建议检查是否写了来源。你们好", "same-gesture short trailing live-selection fragments still merge after sentence punctuation")
expect(SelectionAttachmentMerge.mergedText(existing: "利率", incoming: "利率是资金使用价格", withinSelectionGesture: false) == "利率是资金使用价格", "selection attachment merge still replaces a shorter contained selection with the fuller text")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格。", incoming: "通货膨胀预期会改变真实利率。", withinSelectionGesture: true) == nil, "same-gesture selection attachment does not blindly stitch separate complete sentences")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格", incoming: "通货膨胀预期", withinSelectionGesture: false) == nil, "separate selections outside one gesture remain separate fragments")
expect(SelectionAttachmentMerge.containsSelection("当前笔记已经覆盖材料开头。建议检查是否写了来源。", fragment: "材料 开头。")
    && !SelectionAttachmentMerge.containsSelection("利率是资金使用价格", fragment: ""), "selection attachment containment ignores whitespace and rejects empty fragments")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: true) == 20, "flipped content view keeps selection y")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: false) == 80, "non-flipped content view converts selection y")
expect(!SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false), "selection agent waits for anchor before floating")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: true, pinned: false), "selection agent appears when anchored")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false, keepOpen: true), "keepOpen floats stay visible without a live drag anchor")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: false, hasAnchor: false, pinned: true), "pinned floats stay visible without selection")
expect(SelectionFloatingAgentPlacement.expandedHalfWidth == 190
    && SelectionFloatingAgentPlacement.expandedHalfHeight == 230
    && SelectionFloatingAgentPlacement.compactHalfWidth == 82, "selection agent placement constants bound the narrow expanded surface and compact prompt")
let floatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
let topInsetFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    topInset: 42
)
expect(floatingPoint.x == 522 && floatingPoint.y == 248.5, "selection agent opens close beside the text anchor")
expect(topInsetFloatingPoint.x == 522 && topInsetFloatingPoint.y == 248, "selection agent compensates top bar coordinate space")
let compactEdgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 12, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
let compactCenterFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
expect(compactCenterFloatingPoint.x == 320 && compactCenterFloatingPoint.y == 210, "selection prompt centers on the text anchor when compact")
expect(compactEdgeFloatingPoint.x == 100 && compactEdgeFloatingPoint.y == 210, "selection prompt clamps only at the edge when compact")
let edgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 1160, y: 760),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
expect(edgeFloatingPoint.x == 958 && edgeFloatingPoint.y == 552, "selection agent flips to the left of text near the window edge")
expect(AgentMessage(role: .assistant, text: "整理完成", source: nil).isUsableAgentAnswer, "usable agent answer")
expect(!AgentMessage(role: .assistant, text: "认证已失效", source: nil, failureKind: .unauthorized).isUsableAgentAnswer, "structured authentication failures are not writable")
expect(!AgentMessage(role: .assistant, text: "请求失败", source: nil, failureKind: .generic).isUsableAgentAnswer, "structured agent failures are not writable")
expect(!AgentMessage(
    role: .assistant,
    text: "尚未完成",
    source: nil,
    completionState: .generating
).isUsableAgentAnswer, "a generating reply is not writable before it finishes")
expect(AgentMessage(
    role: .assistant,
    text: "已经生成的安全正文",
    source: nil,
    completionState: .interrupted,
    failureKind: .cancelled,
    retryQuestion: "继续解释"
).isUsableAgentAnswer, "an interrupted reply preserves already generated body text")

let replySource = AgentReplySource(
    id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
    itemID: "material:rates",
    courseID: UUID(uuidString: "30000000-0000-0000-0000-000000000002"),
    kind: .material,
    title: "利率",
    label: "[材料：利率]",
    excerpt: "利率是资金的价格。",
    pageIndex: 17
)
expect(
    replySource.positionLabel(language: .chinese) == "第 18 页",
    "reply sources present their persisted page as a human one-based location"
)
let highlightedReplySource = AgentReplySource(
    itemID: "material:rates",
    kind: .material,
    title: "利率",
    label: "[材料：利率]",
    excerpt: "【第 18 页】\n## 利率\n利率是资金的价格，并受期限和风险影响。"
)
expect(
    highlightedReplySource.highlightQuery == "利率是资金的价格，并受期限和风险影响。",
    "reply source highlighting skips page markers and Markdown headings"
)
let secondReplySource = AgentReplySource(
    id: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!,
    itemID: "material:inflation",
    kind: .material,
    title: "通胀",
    label: "[材料：通胀]",
    excerpt: "通胀改变实际购买力。"
)
let thirdReplySource = AgentReplySource(
    id: UUID(uuidString: "30000000-0000-0000-0000-000000000005")!,
    itemID: "note:rates",
    kind: .note,
    title: "课堂笔记",
    label: "[笔记：课堂笔记]",
    excerpt: "名义利率和实际利率需要分开。"
)
let sourceMarkdown = """
1. 列表保持完整

```swift
let rate = 0.03
```

利率需要结合通胀理解。[材料：利率]、[材料：通胀][笔记：课堂笔记]
"""
let inlineSources = AgentReplySourceInlinePresentation(
    text: sourceMarkdown,
    sources: [replySource, secondReplySource, thirdReplySource],
    language: .chinese
)
let directSourceURL = URL(string: "weibei-source://\(replySource.id.uuidString.lowercased())")!
let additionalSourceURL = URL(string: "weibei-source-group://0")!
let attributedSourceLinks = (try? AttributedString(markdown: inlineSources.markdown))?
    .runs
    .compactMap(\.link) ?? []
expect(
    inlineSources.markdown.contains("```swift\nlet rate = 0.03\n```")
        && inlineSources.markdown.contains("利率 · 第 18 页")
        && inlineSources.markdown.contains("+2")
        && !inlineSources.markdown.contains("[材料：利率]")
        && inlineSources.source(for: directSourceURL) == replySource
        && inlineSources.additionalSources(for: additionalSourceURL)
            == [secondReplySource, thirdReplySource],
    "inline reply sources preserve one Markdown document and collapse adjacent source labels into first plus N"
)
expect(
    attributedSourceLinks.contains(directSourceURL)
        && attributedSourceLinks.contains(additionalSourceURL),
    "native Markdown preserves exact inline source and source-group links"
)
let replyAction = AgentReplyAction(
    id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
    kind: .writeNote,
    targetItemID: "note:rates",
    sourceItemID: "material:rates",
    proposedMarkdown: "## 利率\n利率是资金的价格。",
    evidence: ["[材料：利率]"],
    contextRevision: "revision-1",
    baselineContentDigest: "digest",
    resultContentDigest: "written-digest",
    createdRelationID: UUID(uuidString: "30000000-0000-0000-0000-000000000008"),
    createdAt: Date(timeIntervalSince1970: 10),
    updatedAt: Date(timeIntervalSince1970: 11)
)
let persistentReply = AgentMessage(
    id: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!,
    role: .assistant,
    text: "已经生成的安全正文",
    source: "利率",
    backend: .pi,
    completionState: .interrupted,
    sources: [replySource],
    actions: [replyAction],
    memoryUpdate: AgentReplyMemoryUpdate(
        memoryIDs: [UUID(uuidString: "30000000-0000-0000-0000-000000000005")!],
        summary: "已经理解利率"
    ),
    origin: AgentReplyOrigin(
        requestID: UUID(uuidString: "30000000-0000-0000-0000-000000000006")!,
        chatID: UUID(uuidString: "30000000-0000-0000-0000-000000000007")!,
        courseID: UUID(uuidString: "30000000-0000-0000-0000-000000000002")
    ),
    failureKind: .cancelled,
    retryQuestion: "继续解释",
    toolTrace: ["course-search"],
    createdAt: Date(timeIntervalSince1970: 12)
)
let persistentReplyData = try! JSONEncoder().encode(persistentReply)
let reopenedPersistentReply = try! JSONDecoder().decode(AgentMessage.self, from: persistentReplyData)
expect(reopenedPersistentReply == persistentReply, "reply body, sources, actions, memory update, origin, and interruption state survive JSON reopen")

let replyMemoryID = persistentReply.memoryUpdate!.memoryIDs[0]
let replyRevision = LearningMemoryRevisionRecord(
    revision: 1,
    kind: .understood,
    text: "回答当时已经理解利率",
    evidence: "本轮学习",
    origin: .agentInference,
    status: .active,
    sessionID: persistentReply.origin?.chatID,
    messageID: persistentReply.id,
    actor: .agent,
    recordedAt: Date(timeIntervalSince1970: 12)
)
let laterRevision = LearningMemoryRevisionRecord(
    revision: 2,
    kind: .progress,
    text: "后来只掌握了一部分",
    evidence: "用户修订",
    origin: .userStatement,
    status: .active,
    sessionID: persistentReply.origin?.chatID,
    actor: .user,
    recordedAt: Date(timeIntervalSince1970: 13)
)
let editedReplyMemory = LearningMemoryEntry(
    id: replyMemoryID,
    kind: .progress,
    text: laterRevision.text,
    evidence: laterRevision.evidence,
    origin: laterRevision.origin,
    sessionID: persistentReply.origin?.chatID,
    revisions: [replyRevision, laterRevision]
)
expect(persistentReply.memoryUpdate?.revisions(
    for: persistentReply.id,
    in: [editedReplyMemory]
)?.map(\.text) == [replyRevision.text]
    && persistentReply.memoryUpdate?.revisions(
        for: UUID(),
        in: [editedReplyMemory]
    ) == nil
    && persistentReply.memoryUpdate?.revisions(
        for: persistentReply.id,
        in: []
    ) == nil, "memory update tags show the exact reply revision and fall back to the persisted summary when history is missing")

let legacyReply = AgentMessage(role: .assistant, text: "旧回复", source: nil)
let reopenedLegacyReply = try! JSONDecoder().decode(
    AgentMessage.self,
    from: JSONEncoder().encode(legacyReply)
)
expect(reopenedLegacyReply.completionState == .completed
    && reopenedLegacyReply.sources.isEmpty
    && reopenedLegacyReply.actions.isEmpty, "old reply JSON defaults to a completed reply with no attachments")

var malformedRichReplyObject = try! JSONSerialization.jsonObject(
    with: JSONEncoder().encode(AgentMessage(role: .assistant, text: "正文必须保留", source: nil))
) as! [String: Any]
malformedRichReplyObject["richAnswer"] = ["mode": "broken"]
malformedRichReplyObject["source"] = 42
malformedRichReplyObject["backend"] = "future-backend"
malformedRichReplyObject["completionState"] = "future-state"
malformedRichReplyObject["sources"] = "broken"
malformedRichReplyObject["actions"] = "broken"
let malformedRichReply = try! JSONDecoder().decode(
    AgentMessage.self,
    from: JSONSerialization.data(withJSONObject: malformedRichReplyObject)
)
expect(malformedRichReply.text == "正文必须保留"
    && malformedRichReply.source == nil
    && malformedRichReply.backend == nil
    && malformedRichReply.richAnswer == nil
    && malformedRichReply.completionState == .completed
    && malformedRichReply.sources.isEmpty
    && malformedRichReply.actions.isEmpty
    && malformedRichReply.toolTrace.contains("rich-answer:decode-failed")
    && malformedRichReply.toolTrace.contains("reply-source:decode-failed")
    && malformedRichReply.toolTrace.contains("reply-backend:decode-failed")
    && malformedRichReply.toolTrace.contains("reply-state:decode-failed")
    && malformedRichReply.toolTrace.contains("reply-sources:decode-failed")
    && malformedRichReply.toolTrace.contains("reply-actions:decode-failed"), "broken reply attachments are dropped and diagnosed without swallowing the reply body")

let importedMarkdown = StudyItem(id: "file:/tmp/note.md", title: "note", subtitle: "note.md", kind: .markdown, urlPath: "/tmp/note.md", isSample: false)
let notebookMarkdown = StudyItem(id: "file:/tmp/notebook.md", title: "notebook", subtitle: "notebook.md", kind: .markdown, urlPath: "/tmp/notebook.md", isSample: false, isNotebookNote: true)
let sampleMarkdown = StudyItem(id: "sample", title: "sample", subtitle: "sample", kind: .markdown, urlPath: nil, isSample: true)
expect(importedMarkdown.isImportedMarkdownFile, "imported markdown is readable as material")
expect(!importedMarkdown.editsBackingMarkdownFile, "imported markdown material does not edit backing file")
expect(importedMarkdown.canBecomeNotebookNote, "imported markdown can become an editable notebook note")
expect(notebookMarkdown.editsBackingMarkdownFile, "notebook markdown edits its backing file")
expect(!notebookMarkdown.canBecomeNotebookNote, "notebook markdown does not offer duplicate conversion")
expect(!sampleMarkdown.isImportedMarkdownFile, "sample markdown stays app-owned")
expect(!sampleMarkdown.canBecomeNotebookNote, "sample markdown cannot become a backing-file note")

let relationNoteID = "note:research"
let relationNoteB = "note:shared"
let relationNoteC = "note:replacement"
let relationSourceA = "file:/tmp/a.pdf"
let relationSourceB = "file:/tmp/b.html"
let oldestLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    noteItemID: relationNoteID,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 1)
)
let duplicateLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    noteItemID: relationNoteID,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 2)
)
let sharedSourceLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
    noteItemID: relationNoteB,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 3)
)
let sharedSourceDuplicate = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
    noteItemID: relationNoteB,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 4)
)
let unrelatedSourceLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
    noteItemID: relationNoteID,
    sourceItemID: relationSourceB,
    createdAt: Date(timeIntervalSince1970: 5)
)
var noteSourceRelations = NoteSourceRelations(links: [duplicateLink, oldestLink])
expect(noteSourceRelations.links == [oldestLink]
    && noteSourceRelations.sourceIDs(for: relationNoteID) == [relationSourceA], "note-source relations keep one durable pair and preserve the oldest identity")
noteSourceRelations.replaceSources(for: relationNoteID, sourceItemIDs: [relationSourceB])
expect(noteSourceRelations.sourceIDs(for: relationNoteID) == [relationSourceB]
    && !noteSourceRelations.isLinked(noteItemID: relationNoteID, sourceItemID: relationSourceA), "explicitly replacing a note's sources removes unlinked material")
noteSourceRelations.sanitize(validNoteItemIDs: [relationNoteID], validSourceItemIDs: [relationSourceA])
expect(noteSourceRelations.links.isEmpty, "note-source sanitation removes relationships whose source no longer exists")

var sharedSourceRelations = NoteSourceRelations(
    links: [unrelatedSourceLink, sharedSourceDuplicate, sharedSourceLink, duplicateLink, oldestLink]
)
expect(sharedSourceRelations.links == [oldestLink, sharedSourceLink, unrelatedSourceLink]
    && sharedSourceRelations.noteIDs(for: relationSourceA) == [relationNoteID, relationNoteB], "one source can be shared by multiple notes while duplicate pairs keep their oldest identity")
sharedSourceRelations.replaceNotes(
    for: relationSourceA,
    noteItemIDs: [relationNoteB, relationNoteC]
)
expect(sharedSourceRelations.noteIDs(for: relationSourceA) == [relationNoteB, relationNoteC]
    && sharedSourceRelations.links.contains(sharedSourceLink)
    && sharedSourceRelations.links.contains(unrelatedSourceLink)
    && !sharedSourceRelations.isLinked(noteItemID: relationNoteID, sourceItemID: relationSourceA), "replacing a source's notes preserves retained links and removes only deselected notes")
let relationIndex = NoteSourceRelationIndex(links: sharedSourceRelations.links)
expect(relationIndex.sourceIDs(for: relationNoteB) == [relationSourceA]
    && relationIndex.noteIDs(for: relationSourceA) == [relationNoteB, relationNoteC]
    && relationIndex.sourceCount(for: relationNoteID) == 1
    && relationIndex.noteCount(for: relationSourceB) == 1, "relationship index reuses normalized note-to-source and source-to-note lookups")

let courseMaterials = [
    StudyItem(id: "material:a", title: "第一讲", subtitle: "第一讲.pdf", kind: .pdf, urlPath: "/tmp/course/a.pdf", isSample: false),
    StudyItem(id: "material:b", title: "第二讲", subtitle: "第二讲.html", kind: .html, urlPath: "/tmp/course/b.html", isSample: false),
    StudyItem(id: "material:c", title: "补充材料", subtitle: "补充材料.txt", kind: .text, urlPath: "/tmp/course/c.txt", isSample: false)
]
let courseNotes = [
    StudyItem(id: "note:a", title: "第一讲笔记", subtitle: "第一讲笔记.md", kind: .markdown, urlPath: "/tmp/course/note-a.md", isSample: false, isNotebookNote: true),
    StudyItem(id: "note:b", title: "共同主题", subtitle: "共同主题.md", kind: .markdown, urlPath: "/tmp/course/note-b.md", isSample: false, isNotebookNote: true),
    StudyItem(id: "note:c", title: "待整理", subtitle: "待整理.md", kind: .markdown, urlPath: "/tmp/course/note-c.md", isSample: false, isNotebookNote: true)
]
let builtInSample = StudyItem(id: "sample:ignored", title: "内置样例", subtitle: "样例", kind: .html, urlPath: nil, isSample: true)
let courseLinks = [
    NoteSourceLink(noteItemID: "note:a", sourceItemID: "material:a", createdAt: Date(timeIntervalSince1970: 10)),
    NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:a", createdAt: Date(timeIntervalSince1970: 11)),
    NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:b", createdAt: Date(timeIntervalSince1970: 12)),
    NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:b", createdAt: Date(timeIntervalSince1970: 13)),
    NoteSourceLink(noteItemID: "note:missing", sourceItemID: "material:c", createdAt: Date(timeIntervalSince1970: 14)),
    NoteSourceLink(noteItemID: "note:a", sourceItemID: "sample:ignored", createdAt: Date(timeIntervalSince1970: 15))
]
let firstCourseSessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
let secondCourseSessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
let courseSummary = CourseWorkspaceSummary(
    importedItems: courseMaterials + courseNotes + [builtInSample],
    noteSourceLinks: courseLinks,
    studyLocationsByItemID: [
        "material:a": StudyLocation(itemID: "material:a", itemTitle: "第一讲"),
        "material:c": StudyLocation(itemID: "material:c", itemTitle: "补充材料"),
        "material:missing": StudyLocation(itemID: "material:missing", itemTitle: "已移除资料")
    ],
    studySessions: [
        StudySession(
            id: firstCourseSessionID,
            title: "第一次学习",
            messages: [AgentMessage(role: .user, text: "解释第一讲", source: "第一讲")]
        ),
        StudySession(id: secondCourseSessionID, title: "第二次学习")
    ],
    learningMemoryEntries: [
        LearningMemoryEntry(kind: .confusion, text: "困惑一", evidence: "用户提出", origin: .userStatement),
        LearningMemoryEntry(kind: .confusion, text: "困惑二", evidence: "用户提出", origin: .userStatement),
        LearningMemoryEntry(kind: .confusion, text: "已解决困惑", evidence: "用户提出", origin: .userStatement, status: .resolved),
        LearningMemoryEntry(kind: .goal, text: "课程目标", evidence: "用户提出", origin: .userStatement)
    ]
)
expect(courseSummary.materialCount == 3
    && courseSummary.noteCount == 3
    && courseSummary.explicitLinkCount == 3
    && courseSummary.readingPositionCount == 2
    && courseSummary.unlinkedMaterialCount == 1
    && courseSummary.unlinkedNoteCount == 1
    && courseSummary.studySessionCount == 1
    && courseSummary.unresolvedConfusionCount == 2, "course workspace summary reports only durable facts from the imported course")

let courseHomeHighlightCourseID = UUID(uuidString: "10000000-0000-0000-0000-000000000010")!
let courseHomeHighlightSessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000011")!
let courseHomeHighlightSession = StudySession(
    id: courseHomeHighlightSessionID,
    title: "课程学习",
    messages: [AgentMessage(role: .user, text: "继续学习", source: "课程")],
    courseID: courseHomeHighlightCourseID,
    flow: StudyFlowState(suggestedNext: ["复习第二章"]),
    updatedAt: Date(timeIntervalSince1970: 200)
)
let courseHomeHighlights = CourseHomeLearningHighlights(
    courseID: courseHomeHighlightCourseID,
    learningMemoryEntries: [
        LearningMemoryEntry(
            kind: .understood,
            text: "较新的已掌握内容",
            evidence: "学习表现",
            origin: .agentInference,
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 300)
        ),
        LearningMemoryEntry(
            kind: .summary,
            text: "真实课程小结",
            evidence: "课程学习",
            origin: .agentInference,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        ),
        LearningMemoryEntry(
            kind: .summary,
            text: "已解决的旧小结",
            evidence: "课程学习",
            origin: .agentInference,
            status: .resolved,
            createdAt: Date(timeIntervalSince1970: 400),
            updatedAt: Date(timeIntervalSince1970: 400)
        ),
        LearningMemoryEntry(
            kind: .nextStep,
            text: "完成课程例题",
            evidence: "课程学习",
            origin: .agentInference,
            sessionID: courseHomeHighlightSessionID,
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 150)
        ),
    ],
    studySessions: [courseHomeHighlightSession]
)
expect(courseHomeHighlights.summary?.text == "真实课程小结"
    && courseHomeHighlights.nextStepText == "完成课程例题"
    && courseHomeHighlights.nextStepSessionID == courseHomeHighlightSessionID,
    "course home prefers a real active summary and keeps only an exact same-course Chat action")
let courseHomeFallbackHighlights = CourseHomeLearningHighlights(
    courseID: courseHomeHighlightCourseID,
    learningMemoryEntries: [
        LearningMemoryEntry(
            kind: .progress,
            text: "只是一条进度",
            evidence: "课程学习",
            origin: .agentInference
        )
    ],
    studySessions: [courseHomeHighlightSession]
)
expect(courseHomeFallbackHighlights.summary == nil
    && courseHomeFallbackHighlights.nextStepText == "复习第二章"
    && courseHomeFallbackHighlights.nextStepSessionID == courseHomeHighlightSessionID,
    "course home falls back to a real same-course session suggestion without treating progress as a summary")
let emptyCourseHomeHighlights = CourseHomeLearningHighlights(
    courseID: courseHomeHighlightCourseID,
    learningMemoryEntries: [],
    studySessions: [
        StudySession(
            title: "另一门课",
            messages: [AgentMessage(role: .user, text: "不能串课", source: "另一门课")],
            courseID: UUID(uuidString: "10000000-0000-0000-0000-000000000012"),
            flow: StudyFlowState(suggestedNext: ["不应显示"])
        ),
    ]
)
expect(emptyCourseHomeHighlights.summary == nil
    && emptyCourseHomeHighlights.nextStepText == nil
    && emptyCourseHomeHighlights.nextStepSessionID == nil,
    "course home empty states do not borrow memory or suggestions from another course")
let invalidCourseHomeSessions = [
    StudySession(
        title: "跨课来源",
        messages: [AgentMessage(role: .user, text: "不能跳转", source: "另一门课")],
        courseID: UUID(uuidString: "10000000-0000-0000-0000-000000000012")
    ),
    StudySession(
        title: "未关联来源",
        messages: [AgentMessage(role: .user, text: "不能跳转", source: "未关联")]
    ),
    StudySession(
        title: "空对话来源",
        courseID: courseHomeHighlightCourseID
    ),
]
for invalidSession in invalidCourseHomeSessions {
    let invalidTargetHighlights = CourseHomeLearningHighlights(
        courseID: courseHomeHighlightCourseID,
        learningMemoryEntries: [
            LearningMemoryEntry(
                kind: .summary,
                text: "已解决的小结",
                evidence: "课程学习",
                origin: .agentInference,
                status: .resolved
            ),
            LearningMemoryEntry(
                kind: .understood,
                text: "  \n ",
                evidence: "课程学习",
                origin: .agentInference
            ),
            LearningMemoryEntry(
                kind: .nextStep,
                text: "保留这条真实文字",
                evidence: "课程学习",
                origin: .agentInference,
                sessionID: invalidSession.id
            ),
        ],
        studySessions: invalidCourseHomeSessions
    )
    expect(invalidTargetHighlights.summary == nil
        && invalidTargetHighlights.nextStepText == "保留这条真实文字"
        && invalidTargetHighlights.nextStepSessionID == nil,
        "course home keeps a real next-step text but removes actions for cross-course, unrelated, and empty Chats")
}

let courseA = Course(
    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    title: "货币金融学",
    colorIndex: 0,
    sourceRootPath: "/Courses/Money"
)
let courseB = Course(
    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
    title: "经济思想史",
    colorIndex: 1,
    sourceRootPath: "/Courses/History"
)
var courseMemberships = CourseItemMemberships()
courseMemberships.assign(itemIDs: Set(["material-a", "note-a"]), to: courseA.id)
courseMemberships.assign(itemIDs: Set(["material-a", "material-b"]), to: courseB.id)
expect(Set(courseMemberships.courseIDs(for: "material-a")) == Set([courseA.id, courseB.id])
    && Set(courseMemberships.itemIDs(in: courseA.id)) == Set(["material-a", "note-a"])
    && Set(courseMemberships.itemIDs(in: courseB.id)) == Set(["material-a", "material-b"]), "one item can belong to multiple real courses without duplicating the item")
courseMemberships.replaceCourses(for: "note-a", courseIDs: Set([courseB.id]))
expect(courseMemberships.courseIDs(for: "note-a") == [courseB.id]
    && !courseMemberships.itemIDs(in: courseA.id).contains("note-a"), "changing course membership removes only the replaced item-course pair")

let persisted = PersistedWorkspace(
    courses: [courseA, courseB],
    courseItemMemberships: courseMemberships.values,
    activeCourseID: courseB.id,
    noteSourceLinks: [oldestLink],
    noteSourceLinksMigrationVersion: 1,
    learningMemoryStates: [
        ScopedLearningMemoryState(
            scope: .course(courseA.id),
            revision: 1,
            entries: [
                LearningMemoryEntry(
                    kind: .confusion,
                    text: "利率与贴现率仍会混淆",
                    evidence: "用户在课程 Chat 中提出",
                    origin: .userStatement,
                    sessionID: firstCourseSessionID,
                    revisions: [
                        LearningMemoryRevisionRecord(
                            revision: 1,
                            kind: .confusion,
                            text: "利率与贴现率仍会混淆",
                            evidence: "用户在课程 Chat 中提出",
                            origin: .userStatement,
                            status: .active,
                            sessionID: firstCourseSessionID,
                            actor: .user
                        )
                    ]
                )
            ]
        )
    ],
    learningMemoryScopeMigrationVersion: 1,
    threePaneOrder: [.agent, .reader, .notes],
    noteRenderMode: .preview,
    showLibrary: false,
    showReader: false,
    showAgent: true,
    showNotes: false,
    showRightPane: true,
    showDailyInspiration: false,
    adaptImportedDocumentColors: false
)
let restored = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(persisted))
expect(restored.showLibrary == false && restored.showReader == false && restored.showAgent == true && restored.showNotes == false && restored.showRightPane == true, "pane visibility state persists")
expect(restored.courses == [courseA, courseB]
    && restored.courseItemMemberships == courseMemberships.values
    && restored.activeCourseID == courseB.id, "courses, many-to-many membership, and the active course persist together")
expect(restored.showDailyInspiration == false, "daily inspiration can be disabled and restored from workspace persistence")
let reenabledInspiration = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(PersistedWorkspace(showDailyInspiration: true)))
expect(reenabledInspiration.showDailyInspiration == true, "daily inspiration can be re-enabled and restored from workspace persistence")
let legacyWorkspace = try JSONDecoder().decode(PersistedWorkspace.self, from: Data(#"{"importedItems":[],"notesByItemID":{}}"#.utf8))
expect(legacyWorkspace.showDailyInspiration == nil
    && legacyWorkspace.courses == nil
    && legacyWorkspace.courseItemMemberships == nil
    && legacyWorkspace.activeCourseID == nil,
    "older workspace snapshots remain decodable without inventing a fake course")
expect(restored.adaptImportedDocumentColors == false
    && legacyWorkspace.adaptImportedDocumentColors == nil,
    "imported-document color adaptation persists while old workspaces keep the legacy default")
expect(restored.noteRenderMode == .preview, "legacy preview note mode remains decodable for old workspace snapshots")
expect(restored.threePaneOrder == [.agent, .reader, .notes], "custom three-pane order persists")
expect(restored.noteSourceLinks == [oldestLink] && restored.noteSourceLinksMigrationVersion == 1, "note-source relations and one-time migration state persist together")
expect(restored.learningMemoryStates?.first?.scope == .course(courseA.id)
    && restored.learningMemoryStates?.first?.revision == 1
    && restored.learningMemoryStates?.first?.entries.first?.revisions?.first?.actor == .user
    && restored.learningMemoryScopeMigrationVersion == 1, "scoped learning memories preserve their independent revision history")

let attachmentRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("weibei-self-check-\(UUID().uuidString)", isDirectory: true)
let attachmentDirectory = attachmentRoot.appendingPathComponent(".weibei-assets", isDirectory: true)
let dataURL = "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())"
let firstAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(firstAttachment.src == ".weibei-assets/图 1).png", "attachment uses relative markdown path")
expect(firstAttachment.alt == "图 1)", "attachment alt uses safe stem")
expect(MarkdownAttachmentStore.markdownImage(for: firstAttachment) == "![图 1)](.weibei-assets/图%201%29.png)", "markdown image escapes path")

let secondAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(secondAttachment.src == ".weibei-assets/图 1)-2.png", "attachment avoids overwriting duplicate names")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(firstAttachment.src).path), "first attachment written")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(secondAttachment.src).path), "second attachment written")
let rawAttachment = try MarkdownAttachmentStore.save(
    data: Data([1, 2, 3]),
    originalName: "dragged.webp",
    mime: "",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(rawAttachment.src == ".weibei-assets/dragged.webp", "raw image data save keeps image extension")
expect(MarkdownAttachmentStore.isSupportedImageExtension("HEIC"), "image extension check is case insensitive")
expect(MarkdownAttachmentStore.mimeType(forFileExtension: "jpeg") == "image/jpeg", "mime from extension")
expect(MarkdownAttachmentStore.isSupportedImageExtension("TIF") && MarkdownAttachmentStore.mimeType(forFileExtension: "tif") == "image/tiff" && MarkdownAttachmentStore.fileExtension(originalName: "scan.tif", mime: "image/tiff") == "tif", "TIFF images keep their .tif extension and MIME type")
let blockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "来源：课程 HTML",
    replacing: NSRange(location: ("来源：课程 HTML" as NSString).length, length: 0)
)
expect(blockInsert.text == "来源：课程 HTML\n\n![pasted](Attachments/pasted.png)", "block markdown insertion separates from inline text")
let middleBlockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "前文后文",
    replacing: NSRange(location: ("前文" as NSString).length, length: 0)
)
expect(middleBlockInsert.text == "前文\n\n![pasted](Attachments/pasted.png)\n\n后文", "block markdown insertion separates both sides")
expect(
    CourseDocumentSearchIndex.text("久期衡量利率风险，凸性修正非线性", matchesAnyTermIn: "久期 凸性"),
    "multi-term course search matches freshly written note text before indexing"
)
try? FileManager.default.removeItem(at: attachmentRoot)

print("WeiBei self-check passed")
