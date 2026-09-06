import AppKit
import os
import SwiftUI
import WebKit
import WeiBeiCore

enum WeiBeiWritingFont: String, CaseIterable, Identifiable {
    case system
    case serif
    case literary

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "SF Pro / PingFang SC"
        case .serif: return "Songti SC"
        case .literary: return "WeiBeiStele"
        }
    }
}

final class MarkdownImageSchemeHandler: NSObject, WKURLSchemeHandler, URLSessionDataDelegate, URLSessionTaskDelegate {
    private final class RemoteLoad {
        let schemeTask: WKURLSchemeTask
        let requestURL: URL
        var dataTask: URLSessionDataTask?
        var data = Data()
        var mimeType = ""
        var redirectCount = 0

        init(schemeTask: WKURLSchemeTask, requestURL: URL) {
            self.schemeTask = schemeTask
            self.requestURL = requestURL
        }
    }

    private static let maximumRedirectCount = 5
    var markdownBaseURLString = ""
    var attachmentDirectory: URL?
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    private let loadLock = NSLock()
    private var remoteLoads: [Int: RemoteLoad] = [:]
    private var remoteTaskIDsBySchemeTask: [ObjectIdentifier: Int] = [:]
    private var pendingRemoteSchemeTaskIDs: Set<ObjectIdentifier> = []
    private var stoppedSchemeTaskIDs: Set<ObjectIdentifier> = []
    private var isInvalidated = false
    private let remoteValidationQueue = DispatchQueue(
        label: "WeiBei.MarkdownRemoteImage.Validation",
        qos: .utility
    )
    private let remoteDelegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "WeiBei.MarkdownRemoteImage"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var remoteSession: URLSession?

