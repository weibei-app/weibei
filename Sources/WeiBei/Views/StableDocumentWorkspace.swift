import AppKit
import QuartzCore
import SwiftUI
import WeiBeiCore

extension Notification.Name {
    static let weiBeiDocumentDividerDragBegan = Notification.Name("WeiBeiDocumentDividerDragBegan")
    static let weiBeiDocumentDividerDragEnded = Notification.Name("WeiBeiDocumentDividerDragEnded")
}

struct StableDocumentWorkspace: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    /// Resolved by WeiBeiMotionScope — AppKit split animation never reads the system switch.
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Binding var firstSplit: CGFloat
    @Binding var secondSplit: CGFloat
    @Binding var halfSplit: CGFloat
    let registry: PersistentPaneHostRegistry
    let normalizedOrder: [WorkspacePaneRole]
    let visibleOrder: [WorkspacePaneRole]
    let draggedRole: WorkspacePaneRole?
    let expansionRequest: PaneExpansionRequest?
    /// Explicit input so theme changes always re-enter `updateNSView` and repaint the empty board layer.
    /// Do not rely only on `@EnvironmentObject` for long-lived NSHostingView paper sync.
    let appearanceMode: WeiBeiAppearanceMode
    let onFramesChange: ([WorkspacePaneRole], [CGRect]) -> Void
    let onExpansionRequestHandled: (UUID) -> Void

    func makeCoordinator() -> StableDocumentSplitCoordinator {
        StableDocumentSplitCoordinator(
            firstSplit: $firstSplit,
            secondSplit: $secondSplit,
            halfSplit: $halfSplit
        )
    }

    func makeNSView(context: Context) -> StableDocumentSplitView {
        let splitView = StableDocumentSplitView()
        let roleHosts = Dictionary(uniqueKeysWithValues: WorkspacePaneRole.allCases.map { role in
            (role, nativeHost(
                PersistentPaneHost(role: role, registry: registry)
                    .environmentObject(store)
                    .environmentObject(store.paneState)
                    .environmentObject(store.interaction)
                    .environmentObject(store.threePaneReorder)
                    .environmentObject(store.libraryDrawer)
                    .weiBeiMotionScoped(),
                identifier: "stable-document-slot-\(role.rawValue)"
            ))
        })
        let emptyHost = nativeHost(
            EmptyWorkspaceLauncherView()
                .environmentObject(store)
                .environmentObject(store.paneState)
                .environmentObject(store.interaction)
                .environmentObject(store.libraryDrawer)
                .weiBeiMotionScoped(),
            identifier: "stable-document-empty-workspace"
        )
        splitView.install(roleHosts: roleHosts, emptyHost: emptyHost)
        context.coordinator.install(in: splitView)
        applyEmptyBoardPaper(to: splitView, mode: appearanceMode)
        update(splitView, coordinator: context.coordinator)
        return splitView
    }

    func updateNSView(_ splitView: StableDocumentSplitView, context: Context) {
        update(splitView, coordinator: context.coordinator)
        // Empty board is a long-lived NSHostingView. Never reassign `rootView` here
        // (pane continuity / SelfCheck). Sync AppKit paper under the SwiftUI board instead;
        // EmptyWorkspaceLauncherView rebuilds its own colors from store + theme notification.
        applyEmptyBoardPaper(to: splitView, mode: appearanceMode)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: StableDocumentSplitView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width >= 0, height >= 0 else { return nil }
        // The canvas owns this size. Default AppKit fitting would recursively
        // measure every hosted pane and its rich text whenever scrolling lays out.
        return CGSize(width: width, height: height)
    }

    private func applyEmptyBoardPaper(to splitView: StableDocumentSplitView, mode: WeiBeiAppearanceMode) {
        let paper = WeiBeiNativePalette.paper(for: mode)
        let cgPaper = paper.cgColor
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = cgPaper
        splitView.emptyHost?.wantsLayer = true
        splitView.emptyHost?.layer?.backgroundColor = cgPaper
    }

    static func dismantleNSView(_ splitView: StableDocumentSplitView, coordinator: StableDocumentSplitCoordinator) {
        coordinator.stop(in: splitView)
    }

    private func update(_ splitView: StableDocumentSplitView, coordinator: StableDocumentSplitCoordinator) {
        coordinator.firstSplit = $firstSplit
        coordinator.secondSplit = $secondSplit
        coordinator.halfSplit = $halfSplit
        coordinator.onFramesChange = onFramesChange
        coordinator.onExpansionRequestHandled = onExpansionRequestHandled
        coordinator.reduceMotion = reduceMotion
        splitView.setReduceMotion(reduceMotion)
        coordinator.update(
            state: StableDocumentLayoutState(
                normalizedOrder: WorkspacePaneRole.normalized(normalizedOrder),
                visibleOrder: visibleOrder,
                firstSplit: firstSplit,
                secondSplit: secondSplit,
                halfSplit: halfSplit
            ),
            draggedRole: draggedRole,
            expansionRequest: expansionRequest,
            in: splitView
        )
    }

    private func nativeHost<Content: View>(_ content: Content, identifier: String) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(content))
        host.identifier = NSUserInterfaceItemIdentifier(identifier)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = []
        host.sizingOptions = []
        host.setContentHuggingPriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        return host
    }
}