    private func makeRemoteSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: remoteDelegateQueue
        )
    }

    func invalidate() {
        loadLock.lock()
        guard !isInvalidated else {
            loadLock.unlock()
            return
        }
        isInvalidated = true
        let session = remoteSession
        remoteSession = nil
        remoteLoads.removeAll()
        remoteTaskIDsBySchemeTask.removeAll()
        pendingRemoteSchemeTaskIDs.removeAll()
        stoppedSchemeTaskIDs.removeAll()
        loadLock.unlock()
        session?.invalidateAndCancel()
    }

    var hasActiveRemoteSession: Bool {
        loadLock.lock()
        defer { loadLock.unlock() }
        return remoteSession != nil
    }

    func update(markdownBaseURLString: String, attachmentDirectory: URL?, appearanceMode: WeiBeiAppearanceMode, interfaceLanguage: WeiBeiInterfaceLanguage) {
        self.markdownBaseURLString = markdownBaseURLString
        self.attachmentDirectory = attachmentDirectory
        self.appearanceMode = appearanceMode
        self.interfaceLanguage = interfaceLanguage
    }

    /// Native chat shares the same bounded file and remote-image policy as the editor.
    func loadImage(source: String, completion: @escaping (Data?) -> Void) {
        if source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") {
            let header = String(source[source.index(source.startIndex, offsetBy: 5)..<comma])
            let payload = String(source[source.index(after: comma)...])
            let data = header.hasSuffix(";base64")
                ? Data(base64Encoded: payload)
                : payload.removingPercentEncoding.map { Data($0.utf8) }
            guard let data, data.count <= CourseProjectFileWorker.markdownImageMaximumByteCount,
                  MarkdownAttachmentStore.validatedImageMIMEType(data: data,
                    suggestedMIMEType: String(header.split(separator: ";").first ?? ""), allowsSVG: true) != nil
            else { completion(nil); return }
            completion(data)
            return
        }
        let base = URL(string: markdownBaseURLString)
        guard let sourceURL = URL(string: source, relativeTo: base)?.absoluteURL else {
            completion(nil)
            return
        }
        var request = URLComponents()
        request.scheme = "weibeiimage"
        request.host = "image"
        request.queryItems = [URLQueryItem(name: "src", value: sourceURL.absoluteString)]
        guard let url = request.url else { completion(nil); return }
        start(NativeImageLoad(request: URLRequest(url: url), completion: completion))
    }

    func validatedLocalImageURL(source: String) -> URL? {
        guard let url = URL(string: source, relativeTo: URL(string: markdownBaseURLString))?.absoluteURL,
              url.isFileURL, localImageData(url) != nil else { return nil }
        return url
    }

    private final class NativeImageLoad: NSObject, WKURLSchemeTask {
        let request: URLRequest
        private var data = Data()
        private let completion: (Data?) -> Void

        init(request: URLRequest, completion: @escaping (Data?) -> Void) {
            self.request = request
            self.completion = completion
        }
        func didReceive(_ response: URLResponse) {}
        func didReceive(_ data: Data) { self.data.append(data) }
        func didFinish() {
            let result = data
            DispatchQueue.main.async { self.completion(result) }
        }
        func didFailWithError(_ error: Error) {
            DispatchQueue.main.async { self.completion(nil) }
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        start(urlSchemeTask)
    }

    private func start(_ urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let sourceURL = sourceURL(from: requestURL) else {
            fail(urlSchemeTask, code: 1)
            return
        }

        if sourceURL.isFileURL {
            loadLocalImage(sourceURL, requestURL: requestURL, task: urlSchemeTask)
        } else if sourceURL.scheme?.lowercased() == "https" {
            loadRemoteImage(sourceURL, requestURL: requestURL, task: urlSchemeTask)
        } else {
            fail(urlSchemeTask, code: 2)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let schemeTaskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        loadLock.lock()
        let remoteTaskID = remoteTaskIDsBySchemeTask.removeValue(forKey: schemeTaskID)
        let load = remoteTaskID.flatMap { remoteLoads.removeValue(forKey: $0) }
        if pendingRemoteSchemeTaskIDs.remove(schemeTaskID) != nil {
            stoppedSchemeTaskIDs.insert(schemeTaskID)
        }
        loadLock.unlock()
        load?.dataTask?.cancel()
    }

    private func localImageData(_ fileURL: URL) -> (data: Data, mime: String)? {
        guard let root = allowedRoots().first(where: {
            CourseProjectPathPolicy.relativePath(of: fileURL, inside: $0) != nil
        }),
        let data = try? CourseProjectFileWorker.readBoundedRegularFile(
            at: fileURL, inside: root,
            maximumByteCount: CourseProjectFileWorker.markdownImageMaximumByteCount
        ),
        let mime = MarkdownAttachmentStore.validatedImageMIMEType(
            data: data, suggestedMIMEType: mimeType(for: fileURL), allowsSVG: true
        ) else { return nil }
        return (data, mime)
    }

    private func loadLocalImage(_ fileURL: URL, requestURL: URL, task urlSchemeTask: WKURLSchemeTask) {
        guard let image = localImageData(fileURL) else {
            sendMissingImage(for: requestURL, task: urlSchemeTask)
            return
        }
        send(image.data, mimeType: image.mime, for: requestURL, task: urlSchemeTask)
    }

    private func loadRemoteImage(_ sourceURL: URL, requestURL: URL, task urlSchemeTask: WKURLSchemeTask) {
        let schemeTaskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        loadLock.lock()
        guard !isInvalidated else {
            loadLock.unlock()
            return
        }
        pendingRemoteSchemeTaskIDs.insert(schemeTaskID)
        loadLock.unlock()
        remoteValidationQueue.async { [weak self] in
            guard let self else { return }
            guard let request = Self.sanitizedRemoteRequest(for: sourceURL) else {
                self.loadLock.lock()
                self.pendingRemoteSchemeTaskIDs.remove(schemeTaskID)
                let shouldIgnore = self.isInvalidated
                    || self.stoppedSchemeTaskIDs.remove(schemeTaskID) != nil
                self.loadLock.unlock()
                if !shouldIgnore {
                    self.fail(urlSchemeTask, code: 3)
                }
                return
            }
            let load = RemoteLoad(schemeTask: urlSchemeTask, requestURL: requestURL)
            self.loadLock.lock()
            self.pendingRemoteSchemeTaskIDs.remove(schemeTaskID)
            guard !self.isInvalidated,
                  self.stoppedSchemeTaskIDs.remove(schemeTaskID) == nil else {
                self.loadLock.unlock()
                return
            }
            let session = self.remoteSession ?? self.makeRemoteSession()
            self.remoteSession = session
            let dataTask = session.dataTask(with: request)
            load.dataTask = dataTask
            self.remoteLoads[dataTask.taskIdentifier] = load
            self.remoteTaskIDsBySchemeTask[schemeTaskID] = dataTask.taskIdentifier
            self.loadLock.unlock()
            dataTask.resume()
        }
    }

    private func send(_ data: Data, mimeType: String, for requestURL: URL, task urlSchemeTask: WKURLSchemeTask) {
        let response = URLResponse(
            url: requestURL,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    private func sourceURL(from requestURL: URL) -> URL? {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "src" })?.value,
              let url = URL(string: value) else {
            return nil
        }
        return url.isFileURL ? url.standardizedFileURL : url
    }

    private func allowedRoots() -> [URL] {
        var roots: [URL] = []
        if let baseURL = URL(string: markdownBaseURLString), baseURL.isFileURL {
            roots.append(baseURL)
        }
        if let attachmentDirectory {
            roots.append(attachmentDirectory)
        }
        return roots
    }

    static func sanitizedRemoteRequest(for url: URL) -> URLRequest? {
        guard let validatedURL = try? WeiBeiWebResearchURLPolicy
            .validatedPublicHTTPSURL(url.absoluteString) else {
            return nil
        }
        var request = URLRequest(
            url: validatedURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              response.expectedContentLength <= Int64(CourseProjectFileWorker.markdownImageMaximumByteCount),
              let mimeType = response.mimeType?.lowercased(),
              mimeType.hasPrefix("image/"),
              mimeType != "image/svg+xml",
              let load = remoteLoad(for: dataTask.taskIdentifier) else {
            completionHandler(.cancel)
            failRemoteLoad(taskIdentifier: dataTask.taskIdentifier, code: 4)
            return
        }
        load.mimeType = mimeType
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let load = remoteLoad(for: dataTask.taskIdentifier),
              data.count <= CourseProjectFileWorker.markdownImageMaximumByteCount,
              load.data.count <= CourseProjectFileWorker.markdownImageMaximumByteCount - data.count else {
            dataTask.cancel()
            failRemoteLoad(taskIdentifier: dataTask.taskIdentifier, code: 5)
            return
        }
        load.data.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let load = remoteLoad(for: task.taskIdentifier) else {
            completionHandler(nil)
            return
        }
        load.redirectCount += 1
        guard load.redirectCount <= Self.maximumRedirectCount,
              let url = request.url,
              let sanitized = Self.sanitizedRemoteRequest(for: url) else {
            completionHandler(nil)
            failRemoteLoad(taskIdentifier: task.taskIdentifier, code: 6)
            return
        }
        completionHandler(sanitized)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        willCacheResponse proposedResponse: CachedURLResponse,
        completionHandler: @escaping (CachedURLResponse?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error == nil else {
            failRemoteLoad(taskIdentifier: task.taskIdentifier, code: 7)
            return
        }
        guard let load = takeRemoteLoad(taskIdentifier: task.taskIdentifier) else {
            return
        }
        guard let mimeType = MarkdownAttachmentStore.validatedImageMIMEType(
            data: load.data,
            suggestedMIMEType: load.mimeType,
            allowsSVG: false
        ) else {
            fail(load.schemeTask, code: 7)
            return
        }
        send(load.data, mimeType: mimeType, for: load.requestURL, task: load.schemeTask)
    }

    private func remoteLoad(for taskIdentifier: Int) -> RemoteLoad? {
        loadLock.lock()
        defer { loadLock.unlock() }
        return remoteLoads[taskIdentifier]
    }

    private func takeRemoteLoad(taskIdentifier: Int) -> RemoteLoad? {
        loadLock.lock()
        defer { loadLock.unlock() }
        guard let load = remoteLoads.removeValue(forKey: taskIdentifier) else { return nil }
        remoteTaskIDsBySchemeTask.removeValue(
            forKey: ObjectIdentifier(load.schemeTask as AnyObject)
        )
        return load
    }

    private func failRemoteLoad(taskIdentifier: Int, code: Int) {
        guard let load = takeRemoteLoad(taskIdentifier: taskIdentifier) else { return }
        fail(load.schemeTask, code: code)
    }

    private func fail(_ task: WKURLSchemeTask, code: Int) {
        task.didFailWithError(NSError(
            domain: "WeiBei.MarkdownImageScheme",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: interfaceLanguage.text(
                    "图片无法读取",
                    "Image could not be read"
                )
            ]
        ))
    }

    private func sendMissingImage(for requestURL: URL, task urlSchemeTask: WKURLSchemeTask) {
        let colors = missingImageColors
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="156" height="34" viewBox="0 0 156 34">
          <rect width="156" height="34" rx="3" fill="\(colors.background)"/>
          <path d="M18 22l5-6 4 4 3-3 6 5" fill="none" stroke="\(colors.accent)" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
          <rect x="17" y="11" width="20" height="14" rx="2" fill="none" stroke="\(colors.accent)" stroke-width="1.2"/>
          <text x="48" y="22" fill="\(colors.text)" font-family="-apple-system, BlinkMacSystemFont, 'Songti SC', serif" font-size="13">\(interfaceLanguage.text("图片未找到", "Image missing"))</text>
        </svg>
        """
        let data = Data(svg.utf8)
        let response = URLResponse(
            url: requestURL,
            mimeType: "image/svg+xml",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    private var missingImageColors: (background: String, accent: String, text: String) {
        switch appearanceMode {
        case .paper:
            return ("#efe6d8", "#9f3b2f", "#6b5148")
        case .xuan:
            return ("#f2eee6", "#9a3a2e", "#5f5a52")
        case .inkstone:
            return ("#151515", "#a6362b", "#d7cbb0")
        case .stele:
            return ("#1e2228", "#b04034", "#d2d6dc")
        case .glassLight:
            return ("#edf4fb", "#9c281d", "#46515f")
        case .glassDark:
            return ("#1b2330", "#eb5746", "#e8eef9")
        case .glassMist:
            return ("#f4f9ff", "#8a2f24", "#25231f")
        case .glassSlate:
            return ("#1b212b", "#b04034", "#d2d6dc")
        }
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "svg": return "image/svg+xml"
        default: return MarkdownAttachmentStore.mimeType(forFileExtension: fileURL.pathExtension)
        }
    }
}

private enum MarkdownWebNetworkGuard {
    private static let identifier = "com.changfenhuang.weibei.markdown.block-network.v1"
    private static let rules = """
    [
      {"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^wss?://.*"},"action":{"type":"block"}}
    ]
    """

    static func install(
        in controller: WKUserContentController,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: rules
        ) { ruleList, error in
            DispatchQueue.main.async {
                if let ruleList {
                    controller.add(ruleList)
                    completion(.success(()))
                } else {
                    completion(.failure(error ?? NSError(
                        domain: "WeiBei.MarkdownWebNetworkGuard",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "content rule list unavailable"
                        ]
                    )))
                }
            }
        }
    }
}

final class MarkdownWebView: WKWebView {
    var pasteImageFromClipboard: (() -> Bool)?
    var passesVerticalScrollToSuperview = false {
        didSet { updateScrollWheelMonitor() }
    }
    private var scrollWheelMonitor: Any?

    deinit {
        removeScrollWheelMonitor()
    }

    /// Compact agent/chat previews use a fixed SwiftUI frame. Never answer
    /// Auto Layout with WebKit's systemLayoutSizeFittingSize — that path
    /// dominated hang samples (build 662) while LazyVStack remasured rows.
    override var fittingSize: NSSize {
        guard passesVerticalScrollToSuperview else { return super.fittingSize }
        let size = bounds.size
        return NSSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    override var intrinsicContentSize: NSSize {
        guard passesVerticalScrollToSuperview else { return super.intrinsicContentSize }
        return fittingSize
    }

    /// Compact agent previews must not steal keyboard focus from the composer.
    override var acceptsFirstResponder: Bool {
        passesVerticalScrollToSuperview ? false : super.acceptsFirstResponder
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollWheelMonitor()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           pasteImageFromClipboard?() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard passesVerticalScrollToSuperview,
              abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
            super.scrollWheel(with: event)
            return
        }

        if !forwardVerticalScroll(event) {
            super.scrollWheel(with: event)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passesVerticalScrollToSuperview, NSApp.currentEvent?.type == .scrollWheel {
            return nil
        }
        return super.hitTest(point)
    }

    private func nearestSuperviewScrollView() -> NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private func updateScrollWheelMonitor() {
        guard passesVerticalScrollToSuperview, window != nil else {
            removeScrollWheelMonitor()
            return
        }
        guard scrollWheelMonitor == nil else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.shouldForwardVerticalScroll(event) else {
                return event
            }
            return self.forwardVerticalScroll(event) ? nil : event
        }
    }

    private func removeScrollWheelMonitor() {
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
            self.scrollWheelMonitor = nil
        }
    }

    private func shouldForwardVerticalScroll(_ event: NSEvent) -> Bool {
        guard passesVerticalScrollToSuperview,
              event.window === window,
              abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
            return false
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        return bounds.contains(localPoint)
    }

    @discardableResult
    private func forwardVerticalScroll(_ event: NSEvent) -> Bool {
        guard let outerScrollView = nearestSuperviewScrollView() else { return false }
        outerScrollView.scrollWheel(with: event)
        return true
    }

    @discardableResult
    func scrollOuterSuperview(deltaY: CGFloat) -> Bool {
        guard passesVerticalScrollToSuperview,
              let outerScrollView = nearestSuperviewScrollView(),
              let documentView = outerScrollView.documentView else { return false }
        let clipView = outerScrollView.contentView
        let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
        let direction: CGFloat = documentView.isFlipped ? 1 : -1
        let nextY = min(max(clipView.bounds.origin.y + deltaY * direction, 0), maxY)
        guard abs(nextY - clipView.bounds.origin.y) > 0.01 else { return false }
        clipView.scroll(to: CGPoint(x: clipView.bounds.origin.x, y: nextY))
        outerScrollView.reflectScrolledClipView(clipView)
        return true
    }

}

struct RichMarkdownEditorView: NSViewRepresentable {
    /// Resolved by WeiBeiMotionScope — pushed into the page before first paint and
    /// synced live on preference changes (never reloads the note).
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    /// App-wide text tier multiplier; drives the page's `--weibei-text-scale`
    /// variable so editor body copy follows ⌘+/⌘− without a reload.
    @Environment(\.weiBeiTextScale) private var textScale
    var documentID = ""
    var markdown: String
    @Binding var command: NoteEditorCommand?
    var editingSession: NoteEditingSession? = nil
    var isEditable = true
    var isFocused = false
    var focusRequest = 0
    var markdownBaseURL: URL?
    var attachmentDirectory: URL?
    var searchQuery = ""
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var isCompactPreview = false
    var isChatWideTypography = false
    /// A live read-only answer uses Milkdown's cumulative streaming document
    /// diff. Completion ends that same session and reports its finalized height
    /// back through the existing WebKit message bridge.
    var streamsMarkdownUpdates = false
    var onSelectionChange: (String, CGPoint?) -> Void
    var onSelectionFormattingChange: (NoteSelectionFormatting?) -> Void = { _ in }
    var onLinkEditorRequest: () -> Void = {}
    var onAskAgentWithSelection: (String, CGPoint?) -> Void
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    var onActiveHeadingChange: (Int?) -> Void = { _ in }
    var onOutlineChange: ([NoteEditorOutlineItem]) -> Void = { _ in }
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onRenderReady: () -> Void = {}
    var onFinalizedRenderReady: (CGFloat) -> Void = { _ in }
    var onRenderFailure: () -> Void = {}
    var onContentCommandPending: (String, NoteEditorCommand) -> Void = { _, _ in }
    var onContentCommandApplied: (String, NoteEditorCommand) -> Void = { _, _ in }
    var onCommandRejected: (String, NoteEditorCommand) -> Void = { _, _ in }
    var onSearchResult: (String, Bool) -> Void = { _, _ in }
    /// JSON array of `{id,text}` for selection-ask underline marks (read-only surfaces).
    var selectionAskMarks: String = "[]"
    var onSelectionAskMark: (String) -> Void = { _ in }
    /// JSON array of `{id,text}` for remark marks — 句末朱砂短棒(记过)。
    var selectionRemarkMarks: String = "[]"
    var onSelectionRemarkMark: (String) -> Void = { _ in }
    private static let localImageScheme = "weibeiimage"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            documentID: documentID,
            markdown: markdown,
            command: $command,
            editingSession: editingSession,
            isEditable: isEditable,
            isFocused: isFocused,
            focusRequest: focusRequest,
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            searchQuery: searchQuery,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage,
            streamsMarkdownUpdates: streamsMarkdownUpdates,
            selectionAskMarks: selectionAskMarks,
            selectionRemarkMarks: selectionRemarkMarks,
            onContentHeightChange: onContentHeightChange,
            onActiveHeadingChange: onActiveHeadingChange,
            onOutlineChange: onOutlineChange,
            onSelectionChange: onSelectionChange,
            onSelectionFormattingChange: onSelectionFormattingChange,
            onLinkEditorRequest: onLinkEditorRequest,
            onAskAgentWithSelection: onAskAgentWithSelection,
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onRenderReady: onRenderReady,
            onFinalizedRenderReady: onFinalizedRenderReady,
            onRenderFailure: onRenderFailure,
            onContentCommandPending: onContentCommandPending,
            onContentCommandApplied: onContentCommandApplied,
            onCommandRejected: onCommandRejected,
            onSearchResult: onSearchResult,
            onSelectionAskMark: onSelectionAskMark,
            onSelectionRemarkMark: onSelectionRemarkMark
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WeiBeiWebViewConfiguration.make(surface: .editor)
        let controller = WKUserContentController()
        context.coordinator.imageSchemeHandler.update(
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage
        )
        configuration.setURLSchemeHandler(context.coordinator.imageSchemeHandler, forURLScheme: Self.localImageScheme)
        for name in Self.scriptMessageNames {
            controller.add(context.coordinator, name: name)
        }
        controller.addUserScript(WKUserScript(
            source: """
            window.initialMarkdown = \(Self.json(markdown));
            window.weiBeiDocumentID = \(Self.json(documentID));
            window.weiBeiDocumentGeneration = \(editingSession?.documentGeneration ?? 0);
            window.weiBeiMarkdownEditable = \(isEditable ? "true" : "false");
            window.weiBeiMarkdownBaseURL = \(Self.json(markdownBaseURL?.absoluteString ?? ""));
            window.weiBeiLocalImageScheme = \(Self.json(Self.localImageScheme));
            window.weiBeiTheme = \(Self.json(appearanceMode.webThemeName));
            window.weiBeiInterfaceLanguage = \(Self.json(interfaceLanguage.rawValue));
            window.weiBeiMarkdownCompactPreview = \(isCompactPreview ? "true" : "false");
            window.weiBeiChatWideTypography = \(isChatWideTypography ? "true" : "false");
            window.weiBeiReduceMotion = \(reduceMotion ? "true" : "false");
            document.documentElement.dataset.weibeiReduceMotion = window.weiBeiReduceMotion;
            window.weiBeiTextScale = \(textScale);
            document.documentElement.style.setProperty('--weibei-text-scale', String(window.weiBeiTextScale));
            document.documentElement.dataset.weibeiTheme = window.weiBeiTheme === "glassLight" || window.weiBeiTheme === "glassMist"
              ? "xuan"
              : window.weiBeiTheme === "glassDark" || window.weiBeiTheme === "glassSlate" ? "stele" : window.weiBeiTheme;
            if (["glassLight", "glassDark", "glassMist", "glassSlate"].includes(window.weiBeiTheme)) {
              document.documentElement.dataset.weibeiGlass = window.weiBeiTheme;
            }
            document.documentElement.dataset.weibeiLanguage = window.weiBeiInterfaceLanguage;
            document.documentElement.dataset.weibeiCompactPreview = window.weiBeiMarkdownCompactPreview ? "true" : "false";
            document.documentElement.dataset.weibeiChatWide = window.weiBeiChatWideTypography ? "true" : "false";
            (() => {
              if (window.weiBeiMarkdownCompactPreview) {
                window.addEventListener("wheel", (event) => {
                  if (Math.abs(event.deltaY) < Math.abs(event.deltaX)) return;
                  event.preventDefault();
                  window.webkit?.messageHandlers?.compactPreviewWheel?.postMessage({
                    documentID: window.weiBeiDocumentID || "",
                    deltaY: event.deltaY
                  });
                }, { capture: true, passive: false });
              }
            })();
            """ + Self.selectionAskMarksBootstrapScript + Self.selectionRemarkMarksBootstrapScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller
        WeiBeiWebViewConfiguration.installConsoleErrorBridge(on: controller, surface: .editor)

        let view = MarkdownWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.passesVerticalScrollToSuperview = isCompactPreview
        Self.applyWebAppearance(to: view, appearanceMode: appearanceMode)
        view.pasteImageFromClipboard = { [weak coordinator = context.coordinator] in
            coordinator?.pasteImageFromClipboard() ?? false
        }
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        WeiBeiPerf.event(
            "webview.markdown_create",
            extra:
                "instance=\(context.coordinator.performanceInstanceID.uuidString.lowercased()) surface=\(isEditable ? "editor" : "preview") compact=\(isCompactPreview ? 1 : 0) wide=\(isChatWideTypography ? 1 : 0) doc=\(documentID) mdlen=\(markdown.count)"
        )
        let resourceURL = WeiBeiResources.bundle.url(
            forResource: "index",
            withExtension: "html"
        )
        MarkdownWebNetworkGuard.install(in: controller) {
            [weak view, weak coordinator = context.coordinator] result in
            guard let view else { return }
            guard case .success = result else {
                coordinator?.reportRenderFailure()
                return
            }
            if let resourceURL {
                let editorDirectory = resourceURL.deletingLastPathComponent()
                view.loadFileURL(
                    resourceURL,
                    allowingReadAccessTo: editorDirectory.deletingLastPathComponent()
                )
            } else {
                view.loadHTMLString(
                    "<p>\(interfaceLanguage.text("编辑器资源缺失。", "Editor resources are missing."))</p>",
                    baseURL: nil
                )
            }
        }
        return view
    }

    /// Chat/notes send publishes WorkspaceStore and remasures every markdown WKWebView.
    /// Accept the SwiftUI proposal so AppKit never walks WebKit Auto Layout fittingSize
    /// (cpu_resource + sample 2026-08-01: PlatformView.sizeThatFits freeze on send).
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WKWebView,
        context: Context
    ) -> CGSize? {
        let fallback = nsView.bounds.size
        let width = proposal.width ?? (fallback.width > 1 ? fallback.width : 1)
        let height = proposal.height ?? (fallback.height > 1 ? fallback.height : 1)
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        (view as? MarkdownWebView)?.passesVerticalScrollToSuperview = isCompactPreview
        Self.applyWebAppearance(to: view, appearanceMode: appearanceMode)
        context.coordinator.markdown = markdown
        context.coordinator.command = $command
        context.coordinator.editingSession = editingSession
        let wasStreamingMarkdown = context.coordinator.streamsMarkdownUpdates
        context.coordinator.streamsMarkdownUpdates = streamsMarkdownUpdates
        if !context.coordinator.isReady, wasStreamingMarkdown, !streamsMarkdownUpdates {
            context.coordinator.pendingStreamingCompletion = true
        } else if streamsMarkdownUpdates {
            context.coordinator.pendingStreamingCompletion = false
        }
        if context.coordinator.editingSession != nil {
            context.coordinator.transitionV2DocumentIfNeeded(to: documentID, markdown: markdown)
        } else if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
            context.coordinator.pendingStreamingCompletion = false
            context.coordinator.setDocumentID(documentID)
        }
        context.coordinator.attachmentDirectory = attachmentDirectory
        context.coordinator.imageSchemeHandler.update(
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage
        )
        context.coordinator.searchQuery = searchQuery
        if context.coordinator.appearanceMode != appearanceMode {
            context.coordinator.appearanceMode = appearanceMode
            if context.coordinator.isReady {
                context.coordinator.setTheme(appearanceMode)
            }
        }
        if context.coordinator.interfaceLanguage != interfaceLanguage {
            context.coordinator.interfaceLanguage = interfaceLanguage
            if context.coordinator.isReady {
                context.coordinator.setInterfaceLanguage(interfaceLanguage)
            }
        }
        if context.coordinator.reduceMotion != reduceMotion {
            context.coordinator.reduceMotion = reduceMotion
            if context.coordinator.isReady {
                context.coordinator.setReduceMotion(reduceMotion)
            }
        }
        if context.coordinator.textScale != textScale {
            context.coordinator.textScale = textScale
            if context.coordinator.isReady {
                context.coordinator.setTextScale(textScale)
            }
        }
        context.coordinator.isFocused = isFocused
        context.coordinator.focusRequest = focusRequest
        context.coordinator.onWikiLink = onWikiLink
        context.coordinator.onSourceReference = onSourceReference
        context.coordinator.onRenderReady = onRenderReady
        context.coordinator.onFinalizedRenderReady = onFinalizedRenderReady
        context.coordinator.onRenderFailure = onRenderFailure
        context.coordinator.onContentCommandPending = onContentCommandPending
        context.coordinator.onContentCommandApplied = onContentCommandApplied
        context.coordinator.onCommandRejected = onCommandRejected
        context.coordinator.onSearchResult = onSearchResult
        let nextBaseURL = markdownBaseURL?.absoluteString ?? ""
        if context.coordinator.markdownBaseURLString != nextBaseURL {
            context.coordinator.markdownBaseURLString = nextBaseURL
            context.coordinator.setMarkdownBaseURL(nextBaseURL)
        }
        if context.coordinator.isEditable != isEditable {
            context.coordinator.isEditable = isEditable
            context.coordinator.setEditable(isEditable)
        }
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onSelectionFormattingChange = onSelectionFormattingChange
        context.coordinator.onLinkEditorRequest = onLinkEditorRequest
        context.coordinator.onAskAgentWithSelection = onAskAgentWithSelection
        context.coordinator.onContentHeightChange = onContentHeightChange
        context.coordinator.onActiveHeadingChange = onActiveHeadingChange
        context.coordinator.onOutlineChange = onOutlineChange
        context.coordinator.onSelectionAskMark = onSelectionAskMark
        context.coordinator.selectionAskMarks = selectionAskMarks
        context.coordinator.onSelectionRemarkMark = onSelectionRemarkMark
        context.coordinator.selectionRemarkMarks = selectionRemarkMarks
        if context.coordinator.isChatWideTypography != isChatWideTypography {
            context.coordinator.isChatWideTypography = isChatWideTypography
            if context.coordinator.isReady {
                context.coordinator.setChatWideTypography(isChatWideTypography)
            }
        }

        if context.coordinator.isReady, context.coordinator.editingSession == nil {
            if streamsMarkdownUpdates, isCompactPreview, !isEditable {
                if context.coordinator.webMarkdown != markdown || !wasStreamingMarkdown {
                    context.coordinator.updateStreamingMarkdown(markdown)
                }
            } else if wasStreamingMarkdown {
                context.coordinator.finishStreamingMarkdown(markdown)
            } else if context.coordinator.webMarkdown != markdown {
                context.coordinator.setMarkdown(markdown)
            }
        }

        if context.coordinator.isReady {
            context.coordinator.applySearch()
            context.coordinator.applyFocus()
            context.coordinator.applySelectionAskMarks()
            context.coordinator.applySelectionRemarkMarks()
        }

        context.coordinator.runPendingCommandIfReady()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.rejectUnconfirmedContentCommands()
        coordinator.unbindEditingSession()
        coordinator.imageSchemeHandler.invalidate()
        WeiBeiPerf.event(
            "webview.markdown_destroy",
            extra:
                "instance=\(coordinator.performanceInstanceID.uuidString.lowercased())"
        )
        view.navigationDelegate = nil
        for name in scriptMessageNames {
            view.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    private static let scriptMessageNames = [
        "editorReady",
        "dirtyChanged",
        "snapshotReady",
        "commandApplied",
        "commandRejected",
        "outlineChanged",
        "selectionChanged",
        "askAgentWithSelection",
        "linkEditorRequested",
        "wikiLinkActivated",
        "sourceReferenceActivated",
        "editorFailure",
        "imageAttachmentRequested",
        "imagePickerRequested",
        "contentHeightChanged",
        "finalizedStreaming",
        "activeHeadingChanged",
        "compactPreviewWheel",
        "selectionAskMark",
        "remarkMark",
        "streamDebug"
    ]

    /// CSS + apply helper for cinnabar underlines on asked selections (read-only markdown).
    private static let selectionAskMarksBootstrapScript = """
    (() => {
      if (window.WeiBeiSelectionAskMarks) return;
      const style = document.createElement("style");
      style.textContent = `
        .weibei-selection-ask-mark {
          text-decoration-line: underline;
          text-decoration-color: rgba(145, 38, 27, 0.72);
          text-decoration-thickness: 1.5px;
          text-underline-offset: 3px;
          cursor: pointer;
          border-radius: 2px;
          transition: background-color 120ms ease;
        }
        .weibei-selection-ask-mark:hover {
          background-color: rgba(145, 38, 27, 0.12);
        }
        [data-weibei-theme="inkstone"] .weibei-selection-ask-mark {
          text-decoration-color: rgba(200, 120, 100, 0.85);
        }
        [data-weibei-theme="inkstone"] .weibei-selection-ask-mark:hover {
          background-color: rgba(200, 120, 100, 0.16);
        }
      `;
      document.documentElement.appendChild(style);
      window.WeiBeiSelectionAskMarks = {
        apply: function(marks) {
          window.WeiBeiEditor?.setSelectionAskMarks(marks);
        }
      };
    })();
    """

    private static let selectionRemarkMarksBootstrapScript = """
    (() => {
      if (window.WeiBeiSelectionRemarkMarks) return;
      const style = document.createElement("style");
      style.textContent = `
        .weibei-remark-mark {
          cursor: pointer;
          border-radius: 2px;
          transition: background-color 120ms ease;
        }
        .weibei-remark-mark::after {
          content: "";
          display: inline-block;
          width: 9px;
          height: 9px;
          margin-left: 5px;
          vertical-align: -0.06em;
          border-radius: 50%;
          background-color: rgba(145, 38, 27, 1.0);
        }
        .weibei-remark-mark:hover {
          background-color: rgba(145, 38, 27, 0.14);
        }
        [data-weibei-theme="inkstone"] .weibei-remark-mark::after {
          background-color: rgba(200, 120, 100, 1.0);
        }
        [data-weibei-theme="inkstone"] .weibei-remark-mark:hover {
          background-color: rgba(200, 120, 100, 0.18);
        }
      `;
      document.documentElement.appendChild(style);
      window.WeiBeiSelectionRemarkMarks = {
        apply: function(marks) {
          window.WeiBeiEditor?.setSelectionRemarkMarks(marks);
        }
      };
    })();
    """

    private static func applyWebAppearance(to view: WKWebView, appearanceMode: WeiBeiAppearanceMode) {
        view.underPageBackgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)
        view.appearance = NSAppearance(named: appearanceMode.isDark ? .darkAqua : .aqua)
    }

    private static func json(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var markdown: String
        var command: Binding<NoteEditorCommand?>
        var editingSession: NoteEditingSession?
        var documentID: String
        var onSelectionChange: (String, CGPoint?) -> Void
        var onSelectionFormattingChange: (NoteSelectionFormatting?) -> Void
        var onLinkEditorRequest: () -> Void
        var onAskAgentWithSelection: (String, CGPoint?) -> Void
        var onContentHeightChange: (CGFloat) -> Void
        var onActiveHeadingChange: (Int?) -> Void
        var onOutlineChange: ([NoteEditorOutlineItem]) -> Void
        var onWikiLink: (String) -> Void
        var onSourceReference: (String) -> Void
        var onRenderReady: () -> Void
        var onFinalizedRenderReady: (CGFloat) -> Void
        var onRenderFailure: () -> Void
        var onContentCommandPending: (String, NoteEditorCommand) -> Void
        var onContentCommandApplied: (String, NoteEditorCommand) -> Void
        var onCommandRejected: (String, NoteEditorCommand) -> Void
        var onSearchResult: (String, Bool) -> Void
        var onSelectionAskMark: (String) -> Void
        var selectionAskMarks: String
        var onSelectionRemarkMark: (String) -> Void
        var selectionRemarkMarks: String
        var isChatWideTypography = false
        var streamsMarkdownUpdates: Bool
        weak var webView: WKWebView?
        var isReady = false
        var isEditable: Bool
        var isFocused: Bool
        var focusRequest: Int
        var markdownBaseURLString: String
        var attachmentDirectory: URL?
        var searchQuery: String
        var appearanceMode: WeiBeiAppearanceMode
        var interfaceLanguage: WeiBeiInterfaceLanguage
        var reduceMotion = false
        var textScale: CGFloat = 1
        var webMarkdown = ""
        var pendingStreamingCompletion = false
        var lastCommandID: UUID?
        private var queuedCommands: [InFlightCommand] = []
        private var inFlightCommand: InFlightCommand?
        private var editingSessionBindingToken: UUID?
        private var pendingV2DocumentID: String?
        let performanceInstanceID = UUID()
        fileprivate let imageSchemeHandler = MarkdownImageSchemeHandler()
        private var lastAppliedSearchQuery = ""
        private var lastAppliedFocusRequest = -1
        private var lastAppliedSelectionAskMarks = ""
        private var lastAppliedSelectionRemarkMarks = ""
        private var finalizedRenderGeneration = 0
        private var hasReportedRenderFailure = false
        private var pendingFinalizedRenderGeneration: Int?

        private struct InFlightCommand {
            let command: NoteEditorCommand
            let documentID: String
            let documentGeneration: UInt64
            let minimumRevision: UInt64
        }

        init(
            documentID: String,
            markdown: String,
            command: Binding<NoteEditorCommand?>,
            editingSession: NoteEditingSession?,
            isEditable: Bool,
            isFocused: Bool,
            focusRequest: Int,
            markdownBaseURLString: String,
            attachmentDirectory: URL?,
            searchQuery: String,
            appearanceMode: WeiBeiAppearanceMode,
            interfaceLanguage: WeiBeiInterfaceLanguage,
            streamsMarkdownUpdates: Bool,
            selectionAskMarks: String,
            selectionRemarkMarks: String,
            onContentHeightChange: @escaping (CGFloat) -> Void,
            onActiveHeadingChange: @escaping (Int?) -> Void,
            onOutlineChange: @escaping ([NoteEditorOutlineItem]) -> Void,
            onSelectionChange: @escaping (String, CGPoint?) -> Void,
            onSelectionFormattingChange: @escaping (NoteSelectionFormatting?) -> Void,
            onLinkEditorRequest: @escaping () -> Void,
            onAskAgentWithSelection: @escaping (String, CGPoint?) -> Void,
            onWikiLink: @escaping (String) -> Void,
            onSourceReference: @escaping (String) -> Void,
            onRenderReady: @escaping () -> Void,
            onFinalizedRenderReady: @escaping (CGFloat) -> Void,
            onRenderFailure: @escaping () -> Void,
            onContentCommandPending: @escaping (String, NoteEditorCommand) -> Void,
            onContentCommandApplied: @escaping (String, NoteEditorCommand) -> Void,
            onCommandRejected: @escaping (String, NoteEditorCommand) -> Void,
            onSearchResult: @escaping (String, Bool) -> Void,
            onSelectionAskMark: @escaping (String) -> Void,
            onSelectionRemarkMark: @escaping (String) -> Void
        ) {
            self.documentID = documentID
            self.markdown = markdown
            self.command = command
            self.editingSession = editingSession
            self.isEditable = isEditable
            self.isFocused = isFocused
            self.focusRequest = focusRequest
            self.markdownBaseURLString = markdownBaseURLString
            self.attachmentDirectory = attachmentDirectory
            self.searchQuery = searchQuery
            self.appearanceMode = appearanceMode
            self.interfaceLanguage = interfaceLanguage
            self.streamsMarkdownUpdates = streamsMarkdownUpdates
            self.selectionAskMarks = selectionAskMarks
            self.selectionRemarkMarks = selectionRemarkMarks
            self.onContentHeightChange = onContentHeightChange
            self.onActiveHeadingChange = onActiveHeadingChange
            self.onOutlineChange = onOutlineChange
            self.onSelectionChange = onSelectionChange
            self.onSelectionFormattingChange = onSelectionFormattingChange
            self.onLinkEditorRequest = onLinkEditorRequest
            self.onAskAgentWithSelection = onAskAgentWithSelection
            self.onWikiLink = onWikiLink
            self.onSourceReference = onSourceReference
            self.onRenderReady = onRenderReady
            self.onFinalizedRenderReady = onFinalizedRenderReady
            self.onRenderFailure = onRenderFailure
            self.onContentCommandPending = onContentCommandPending
            self.onContentCommandApplied = onContentCommandApplied
            self.onCommandRejected = onCommandRejected
            self.onSearchResult = onSearchResult
            self.onSelectionAskMark = onSelectionAskMark
            self.onSelectionRemarkMark = onSelectionRemarkMark
        }

        func bindEditingSession() {
            guard let editingSession, editingSessionBindingToken == nil else { return }
            editingSessionBindingToken = editingSession.bindSnapshotRequestHandler { [weak self] request in
                self?.dispatchV2(request)
            }
        }

        func unbindEditingSession() {
            guard let editingSession, let editingSessionBindingToken else { return }
            editingSession.unbindSnapshotRequestHandler(editingSessionBindingToken)
            self.editingSessionBindingToken = nil
        }

        func transitionV2DocumentIfNeeded(to nextDocumentID: String, markdown: String) {
            guard let editingSession else { return }
            if nextDocumentID == editingSession.documentID {
                guard isReady, !editingSession.dirty, webMarkdown != markdown else { return }
                editingSession.replaceDocument(with: nextDocumentID)
                documentID = nextDocumentID
                loadV2Document(markdown)
                return
            }
            guard
                  pendingV2DocumentID != nextDocumentID else { return }

            let sourceDocumentID = editingSession.documentID
            let loadNext = { [weak self, weak editingSession] (nextMarkdown: String) in
                guard let self, let editingSession,
                      self.pendingV2DocumentID == nextDocumentID else { return }
                self.pendingV2DocumentID = nil
                editingSession.replaceDocument(with: nextDocumentID)
                self.documentID = nextDocumentID
                self.loadV2Document(nextMarkdown)
            }

            pendingV2DocumentID = nextDocumentID
            if isReady, editingSession.dirty {
                editingSession.requestSnapshot { [weak self] result in
                    switch result {
                    case .success(let snapshot):
                        loadNext(sourceDocumentID.hasPrefix("draft:") ? snapshot.markdown : markdown)
                    case .failure:
                        self?.pendingV2DocumentID = nil
                        self?.reportRenderFailure()
                    }
                }
            } else {
                loadNext(markdown)
            }
        }

        private func loadV2Document(_ markdown: String) {
            guard isReady, let editingSession else { return }
            webMarkdown = markdown
            dispatchV2(NoteEditorCommandEnvelope(
                documentID: editingSession.documentID,
                documentGeneration: editingSession.documentGeneration,
                type: .loadDocument,
                payload: NoteEditorLoadDocumentPayload(
                    markdown: markdown,
                    initialRevision: editingSession.currentRevision
                )
            ))
        }

        private func dispatchV2<Payload>(_ command: NoteEditorCommandEnvelope<Payload>) {
            guard let data = try? JSONEncoder().encode(command),
                  let json = String(data: data, encoding: .utf8) else { return }
            evaluate("window.WeiBeiEditor?.dispatchCommand(\(json))")
        }
        private func decodeV2Event<Event: Decodable>(_ type: Event.Type, from body: Any) -> Event? {
            guard JSONSerialization.isValidJSONObject(body),
                  let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportRenderFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportRenderFailure()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                // Initial local editor load and in-page programmatic updates.
                decisionHandler(.allow)
                return
            }
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if Self.isSamePageFragment(targetURL, currentURL: webView.url) {
                decisionHandler(.allow)
                return
            }

            let scheme = targetURL.scheme?.lowercased()
            if scheme == "weibei-source" || scheme == "weibei-source-group" {
                onSourceReference(targetURL.absoluteString)
            } else if scheme == "http" || scheme == "https" || scheme == "mailto" {
                NSWorkspace.shared.open(targetURL)
            }
            // Never replace an answer/editor with an external or unknown page.
            decisionHandler(.cancel)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            reportRenderFailure()
        }

        private static func isSamePageFragment(_ targetURL: URL, currentURL: URL?) -> Bool {
            guard targetURL.fragment?.isEmpty == false,
                  let currentURL,
                  var target = URLComponents(url: targetURL, resolvingAgainstBaseURL: true),
                  var current = URLComponents(url: currentURL, resolvingAgainstBaseURL: true) else {
                return false
            }
            target.fragment = nil
            current.fragment = nil
            return target.url == current.url
        }

        fileprivate func reportRenderFailure() {
            guard !hasReportedRenderFailure else { return }
            hasReportedRenderFailure = true
            // A failure can race the finalized JavaScript evaluation. Invalidate
            // that completion before exposing the native fallback so a broken
            // WebView cannot become ready again.
            finalizedRenderGeneration &+= 1
            pendingFinalizedRenderGeneration = nil
            isReady = false
            rejectUnconfirmedContentCommands()
            onRenderFailure()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // The SwiftUI document can change while the WebView is still booting.
            // Its one ready callback still belongs to this WebView and must be
            // accepted so we can push the latest document into it. Every later
            // callback remains scoped to the current document identity.
            if message.name != "editorReady" {
                guard messageMatchesDocument(message.body) else { return }
            }
            switch message.name {
            case "streamDebug":
                break
            case "editorReady":
                hasReportedRenderFailure = false
                isReady = true
                bindEditingSession()
                setMarkdownBaseURL(markdownBaseURLString)
                if let editingSession {
                    documentID = editingSession.documentID
                    loadV2Document(markdown)
                    setEditable(isEditable)
                    setInterfaceLanguage(interfaceLanguage)
                } else if let text = (message.body as? [String: Any])?["markdown"] as? String {
                    setDocumentID(documentID)
                    setEditable(isEditable)
                    setInterfaceLanguage(interfaceLanguage)
                    webMarkdown = text
                    if streamsMarkdownUpdates {
                        updateStreamingMarkdown(markdown)
                    } else if pendingStreamingCompletion {
                        pendingStreamingCompletion = false
                        finishStreamingMarkdown(markdown)
                    } else if markdown == text {
                        webMarkdown = text
                    } else {
                        setMarkdown(markdown)
                    }
                } else {
                    setDocumentID(documentID)
                    setEditable(isEditable)
                    setInterfaceLanguage(interfaceLanguage)
                    // The JS editor initialized with the markdown baked in at
                    // page load; tokens that accumulated during the cold start
                    // (and any completion that landed before ready) must be
                    // replayed now, or a short answer would stay frozen on the
                    // first chunk forever.
                    if streamsMarkdownUpdates {
                        updateStreamingMarkdown(markdown)
                    } else if pendingStreamingCompletion {
                        pendingStreamingCompletion = false
                        finishStreamingMarkdown(markdown)
                    } else {
                        webMarkdown = markdown
                    }
                }
                applySearch()
                setTheme(appearanceMode)
                setChatWideTypography(isChatWideTypography)
                setTextScale(textScale)
                applyFocus()
                applySelectionAskMarks(force: true)
                applySelectionRemarkMarks(force: true)
                runPendingCommandIfReady()
                onRenderReady()
            case "dirtyChanged":
                guard let event = decodeV2Event(NoteEditorDirtyChangedEvent.self, from: message.body) else { return }
                _ = editingSession?.receive(event)
            case "snapshotReady":
                guard let event = decodeV2Event(NoteEditorSnapshotReadyEvent.self, from: message.body) else { return }
                if editingSession?.receive(event) == true {
                    webMarkdown = event.markdown
                }
            case "commandApplied":
                guard let event = decodeV2Event(NoteEditorCommandResultEvent.self, from: message.body) else { return }
                finishCommand(
                    event.commandID,
                    documentID: event.documentID,
                    documentGeneration: event.documentGeneration,
                    rejectionReason: nil
                )
            case "commandRejected":
                guard let event = decodeV2Event(NoteEditorCommandResultEvent.self, from: message.body) else { return }
                finishCommand(
                    event.commandID,
                    documentID: event.documentID,
                    documentGeneration: event.documentGeneration,
                    rejectionReason: event.reason ?? "rejected"
                )
            case "outlineChanged":
                guard let event = decodeV2Event(
                    NoteEditorOutlineChangedEvent.self,
                    from: message.body
                ), event.documentID == editingSession?.documentID,
                   event.documentGeneration == editingSession?.documentGeneration else { return }
                onOutlineChange(event.items)
            case "selectionChanged":
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String else { return }
                onSelectionChange(text, anchor(from: body["rect"] as? [String: Any]))
                if text.isEmpty {
                    onSelectionFormattingChange(nil)
                } else {
                    onSelectionFormattingChange(NoteSelectionFormatting(
                        activeMarks: Set(body["activeMarks"] as? [String] ?? []),
                        blockType: body["blockType"] as? String ?? "",
                        canConvertToMath: body["canConvertToMath"] as? Bool ?? false,
                        linkTarget: body["linkTarget"] as? String ?? ""
                    ))
                }
            case "askAgentWithSelection":
                guard let body = message.body as? [String: Any] else { return }
                let text = body["text"] as? String ?? ""
                onAskAgentWithSelection(text, anchor(from: body["rect"] as? [String: Any]))
            case "linkEditorRequested":
                onLinkEditorRequest()
            case "selectionAskMark":
                guard let body = message.body as? [String: Any],
                      let threadID = body["threadId"] as? String,
                      !threadID.isEmpty else { return }
                onSelectionAskMark(threadID)
            case "remarkMark":
                guard let body = message.body as? [String: Any],
                      let recordID = body["recordId"] as? String,
                      !recordID.isEmpty else { return }
                onSelectionRemarkMark(recordID)
            case "wikiLinkActivated":
                guard let body = message.body as? [String: Any],
                      let title = body["title"] as? String else { return }
                onWikiLink(title)
            case "sourceReferenceActivated":
                guard let body = message.body as? [String: Any],
                      let reference = body["reference"] as? String else { return }
                onSourceReference(reference)
            case "imageAttachmentRequested":
                guard isEditable,
                      let body = message.body as? [String: Any],
                      let id = body["id"] as? String else { return }
                if let attachment = saveImageAttachment(from: body) {
                    evaluate("""
                    window.WeiBeiEditor?.resolveAttachment(
                      \(Self.json(id)),
                      \(Self.json(attachment.src)),
                      \(Self.json(attachment.alt))
                    )
                    """)
                } else {
                    evaluate("window.WeiBeiEditor?.rejectAttachment(\(Self.json(id)), \(Self.json(interfaceLanguage.text("图片无法写入本地附件目录", "Image could not be written to the local attachments folder")))")
                }
            case "imagePickerRequested":
                guard isEditable,
                      let body = message.body as? [String: Any],
                      let id = body["id"] as? String else { return }
                presentImagePicker(requestID: id, documentID: documentID)
            case "contentHeightChanged":
                guard let body = message.body as? [String: Any],
                      let height = body["height"] as? Double else { return }
                WeiBeiPerf.event(
                    "webview.markdown_height_received",
                    extra:
                        "instance=\(performanceInstanceID.uuidString.lowercased())"
                )
                onContentHeightChange(CGFloat(height))
            case "finalizedStreaming":
                guard let body = message.body as? [String: Any],
                      let height = body["height"] as? Double,
                      height.isFinite,
                      height > 0,
                      pendingFinalizedRenderGeneration == finalizedRenderGeneration else { return }
                pendingFinalizedRenderGeneration = nil
                onFinalizedRenderReady(CGFloat(height))
            case "editorFailure":
                reportRenderFailure()
            case "activeHeadingChanged":
                guard let body = message.body as? [String: Any] else { return }
                onActiveHeadingChange((body["index"] as? NSNumber)?.intValue)
            case "compactPreviewWheel":
                guard let body = message.body as? [String: Any],
                      let deltaY = body["deltaY"] as? Double else { return }
                (webView as? MarkdownWebView)?.scrollOuterSuperview(deltaY: CGFloat(deltaY))
            default:
                break
            }
        }

        private func messageMatchesDocument(_ body: Any) -> Bool {
            guard let body = body as? [String: Any],
                  let messageDocumentID = body["documentID"] as? String else {
                return documentID.isEmpty
            }
            return messageDocumentID == documentID
        }

        func setMarkdown(_ text: String) {
            finalizedRenderGeneration &+= 1
            pendingFinalizedRenderGeneration = nil
            webMarkdown = text
            evaluate("window.WeiBeiEditor?.setMarkdown(\(Self.json(text)))")
        }

        func updateStreamingMarkdown(_ text: String) {
            finalizedRenderGeneration &+= 1
            pendingFinalizedRenderGeneration = nil
            let previous = webMarkdown
            webMarkdown = text
            // The WebView already holds `previous`, so a pure extension only
            // needs the appended suffix; re-sending the full document would
            // JSON-encode and cross-process-compile an ever-growing script
            // on every streaming tick. Any non-extension falls back to full.
            if !previous.isEmpty, text.hasPrefix(previous) {
                let suffix = text[previous.endIndex...]
                guard !suffix.isEmpty else { return }
                evaluate("window.WeiBeiEditor?.appendStreamingMarkdown(\(Self.json(String(suffix))))")
            } else {
                evaluate("window.WeiBeiEditor?.updateStreamingMarkdown(\(Self.json(text)))")
            }
        }

        func finishStreamingMarkdown(_ text: String) {
            finalizedRenderGeneration &+= 1
            let generation = finalizedRenderGeneration
            let finalizedDocumentID = documentID
            pendingFinalizedRenderGeneration = generation
            webMarkdown = text
            webView?.evaluateJavaScript("""
            (() => {
              const didFinish = window.WeiBeiEditor?.finishStreamingMarkdown(\(Self.json(text)));
              return didFinish === true;
            })();
            """) { [weak self] value, error in
                guard let self,
                      generation == self.finalizedRenderGeneration,
                      finalizedDocumentID == self.documentID else { return }
                guard error == nil,
                      value as? Bool == true else {
                    self.pendingFinalizedRenderGeneration = nil
                    self.reportRenderFailure()
                    return
                }
                // Scheduling succeeded. `finalizedStreaming` is the only ready
                // signal; it arrives after the final body push, caret retirement,
                // session end, and authoritative height publication.
            }
        }

        func setEditable(_ editable: Bool) {
            guard let editingSession else { return }
            dispatchV2(NoteEditorCommandEnvelope(
                documentID: editingSession.documentID,
                documentGeneration: editingSession.documentGeneration,
                type: .setEditable,
                payload: NoteEditorEditablePayload(editable: editable)
            ))
        }

        func setDocumentID(_ id: String) {
            evaluate("window.WeiBeiEditor?.setDocumentID(\(Self.json(id)))")
        }

        func setMarkdownBaseURL(_ url: String) {
            evaluate("window.WeiBeiEditor?.setMarkdownBaseURL(\(Self.json(url)))")
        }

        func setTheme(_ mode: WeiBeiAppearanceMode) {
            if let editingSession {
                dispatchV2(NoteEditorCommandEnvelope(
                    documentID: editingSession.documentID,
                    documentGeneration: editingSession.documentGeneration,
                    type: .setTheme,
                    payload: NoteEditorThemePayload(theme: mode.webThemeName)
                ))
            } else {
                evaluate("window.WeiBeiEditor?.setTheme?.(\(Self.json(mode.webThemeName)))")
            }
        }

        func setInterfaceLanguage(_ language: WeiBeiInterfaceLanguage) {
            if let editingSession {
                dispatchV2(NoteEditorCommandEnvelope(
                    documentID: editingSession.documentID,
                    documentGeneration: editingSession.documentGeneration,
                    type: .setLanguage,
                    payload: NoteEditorLanguagePayload(language: language.rawValue)
                ))
            } else {
                evaluate("window.WeiBeiEditor?.setInterfaceLanguage?.(\(Self.json(language.rawValue)))")
            }
        }

        /// Live reduce-motion sync into the existing page — no reload, no
        /// protocol extension; the page only ever sees the final boolean.
        func setReduceMotion(_ reduce: Bool) {
            evaluate("window.WeiBeiEditor?.setReduceMotion?.(\(reduce ? "true" : "false"))")
        }

        /// Live text-scale sync into the existing page — same contract as the
        /// page-side `--weibei-text-scale` variable, no reload involved.
        func setTextScale(_ scale: CGFloat) {
            evaluate("window.WeiBeiEditor?.setTextScale?.(\(scale))")
        }

        func setChatWideTypography(_ wide: Bool) {
            evaluate("""
            window.weiBeiChatWideTypography = \(wide ? "true" : "false");
            document.documentElement.dataset.weibeiChatWide = window.weiBeiChatWideTypography ? "true" : "false";
            """)
        }

        private func run(_ inFlight: InFlightCommand) {
            let command = inFlight.command
            let type: NoteEditorCommandType
            switch command.kind {
            case .replaceSelection: type = .replaceSelection
            case .selectionCommand:
                dispatchQueued(NoteEditorCommandEnvelope(
                    commandID: command.id.uuidString,
                    documentID: inFlight.documentID,
                    documentGeneration: inFlight.documentGeneration,
                    minimumRevision: inFlight.minimumRevision,
                    type: .executeSelectionCommand,
                    payload: NoteEditorSelectionCommandPayload(action: command.markdown, value: command.value)
                ), source: inFlight)
                return
            case .applyAgentPatch: type = .applyMarkdownFragment
            case .insertMarkdown: type = .insertStructuredBlock
            case .reloadDocument:
                webMarkdown = command.markdown
                dispatchQueued(NoteEditorCommandEnvelope(
                    commandID: command.id.uuidString,
                    documentID: inFlight.documentID,
                    documentGeneration: inFlight.documentGeneration,
                    type: .loadDocument,
                    payload: NoteEditorLoadDocumentPayload(
                        markdown: command.markdown,
                        initialRevision: inFlight.minimumRevision
                    )
                ), source: inFlight)
                return
            case .scrollToHeading:
                guard let index = Int(command.markdown) else {
                    rejectCommand(inFlight, reason: "invalid heading index")
                    return
                }
                dispatchQueued(NoteEditorCommandEnvelope(
                    commandID: command.id.uuidString,
                    documentID: inFlight.documentID,
                    documentGeneration: inFlight.documentGeneration,
                    minimumRevision: inFlight.minimumRevision,
                    type: .scrollToHeading,
                    payload: NoteEditorScrollPayload(index: index)
                ), source: inFlight)
                return
            }
            dispatchQueued(NoteEditorCommandEnvelope(
                commandID: command.id.uuidString,
                documentID: inFlight.documentID,
                documentGeneration: inFlight.documentGeneration,
                minimumRevision: inFlight.minimumRevision,
                type: type,
                payload: NoteEditorMarkdownPayload(markdown: command.markdown)
            ), source: inFlight)
        }

        func runPendingCommandIfReady() {
            ingestCommandBinding()
            guard isReady,
                  pendingV2DocumentID == nil,
                  inFlightCommand == nil,
                  let next = queuedCommands.first else { return }
            inFlightCommand = next
            run(next)
        }

        /// 内容命令保序且不设数量上限；只有最终状态可替代前态的命令合并。
        private func ingestCommandBinding() {
            guard let pending = command.wrappedValue,
                  pending.id != lastCommandID,
                  !queuedCommands.contains(where: {
                      $0.command.id == pending.id
                  }),
                  let editingSession else { return }
            let source = InFlightCommand(
                command: pending,
                documentID: editingSession.documentID,
                documentGeneration: editingSession.documentGeneration,
                minimumRevision: editingSession.currentRevision
            )
            if let tail = queuedCommands.last,
               tail.command.id != inFlightCommand?.command.id,
               tail.command.kind == pending.kind,
               pending.kind == .reloadDocument || pending.kind == .scrollToHeading {
                queuedCommands[queuedCommands.count - 1] = source
            } else {
                queuedCommands.append(source)
            }
            if pending.kind.isContentCommand {
                onContentCommandPending(source.documentID, pending)
            }
            let ingestedID = pending.id
            DispatchQueue.main.async {
                if self.command.wrappedValue?.id == ingestedID {
                    self.command.wrappedValue = nil
                }
            }
        }

        private func dispatchQueued<Payload>(
            _ envelope: NoteEditorCommandEnvelope<Payload>,
            source: InFlightCommand
        ) {
            guard let data = try? JSONEncoder().encode(envelope),
                  let json = String(data: data, encoding: .utf8),
                  let webView else {
                rejectCommand(source, reason: "bridge unavailable")
                return
            }
            webView.evaluateJavaScript("window.WeiBeiEditor?.dispatchCommand(\(json))") { [weak self] result, error in
                guard let self,
                      self.inFlightCommand?.command.id == source.command.id else { return }
                if let error {
                    Self.bridgeLogger.error(
                        "editor command evaluation failed: \(error.localizedDescription, privacy: .private)"
                    )
                    self.rejectCommand(source, reason: "javascript evaluation failed")
                } else if result as? Bool != true {
                    Self.bridgeLogger.error("editor command was not accepted by the web bridge")
                    self.rejectCommand(source, reason: "command was not accepted")
                }
            }
        }

        private func finishCommand(
            _ commandID: String,
            documentID: String,
            documentGeneration: UInt64,
            rejectionReason: String?
        ) {
            guard let id = UUID(uuidString: commandID),
                  let inFlight = inFlightCommand,
                  id == inFlight.command.id,
                  documentID == inFlight.documentID,
                  documentGeneration == inFlight.documentGeneration,
                  queuedCommands.first?.command.id == id else { return }
            let source = queuedCommands.removeFirst()
            inFlightCommand = nil
            if let rejectionReason {
                Self.bridgeLogger.error(
                    "editor command rejected: \(rejectionReason, privacy: .private)"
                )
                if command.wrappedValue?.id == source.command.id {
                    command.wrappedValue = nil
                }
                onCommandRejected(source.documentID, source.command)
            } else {
                lastCommandID = source.command.id
                if source.command.kind.isContentCommand {
                    onContentCommandApplied(
                        source.documentID,
                        source.command
                    )
                }
            }
            runPendingCommandIfReady()
        }

        func rejectUnconfirmedContentCommands() {
            ingestCommandBinding()
            let abandoned = queuedCommands
            queuedCommands.removeAll()
            inFlightCommand = nil
            if let bound = command.wrappedValue,
               bound.id == lastCommandID || abandoned.contains(where: {
                   $0.command.id == bound.id
               }) {
                command.wrappedValue = nil
            }
            for source in abandoned
            where source.command.kind.isContentCommand {
                onCommandRejected(source.documentID, source.command)
            }
        }

        private func rejectCommand(_ source: InFlightCommand, reason: String) {
            guard inFlightCommand?.command.id == source.command.id else { return }
            finishCommand(
                source.command.id.uuidString,
                documentID: source.documentID,
                documentGeneration: source.documentGeneration,
                rejectionReason: reason
            )
        }

        private static let bridgeLogger = Logger(
            subsystem: "app.weibei.Weibei",
            category: "NoteEditorBridge"
        )

        private func evaluate(_ script: String) {
            // 出错不再无声吞掉：脚本头 160 字符进统一日志，排查编辑器桥问题有迹可循。
            webView?.evaluateJavaScript(script) { _, error in
                if let error {
                    Self.bridgeLogger.warning(
                        "editor script failed: \(error.localizedDescription) script: \(script.prefix(160), privacy: .public)"
                    )
                }
            }
        }

        func applySearch() {
            let query = ReaderSearch.cleaned(searchQuery)
            guard query != lastAppliedSearchQuery else { return }
            lastAppliedSearchQuery = query
            let script = """
            (() => {
              const query = \(Self.json(query));
              const selection = window.getSelection();
              selection?.removeAllRanges();
              window.webkit?.messageHandlers?.selectionChanged?.postMessage({
                text: "",
                rect: null,
                documentID: window.weiBeiDocumentID || ""
              });
              if (!query) return false;
              window.weiBeiSuppressSelectionReport = true;
              const found = window.find(query, false, false, true, false, true, false);
              window.setTimeout(() => { window.weiBeiSuppressSelectionReport = false; }, 80);
              return found;
            })();
            """
            webView?.evaluateJavaScript(script) { [weak self] value, error in
                guard !query.isEmpty else { return }
                self?.onSearchResult(query, error == nil && (value as? Bool) == true)
            }
        }

        func applyFocus() {
            guard isFocused, focusRequest != lastAppliedFocusRequest else { return }
            lastAppliedFocusRequest = focusRequest
            webView?.window?.makeFirstResponder(webView)
            if let editingSession {
                dispatchV2(NoteEditorCommandEnvelope(
                    documentID: editingSession.documentID,
                    documentGeneration: editingSession.documentGeneration,
                    type: .focus,
                    payload: NoteEditorEmptyPayload()
                ))
            } else {
                evaluate("document.querySelector('.ProseMirror')?.focus()")
            }
        }

        func applySelectionAskMarks(force: Bool = false) {
            guard isReady, !isEditable else { return }
            guard force || selectionAskMarks != lastAppliedSelectionAskMarks else { return }
            lastAppliedSelectionAskMarks = selectionAskMarks
            // Delay so Milkdown finishes painting before we wrap text nodes.
            let marks = selectionAskMarks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.isReady, !self.isEditable else { return }
                self.evaluate("window.WeiBeiSelectionAskMarks && window.WeiBeiSelectionAskMarks.apply(\(marks));")
            }
        }

        func applySelectionRemarkMarks(force: Bool = false) {
            guard isReady, !isEditable else { return }
            guard force || selectionRemarkMarks != lastAppliedSelectionRemarkMarks else { return }
            lastAppliedSelectionRemarkMarks = selectionRemarkMarks
            let marks = selectionRemarkMarks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.isReady, !self.isEditable else { return }
                self.evaluate("window.WeiBeiSelectionRemarkMarks && window.WeiBeiSelectionRemarkMarks.apply(\(marks));")
            }
        }

        func pasteImageFromClipboard() -> Bool {
            guard isEditable,
                  let editingSession,
                  let image = NSImage(pasteboard: .general),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                return false
            }

            let body: [String: Any] = [
                "dataURL": "data:image/png;base64,\(data.base64EncodedString())",
                "name": "pasted-image.png",
                "mime": "image/png"
            ]
            guard let attachment = saveImageAttachment(from: body) else { return false }
            let markdown = MarkdownAttachmentStore.markdownImage(for: attachment)
            dispatchV2(NoteEditorCommandEnvelope(
                documentID: editingSession.documentID,
                documentGeneration: editingSession.documentGeneration,
                minimumRevision: editingSession.currentRevision,
                type: .insertStructuredBlock,
                payload: NoteEditorMarkdownPayload(markdown: markdown)
            ))
            return true
        }

        private func saveImageAttachment(from body: [String: Any]) -> MarkdownAttachment? {
            guard let attachmentDirectory,
                  let dataURL = body["dataURL"] as? String else { return nil }
            let originalName = (body["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mime = body["mime"] as? String ?? ""
            return try? MarkdownAttachmentStore.save(
                dataURL: dataURL,
                originalName: originalName,
                mime: mime,
                attachmentDirectory: attachmentDirectory,
                markdownBaseURLString: markdownBaseURLString
            )
        }

        /**
         * Presents the native single-image picker for a slash image command.
         *
         * @param requestID - JavaScript request identifier
         * @param documentID - Document identity captured when the command was issued
         */
        private func presentImagePicker(requestID: String, documentID requestedDocumentID: String) {
            guard let window = webView?.window else {
                evaluate("window.WeiBeiEditor?.rejectImagePicker(\(Self.json(requestID)), \(Self.json(interfaceLanguage.text("无法打开图片选择器", "Image picker could not be opened"))))")
                return
            }
            let panel = NSOpenPanel()
            panel.title = interfaceLanguage.text("插入图片", "Insert Image")
            panel.prompt = interfaceLanguage.text("插入", "Insert")
            panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .tiff, .heic]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                guard self.documentID == requestedDocumentID else {
                    self.evaluate("window.WeiBeiEditor?.discardImagePicker(\(Self.json(requestID)))")
                    return
                }
                guard response == .OK else {
                    self.evaluate("window.WeiBeiEditor?.cancelImagePicker(\(Self.json(requestID)))")
                    return
                }
                guard let fileURL = panel.url, let attachmentDirectory = self.attachmentDirectory else {
                    self.evaluate("window.WeiBeiEditor?.rejectImagePicker(\(Self.json(requestID)), \(Self.json(self.interfaceLanguage.text("图片无法写入本地附件目录", "Image could not be written to the local attachments folder"))))")
                    return
                }
                let markdownBaseURLString = self.markdownBaseURLString
                let failureMessage = self.interfaceLanguage.text("图片读取或写入失败，请检查文件与附件目录权限", "Image could not be read or saved. Check the file and attachments folder permissions.")
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try Self.saveImageAttachment(fromFileURL: fileURL, attachmentDirectory: attachmentDirectory, markdownBaseURLString: markdownBaseURLString) }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        guard self.documentID == requestedDocumentID else {
                            self.evaluate("window.WeiBeiEditor?.discardImagePicker(\(Self.json(requestID)))")
                            return
                        }
                        switch result {
                        case let .success(attachment):
                            self.evaluate("window.WeiBeiEditor?.resolveImagePicker(\(Self.json(requestID)), \(Self.json(attachment.src)), \(Self.json(attachment.alt)))")
                        case .failure:
                            self.evaluate("window.WeiBeiEditor?.rejectImagePicker(\(Self.json(requestID)), \(Self.json(failureMessage)))")
                        }
                    }
                }
            }
        }

        /** Reads and saves a picker image on a background queue. */
        private static func saveImageAttachment(fromFileURL fileURL: URL, attachmentDirectory: URL, markdownBaseURLString: String) throws -> MarkdownAttachment {
            let data = try CourseProjectFileWorker.readBoundedRegularFile(
                at: fileURL,
                maximumByteCount: CourseProjectFileWorker.markdownImageMaximumByteCount
            )
            return try MarkdownAttachmentStore.save(
                data: data,
                originalName: fileURL.lastPathComponent,
                mime: MarkdownAttachmentStore.mimeType(
                    forFileExtension: fileURL.pathExtension
                ),
                attachmentDirectory: attachmentDirectory,
                markdownBaseURLString: markdownBaseURLString
            )
        }

        private func anchor(from rect: [String: Any]?) -> CGPoint? {
            guard let view = webView,
                  let rect,
                  let x = rect["x"] as? Double,
                  let y = rect["y"] as? Double else {
                return nil
            }
            return SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)
        }

        private static func json(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }

    }
}