struct StableDocumentLayoutState: Equatable {
    let normalizedOrder: [WorkspacePaneRole]
    let visibleOrder: [WorkspacePaneRole]
    let firstSplit: CGFloat
    let secondSplit: CGFloat
    let halfSplit: CGFloat

    func hasSameStructure(as other: StableDocumentLayoutState) -> Bool {
        normalizedOrder == other.normalizedOrder && visibleOrder == other.visibleOrder
    }

    func hasSameStoredRatios(as other: StableDocumentLayoutState) -> Bool {
        abs(firstSplit - other.firstSplit) < 0.001
            && abs(secondSplit - other.secondSplit) < 0.001
            && abs(halfSplit - other.halfSplit) < 0.001
    }
}

final class StableDocumentSplitView: NSView {
    fileprivate var roleHosts: [WorkspacePaneRole: NSHostingView<AnyView>] = [:]
    fileprivate var emptyHost: NSHostingView<AnyView>?
    fileprivate let dividerViews = [StableDocumentDividerView(), StableDocumentDividerView()]
    fileprivate weak var coordinator: StableDocumentSplitCoordinator?
    override var isFlipped: Bool { true }

    func install(
        roleHosts: [WorkspacePaneRole: NSHostingView<AnyView>],
        emptyHost: NSHostingView<AnyView>
    ) {
        precondition(roleHosts.count == WorkspacePaneRole.allCases.count)
        autoresizesSubviews = false
        wantsLayer = true
        layer?.masksToBounds = true
        self.roleHosts = roleHosts
        self.emptyHost = emptyHost
        addSubview(emptyHost)
        for role in WorkspacePaneRole.defaultThreePaneOrder {
            guard let host = roleHosts[role] else { continue }
            host.isHidden = true
            addSubview(host)
        }
        for divider in dividerViews {
            divider.isHidden = true
            addSubview(divider)
        }
        assertStableOwnership()
    }

    func setReduceMotion(_ reduce: Bool) {
        for divider in dividerViews where divider.reduceMotion != reduce {
            divider.reduceMotion = reduce
        }
    }

    func assertStableOwnership() {
        assert(emptyHost?.superview === self)
        assert(roleHosts.values.allSatisfy { $0.superview === self })
        assert(dividerViews.allSatisfy { $0.superview === self })
    }

    override func layout() {
        super.layout()
        // Divider frames move with layout — keep bidirectional resize cursors accurate.
        window?.invalidateCursorRects(for: self)
        for divider in dividerViews where !divider.isHidden {
            window?.invalidateCursorRects(for: divider)
            divider.window?.invalidateCursorRects(for: divider)
        }
        coordinator?.containerDidLayout(self)
    }
}

private final class StableDocumentDividerView: NSView {
    var onDragStart: (() -> Void)?
    var onDragChange: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    /// Resolved app reduce-motion, pushed from SwiftUI — never read the system switch here.
    var reduceMotion = false {
        didSet {
            if reduceMotion {
                updateAccentLine()
            }
        }
    }
    private var dragStartX: CGFloat?
    private let accentLayer = CALayer()
    private var isHovering = false
    private var isPressed = false

    /// Fixed 1pt cinnabar emphasis line over the neutral divider line:
    /// transparent at rest, ~0.55 on hover, full strength while dragging.
    private enum AccentPhase {
        case idle
        case hover
        case pressed
    }

    private var accentPhase: AccentPhase = .idle {
        didSet {
            guard oldValue != accentPhase else { return }
            updateAccentLine()
        }
    }

    private var accentTargetOpacity: Float {
        switch accentPhase {
        case .idle: return 0
        case .hover: return 0.55
        case .pressed: return 1
        }
    }

    /// Enter fast (80ms), leave a touch slower (140ms).
    private var accentTransitionDuration: TimeInterval {
        accentPhase == .idle ? 0.14 : 0.08
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.splitter)
        wantsLayer = true
        accentLayer.opacity = 0
        layer?.addSublayer(accentLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        accentLayer.frame = CGRect(
            x: bounds.midX - 0.5,
            y: 14,
            width: 1,
            height: max(0, bounds.height - 28)
        )
    }

    override func resetCursorRects() {
        // Full bounds of the 10pt gutter — not just the 1pt line.
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateAccentLine()
    }

    override func draw(_ dirtyRect: NSRect) {
        dividerFill.setFill()
        bounds.fill()
        dividerLine.setFill()
        NSRect(x: bounds.midX - 0.5, y: bounds.minY + 14, width: 1, height: max(0, bounds.height - 28)).fill()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        isHovering = true
        if !isPressed {
            accentPhase = .hover
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        if !isPressed {
            accentPhase = .idle
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseEnteredAndExited,
            .cursorUpdate,
            .inVisibleRect
        ]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        isPressed = true
        accentPhase = .pressed
        dragStartX = event.locationInWindow.x
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartX else { return }
        onDragChange?(event.locationInWindow.x - dragStartX)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartX = nil
        isPressed = false
        // Released while still over the divider: back to hover, not idle.
        accentPhase = isHovering ? .hover : .idle
        onDragEnd?()
    }

    private func updateAccentLine() {
        let target = accentTargetOpacity
        accentLayer.backgroundColor = WeiBeiNativePalette.cinnabar().cgColor
        guard !reduceMotion else {
            accentLayer.removeAllAnimations()
            accentLayer.opacity = target
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = accentLayer.presentation()?.opacity ?? accentLayer.opacity
        animation.toValue = target
        animation.duration = accentTransitionDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        accentLayer.opacity = target
        accentLayer.add(animation, forKey: "weiBeiAccentOpacity")
    }

    private var dividerFill: NSColor {
        // Follow the product theme (纸面/宣纸/墨石/石碑), not system aqua/darkAqua alone.
        WeiBeiNativePalette.dividerFill()
    }

    private var dividerLine: NSColor {
        WeiBeiNativePalette.dividerLine()
    }
}

final class StableDocumentSplitCoordinator {
    var firstSplit: Binding<CGFloat>
    var secondSplit: Binding<CGFloat>
    var halfSplit: Binding<CGFloat>
    var onFramesChange: (([WorkspacePaneRole], [CGRect]) -> Void)?
    var onExpansionRequestHandled: ((UUID) -> Void)?
    /// Resolved app reduce-motion from SwiftUI; drives every AppKit animation decision here.
    var reduceMotion = false

    private var desiredState: StableDocumentLayoutState?
    private var appliedState: StableDocumentLayoutState?
    private var displayedVisibleOrder: [WorkspacePaneRole] = []
    private var recentReadableWidths: [WorkspacePaneRole: CGFloat] = [:]
    private var lastContainerSize = CGSize.zero
    private var isAnimatingLayout = false
    private var isDraggingDivider = false
    private var isWritingStoredRatios = false
    private var pendingState: StableDocumentLayoutState?
    private var pendingExpansionRequest: PaneExpansionRequest?
    private var handledExpansionRequestID: UUID?
    private var dividerDrag: DividerDrag?
    private var animationSequence = 0
    private var activeAnimationToken: Int?

    private let dividerWidth: CGFloat = 10
    private let railWidth = ContentRailMetrics.railOnlyWidth
    private let railSnapThreshold = ContentRailMetrics.snapThreshold
    private let readableWidthThreshold = ContentRailMetrics.readableWidth
    private let defaultReadableWidth = ContentRailMetrics.defaultReadableWidth
    // Restored from 8a172fe5「保持分栏切换连续」— known-smooth pane show/hide motion.
    private let layoutAnimationDuration = 0.24
    private let snapAnimationDuration = 0.18
    private let animationFallbackGrace: TimeInterval = 0.25

    init(
        firstSplit: Binding<CGFloat>,
        secondSplit: Binding<CGFloat>,
        halfSplit: Binding<CGFloat>
    ) {
        self.firstSplit = firstSplit
        self.secondSplit = secondSplit
        self.halfSplit = halfSplit
    }

    func install(in splitView: StableDocumentSplitView) {
        splitView.coordinator = self
        for (index, divider) in splitView.dividerViews.enumerated() {
            divider.onDragStart = { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.beginDividerDrag(index: index, in: splitView)
            }
            divider.onDragChange = { [weak self, weak splitView] delta in
                guard let self, let splitView else { return }
                self.updateDividerDrag(delta: delta, in: splitView)
            }
            divider.onDragEnd = { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.endDividerDrag(in: splitView)
            }
        }
    }

    func stop(in splitView: StableDocumentSplitView) {
        splitView.coordinator = nil
        for divider in splitView.dividerViews {
            divider.onDragStart = nil
            divider.onDragChange = nil
            divider.onDragEnd = nil
        }
    }

    func update(
        state: StableDocumentLayoutState,
        draggedRole: WorkspacePaneRole?,
        expansionRequest: PaneExpansionRequest?,
        in splitView: StableDocumentSplitView
    ) {
        splitView.assertStableOwnership()
        desiredState = state
        updateDragAppearance(draggedRole, in: splitView)

        if let expansionRequest, expansionRequest.id != handledExpansionRequestID {
            pendingExpansionRequest = expansionRequest
        }

        guard splitView.bounds.width > 0, splitView.bounds.height > 0 else {
            splitView.needsLayout = true
            return
        }

        if isAnimatingLayout || isDraggingDivider {
            pendingState = state
            return
        }

        guard let appliedState else {
            apply(state: state, in: splitView, animated: false, preserveCurrentWidths: false)
            handlePendingExpansionRequest(in: splitView)
            return
        }

        if !state.hasSameStructure(as: appliedState) {
            apply(
                state: state,
                in: splitView,
                animated: true,
                preserveCurrentWidths: true
            )
            return
        }

        if isWritingStoredRatios {
            self.appliedState = state
        } else if !state.hasSameStoredRatios(as: appliedState) {
            apply(state: state, in: splitView, animated: false, preserveCurrentWidths: false)
        }
        handlePendingExpansionRequest(in: splitView)
    }

    func containerDidLayout(_ splitView: StableDocumentSplitView) {
        guard splitView.bounds.width > 0, splitView.bounds.height > 0 else { return }
        guard !isAnimatingLayout, !isDraggingDivider else { return }
        let size = splitView.bounds.size
        guard appliedState == nil || abs(size.width - lastContainerSize.width) > 0.5 || abs(size.height - lastContainerSize.height) > 0.5 else { return }
        guard let state = desiredState else { return }
        apply(state: state, in: splitView, animated: false, preserveCurrentWidths: appliedState != nil)
        handlePendingExpansionRequest(in: splitView)
    }

    private func apply(
        state: StableDocumentLayoutState,
        in splitView: StableDocumentSplitView,
        animated: Bool,
        preserveCurrentWidths: Bool
    ) {
        let visibleOrder = state.visibleOrder.filter { state.normalizedOrder.contains($0) }
        let widths = paneWidths(
            for: visibleOrder,
            state: state,
            in: splitView,
            preserveCurrentWidths: preserveCurrentWidths
        )
        let targetFrames = visibleFrames(order: visibleOrder, widths: widths, size: splitView.bounds.size)
        let container = CGRect(origin: .zero, size: splitView.bounds.size)
        let currentFrames = Dictionary(uniqueKeysWithValues: WorkspacePaneRole.allCases.compactMap { role in
            splitView.roleHosts[role].map { (role, $0.frame) }
        })
        let allTargetFrames = allRoleFrames(
            normalizedOrder: state.normalizedOrder,
            visibleFrames: targetFrames,
            currentFrames: currentFrames,
            container: container
        )
        let targetDividerFrames = dividerFramesForOrder(
            visibleOrder,
            visibleFrames: targetFrames,
            size: splitView.bounds.size
        )
        let previousVisible = Set(displayedVisibleOrder)
        let nextVisible = Set(visibleOrder)
        let shouldAnimate = animated && !reduceMotion

        prepareHosts(
            previousVisible: previousVisible,
            nextVisible: nextVisible,
            targetFrames: allTargetFrames,
            in: splitView
        )
        prepareDividers(targetFrames: targetDividerFrames, in: splitView)
        displayedVisibleOrder = visibleOrder
        appliedState = state
        lastContainerSize = splitView.bounds.size

        guard shouldAnimate else {
            setFramesImmediately(
                roleFrames: allTargetFrames,
                dividerFrames: targetDividerFrames,
                visibleOrder: visibleOrder,
                in: splitView
            )
            finishLayout(state: state, in: splitView, saveRatios: animated)
            return
        }

        let animationToken = beginAnimation()
        let finishAnimation = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.completeAnimation(animationToken) {
                self.setFramesImmediately(
                    roleFrames: allTargetFrames,
                    dividerFrames: targetDividerFrames,
                    visibleOrder: visibleOrder,
                    in: splitView
                )
                self.finishLayout(state: state, in: splitView, saveRatios: true)
                self.applyPendingWork(in: splitView)
            }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = layoutAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            animateFrames(
                roleFrames: allTargetFrames,
                dividerFrames: targetDividerFrames,
                visibleOrder: visibleOrder,
                in: splitView
            )
        }, completionHandler: finishAnimation)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + layoutAnimationDuration + animationFallbackGrace,
            execute: finishAnimation
        )
    }

    private func paneWidths(
        for visibleOrder: [WorkspacePaneRole],
        state: StableDocumentLayoutState,
        in splitView: StableDocumentSplitView,
        preserveCurrentWidths: Bool
    ) -> [CGFloat] {
        let count = visibleOrder.count
        guard count > 0 else { return [] }
        let usable = max(splitView.bounds.width - CGFloat(count - 1) * dividerWidth, 1)
        if count == 1 {
            return [usable]
        }

        if preserveCurrentWidths, appliedState != nil {
            // Opening more columns (incl. empty board progression): always even left→right
            // so 文稿/对话/笔记 land as equal L/C/R slots instead of crushing neighbors.
            if visibleOrder.count > displayedVisibleOrder.count || displayedVisibleOrder.isEmpty {
                return equalPaneWidths(count: count, total: usable)
            }
            // Closing columns: keep remaining relative widths.
            let desired = visibleOrder.map { role -> CGFloat in
                if displayedVisibleOrder.contains(role),
                   let width = splitView.roleHosts[role]?.frame.width,
                   width > 0.5 {
                    return width
                }
                return recentReadableWidths[role] ?? defaultReadableWidth
            }
            return normalizedWidths(desired, total: usable)
        }

        // Fresh layout (no applied state): still prefer even L/C/R over stale SceneStorage ratios
        // when the user is rebuilding from an empty visible set.
        if displayedVisibleOrder.isEmpty || displayedVisibleOrder.count != count {
            return equalPaneWidths(count: count, total: usable)
        }

        if count == 2 {
            let first = clamped(
                state.halfSplit * usable,
                min: minimumPaneWidth(total: usable, count: count),
                max: usable - minimumPaneWidth(total: usable, count: count)
            )
            return [first, usable - first]
        }

        let minimum = minimumPaneWidth(total: usable, count: count)
        let first = clamped(state.firstSplit * usable, min: minimum, max: usable - 2 * minimum)
        let second = clamped((state.secondSplit - state.firstSplit) * usable, min: minimum, max: usable - first - minimum)
        return [first, second, max(minimum, usable - first - second)]
    }

    /// Even left→right split for the current visible set (empty-board open progression).
    private func equalPaneWidths(count: Int, total: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let base = (total / CGFloat(count) * 100).rounded(.down) / 100
        var widths = Array(repeating: max(0, base), count: count)
        if let last = widths.indices.last {
            widths[last] = max(0, total - base * CGFloat(count - 1))
        }
        return widths
    }

    private func normalizedWidths(_ desired: [CGFloat], total: CGFloat) -> [CGFloat] {
        guard !desired.isEmpty else { return [] }
        let minimum = minimumPaneWidth(total: total, count: desired.count)
        let minimumTotal = minimum * CGFloat(desired.count)
        let extraAvailable = max(0, total - minimumTotal)
        let extras = desired.map { max(0, $0 - minimum) }
        let extraTotal = extras.reduce(0, +)
        var result = extras.map { extra -> CGFloat in
            if extraTotal > 0.5 {
                return minimum + extraAvailable * extra / extraTotal
            }
            return minimum + extraAvailable / CGFloat(desired.count)
        }
        if let lastIndex = result.indices.last {
            result[lastIndex] += total - result.reduce(0, +)
        }
        return result
    }

    private func minimumPaneWidth(total: CGFloat, count: Int) -> CGFloat {
        min(railWidth, total / CGFloat(max(count, 1)))
    }

    private func visibleFrames(order: [WorkspacePaneRole], widths: [CGFloat], size: CGSize) -> [WorkspacePaneRole: CGRect] {
        var frames: [WorkspacePaneRole: CGRect] = [:]
        var x: CGFloat = 0
        for (index, role) in order.enumerated() {
            let width = widths[safe: index] ?? 0
            frames[role] = CGRect(x: x, y: 0, width: width, height: size.height)
            x += width
            if index < order.count - 1 {
                x += dividerWidth
            }
        }
        return frames
    }

    private func allRoleFrames(
        normalizedOrder: [WorkspacePaneRole],
        visibleFrames: [WorkspacePaneRole: CGRect],
        currentFrames: [WorkspacePaneRole: CGRect],
        container: CGRect
    ) -> [WorkspacePaneRole: CGRect] {
        var frames = visibleFrames
        for role in normalizedOrder where visibleFrames[role] == nil {
            frames[role] = PaneSeatMotion.closingFrame(
                for: role,
                current: currentFrames[role],
                container: container
            )
        }
        return frames
    }

    private func prepareHosts(
        previousVisible: Set<WorkspacePaneRole>,
        nextVisible: Set<WorkspacePaneRole>,
        targetFrames: [WorkspacePaneRole: CGRect],
        in splitView: StableDocumentSplitView
    ) {
        // 文稿 grows from the left of its slot, 对话 from the slot mid-line,
        // 笔记 from the right — including the second/third pane after another is open.
        for role in nextVisible.subtracting(previousVisible) {
            guard let host = splitView.roleHosts[role], let target = targetFrames[role] else { continue }
            host.alphaValue = 1
            host.frame = PaneSeatMotion.openingFrame(for: role, target: target)
            host.isHidden = false
        }
        for role in previousVisible.union(nextVisible) {
            splitView.roleHosts[role]?.isHidden = false
            if nextVisible.contains(role) {
                splitView.roleHosts[role]?.alphaValue = 1
            }
        }
        if nextVisible.isEmpty {
            splitView.emptyHost?.isHidden = false
            if previousVisible.isEmpty {
                splitView.emptyHost?.alphaValue = 1
            } else {
                splitView.emptyHost?.alphaValue = 0
            }
        }
    }

    private func prepareDividers(targetFrames: [CGRect], in splitView: StableDocumentSplitView) {
        for (index, divider) in splitView.dividerViews.enumerated() where targetFrames.indices.contains(index) {
            if divider.isHidden {
                let target = targetFrames[index]
                divider.frame = CGRect(x: target.minX, y: 0, width: 0, height: target.height)
                divider.alphaValue = 0
                divider.isHidden = false
            }
        }
    }

    private func setFramesImmediately(
        roleFrames: [WorkspacePaneRole: CGRect],
        dividerFrames: [CGRect],
        visibleOrder: [WorkspacePaneRole],
        in splitView: StableDocumentSplitView
    ) {
        setRoleFramesImmediately(roleFrames, in: splitView)
        updateDividerFrames(dividerFrames, animated: false, in: splitView)
        splitView.emptyHost?.frame = splitView.bounds
        splitView.emptyHost?.alphaValue = visibleOrder.isEmpty ? 1 : 0
    }

    private func setRoleFramesImmediately(
        _ frames: [WorkspacePaneRole: CGRect],
        in splitView: StableDocumentSplitView
    ) {
        let previousAgentWidth = splitView.roleHosts[.agent]?.frame.width
        for (role, frame) in frames {
            splitView.roleHosts[role]?.frame = frame
        }
        guard let previousAgentWidth,
              let agentHost = splitView.roleHosts[.agent],
              abs(previousAgentWidth - agentHost.frame.width) > 0.5 else { return }
        // NSHostingView can defer SwiftUI's new width until the current window or
        // divider event ends. Flush only the resized chat host at the shared frame path.
        agentHost.layoutSubtreeIfNeeded()
    }

    private func animateFrames(
        roleFrames: [WorkspacePaneRole: CGRect],
        dividerFrames: [CGRect],
        visibleOrder: [WorkspacePaneRole],
        in splitView: StableDocumentSplitView
    ) {
        // Width-only animation (8a172fe5) — no concurrent alpha thrash on WebView hosts.
        for (role, frame) in roleFrames {
            splitView.roleHosts[role]?.animator().frame = frame
        }
        updateDividerFrames(dividerFrames, animated: true, in: splitView)
        splitView.emptyHost?.animator().frame = splitView.bounds
        splitView.emptyHost?.animator().alphaValue = visibleOrder.isEmpty ? 1 : 0
    }

    private func updateDividerFrames(_ frames: [CGRect], animated: Bool, in splitView: StableDocumentSplitView) {
        for (index, divider) in splitView.dividerViews.enumerated() {
            let target = frames[safe: index] ?? collapsedDividerFrame(index: index, frames: frames, size: splitView.bounds.size)
            if animated {
                divider.animator().frame = target
                divider.animator().alphaValue = frames.indices.contains(index) ? 1 : 0
            } else {
                divider.frame = target
                divider.alphaValue = frames.indices.contains(index) ? 1 : 0
            }
        }
    }

    private func collapsedDividerFrame(index: Int, frames: [CGRect], size: CGSize) -> CGRect {
        let x = frames.last?.maxX ?? (index == 0 ? 0 : size.width)
        return CGRect(x: x, y: 0, width: 0, height: size.height)
    }

    private func finishLayout(state: StableDocumentLayoutState, in splitView: StableDocumentSplitView, saveRatios: Bool) {
        splitView.assertStableOwnership()
        let visible = Set(displayedVisibleOrder)
        for role in WorkspacePaneRole.allCases {
            let host = splitView.roleHosts[role]
            host?.isHidden = !visible.contains(role)
            host?.alphaValue = 1
        }
        for (index, divider) in splitView.dividerViews.enumerated() {
            divider.isHidden = index >= max(0, displayedVisibleOrder.count - 1)
            divider.alphaValue = divider.isHidden ? 0 : 1
        }
        splitView.emptyHost?.isHidden = !displayedVisibleOrder.isEmpty
        splitView.emptyHost?.alphaValue = displayedVisibleOrder.isEmpty ? 1 : 0
        captureReadableWidths(in: splitView)
        if saveRatios {
            persistRatios(in: splitView)
        }
        appliedState = StableDocumentLayoutState(
            normalizedOrder: state.normalizedOrder,
            visibleOrder: state.visibleOrder,
            firstSplit: firstSplit.wrappedValue,
            secondSplit: secondSplit.wrappedValue,
            halfSplit: halfSplit.wrappedValue
        )
        reportFrames(in: splitView)
    }

    private func applyPendingWork(in splitView: StableDocumentSplitView) {
        if let pendingState {
            self.pendingState = nil
            if let appliedState, !pendingState.hasSameStructure(as: appliedState) {
                apply(state: pendingState, in: splitView, animated: true, preserveCurrentWidths: true)
                return
            }
            if let appliedState,
               !isWritingStoredRatios,
               !pendingState.hasSameStoredRatios(as: appliedState) {
                apply(state: pendingState, in: splitView, animated: false, preserveCurrentWidths: false)
                return
            }
        }
        handlePendingExpansionRequest(in: splitView)
        splitView.needsLayout = true
    }

    private func updateDragAppearance(_ draggedRole: WorkspacePaneRole?, in splitView: StableDocumentSplitView) {
        for (role, host) in splitView.roleHosts {
            host.alphaValue = role == draggedRole ? 0.08 : 1
        }
    }

    private struct DividerDrag {
        let index: Int
        let baseWidths: [CGFloat]
    }

    private func beginDividerDrag(index: Int, in splitView: StableDocumentSplitView) {
        guard !isAnimatingLayout, displayedVisibleOrder.count > index + 1 else { return }
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        guard widths.count == displayedVisibleOrder.count else { return }
        captureReadableWidths(in: splitView)
        dividerDrag = DividerDrag(index: index, baseWidths: widths)
        isDraggingDivider = true
        NotificationCenter.default.post(name: .weiBeiDocumentDividerDragBegan, object: splitView)
    }

    private func updateDividerDrag(delta: CGFloat, in splitView: StableDocumentSplitView) {
        guard let dividerDrag else { return }
        var widths = dividerDrag.baseWidths
        let leftIndex = dividerDrag.index
        let rightIndex = dividerDrag.index + 1
        let combined = widths[leftIndex] + widths[rightIndex]
        let minimum = minimumPaneWidth(total: combined, count: 2)
        let left = clamped(widths[leftIndex] + delta, min: minimum, max: combined - minimum)
        widths[leftIndex] = left
        widths[rightIndex] = combined - left
        applyVisibleWidthsImmediately(widths, in: splitView)
    }

    private func endDividerDrag(in splitView: StableDocumentSplitView) {
        guard dividerDrag != nil else { return }
        dividerDrag = nil
        isDraggingDivider = false
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        let snapped = snappedWidths(widths)
        if zip(widths, snapped).contains(where: { abs($0 - $1) > 0.5 }) {
            animateVisibleWidths(snapped, duration: snapAnimationDuration, in: splitView) { [weak self, weak splitView] in
                guard let self, let splitView else { return }
                self.captureReadableWidths(in: splitView)
                self.persistRatios(in: splitView)
                self.reportFrames(in: splitView)
                self.applyPendingWork(in: splitView)
                self.notifyDividerDragEnded(in: splitView)
            }
        } else {
            captureReadableWidths(in: splitView)
            persistRatios(in: splitView)
            reportFrames(in: splitView)
            applyPendingWork(in: splitView)
            notifyDividerDragEnded(in: splitView)
        }
    }

    private func notifyDividerDragEnded(in splitView: StableDocumentSplitView) {
        NotificationCenter.default.post(name: .weiBeiDocumentDividerDragEnded, object: splitView)
    }

    private func snappedWidths(_ widths: [CGFloat]) -> [CGFloat] {
        guard widths.count >= 2 else { return widths }
        let snapIndices = widths.indices.filter { widths[$0] <= railSnapThreshold }
        guard !snapIndices.isEmpty else { return widths }
        var target = widths
        for index in snapIndices {
            let released = max(0, widths[index] - railWidth)
            target[index] = min(railWidth, widths[index])
            guard released > 0.5 else { continue }
            let recipients = widths.indices.filter { $0 != index && !snapIndices.contains($0) }
            let recipient = recipients.min { abs($0 - index) < abs($1 - index) }
                ?? widths.indices.filter { $0 != index }.max { widths[$0] < widths[$1] }
            if let recipient {
                target[recipient] += released
            }
        }
        return target
    }

    private func applyVisibleWidthsImmediately(_ widths: [CGFloat], in splitView: StableDocumentSplitView) {
        let frames = visibleFrames(order: displayedVisibleOrder, widths: widths, size: splitView.bounds.size)
        setRoleFramesImmediately(frames, in: splitView)
        let dividers = dividerFramesForOrder(displayedVisibleOrder, visibleFrames: frames, size: splitView.bounds.size)
        updateDividerFrames(dividers, animated: false, in: splitView)
        reportFrames(in: splitView)
    }

    private func animateVisibleWidths(
        _ widths: [CGFloat],
        duration: TimeInterval,
        in splitView: StableDocumentSplitView,
        completion: @escaping () -> Void
    ) {
        let frames = visibleFrames(order: displayedVisibleOrder, widths: widths, size: splitView.bounds.size)
        let dividers = dividerFramesForOrder(displayedVisibleOrder, visibleFrames: frames, size: splitView.bounds.size)
        let animationToken = beginAnimation()
        let finishAnimation = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.completeAnimation(animationToken) {
                self.applyVisibleWidthsImmediately(widths, in: splitView)
                completion()
            }
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            for (role, frame) in frames {
                splitView.roleHosts[role]?.animator().frame = frame
            }
            updateDividerFrames(dividers, animated: true, in: splitView)
        }, completionHandler: finishAnimation)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + duration + animationFallbackGrace,
            execute: finishAnimation
        )
    }

    private func beginAnimation() -> Int {
        animationSequence += 1
        activeAnimationToken = animationSequence
        isAnimatingLayout = true
        return animationSequence
    }

    private func completeAnimation(_ token: Int, completion: () -> Void) {
        guard activeAnimationToken == token else { return }
        activeAnimationToken = nil
        isAnimatingLayout = false
        completion()
    }

    private func handlePendingExpansionRequest(in splitView: StableDocumentSplitView) {
        guard !isAnimatingLayout, !isDraggingDivider,
              let request = pendingExpansionRequest,
              request.id != handledExpansionRequestID else { return }
        pendingExpansionRequest = nil
        handledExpansionRequestID = request.id
        guard let requestedIndex = displayedVisibleOrder.firstIndex(of: request.role) else {
            onExpansionRequestHandled?(request.id)
            return
        }
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        guard widths.count == displayedVisibleOrder.count else {
            onExpansionRequestHandled?(request.id)
            return
        }
        let target = expandedWidths(widths, requestedIndex: requestedIndex, role: request.role)
        let finishExpansion = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.captureReadableWidths(in: splitView)
            self.reportFrames(in: splitView)
            self.onExpansionRequestHandled?(request.id)
            self.applyPendingWork(in: splitView)
        }
        if reduceMotion {
            // Reduced motion: apply the width directly and ack synchronously — no wait.
            applyVisibleWidthsImmediately(target, in: splitView)
            finishExpansion()
            return
        }
        animateVisibleWidths(target, duration: layoutAnimationDuration, in: splitView, completion: finishExpansion)
    }

    private func expandedWidths(_ widths: [CGFloat], requestedIndex: Int, role: WorkspacePaneRole) -> [CGFloat] {
        guard widths.indices.contains(requestedIndex), displayedVisibleOrder.count == widths.count else { return widths }
        let total = widths.reduce(0, +)
        let minimum = minimumPaneWidth(total: total, count: widths.count)
        let otherIndices = widths.indices.filter { $0 != requestedIndex }
        let otherMinimums = otherIndices.map { index -> CGFloat in
            guard displayedVisibleOrder[index] == .reader else { return minimum }
            return min(
                readableWidthThreshold,
                max(minimum, total - minimum * CGFloat(widths.count - 1))
            )
        }
        let maxRequested = max(minimum, total - otherMinimums.reduce(0, +))
        let requestedMinimum = min(readableWidthThreshold, maxRequested)
        let requested = clamped(
            max(widths[requestedIndex], ContentRailPolicy.expansionWidth(recentWidth: recentReadableWidths[role])),
            min: requestedMinimum,
            max: maxRequested
        )
        let remaining = max(0, total - requested)
        let otherDesired = otherIndices.map { widths[$0] }
        let allocated = normalizedWidths(otherDesired, total: remaining, minimums: otherMinimums)
        var result = widths
        result[requestedIndex] = requested
        for (offset, index) in otherIndices.enumerated() {
            result[index] = allocated[safe: offset] ?? minimum
        }
        return result
    }

    private func normalizedWidths(_ desired: [CGFloat], total: CGFloat, minimums: [CGFloat]) -> [CGFloat] {
        guard desired.count == minimums.count, !desired.isEmpty else { return desired }
        let minimumTotal = minimums.reduce(0, +)
        guard minimumTotal <= total else {
            return normalizedWidths(minimums, total: total)
        }
        let extraAvailable = total - minimumTotal
        let extras = zip(desired, minimums).map { pair in max(0, pair.0 - pair.1) }
        let extraTotal = extras.reduce(0, +)
        var result = zip(minimums, extras).map { pair -> CGFloat in
            let minimum = pair.0
            let extra = pair.1
            if extraTotal > 0.5 {
                return minimum + extraAvailable * extra / extraTotal
            }
            return minimum + extraAvailable / CGFloat(desired.count)
        }
        if let lastIndex = result.indices.last {
            result[lastIndex] += total - result.reduce(0, +)
        }
        return result
    }

    private func captureReadableWidths(in splitView: StableDocumentSplitView) {
        for role in displayedVisibleOrder {
            guard let width = splitView.roleHosts[role]?.frame.width, width >= readableWidthThreshold else { continue }
            recentReadableWidths[role] = width
        }
    }

    private func persistRatios(in splitView: StableDocumentSplitView) {
        let widths = displayedVisibleOrder.compactMap { splitView.roleHosts[$0]?.frame.width }
        guard widths.count == displayedVisibleOrder.count, widths.count >= 2 else { return }
        let usable = max(widths.reduce(0, +), 1)
        isWritingStoredRatios = true
        if widths.count == 2 {
            halfSplit.wrappedValue = clamped(widths[0] / usable, min: 0, max: 1)
        } else {
            firstSplit.wrappedValue = clamped(widths[0] / usable, min: 0, max: 1)
            secondSplit.wrappedValue = clamped((widths[0] + widths[1]) / usable, min: 0, max: 1)
        }
        DispatchQueue.main.async { [weak self] in
            self?.isWritingStoredRatios = false
        }
    }

    private func reportFrames(in splitView: StableDocumentSplitView) {
        let order = displayedVisibleOrder
        let frames = order.compactMap { splitView.roleHosts[$0]?.frame }
        guard frames.count == order.count else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onFramesChange?(order, frames)
        }
    }

    private func dividerFramesForOrder(
        _ order: [WorkspacePaneRole],
        visibleFrames: [WorkspacePaneRole: CGRect],
        size: CGSize
    ) -> [CGRect] {
        order.dropLast().compactMap { role in
            guard let frame = visibleFrames[role] else { return nil }
            return CGRect(x: frame.maxX, y: 0, width: dividerWidth, height: size.height)
        }
    }

    private func clamped(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), Swift.max(min, max))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
