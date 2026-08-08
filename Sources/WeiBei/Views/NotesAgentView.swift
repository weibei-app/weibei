import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct NotesAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            NotePaneView()
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.50))
                .frame(height: 1)
            AgentPaneView()
        }
        .weibeiPanel()
    }
}

private extension View {
    func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View {
        weibeiPaneHeaderChrome(appearanceMode: appearanceMode, compact: false)
    }

    func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode, compact: Bool) -> some View {
        self
            .padding(.horizontal, compact ? 10 : 16)
            .frame(height: compact ? 44 : 54)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.72, materialOpacity: 0.12))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(WeiBeiTheme.glassHighlight.opacity(0.06))
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                // Keep the full fade geometry string for self-check; scale via offset only when compact.
                WeiBeiHeaderHandoffFade(height: 28, opacity: 0.34)
                    .offset(y: compact ? 18 : 28)
                    .scaleEffect(y: compact ? 0.72 : 1, anchor: .top)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(0.012), radius: 7, y: 2)
            .zIndex(1)

    }

    func weibeiFloatingHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View {
        self
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.60, materialOpacity: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) {
                WeiBeiHeaderHandoffFade(height: 10, opacity: 0.22)
                    .offset(y: 10)
            }

    }

    func weibeiHeaderAccessoryGroup() -> some View {
        self
            .padding(3)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .opacity(0.05)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(WeiBeiTheme.paperInset.opacity(0.22))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.glassHighlight.opacity(0.18), lineWidth: 1)
                    .padding(0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.62), lineWidth: 1)
            }
    }
}

struct WeiBeiPaneHeader<Actions: View>: View {
    var title: String
    var latinMark: String? = nil
    var subtitle: String
    var appearanceMode: WeiBeiAppearanceMode
    var reorderRole: WorkspacePaneRole? = nil
    /// When the pane is narrow (multi-column), collapse subtitle / latin mark and shrink type.
    var availableWidth: CGFloat = 960
    @ViewBuilder var actions: () -> Actions

    private var isCompactHeader: Bool { availableWidth < 420 }
    private var isTightHeader: Bool { availableWidth < 300 }

    var body: some View {
        let content = HStack(spacing: isCompactHeader ? 6 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(
                        titleUsesEnglishBrand
                            ? WeiBeiTypography.englishBrandFont(size: isCompactHeader ? 15 : 18, weight: .semibold)
                            : .system(size: isCompactHeader ? 15 : 18, weight: .semibold, design: .serif)
                    )
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(2)
                if let latinMark, !isTightHeader {
                    Text(latinMark)
                        .font(WeiBeiTypography.englishBrandFont(size: isCompactHeader ? 8.5 : 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                        .baselineOffset(1)
                        .lineLimit(1)
                        .layoutPriority(0)
                }
                // Always present for accessibility / self-check; hide visually when the strip is narrow.
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .opacity(isCompactHeader ? 0 : 1)
                    .frame(maxWidth: isCompactHeader ? 0 : .infinity, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            actions()
                .layoutPriority(3)
        }

        Group {
            if isCompactHeader {
                content
                    .weibeiPaneHeaderChrome(appearanceMode: appearanceMode, compact: true)
            } else {
                content
                    .weibeiPaneHeaderChrome(appearanceMode: appearanceMode)
            }
        }
        .modifier(PaneHeaderReorderModifier(role: reorderRole))
        .accessibilityLabel(Text("\(title). \(subtitle)"))
    }

    private var titleUsesEnglishBrand: Bool {
        title.unicodeScalars.allSatisfy(\.isASCII)
    }
}

struct PaneHeaderReorderModifier: ViewModifier {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var dragActive = false
    @State private var hovering = false
    @State private var cursorPushed = false

    var role: WorkspacePaneRole?

    func body(content: Content) -> some View {
        if let role {
            content
                .overlay {
                    if dragActive {
                        HStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(WeiBeiTheme.secondaryInk.opacity(0.42))
                                .frame(width: 2, height: 28)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .transition(WeiBeiTransition.floating)
                    }
                }
                .contentShape(Rectangle())
                .offset(y: hovering || dragActive ? -1 : 0)
                .scaleEffect(dragActive ? 1.01 : hovering ? 1.004 : 1, anchor: .top)
                .textSelection(.disabled)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onChanged { value in
                            guard abs(value.translation.width) > 2 else { return }
                            // No withAnimation on drag updates — that was thrashing the whole workspace.
                            if !dragActive {
                                store.beginThreePaneReorder(role)
                                dragActive = true
                            }
                            store.updateThreePaneReorder(role, horizontalDelta: value.translation.width)
                        }
                        .onEnded { value in
                            store.finishThreePaneReorder(role, horizontalDelta: value.translation.width)
                            dragActive = false
                        }
                )
                .onHover { value in
                    withAnimation(WeiBeiMotion.hover) {
                        hovering = value
                    }
                    updateCursor(isHovering: value)
                }
                .onChange(of: store.normalizedThreePaneOrder) { _, _ in
                    if dragActive {
                        withAnimation(WeiBeiMotion.micro) {
                            dragActive = false
                        }
                    }
                }
                .onDisappear {
                    if dragActive {
                        store.cancelThreePaneReorder()
                    }
                    popCursorIfNeeded()
                }
                .animation(WeiBeiMotion.hover, value: hovering)
        } else {
            content
        }
    }

    private func updateCursor(isHovering: Bool) {
        if isHovering, !cursorPushed {
            NSCursor.openHand.push()
            cursorPushed = true
        } else if !isHovering {
            popCursorIfNeeded()
        }
    }

    private func popCursorIfNeeded() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

private struct AgentComposerField: View {
    @EnvironmentObject private var store: WorkspaceStore
    var prompt: String
    var focused: FocusState<Bool>.Binding
    var font: Font
    var promptFont: Font
    var lineLimit: ClosedRange<Int>
    var height: CGFloat
    /// Cap for immersive grow; nil means fixed compact height.
    var maxHeight: CGFloat? = nil
    var sendButtonSize: CGFloat
    var trailingPadding: CGFloat
    var sendTrailing: CGFloat
    var sendBottom: CGFloat
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 0
    /// Codex-style footer: model chip on the left, send on the right inside the card.
    var showsModelFooter: Bool = false
    /// Floating paper surfaces already provide their own chrome.
    var showsChrome = true
    var submit: () -> Void

    private var canSend: Bool {
        !store.isStoppingAgent
            && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsControl: Bool {
        store.isAgentRunningInActiveChat || canSend
    }

    private var isWideComposer: Bool { maxHeight != nil || showsModelFooter }

    var body: some View {
        // Compact: fixed short field. Wide: min height, grow with lines up to maxHeight.
        let corner: CGFloat = isWideComposer ? 24 : WeiBeiMetric.controlRadius
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: isWideComposer ? .leading : .topLeading) {
                TextField(
                    "",
                    text: $store.agentDraft,
                    prompt: Text(prompt)
                        .font(promptFont)
                        .foregroundStyle(WeiBeiTheme.placeholderInk),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .font(font)
                .foregroundColor(WeiBeiTheme.ink)
                .focused(focused)
                .onSubmit(submit)
                .padding(.top, verticalPadding)
                .padding(.bottom, showsModelFooter ? 6 : verticalPadding)
                .padding(.trailing, showsModelFooter ? 0 : (showsControl ? trailingPadding : 0))
                // ChatGPT-like: a single line (and its placeholder) sits
                // vertically centered in the collapsed pill; extra lines grow
                // the card upward toward maxHeight.
                .frame(maxWidth: .infinity, alignment: isWideComposer ? .leading : .topLeading)
                .padding(.horizontal, horizontalPadding)

                if showsControl && !showsModelFooter {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            sendButton
                                .padding(.trailing, sendTrailing)
                                .padding(.bottom, sendBottom)
                        }
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: isWideComposer ? .infinity : nil,
                alignment: isWideComposer ? .leading : .topLeading
            )

            if showsModelFooter {
                HStack(spacing: 10) {
                    Text(store.modelName.isEmpty ? store.ui("模型", "Model") : store.modelName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if showsControl {
                        sendButton
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 10)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: maxHeight, alignment: .topLeading)
        .background {
            if showsChrome {
                // ChatGPT-like: same paper as the thread, lifted only by a soft
                // border and a whisper of shadow — no fill-color seam.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(WeiBeiTheme.paperRaised.opacity(store.appearanceMode.isDark ? 0.34 : 0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            if showsChrome {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        focused.wrappedValue ? WeiBeiTheme.hairline.opacity(0.9) : WeiBeiTheme.hairline.opacity(0.55),
                        lineWidth: 1
                    )
            }
        }
        .shadow(
            color: showsChrome ? WeiBeiTheme.ink.opacity(0.05) : .clear,
            radius: showsChrome ? 10 : 0,
            y: showsChrome ? 3 : 0
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focused.wrappedValue = true
        }
        .onChange(of: store.agentDraft) { _, _ in
            guard focused.wrappedValue else { return }
            guard let span = WeiBeiPerf.begin(
                "input.agent_to_next_main_queue_proxy"
            ) else {
                return
            }
            DispatchQueue.main.async {
                WeiBeiPerf.end(
                    span,
                    extra:
                        "outcome=completed endpoint=next_main_queue_proxy"
                )
            }
        }
        .animation(WeiBeiMotion.micro, value: showsControl)
        .accessibilityIdentifier(isWideComposer ? "agent-composer-codex" : "agent-composer-compact")
    }

    private var sendButton: some View {
        Button {
            store.isAgentRunningInActiveChat ? store.cancelAgentRequest() : submit()
        } label: {
            Image(systemName: store.isAgentRunningInActiveChat ? "stop.fill" : "paperplane.fill")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: sendButtonSize, prominence: store.isAgentRunningInActiveChat ? .neutral : .primary))
        .accessibilityLabel(Text(store.isAgentRunningInActiveChat ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send")))
        .help(store.isAgentRunningInActiveChat ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send"))
        .keyboardShortcut(.return, modifiers: [.command])
        .transition(WeiBeiTransition.floating)
        .animation(WeiBeiMotion.micro, value: showsControl)
    }
}

private struct AccessibilityFrameProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        probe.wantsLayer = true
        probe.setAccessibilityElement(true)
        probe.setAccessibilityRole(.group)
        probe.setAccessibilityIdentifier(identifier)
        probe.setAccessibilityLabel("weibei pane frame anchor")
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityIdentifier(identifier)
    }

    /// Never ask Auto Layout for an empty probe's fittingSize during pane remasure storms.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: max(proposal.width ?? nsView.bounds.width, 1),
            height: max(proposal.height ?? nsView.bounds.height, 1)
        )
    }
}

struct NotePaneView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var hoveredNoteMode: NoteRenderMode?
    /// Local typing buffer so each keystroke does not republish WorkspaceStore.noteText to the whole tree.
    @State private var draftNoteText = ""
    @State private var draftNoteItemID: String?
    @State private var isApplyingExternalNote = false
    @State private var noteDraftFlushTask: Task<Void, Never>?
    @State private var activeNoteRailID: String?
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil

    private let noteDraftFlushDelayNanoseconds: UInt64 = 220_000_000

    var body: some View {
        GeometryReader { geometry in
            let railOnly = ContentRailMetrics.isRailOnly(
                availableWidth: geometry.size.width,
                allowed: store.layout.allowsRailOnlyPanes
            )
            let railItems = noteRailItems
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if showsPaneHeader && hasNoteContent {
                        noteHeader
                    }

                    if let noteFileError = store.noteFileError {
                        Text(noteFileError)
                            .font(.caption)
                            .foregroundStyle(noteFileStatusColor(for: noteFileError))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                    } else if let transientNoteStatus = store.transientNoteStatus {
                        Text(transientNoteStatus)
                            .font(.caption)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }

                    noteBody
                }
                .opacity(railOnly ? 0 : 1)
                .allowsHitTesting(!railOnly)

                if store.layout != .immersiveWriting {
                    ContentRailView(
                        label: store.ui("文稿目录", "Draft outline"),
                        items: railItems,
                        activeID: activeNoteRailID ?? railItems.first?.id,
                        appearanceMode: store.appearanceMode,
                        isRailOnly: railOnly,
                        availableWidth: geometry.size.width,
                        topInset: railOnly ? 0 : (showsPaneHeader ? 44 : 34),
                        onActivate: { activateNoteRailItem($0, railOnly: railOnly) }
                    )
                    .zIndex(4)
                }
            }
        }
        .frame(minHeight: 280)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .topLeading) {
            AccessibilityFrameProbe(identifier: "stable-document-slot-reader")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if !showsPaneHeader && hasNoteContent {
                immersiveNoteHeader
            }
        }
        .animation(WeiBeiMotion.panel, value: store.notebookCreationDraft?.id)
        .onAppear {
            pullExternalNoteText()
        }
        .onDisappear {
            flushNoteDraft(immediate: true)
        }
        .onChange(of: store.activeNoteItemID) { previousID, _ in
            if let previousID, previousID == draftNoteItemID {
                flushNoteDraft(for: previousID, immediate: true)
            }
            pullExternalNoteText()
        }
        .onChange(of: store.noteText) { _, newValue in
            guard !isApplyingExternalNote else { return }
            // External writers (agent insert, wiki open, import) win over a stale draft.
            if newValue != draftNoteText {
                noteDraftFlushTask?.cancel()
                noteDraftFlushTask = nil
                draftNoteText = newValue
                draftNoteItemID = store.activeNoteItemID
                store.clearStagedNoteDraft(for: draftNoteItemID)
            }
        }
        .onChange(of: store.focusedPane) { _, pane in
            if pane != .notes {
                flushNoteDraft(immediate: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stable-document-slot-reader")
        .accessibilityLabel(Text("notes reader pane"))
    }

    private var hasNoteContent: Bool {
        store.activeNoteItem != nil || store.blankNoteDraftMaterialID != nil
    }

    @ViewBuilder
    private var noteHeader: some View {
        if let draft = store.notebookCreationDraft {
            notebookCreationPanel(draft: draft)
            .weibeiPaneHeaderChrome(appearanceMode: store.appearanceMode)
            .modifier(PaneHeaderReorderModifier(role: reorderRole))
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        } else {
            WeiBeiPaneHeader(
                title: store.ui("笔记", "Notes"),
                latinMark: store.interfaceLanguage == .chinese ? "NOTES" : nil,
                subtitle: noteHeaderSubtitle,
                appearanceMode: store.appearanceMode,
                reorderRole: reorderRole
            ) {
                ContextualContentListButton(kind: .note)
                LinkedSourcesControl()
                writingAssistControl
                noteModeControl
                newNoteControl
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        }
    }

    private var immersiveNoteHeader: some View {
        ZStack(alignment: .top) {
            ImmersiveHoverTitleView(
                mark: "NOTES",
                title: noteHeaderSubtitle,
                appearanceMode: store.appearanceMode,
                isPinned: store.notebookCreationDraft != nil || store.linkedSourcesPresented,
                actionsAlignedTrailing: true,
                reorderRole: reorderRole
            ) {
                ContextualContentListButton(kind: .note)
                LinkedSourcesControl()
                writingAssistControl
                noteModeControl
                newNoteControl
            }

            if let draft = store.notebookCreationDraft {
                notebookCreationPanel(draft: draft)
                    .padding(.horizontal, 10)
                    .frame(width: 420, height: 34)
                    .padding(.top, 42)
                    .transition(WeiBeiTransition.floating)
            }
        }
    }

    private func notebookCreationPanel(draft: NotebookCreationDraft) -> some View {
        NotebookCreationPanel(
            draft: draft,
            title: Binding(
                get: { store.notebookCreationDraft?.title ?? "" },
                set: { store.notebookCreationDraft?.title = $0 }
            ),
            confirm: {
                withAnimation(WeiBeiMotion.panel) {
                    store.confirmNotebookNoteCreation()
                }
            },
            cancel: {
                withAnimation(WeiBeiMotion.panel) {
                    store.cancelNotebookNoteCreation()
                }
            }
        )
    }

    private var writingAssistControl: some View {
        Menu {
            Button {
                prepareWritingAssist(store.ui(
                    "请根据\(store.agentPromptScope)，给出一版更清晰的笔记大纲。",
                    "Use \(store.agentPromptScope) to produce a clearer note outline."
                ))
            } label: {
                Label(store.ui("大纲建议", "Outline"), systemImage: "list.bullet.rectangle")
            }
            Button {
                prepareWritingAssist(store.hasSelectedMaterial
                    ? store.ui(
                        "请检查当前笔记缺少来源的位置，并建议应该引用当前资料的哪些部分。",
                        "Find where the current note needs sources and suggest which parts of the current material to cite."
                    )
                    : store.ui(
                        "请检查当前笔记缺少来源的位置，并标出需要补证据的段落。",
                        "Find where the current note needs sources and mark the paragraphs that need evidence."
                    ))
            } label: {
                Label(store.ui("补来源", "Add Sources"), systemImage: "link")
            }
            Button {
                prepareWritingAssist(store.ui(
                    "请整理和润色当前笔记，保留原意，并标出缺少来源的位置。",
                    "Organize and polish the current note, preserve the meaning, and mark where sources are missing."
                ))
            } label: {
                Label(store.ui("润色表达", "Polish"), systemImage: "text.quote")
            }
        } label: {
            Label(store.ui("整理", "Refine"), systemImage: "text.badge.checkmark")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .accessibilityLabel(Text(store.ui("整理当前笔记", "Refine current note")))
        .help(store.ui("按需生成大纲、补来源或润色表达", "Create an outline, add sources, or polish on demand"))
    }

    private func prepareWritingAssist(_ prompt: String) {
        flushNoteDraft(immediate: true)
        withAnimation(WeiBeiMotion.layout) {
            store.agentDraft = prompt
            store.setLayout(.immersiveConversation)
            store.revealRightPane(focusing: .agent)
        }
    }

    @ViewBuilder
    private var newNoteControl: some View {
        if store.hasSelectedMaterial {
            Menu {
                Button(store.ui("空白课程笔记", "Blank Course Note")) {
                    withAnimation(WeiBeiMotion.panel) {
                        store.promptCreateBlankNotebookNote()
                    }
                }
                Button(store.ui("当前资料笔记", "Current Material Note")) {
                    withAnimation(WeiBeiMotion.panel) {
                        store.promptCreateNotebookNoteFromCurrentMaterial()
                    }
                }
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 24))
            .accessibilityLabel(Text(store.ui("新建课程笔记", "New Course Note")))
            .help(store.ui("新建空白笔记或当前资料笔记", "Create a blank note or a note for the current material"))
        } else {
            Button {
                withAnimation(WeiBeiMotion.panel) {
                    store.promptCreateBlankNotebookNote()
                }
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 24))
            .accessibilityLabel(Text(store.ui("新建空白课程笔记", "New Blank Course Note")))
            .help(store.ui("新建空白课程笔记", "Create a blank course note"))
        }
    }

    private var noteModeControl: some View {
        HStack(spacing: 3) {
            ForEach(NoteRenderMode.visibleCases) { mode in
                noteModeButton(for: mode)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 28)
        .weibeiHeaderAccessoryGroup()
    }

    private func noteModeButton(for mode: NoteRenderMode) -> some View {
        let selected = store.noteRenderMode.visibleMode == mode
        let label = mode.label(language: store.interfaceLanguage)
        return Button {
            withAnimation(WeiBeiMotion.layout) {
                store.setNoteRenderMode(mode)
            }
        } label: {
            noteModeButtonLabel(mode: mode, selected: selected, hovering: hoveredNoteMode == mode)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                hoveredNoteMode = hovering ? mode : (hoveredNoteMode == mode ? nil : hoveredNoteMode)
            }
        }
        .accessibilityLabel(Text(label))
        .help(label)
    }

    private func noteModeButtonLabel(mode: NoteRenderMode, selected: Bool, hovering: Bool) -> some View {
        let foreground = selected ? WeiBeiTheme.cinnabar : hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk
        return Image(systemName: noteModeIcon(for: mode))
            .font(.system(size: 11.6, weight: selected ? .semibold : .medium))
            .frame(width: 28, height: 24)
            .foregroundStyle(foreground)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(noteModeButtonFill(selected: selected, hovering: hovering))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(noteModeButtonStroke(selected: selected, hovering: hovering), lineWidth: selected ? 0.7 : 0.45)
            }
            .scaleEffect(hovering && !selected ? 1.012 : 1)
            .contentShape(Rectangle())
            .animation(WeiBeiMotion.micro, value: selected)
            .animation(WeiBeiMotion.hover, value: hovering)
    }

    private func noteModeIcon(for mode: NoteRenderMode) -> String {
        switch mode {
        case .rich:
            return "square.and.pencil"
        case .split:
            return "rectangle.split.2x1"
        case .source:
            return "chevron.left.forwardslash.chevron.right"
        case .preview:
            return "eye"
        }
    }

    private func noteModeButtonFill(selected: Bool, hovering: Bool) -> Color {
        if selected {
            return WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode.isDark ? 0.44 : 0.62)
        }
        if hovering {
            return WeiBeiTheme.paperRaised.opacity(store.appearanceMode.isDark ? 0.16 : 0.20)
        }
        return Color.clear
    }

    private func noteModeButtonStroke(selected: Bool, hovering: Bool) -> Color {
        if selected {
            return WeiBeiTheme.cinnabar.opacity(store.appearanceMode.isDark ? 0.34 : 0.24)
        }
        if hovering {
            return WeiBeiTheme.hairline.opacity(store.appearanceMode.isDark ? 0.30 : 0.18)
        }
        return Color.clear
    }

    private var noteHeaderSubtitle: String {
        store.agentNoteTitle
    }

    private func noteFileStatusColor(for message: String) -> Color {
        message.hasPrefix("无法") || message.hasPrefix("Could not") ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk
    }

    @ViewBuilder
    private var noteBody: some View {
        if store.activeNoteItem == nil
            && store.blankNoteDraftMaterialID == nil {
            ContextualContentPicker(kind: .note)
        } else {
            Group {
            switch store.noteRenderMode.visibleMode {
            case .rich:
                richEditor
            case .split:
                HSplitView {
                    noteEditor
                        .frame(minWidth: 220)
                    MarkdownPreviewView(
                        markdown: draftNoteText,
                        markdownBaseURL: store.currentMarkdownBaseURL,
                        appearanceMode: store.appearanceMode,
                        interfaceLanguage: store.interfaceLanguage,
                        compact: true,
                        fitsContentHeight: false,
                        onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
                        onSourceReference: { reference in store.openSourceReference(reference) },
                        onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
                        onSelectionChange: { text, anchor in
                            store.updateSelection(text, source: .note, anchor: anchor, isEditable: false)
                        }
                    )
                        .frame(minWidth: 220)
                }
            case .source:
                noteEditor
            case .preview:
                richEditor
            }
            }
            .transition(WeiBeiTransition.layout)
            .animation(WeiBeiMotion.layout, value: store.noteRenderMode.visibleMode)
            .overlay(alignment: .topLeading) {
                if noteIsEmpty {
                    emptyNoteHint
                        .transition(WeiBeiTransition.message)
                }
            }
        }
    }

    private var noteMarkdownBinding: Binding<String> {
        Binding(
            get: { draftNoteText },
            set: { value in
                guard value != draftNoteText else { return }
                draftNoteText = value
                draftNoteItemID = store.activeNoteItemID
                if draftNoteItemID == nil {
                    store.updateNote(value)
                    return
                }
                store.stageNoteDraft(value, for: draftNoteItemID)
                scheduleNoteDraftFlush()
            }
        )
    }

    private var noteRailItems: [ContentRailItem] {
        let lines = draftNoteText.components(separatedBy: .newlines)
        let headings = lines.enumerated().compactMap { offset, line -> (line: Int, level: Int, title: String)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let level = trimmed.prefix { $0 == "#" }.count
            guard (1...4).contains(level) else { return nil }
            let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: level)
            guard markerEnd < trimmed.endIndex, trimmed[markerEnd].isWhitespace else { return nil }
            let title = trimmed[markerEnd...].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return (offset, level, title)
        }

        return headings.enumerated().map { index, heading in
            let nextLine = index + 1 < headings.count ? headings[index + 1].line : lines.count
            let excerpt = lines[(heading.line + 1)..<max(heading.line + 1, nextLine)]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let position = lines.count > 1 ? CGFloat(heading.line) / CGFloat(lines.count - 1) : 0
            return ContentRailItem(
                id: "note-heading-\(index)",
                position: position,
                level: heading.level - 1,
                title: heading.title,
                excerpt: railPreviewText(excerpt),
                metadata: store.ui("第 \(index + 1) / \(headings.count) 节 · H\(heading.level)", "Section \(index + 1) / \(headings.count) · H\(heading.level)")
            )
        }
    }

    private func activateNoteRailItem(_ item: ContentRailItem, railOnly: Bool) {
        guard let index = Int(item.id.replacingOccurrences(of: "note-heading-", with: "")) else { return }
        activeNoteRailID = item.id
        let navigate = {
            store.noteEditorCommand = NoteEditorCommand(kind: .scrollToHeading, markdown: String(index))
        }
        if railOnly {
            store.requestPaneExpansion(.notes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: navigate)
        } else {
            navigate()
        }
    }

    private func railPreviewText(_ value: String) -> String {
        let collapsed = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(180))
    }

    private var richEditor: some View {
        let itemID = store.activeNoteItemID
        return RichMarkdownEditorView(documentID: itemID ?? "", markdown: noteMarkdownBinding, command: Binding(get: {
            store.noteEditorCommand
        }, set: { value in
            store.noteEditorCommand = value
        }),
        isEditable: true,
        isFocused: store.focusedPane == .notes,
        focusRequest: store.focusRequest,
        markdownBaseURL: store.currentMarkdownBaseURL,
        attachmentDirectory: store.currentAttachmentDirectory,
        appearanceMode: store.appearanceMode,
        interfaceLanguage: store.interfaceLanguage,
        onSelectionChange: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
        }, onAskAgentWithSelection: { text, anchor in
            flushNoteDraft(immediate: true)
            store.updateSelection(text, source: .note, anchor: anchor)
            store.askSelection()
        }, onActiveHeadingChange: { index in
            activeNoteRailID = index.map { "note-heading-\($0)" }
        }, onWikiLink: { title in
            flushNoteDraft(immediate: true)
            store.openOrCreateWikiNote(title: title)
        }, onSourceReference: { reference in
            flushNoteDraft(immediate: true)
            store.openSourceReference(reference)
        }, onAppShortcut: { key, modifiers in
            if modifiers.contains(.command) {
                flushNoteDraft(immediate: true)
            }
            return store.handleAppShortcut(key: key, modifiers: modifiers)
        })
        .background(WeiBeiTheme.paper)
    }

    private var noteEditor: some View {
        MarkdownSourceEditor(text: noteMarkdownBinding, command: Binding(get: {
            store.noteEditorCommand
        }, set: { value in
            store.noteEditorCommand = value
        }),
        isFocused: store.focusedPane == .notes,
        focusRequest: store.focusRequest,
        markdownBaseURL: store.currentMarkdownBaseURL,
        attachmentDirectory: store.currentAttachmentDirectory,
        appearanceMode: store.appearanceMode,
        onSelectionChange: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
        }, onWikiLink: { title in
            flushNoteDraft(immediate: true)
            store.openOrCreateWikiNote(title: title)
        })
        .background(WeiBeiTheme.paper)
    }

    private var noteIsEmpty: Bool {
        draftNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pullExternalNoteText() {
        isApplyingExternalNote = true
        draftNoteItemID = store.activeNoteItemID
        draftNoteText = store.noteText
        store.clearStagedNoteDraft(for: draftNoteItemID)
        isApplyingExternalNote = false
    }

    private func scheduleNoteDraftFlush() {
        noteDraftFlushTask?.cancel()
        let itemID = draftNoteItemID ?? store.activeNoteItemID
        let snapshot = draftNoteText
        noteDraftFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: noteDraftFlushDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard draftNoteText == snapshot else { return }
            flushNoteDraft(for: itemID, immediate: true)
        }
    }

    private func flushNoteDraft(immediate: Bool = false) {
        flushNoteDraft(for: draftNoteItemID ?? store.activeNoteItemID, immediate: immediate)
    }

    private func flushNoteDraft(for itemID: String?, immediate: Bool) {
        noteDraftFlushTask?.cancel()
        noteDraftFlushTask = nil
        guard let itemID else {
            store.updateNote(draftNoteText)
            return
        }
        let value = (itemID == draftNoteItemID) ? draftNoteText : draftNoteText
        defer { store.clearStagedNoteDraft(for: itemID, matching: value) }
        if itemID == store.activeNoteItemID {
            if store.noteText == value { return }
            isApplyingExternalNote = true
            store.updateNote(value, for: itemID)
            isApplyingExternalNote = false
            return
        }
        // Inactive flush after note switch.
        store.updateNote(value, for: itemID)
        _ = immediate
    }

    private var emptyNoteHint: some View {
        Text(emptyNoteHintText)
            .font(.system(size: 13, weight: .medium, design: .serif))
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.72))
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .allowsHitTesting(false)
    }

    private var emptyNoteHintText: String {
        store.hasSelectedMaterial ? store.ui("开始记录当前材料", "Start taking notes on this material") : store.ui("开始记录当前笔记", "Start writing this note")
    }
}

private struct NotebookCreationPanel: View {
    @EnvironmentObject private var store: WorkspaceStore
    var draft: NotebookCreationDraft
    @Binding var title: String
    var confirm: () -> Void
    var cancel: () -> Void
    @FocusState private var focused: Bool
    @State private var hoveredConfirm = false
    @State private var hoveredCancel = false

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 9) {
            Text(draft.kind == .blank ? store.ui("新建笔记", "New Note") : store.ui("资料笔记", "Material Note"))
                .font(.system(size: 12.5, weight: .semibold, design: .serif))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.86))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            TextField(
                "",
                text: $title,
                prompt: Text(store.ui("笔记名", "Note title"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14.5, weight: .medium))
            .foregroundColor(WeiBeiTheme.ink)
            .focused($focused)
            .onSubmit(confirm)
            .frame(maxWidth: .infinity)
            .frame(height: 24)

            Button(action: confirm) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(confirmColor)
            .frame(width: 28, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(confirmBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(confirmBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(hoveredConfirm && canCreate ? 1.04 : 1)
            .opacity(canCreate ? 1 : 0.42)
            .disabled(!canCreate)
            .keyboardShortcut(.defaultAction)
            .onHover { hovering in
                withAnimation(WeiBeiMotion.hover) {
                    hoveredConfirm = hovering
                }
            }
            .accessibilityLabel(Text(store.ui("创建笔记", "Create Note")))
            .help(store.ui("创建笔记", "Create Note"))

            Button(action: cancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(cancelColor)
            .frame(width: 28, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(cancelBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(cancelBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(hoveredCancel ? 1.04 : 1)
            .onHover { hovering in
                withAnimation(WeiBeiMotion.hover) {
                    hoveredCancel = hovering
                }
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(store.ui("取消", "Cancel")))
            .help(store.ui("取消新建笔记", "Cancel note creation"))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(WeiBeiTheme.paperInset.opacity(0.24))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(0.34), lineWidth: 1)
        }
        .onExitCommand(perform: cancel)
        .onAppear {
            focused = true
        }
    }

    private var confirmColor: Color {
        guard canCreate else { return WeiBeiTheme.tertiaryInk }
        return hoveredConfirm ? WeiBeiTheme.onCinnabar : WeiBeiTheme.secondaryInk
    }

    private var confirmBackground: Color {
        guard canCreate, hoveredConfirm else { return Color.clear }
        return WeiBeiTheme.cinnabar.opacity(0.88)
    }

    private var confirmBorder: Color {
        guard canCreate, hoveredConfirm else { return Color.clear }
        return WeiBeiTheme.cinnabar.opacity(0.48)
    }

    private var cancelColor: Color {
        hoveredCancel ? WeiBeiTheme.cinnabar.opacity(0.72) : WeiBeiTheme.secondaryInk
    }

    private var cancelBackground: Color {
        hoveredCancel ? WeiBeiTheme.cinnabarSoft.opacity(0.68) : Color.clear
    }

    private var cancelBorder: Color {
        hoveredCancel ? WeiBeiTheme.cinnabar.opacity(0.22) : Color.clear
    }
}

final class MarkdownSourceTextView: NSTextView {
    var openWikiLinkAtCursor: (() -> Bool)?
    var hasImagesInPasteboard: ((NSPasteboard) -> Bool)?
    var insertImagesFromPasteboard: ((NSPasteboard) -> Bool)?

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        Array(Set(super.readablePasteboardTypes + [.tiff, .png, .fileURL]))
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "\r",
           openWikiLinkAtCursor?() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if insertImagesFromPasteboard?(NSPasteboard.general) == true {
            return
        }
        super.paste(sender)
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if insertImagesFromPasteboard?(pasteboard) == true {
            return true
        }
        return super.readSelection(from: pasteboard, type: type)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasImagesInPasteboard?(sender.draggingPasteboard) == true ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        insertImagesFromPasteboard?(sender.draggingPasteboard) == true || super.performDragOperation(sender)
    }
}

struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var command: NoteEditorCommand?
    var isFocused = false
    var focusRequest = 0
    var markdownBaseURL: URL?
    var attachmentDirectory: URL?
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var onSelectionChange: (String, CGPoint?) -> Void
    var onWikiLink: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            command: $command,
            isFocused: isFocused,
            focusRequest: focusRequest,
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            appearanceMode: appearanceMode,
            onSelectionChange: onSelectionChange,
            onWikiLink: onWikiLink
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        WeiBeiQuietScrollers.configure(scrollView, hasHorizontalScroller: false)
        scrollView.drawsBackground = false

        let textView = MarkdownSourceTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.string = text
        applyTheme(to: textView)
        textView.delegate = context.coordinator
        textView.openWikiLinkAtCursor = { [weak coordinator = context.coordinator, weak textView] in
            guard let textView else { return false }
            return coordinator?.openWikiLink(in: textView) ?? false
        }
        textView.hasImagesInPasteboard = { [weak coordinator = context.coordinator] pasteboard in
            coordinator?.hasImages(in: pasteboard) ?? false
        }
        textView.insertImagesFromPasteboard = { [weak coordinator = context.coordinator, weak textView] pasteboard in
            guard let textView else { return false }
            return coordinator?.insertImages(from: pasteboard, in: textView) ?? false
        }
        textView.registerForDraggedTypes([.fileURL, .png, .tiff])
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.command = $command
        context.coordinator.markdownBaseURLString = markdownBaseURL?.absoluteString ?? ""
        context.coordinator.attachmentDirectory = attachmentDirectory
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onWikiLink = onWikiLink
        context.coordinator.isFocused = isFocused
        context.coordinator.focusRequest = focusRequest
        context.coordinator.appearanceMode = appearanceMode
        if textView.string != text {
            textView.string = text
        }
        applyTheme(to: textView)
        context.coordinator.applyFocus(in: textView)
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.run(command, in: textView)
            DispatchQueue.main.async {
                self.command = nil
            }
        }
    }

    private func applyTheme(to textView: NSTextView) {
        let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.font = baseFont
        textView.textColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.insertionPointColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.selectedTextAttributes = [
            .backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode),
            .foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode)
        ]
        Self.applySourcePresentation(in: textView, appearanceMode: appearanceMode, baseFont: baseFont)
    }

    private static func applySourcePresentation(
        in textView: NSTextView,
        appearanceMode: WeiBeiAppearanceMode,
        baseFont: NSFont
    ) {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let ink = WeiBeiNativePalette.ink(for: appearanceMode)
        let quotePrefixColor = ink.withAlphaComponent(appearanceMode.isDark ? 0.30 : 0.36)
        let markerColor = NSColor.clear
        let markerFont = NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular)
        let quotePrefixRegex = try? NSRegularExpression(pattern: #"(?m)^\s*(?:>\s*)+"#)
        let calloutControlRegex = try? NSRegularExpression(
            pattern: #"(?m)^(\s*(?:>\s*)*)(\\?\[![A-Za-z][A-Za-z0-9_-]*\][+-]?\s*)"#
        )

        textView.undoManager?.disableUndoRegistration()
        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: ink
        ], range: fullRange)

        quotePrefixRegex?.enumerateMatches(in: textView.string, range: fullRange) { match, _, _ in
            guard let range = match?.range, range.location != NSNotFound else { return }
            textStorage.addAttributes([
                .foregroundColor: quotePrefixColor
            ], range: range)
        }

        calloutControlRegex?.enumerateMatches(in: textView.string, range: fullRange) { match, _, _ in
            guard let markerRange = match?.range(at: 2), markerRange.location != NSNotFound else { return }
            textStorage.addAttributes([
                .font: markerFont,
                .foregroundColor: markerColor,
                .baselineOffset: 0
            ], range: markerRange)
        }
        textStorage.endEditing()
        textView.undoManager?.enableUndoRegistration()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var command: Binding<NoteEditorCommand?>
        var isFocused: Bool
        var focusRequest: Int
        var markdownBaseURLString: String
        var attachmentDirectory: URL?
        var onSelectionChange: (String, CGPoint?) -> Void
        var onWikiLink: (String) -> Void
        var appearanceMode: WeiBeiAppearanceMode
        var lastCommandID: UUID?
        private var lastAppliedFocusRequest = -1

        init(
            text: Binding<String>,
            command: Binding<NoteEditorCommand?>,
            isFocused: Bool,
            focusRequest: Int,
            markdownBaseURLString: String,
            attachmentDirectory: URL?,
            appearanceMode: WeiBeiAppearanceMode,
            onSelectionChange: @escaping (String, CGPoint?) -> Void,
            onWikiLink: @escaping (String) -> Void
        ) {
            self.text = text
            self.command = command
            self.isFocused = isFocused
            self.focusRequest = focusRequest
            self.markdownBaseURLString = markdownBaseURLString
            self.attachmentDirectory = attachmentDirectory
            self.onSelectionChange = onSelectionChange
            self.onWikiLink = onWikiLink
            self.appearanceMode = appearanceMode
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MarkdownSourceEditor.applySourcePresentation(
                in: textView,
                appearanceMode: appearanceMode,
                baseFont: .monospacedSystemFont(ofSize: 15, weight: .regular)
            )
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let stringRange = Range(range, in: textView.string) else {
                onSelectionChange("", nil)
                return
            }
            onSelectionChange(String(textView.string[stringRange]), Self.anchor(for: range, in: textView))
        }

        func run(_ command: NoteEditorCommand, in textView: NSTextView) {
            switch command.kind {
            case .replaceSelection:
                replaceSelection(with: command.markdown, in: textView)
            case .applyAgentPatch:
                applyPatch(command.markdown, in: textView)
            case .insertMarkdown:
                insertMarkdown(command.markdown, in: textView)
            case .scrollToHeading:
                scrollToHeading(command.markdown, in: textView)
            }
        }

        private func scrollToHeading(_ rawIndex: String, in textView: NSTextView) {
            guard let targetIndex = Int(rawIndex), targetIndex >= 0 else { return }
            let pattern = #"(?m)^#{1,4}[\t ]+.+$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            let matches = regex.matches(in: textView.string, range: fullRange)
            guard matches.indices.contains(targetIndex) else { return }
            textView.scrollRangeToVisible(matches[targetIndex].range)
        }

        private func replaceSelection(with markdown: String, in textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0 else {
                applyPatch(markdown, in: textView)
                return
            }
            insertMarkdown(markdown, in: textView)
        }

        private func insertMarkdown(_ markdown: String, in textView: NSTextView) {
            let range = textView.selectedRange()
            textView.textStorage?.replaceCharacters(in: range, with: markdown)
            let cursor = range.location + (markdown as NSString).length
            textView.setSelectedRange(NSRange(location: cursor, length: 0))
            text.wrappedValue = textView.string
            refreshSourcePresentation(in: textView)
        }

        private func applyPatch(_ markdown: String, in textView: NSTextView) {
            let next = "\(textView.string.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(markdown.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            textView.string = next
            text.wrappedValue = next
            textView.setSelectedRange(NSRange(location: (next as NSString).length, length: 0))
            refreshSourcePresentation(in: textView)
        }

        func applyFocus(in textView: NSTextView) {
            guard isFocused, focusRequest != lastAppliedFocusRequest else { return }
            lastAppliedFocusRequest = focusRequest
            textView.window?.makeFirstResponder(textView)
        }

        func openWikiLink(in textView: NSTextView) -> Bool {
            guard let title = WikiLink.enclosingTitle(in: textView.string, cursor: textView.selectedRange().location) else {
                return false
            }
            onWikiLink(title)
            return true
        }

        func insertImages(from pasteboard: NSPasteboard, in textView: NSTextView) -> Bool {
            let attachments = imageAttachments(from: pasteboard)
            guard !attachments.isEmpty else { return false }
            let markdown = attachments.map { MarkdownAttachmentStore.markdownImage(for: $0) }.joined(separator: "\n\n")
            insertBlockMarkdown(markdown, in: textView)
            return true
        }

        func hasImages(in pasteboard: NSPasteboard) -> Bool {
            imageFileURLs(from: pasteboard).isEmpty == false || NSImage(pasteboard: pasteboard) != nil
        }

        private func imageAttachments(from pasteboard: NSPasteboard) -> [MarkdownAttachment] {
            let urls = imageFileURLs(from: pasteboard)
            if !urls.isEmpty {
                let attachments = urls.compactMap(saveImageFile)
                if !attachments.isEmpty { return attachments }
            }

            guard let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                return []
            }

            return [saveImageData(data, originalName: "pasted-image.png", mime: "image/png")].compactMap(\.self)
        }

        private func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? [])
                .compactMap { object in
                    if let url = object as? URL { return url }
                    if let url = object as? NSURL { return url as URL }
                    return nil
                }
                .filter { MarkdownAttachmentStore.isSupportedImageExtension($0.pathExtension) }
        }

        private func saveImageFile(_ url: URL) -> MarkdownAttachment? {
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return saveImageData(
                data,
                originalName: url.lastPathComponent,
                mime: MarkdownAttachmentStore.mimeType(forFileExtension: url.pathExtension)
            )
        }

        private func saveImageData(_ data: Data, originalName: String, mime: String) -> MarkdownAttachment? {
            guard let attachmentDirectory else { return nil }
            return try? MarkdownAttachmentStore.save(
                data: data,
                originalName: originalName,
                mime: mime,
                attachmentDirectory: attachmentDirectory,
                markdownBaseURLString: markdownBaseURLString
            )
        }

        private func insertBlockMarkdown(_ markdown: String, in textView: NSTextView) {
            let result = MarkdownBlockInsertion.insert(markdown, into: textView.string, replacing: textView.selectedRange())
            textView.string = result.text
            textView.setSelectedRange(NSRange(location: result.cursor, length: 0))
            text.wrappedValue = result.text
            refreshSourcePresentation(in: textView)
        }

        private func refreshSourcePresentation(in textView: NSTextView) {
            MarkdownSourceEditor.applySourcePresentation(
                in: textView,
                appearanceMode: appearanceMode,
                baseFont: .monospacedSystemFont(ofSize: 15, weight: .regular)
            )
        }

        private static func anchor(for range: NSRange, in textView: NSTextView) -> CGPoint? {
            guard let window = textView.window else { return nil }
            let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard !rect.isEmpty else { return nil }
            let screenPoint = CGPoint(x: rect.midX, y: rect.minY)
            return SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)
        }
    }
}

struct MarkdownPreviewView: View {
    var markdown: String
    var markdownBaseURL: URL?
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var compact = false
    var fitsContentHeight = true
    /// When true, lock height after the first stable measure so chat LazyVStack
    /// does not thrash on ResizeObserver jitter (hang-proof for agent turns).
    var freezeHeightAfterMeasure = false
    /// A finalized streaming snapshot remains live through its delayed font,
    /// formula and image measurements before offscreen height freezing resumes.
    var allowsHeightFreeze = true
    /// Seed from a session cache so recycled rows do not collapse then grow.
    var seedContentHeight: CGFloat? = nil
    /// Exact point-rounded layout width kept for diagnostics only. Unfreeze uses
    /// the 24pt bucket — 1pt key changes caused scrollbar/layout jitter to
    /// unfreeze every KaTeX row and spin sizeThatFits at 100% CPU (sample 662).
    var layoutWidthKey: Int = 0
    var isChatWideTypography = false
    /// Streaming prefix mode: markdown grows append-only, so keep the current
    /// frame height until the next real measurement instead of collapsing to
    /// the 44pt loading height on every append (which strobed the chat).
    var preservesHeightAcrossMarkdownChanges = false
    /// Pass-through to Milkdown's cumulative document-diff streaming session.
    var streamsMarkdownUpdates = false
    /// Ignore ordinary ResizeObserver events while a streaming answer is being
    /// finalized. The generation-tagged final callback supplies the authoritative
    /// height for that handoff instead.
    var acceptsHeightMeasurements = true
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onRenderReady: () -> Void = {}
    var onFinalizedSnapshotReady: (CGFloat) -> Void = { _ in }
    var onRenderFailure: () -> Void = {}
    var onSelectionChange: (String, CGPoint?) -> Void = { _, _ in }
    var onContentHeightChange: () -> Void = {}
    private static let compactPreviewLoadingHeight: CGFloat = 44
    private static let compactPreviewMaximumHeight: CGFloat = 20_000

    var onMeasuredHeight: (CGFloat) -> Void = { _ in }
    @State private var command: NoteEditorCommand?
    @State private var contentHeight: CGFloat = Self.compactPreviewLoadingHeight
    @State private var heightFrozen = false
    @State private var acceptedMeasureCount = 0
    @State private var maxObservedMeasuredHeight: CGFloat = 0
    @State private var lastLayoutWidthKey = 0
    @State private var lastChatWideTypography = false

    var body: some View {
        RichMarkdownEditorView(
            markdown: .constant(markdown),
            command: $command,
            isEditable: false,
            markdownBaseURL: markdownBaseURL,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage,
            isCompactPreview: compact,
            isChatWideTypography: isChatWideTypography,
            streamsMarkdownUpdates: streamsMarkdownUpdates,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onSelectionChange,
            onContentHeightChange: { height in
                guard acceptsHeightMeasurements else {
                    WeiBeiPerf.event(
                        "webview.markdown_height_ignored",
                        extra: "reason=finalizing"
                    )
                    return
                }
                guard compact && fitsContentHeight else {
                    WeiBeiPerf.event(
                        "webview.markdown_height_ignored",
                        extra: "reason=surface"
                    )
                    return
                }
                guard height.isFinite,
                      height > 0,
                      height <= Self.compactPreviewMaximumHeight else {
                    WeiBeiPerf.event(
                        "webview.markdown_height_ignored",
                        extra: "reason=invalid"
                    )
                    return
                }
                let measuredHeight = ceil(height)
                let nextFrameHeight = max(measuredHeight, Self.compactPreviewLoadingHeight)
                // Once frozen, never change the SwiftUI frame — LazyVStack recycle
                // during chat scroller drags (sample build 663, NSScroller.trackKnob)
                // was accepting late ResizeObserver growth and remasuring every row.
                if freezeHeightAfterMeasure, heightFrozen {
                    // Report the height the row actually keeps, not a measurement
                    // produced while its pane is being clipped toward zero width.
                    // Caching the ignored narrow-width height created giant blank
                    // regions when the conversation pane was opened again.
                    onMeasuredHeight(contentHeight)
                    WeiBeiPerf.event(
                        "webview.markdown_height_ignored",
                        extra: "reason=frozen"
                    )
                    return
                }
                // Ignored measurements can come from the pane's clipped animation
                // width. Never let them poison the later stability backstop.
                maxObservedMeasuredHeight = max(maxObservedMeasuredHeight, nextFrameHeight)
                // This callback only receives a real JS measurement. Keep its
                // success separate from the 44pt minimum SwiftUI frame so a
                // legitimate short quote/list can reveal and freeze too.
                onMeasuredHeight(measuredHeight)
                // Ignore sub-pixel ResizeObserver jitter once we have a real measure.
                if contentHeight >= Self.compactPreviewLoadingHeight,
                   abs(contentHeight - nextFrameHeight) < 2 {
                    if freezeHeightAfterMeasure, allowsHeightFreeze {
                        heightFrozen = true
                    }
                    WeiBeiPerf.event(
                        "webview.markdown_height_ignored",
                        extra: "reason=jitter"
                    )
                    return
                }
                contentHeight = nextFrameHeight
                // Do NOT freeze on a fresh accept: KaTeX displayMode re-layout
                // and font loading can still grow the content. Freeze happens
                // in the jitter branch above once two consecutive measures
                // agree (<2pt). The storm backstop below is deliberately loose
                // AND freezes at the MAX height ever observed — freezing at a
                // partial-layout height clipped long answers mid-line
                // (user report 2026-08-01 23:46).
                acceptedMeasureCount += 1
                if freezeHeightAfterMeasure,
                   allowsHeightFreeze,
                   acceptedMeasureCount >= 12 {
                    contentHeight = max(nextFrameHeight, maxObservedMeasuredHeight)
                    heightFrozen = true
                }
                WeiBeiPerf.event(
                    "webview.markdown_height_accepted"
                )
                onContentHeightChange()
            },
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut,
            onRenderReady: onRenderReady,
            onFinalizedRenderReady: { height in
                guard compact && fitsContentHeight,
                      height.isFinite,
                      height > 0,
                      height <= Self.compactPreviewMaximumHeight else { return }
                let measuredHeight = ceil(height)
                let nextFrameHeight = max(
                    measuredHeight,
                    Self.compactPreviewLoadingHeight
                )
                heightFrozen = false
                acceptedMeasureCount = 0
                contentHeight = nextFrameHeight
                maxObservedMeasuredHeight = nextFrameHeight
                onMeasuredHeight(measuredHeight)
                onContentHeightChange()
                onFinalizedSnapshotReady(measuredHeight)
            },
            onRenderFailure: onRenderFailure
        )
        .background(compact ? Color.clear : WeiBeiTheme.paper)
        .frame(height: compact && fitsContentHeight ? max(contentHeight, Self.compactPreviewLoadingHeight) : nil)
        .onAppear {
            lastLayoutWidthKey = layoutWidthKey
            lastChatWideTypography = isChatWideTypography
            if let seed = seedContentHeight, seed.isFinite, seed > 0 {
                contentHeight = max(ceil(seed), Self.compactPreviewLoadingHeight)
                // Keep frozen across LazyVStack recycle. Unfreezing here forced
                // every chat KaTeX row to remasure while scrolling (build 663).
                if freezeHeightAfterMeasure {
                    heightFrozen = true
                    return
                }
            }
            heightFrozen = false
        }
        .onChange(of: layoutWidthKey) { _, widthKey in
            guard widthKey != lastLayoutWidthKey else { return }
            // Only unfreeze across coarse width buckets. Sub-bucket jitter from
            // scrollbar / split remasure must not restart every chat WKWebView.
            let previousBucket = AgentFinalizedMarkdownHeightCache.widthBucket(
                CGFloat(lastLayoutWidthKey)
            )
            let nextBucket = AgentFinalizedMarkdownHeightCache.widthBucket(
                CGFloat(widthKey)
            )
            lastLayoutWidthKey = widthKey
            guard previousBucket != nextBucket else { return }
            heightFrozen = false
            acceptedMeasureCount = 0
            maxObservedMeasuredHeight = 0
        }
        .onChange(of: isChatWideTypography) { _, wideTypography in
            guard wideTypography != lastChatWideTypography else { return }
            lastChatWideTypography = wideTypography
            heightFrozen = false
            acceptedMeasureCount = 0
            maxObservedMeasuredHeight = 0
        }
        .onChange(of: markdown) { _, _ in
            guard compact && fitsContentHeight else { return }
            heightFrozen = false
            acceptedMeasureCount = 0
            maxObservedMeasuredHeight = 0
            if preservesHeightAcrossMarkdownChanges { return }
            contentHeight = Self.compactPreviewLoadingHeight
            onContentHeightChange()
        }
    }
}

private struct AgentRailTurn {
    var id: UUID
    var startMessageID: UUID
    var startIndex: Int
    var question: String
    var answer: String
}

/// Keeps the last frame-level probe value without publishing it through SwiftUI state.
/// The real parent proposal lays out visible content; sampled width settles render caches.
private final class AgentPaneWidthRelay {
    var pendingWidth: CGFloat?
    var structureTransitionActive = false
    var dividerDragActive = false

    var isActive: Bool {
        structureTransitionActive || dividerDragActive
    }
}

/// Standard chat column metrics — one centered axis shared by messages and composer.
/// Compact = three-pane agent strip; wide = immersive conversation (Codex-like full chat).
///
/// Critical: content width must always fit the measured pane. Never invent a floor larger
/// than `availableWidth`, or multi-pane text centers as if the strip were full-window wide.
private enum AgentChatLayoutMetrics {
    /// ChatGPT-like fixed comfortable column in every layout: narrow panes fill
    /// outright, wide windows cap at ChatGPT's measured column (~960pt, 65% of a
    /// 1470pt window) — user-calibrated against side-by-side screenshots.
    static let wideMaxWidth: CGFloat = 960
    /// Content columns at least this wide read with the immersive typography tier,
    /// regardless of which layout hosts the chat pane.
    static let wideTypographyMinContentWidth: CGFloat = 620
    static let compactSideGutter: CGFloat = 12
    /// Codex-style: modest side margin; column grows/shrinks with the window.
    static let wideSideGutter: CGFloat = 28
    static let compactComposerHeight: CGFloat = 52
    /// Immersive min height — grows with typed lines; never a giant empty white void.
    static let wideComposerMinHeight: CGFloat = 88
    static let wideComposerMaxHeight: CGFloat = 340
    static let compactFontSize: CGFloat = 14.5
    static let wideFontSize: CGFloat = 16.5

    static func isWide(layout: WorkspaceLayout) -> Bool {
        // Immersive conversation only — document multi-pane keeps compact strip metrics.
        layout == .immersiveConversation
    }

    static func contentWidth(availableWidth: CGFloat, wide: Bool) -> CGFloat {
        let gutter = (wide ? wideSideGutter : compactSideGutter) * 2
        let usable = max(availableWidth - gutter, 1)
        // ChatGPT-like in every layout: fill narrow panes outright, cap wide
        // windows at one fixed readable column. The layout enum no longer picks
        // a different ceiling — a full-window chat tab reads like immersive.
        return min(usable, wideMaxWidth)
    }

    static func composerHeight(wide: Bool) -> CGFloat {
        // Fixed min for immersive; field grows via TextField lineLimit, capped by max frame.
        wide ? wideComposerMinHeight : compactComposerHeight
    }

    static func composerMaxHeight(wide: Bool) -> CGFloat {
        wide ? wideComposerMaxHeight : compactComposerHeight
    }

    static func composerFontSize(wide: Bool) -> CGFloat {
        wide ? wideFontSize : compactFontSize
    }
}

struct AgentPaneView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil
    @FocusState private var draftFocused: Bool
    @State private var activeAgentRailID: String?
    @State private var agentFollowsLatest = true
    @State private var sessionPendingDeletion: StudySession?
    /// Settled pane width for renderer caches. 0 until first real measurement.
    @State private var measuredPaneWidth: CGFloat = 0
    @State private var paneWidthRelay = AgentPaneWidthRelay()
    /// Structural pane show/hide animates the AppKit slot every frame. Visible
    /// finalized Markdown follows the live column; offscreen web views hold one
    /// width and settle once at the destination instead of all reflowing per frame.
    @State private var heldPaneLayoutWidth: CGFloat?
    @State private var isPaneWidthMotionActive = false
    @State private var lastReadablePaneWidth: CGFloat = 360
    @State private var paneStructureTransitionSequence = 0
    /// Driven by the AppKit scroll probe — true when the viewport sits well
    /// above the newest message, revealing the jump-to-latest pill.
    @State private var showsJumpToLatest = false
    /// Fold long history on open: only the newest page mounts KaTeX WKWebViews.
    /// The limit only grows in-session — never unmount a mounted row, or scrolling
    /// back re-enters the LazyVStack remount storm this pane was cured of.
    @State private var agentVisibleMessageLimit = AgentPaneView.agentHistoryPageSize
    @State private var isRevealingEarlierAgentHistory = false
    @State private var isAgentHistoryRevealButtonHovered = false

    private static let agentHistoryPageSize = AgentHistoryRevealPolicy.pageSize
    private static let paneStructureTransitionDuration: TimeInterval = 0.24

    private let agentBottomAnchorID = "agentConversationBottom"

    private var hiddenAgentHistoryCount: Int {
        max(store.messages.count - agentVisibleMessageLimit, 0)
    }

    private var visibleAgentMessages: ArraySlice<AgentMessage> {
        store.messages.suffix(max(agentVisibleMessageLimit, 0))
    }

    private var isImmersiveConversation: Bool {
        store.layout == .immersiveConversation
    }

    private var usesWideChatLayout: Bool {
        AgentChatLayoutMetrics.isWide(layout: store.layout)
    }

    private var replySources: [AgentReplySource] {
        store.messages.flatMap(\.sources)
    }

    /// Semantic renderer width; the GeometryReader proposal owns visible layout.
    /// Hidden resident hosts retain their last readable width for the next open.
    private var agentPaneWidth: CGFloat {
        if measuredPaneWidth > ContentRailMetrics.railOnlyThreshold {
            return measuredPaneWidth
        }
        return usesWideChatLayout ? 1100 : lastReadablePaneWidth
    }

    var body: some View {
        let wide = AgentChatLayoutMetrics.isWide(layout: store.layout)
        let showsContentRail = !wide && store.layout.allowsRailOnlyPanes
        let railItems = showsContentRail ? agentRailItems : []
        // The native split host changes this proposal on every divider frame.
        // Read it locally so visible content and the rail follow continuously;
        // never publish those frame-level values into the eager message tree.
        GeometryReader { paneGeometry in
            let liveAvailableWidth = max(paneGeometry.size.width, 1)
            let railOnly = ContentRailMetrics.isRailOnly(
                availableWidth: liveAvailableWidth,
                allowed: store.layout.allowsRailOnlyPanes
            )
            let contentWidth = AgentChatLayoutMetrics.contentWidth(
                availableWidth: liveAvailableWidth,
                wide: wide
            )
            let markdownContentWidth = AgentChatLayoutMetrics.contentWidth(
                availableWidth: heldPaneLayoutWidth ?? agentPaneWidth,
                wide: wide
            )
            let comfy = wide
                || contentWidth >= AgentChatLayoutMetrics.wideTypographyMinContentWidth
            let headerHeight: CGFloat = showsPaneHeader
                ? (liveAvailableWidth < 420 ? 44 : 54)
                : 0

            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        if showsPaneHeader {
                            WeiBeiPaneHeader(
                                title: store.ui("对话", "Chat"),
                                latinMark: store.interfaceLanguage == .chinese ? "CHAT" : nil,
                                subtitle: store.agentConversationSubtitle,
                                appearanceMode: store.appearanceMode,
                                reorderRole: reorderRole,
                                availableWidth: liveAvailableWidth
                            ) {
                                sessionMenu
                            }
                        }

                        ScrollView(showsIndicators: true) {
                            // No scrollTargetLayout / scrollPosition / viewport minHeight
                            // feedback — those all thrash sizeThatFits on the chat stack.
                            // Eager VStack (not LazyVStack): each finalized turn may host
                            // Milkdown/KaTeX WKWebView. Lazy recycle remounted PlatformViews
                            // while dragging the chat scroller and froze the UI (build 664).
                            // Long histories fold behind a reveal button instead — unrendered
                            // rows cost nothing; keep full Markdown rendering for visible ones.
                            VStack(alignment: .leading, spacing: comfy ? 22 : 12) {
                                if hiddenAgentHistoryCount > 0 {
                                    agentHistoryRevealButton(proxy: proxy)
                                        .transition(WeiBeiTransition.message)
                                }
                                ForEach(visibleAgentMessages) { message in
                                    agentMessageRow(
                                        message: message,
                                        contentWidth: contentWidth,
                                        wide: wide
                                    )
                                }
                                if store.isAgentRunningInActiveChat
                                    && !store.hasPersistedGeneratingAgentReply
                                    && !store.agentStreamingText.isEmpty
                                {
                                    agentReadingColumn(
                                        alignment: .leading
                                    ) {
                                        AgentStreamingResponse(
                                            text: store.agentStreamingText,
                                            isChatWideTypography: comfy
                                        )
                                    }
                                    .id("agent-streaming-response")
                                    .transition(WeiBeiTransition.message)
                                }
                                if store.isAgentRunningInActiveChat
                                    && !store.hasPersistedGeneratingAgentReply
                                    && store.agentStreamingText.isEmpty
                                {
                                    agentReadingColumn(
                                        alignment: .leading
                                    ) {
                                        AgentThinkingIndicator()
                                    }
                                    .id("agent-thinking")
                                    .transition(WeiBeiTransition.message)
                                }
                                Color.clear
                                    .frame(height: agentScrollBottomInset)
                                    .id(agentBottomAnchorID)
                                    .background {
                                        AgentScrollDistanceProbe { metrics in
                                            handleScrollMetrics(metrics, proxy: proxy)
                                        }
                                    }
                            }
                            .padding(.horizontal, wide ? 8 : 10)
                            .padding(.vertical, wide ? 14 : 10)
                            .environment(\.agentChatLayoutWidth, markdownContentWidth)
                            .environment(\.agentChatPaneStructureTransitionActive, isPaneWidthMotionActive)
                            .padding(.top, store.messages.isEmpty ? 22 : 0)
                            // A held offscreen renderer may be wider than the pane,
                            // but it must never establish the scroll document width.
                            .frame(
                                width: railOnly ? ContentRailMetrics.readableWidth : liveAvailableWidth,
                                alignment: .topLeading
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .zIndex(0)

                        agentInputTray(wide: wide)
                            .zIndex(1)
                            .animation(WeiBeiMotion.panel, value: store.layout)
                            .animation(WeiBeiMotion.panel, value: wide)
                    }
                    .overlay(alignment: .bottom) {
                        if showsJumpToLatest {
                            jumpToLatestButton(proxy: proxy)
                                .padding(.bottom, composerFieldHeight + (wide ? 46 : 34))
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    // Once the rail owns the pane, keep the invisible resident chat
                    // at one readable proposal instead of laying WebKit out at 1–38pt.
                    .frame(
                        minWidth: railOnly ? ContentRailMetrics.readableWidth : nil,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .opacity(railOnly ? 0 : 1)
                    .allowsHitTesting(!railOnly)

                    if showsContentRail {
                        ContentRailView(
                            label: store.ui("对话轨道", "Conversation rail"),
                            items: railItems,
                            activeID: activeAgentRailID ?? railItems.first?.id,
                            appearanceMode: store.appearanceMode,
                            isRailOnly: railOnly,
                            availableWidth: liveAvailableWidth,
                            topInset: railOnly ? 0 : headerHeight,
                            bottomInset: railOnly ? 0 : agentRailBottomInset,
                            onActivate: { activateAgentRailItem($0, railOnly: railOnly, proxy: proxy) }
                        )
                        .zIndex(4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .onChange(of: store.messages.map(\.id)) { oldIDs, newIDs in
                    // Only a true append to this conversation widens the mounted window.
                    // Initial restore used to look like a 0 -> N append and mounted the
                    // entire rich history, defeating paging and stalling pane toggles.
                    if let appendedCount = AgentHistoryRevealPolicy.appendedMessageCount(
                        previousMessageIDs: oldIDs,
                        currentMessageIDs: newIDs
                    ) {
                        agentVisibleMessageLimit += appendedCount
                    } else {
                        agentVisibleMessageLimit = Self.agentHistoryPageSize
                        isRevealingEarlierAgentHistory = false
                    }
                    if showsContentRail, let lastID = store.messages.last?.id {
                        updateAgentRailPosition(for: lastID)
                    }
                    scrollAgentToBottom(proxy)
                }
                .onChange(of: store.activeStudySessionID) { _, _ in
                    agentVisibleMessageLimit = Self.agentHistoryPageSize
                    isRevealingEarlierAgentHistory = false
                }
            }
            .preference(
                key: AgentPaneWidthKey.self,
                value: liveAvailableWidth
            )
        }
        .onPreferenceChange(AgentPaneWidthKey.self) { width in
            applyMeasuredPaneWidth(width)
        }
        .onReceive(NotificationCenter.default.publisher(for: .weiBeiDocumentDividerDragBegan)) { _ in
            beginPaneDividerDrag()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weiBeiDocumentDividerDragEnded)) { _ in
            endPaneDividerDrag()
        }
        .onChange(of: Set(store.visibleDocumentPaneOrder)) { _, _ in
            beginPaneStructureTransition()
        }
        .onChange(of: store.layout) { _, layout in
            // Entering immersive: seed wide so we never flash the last three-pane strip width.
            // Leaving immersive: drop to 0 so the next probe owns the multi-pane strip.
            if layout == .immersiveConversation {
                if measuredPaneWidth < 700 {
                    measuredPaneWidth = max(measuredPaneWidth, 1100)
                }
            } else if measuredPaneWidth > 700 {
                // Restore the last real compact width; the next probe refines it.
                // Immersive measurements never overwrite this compact seed.
                measuredPaneWidth = lastReadablePaneWidth
            }
        }
        .frame(minHeight: 260)
        .foregroundStyle(WeiBeiTheme.ink)
        // Same opaque paper as notes/reader — clear background lets
        // isMovableByWindowBackground steal header drags as window moves.
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .topLeading) {
            AccessibilityFrameProbe(identifier: "stable-document-slot-agent")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if showsPaneHeader {
                LinearGradient(
                    colors: [
                        WeiBeiTheme.glassHighlight.opacity(0.18),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                .allowsHitTesting(false)
            } else {
                // Match notes: floating slip overlay only — no extra clear ZStack.
                ImmersiveHoverTitleView(
                    mark: "CHAT",
                    title: store.agentConversationSubtitle,
                    appearanceMode: store.appearanceMode,
                    actionsAlignedTrailing: true,
                    reorderRole: reorderRole
                ) {
                    agentSessionCatalogMenu
                }
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
            if usesWideChatLayout, measuredPaneWidth < 700 {
                measuredPaneWidth = max(measuredPaneWidth, 1100)
            }
        }
        .task(id: replySources) {
            await store.validateAgentReplySources(replySources)
        }
        .confirmationDialog(
            store.ui("删除这条对话？", "Delete this Chat?"),
            isPresented: Binding(
                get: { sessionPendingDeletion != nil },
                set: { if !$0 { sessionPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: sessionPendingDeletion
        ) { session in
            Button(store.ui("删除对话", "Delete Chat"), role: .destructive) {
                store.deleteStudySession(session.id)
                sessionPendingDeletion = nil
            }
            Button(store.ui("取消", "Cancel"), role: .cancel) {
                sessionPendingDeletion = nil
            }
        } message: { session in
            Text(sessionDeletionMessage(session))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stable-document-slot-agent")
        .accessibilityLabel(Text("agent chat pane"))
    }

    /// AppKit owns live frames. SwiftUI state receives only the final semantic width so
    /// the eager message tree is not invalidated for every divider pixel.
    private func applyMeasuredPaneWidth(_ width: CGFloat) {
        guard width > 1 else { return }
        if paneWidthRelay.isActive {
            paneWidthRelay.pendingWidth = width
            return
        }
        commitMeasuredPaneWidth(width)
    }

    private func beginPaneDividerDrag() {
        guard !paneWidthRelay.dividerDragActive else { return }
        paneWidthRelay.dividerDragActive = true
        if !isPaneWidthMotionActive {
            heldPaneLayoutWidth = agentPaneWidth
            isPaneWidthMotionActive = true
        }
    }

    private func endPaneDividerDrag() {
        guard paneWidthRelay.dividerDragActive else { return }
        paneWidthRelay.dividerDragActive = false
        guard !paneWidthRelay.structureTransitionActive else { return }
        finishPaneWidthMotion()
    }

    private func commitMeasuredPaneWidth(_ width: CGFloat) {
        if usesWideChatLayout {
            // PersistentPaneHost re-attach can briefly report the old strip width — do not keep it.
            if width < 520, measuredPaneWidth >= 700 {
                return
            }
        }
        guard abs(measuredPaneWidth - width) > 2 else { return }
        measuredPaneWidth = width
        if !usesWideChatLayout,
           store.isPaneVisible(.agent),
           width >= ContentRailMetrics.readableWidth {
            lastReadablePaneWidth = width
        }
    }

    private func beginPaneStructureTransition() {
        paneStructureTransitionSequence &+= 1
        paneWidthRelay.structureTransitionActive = true
        paneWidthRelay.pendingWidth = nil
        if !isPaneWidthMotionActive {
            heldPaneLayoutWidth = agentPaneWidth
            isPaneWidthMotionActive = true
        }
        if reduceMotion {
            paneWidthRelay.structureTransitionActive = false
            if !paneWidthRelay.dividerDragActive {
                finishPaneWidthMotion()
            }
            return
        }
        let sequence = paneStructureTransitionSequence
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.paneStructureTransitionDuration) {
            // AppKit's completion handler shares the same 0.24s deadline. One
            // additional main turn lets it land before the single final reflow.
            DispatchQueue.main.async {
                guard sequence == paneStructureTransitionSequence else { return }
                paneWidthRelay.structureTransitionActive = false
                if !paneWidthRelay.dividerDragActive {
                    finishPaneWidthMotion()
                }
            }
        }
    }

    private func finishPaneWidthMotion() {
        let finalWidth = paneWidthRelay.pendingWidth
        paneWidthRelay.pendingWidth = nil
        heldPaneLayoutWidth = nil
        isPaneWidthMotionActive = false
        // Closing ends at a collapsed resident host. Restore its last readable
        // seed after it is hidden so the next opening has no 2pt layout flash.
        if !store.isPaneVisible(.agent) {
            measuredPaneWidth = lastReadablePaneWidth
        } else if let finalWidth {
            commitMeasuredPaneWidth(finalWidth)
        }
    }

    private func agentMessageRow(
        message: AgentMessage,
        contentWidth: CGFloat,
        wide: Bool
    ) -> some View {
        let isUser = message.role == .user
        let wideFamilies: Set<RichAnswerCapabilityFamily> = [
            .quantityAndCoordinates,
            .processAndState,
            .timeAndSpace,
            .imageAndOverlay,
            .comparisonAndEvaluation,
        ]
        let needsWideCanvas = message.richAnswer?.scenes.contains {
            wideFamilies.contains($0.family)
        } == true

        // Native text rows: no per-message WKWebView height callbacks that thrash scroll.
        return agentReadingColumn(
            canvasWide: needsWideCanvas,
            alignment: isUser ? .trailing : .leading
        ) {
            AgentBubble(
                message: message,
                // Typography follows the real column width, not the layout enum —
                // a full-window chat tab is not .immersiveConversation but reads wide.
                isChatWideTypography: wide
                    || contentWidth >= AgentChatLayoutMetrics.wideTypographyMinContentWidth
            )
        }
        .id(message.id)
        .transition(WeiBeiTransition.message)
    }

    /// One centered reading column for messages, streaming, and loading.
    /// The parent proposal is the source of truth: it shrinks this flexible cap
    /// with the real pane instead of applying an offset derived from sampled width.
    private func agentReadingColumn<Content: View>(
        canvasWide: Bool = false,
        alignment: HorizontalAlignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let readingWidth = AgentChatLayoutMetrics.wideMaxWidth + (canvasWide ? 40 : 0)
        return content()
            .frame(maxWidth: readingWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var agentRailTurns: [AgentRailTurn] {
        var turns: [AgentRailTurn] = []
        for (index, message) in store.messages.enumerated() {
            switch message.role {
            case .user:
                turns.append(AgentRailTurn(
                    id: message.id,
                    startMessageID: message.id,
                    startIndex: index,
                    question: message.text,
                    answer: ""
                ))
            case .assistant:
                if turns.isEmpty {
                    turns.append(AgentRailTurn(
                        id: message.id,
                        startMessageID: message.id,
                        startIndex: index,
                        question: store.ui("对话回复", "Response"),
                        answer: message.text
                    ))
                } else if turns[turns.count - 1].answer.isEmpty {
                    turns[turns.count - 1].answer = message.text
                } else {
                    turns[turns.count - 1].answer += "\n\n" + message.text
                }
            }
        }
        return turns
    }

    private var agentRailItems: [ContentRailItem] {
        let turns = agentRailTurns
        return turns.enumerated().map { index, turn in
            ContentRailItem(
                id: "chat-turn-\(turn.id.uuidString)",
                position: turns.count > 1 ? CGFloat(index) / CGFloat(turns.count - 1) : 0,
                title: railText(turn.question, fallback: store.ui("第 \(index + 1) 轮对话", "Conversation \(index + 1)")),
                excerpt: railText(turn.answer, fallback: store.ui("等待回复", "Waiting for response")),
                metadata: store.ui("第 \(index + 1) / \(turns.count) 轮", "Turn \(index + 1) / \(turns.count)")
            )
        }
    }

    private func activateAgentRailItem(_ item: ContentRailItem, railOnly: Bool, proxy: ScrollViewProxy) {
        guard let turn = agentRailTurns.first(where: { "chat-turn-\($0.id.uuidString)" == item.id }) else { return }
        activeAgentRailID = item.id
        agentFollowsLatest = false
        // Folded turns must mount before scrollTo can find their row.
        revealAgentHistory(throughMessageID: turn.startMessageID)
        let navigate = {
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(turn.startMessageID, anchor: .center)
            }
        }
        if railOnly {
            store.requestPaneExpansion(.agent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: navigate)
        } else {
            navigate()
        }
    }

    private func updateAgentRailPosition(for messageID: UUID?) {
        guard let messageID,
              let visibleIndex = store.messages.firstIndex(where: { $0.id == messageID }) else { return }
        agentFollowsLatest = messageID == store.messages.last?.id
        if let turn = agentRailTurns.last(where: { $0.startIndex <= visibleIndex }) {
            activeAgentRailID = "chat-turn-\(turn.id.uuidString)"
        }
    }

    private func handleScrollMetrics(_ metrics: AgentScrollMetrics, proxy: ScrollViewProxy) {
        // Hysteresis: reveal well above the bottom, hide near it — a boolean
        // flip at 8pt deadband keeps SwiftUI updates off the scroll hot path.
        let shouldShow = metrics.distanceFromBottom > 160
        if shouldShow != showsJumpToLatest {
            withAnimation(WeiBeiMotion.reveal) {
                showsJumpToLatest = shouldShow
            }
        }
        if metrics.distanceFromBottom < 40 {
            agentFollowsLatest = true
        } else if metrics.distanceFromBottom > 160 {
            agentFollowsLatest = false
        }

        if isRevealingEarlierAgentHistory {
            if AgentHistoryRevealPolicy.shouldReleaseRevealLock(
                isUserScrolling: metrics.isUserScrolling
            ) {
                isRevealingEarlierAgentHistory = false
            }
            return
        }
        guard AgentHistoryRevealPolicy.shouldRevealEarlierPage(
            distanceFromTop: metrics.distanceFromTop,
            isUserScrolling: metrics.isUserScrolling,
            isScrollingTowardTop: metrics.isScrollingTowardTop,
            hiddenMessageCount: hiddenAgentHistoryCount,
            revealInFlight: isRevealingEarlierAgentHistory
        ) else { return }
        revealEarlierAgentHistory(proxy: proxy)
    }

    private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
        Button {
            agentFollowsLatest = true
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(Circle().fill(WeiBeiTheme.paperRaised))
                .overlay(Circle().stroke(WeiBeiTheme.hairline.opacity(0.6), lineWidth: 1))
                .shadow(color: WeiBeiTheme.ink.opacity(0.14), radius: 9, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.ui("回到最新消息", "Jump to latest"))
    }

    private func revealAgentHistory(throughMessageID messageID: UUID) {
        guard let index = store.messages.firstIndex(where: { $0.id == messageID }) else { return }
        let needed = store.messages.count - index
        if needed > agentVisibleMessageLimit {
            agentVisibleMessageLimit = needed
        }
    }

    private func revealEarlierAgentHistory(proxy: ScrollViewProxy) {
        guard hiddenAgentHistoryCount > 0, !isRevealingEarlierAgentHistory else { return }
        let anchorID = visibleAgentMessages.first?.id
        isRevealingEarlierAgentHistory = true
        agentFollowsLatest = false
        agentVisibleMessageLimit = AgentHistoryRevealPolicy.expandedVisibleLimit(
            currentLimit: agentVisibleMessageLimit,
            totalMessageCount: store.messages.count
        )
        // Newly mounted rows land above; re-anchor the reader's previous top row.
        if let anchorID {
            DispatchQueue.main.async {
                proxy.scrollTo(anchorID, anchor: .top)
            }
        } else {
            isRevealingEarlierAgentHistory = false
        }
    }

    private func agentHistoryRevealButton(proxy: ScrollViewProxy) -> some View {
        let revealCount = min(Self.agentHistoryPageSize, hiddenAgentHistoryCount)
        return Button {
            revealEarlierAgentHistory(proxy: proxy)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                Text(store.ui("查看更早的 \(revealCount) 条消息", "Show \(revealCount) earlier messages"))
                    .font(.system(size: 12, weight: .medium))
            }
                .foregroundStyle(isAgentHistoryRevealButtonHovered ? WeiBeiTheme.link : WeiBeiTheme.secondaryInk)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background {
                    Capsule()
                        .fill(WeiBeiTheme.paperInset.opacity(isAgentHistoryRevealButtonHovered ? 0.42 : 0.24))
                }
                .overlay {
                    Capsule()
                        .stroke(WeiBeiTheme.hairline.opacity(isAgentHistoryRevealButtonHovered ? 0.72 : 0.44), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isAgentHistoryRevealButtonHovered ? 1.015 : 1)
        .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: isAgentHistoryRevealButtonHovered)
        .onHover { isAgentHistoryRevealButtonHovered = $0 }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func railText(_ value: String, fallback: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: #"[`*_>#\[\]()]"#, with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? fallback : String(collapsed.prefix(180))
    }

    private var agentPrompt: String {
        store.agentInputPrompt
    }

    private func agentInputTray(wide: Bool) -> some View {
        let minHeight = AgentChatLayoutMetrics.composerHeight(wide: wide)
        let maxHeight = AgentChatLayoutMetrics.composerMaxHeight(wide: wide)
        let fontSize = AgentChatLayoutMetrics.composerFontSize(wide: wide)
        // ChatGPT-like: the tray shares the exact conversation paper — no
        // gradient strip, no glass seam, no divider. The rounded field alone
        // separates input from messages.
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: wide ? 8 : 8) {
                if store.hasSelectionAttachments {
                    AgentSelectionAttachmentPill()
                        .transition(WeiBeiTransition.floating)
                }

                AgentComposerField(
                    prompt: agentPrompt,
                    focused: $draftFocused,
                    font: .system(size: fontSize),
                    promptFont: .system(size: fontSize),
                    lineLimit: wide ? 1...10 : 1...6,
                    height: minHeight,
                    maxHeight: maxHeight,
                    sendButtonSize: wide ? 32 : 28,
                    trailingPadding: wide ? 48 : 40,
                    sendTrailing: wide ? 12 : 10,
                    sendBottom: wide ? 10 : 8,
                    horizontalPadding: wide ? 16 : 12,
                    verticalPadding: wide ? 12 : 8,
                    showsModelFooter: wide
                ) {
                    store.submitAgentDraft()
                }
            }
            .font(.system(size: fontSize))
            .frame(maxWidth: AgentChatLayoutMetrics.wideMaxWidth, alignment: .bottom)
            .padding(.top, wide ? 6 : 4)
            .padding(.bottom, wide ? 16 : 12)
            .frame(maxWidth: .infinity)
            .animation(WeiBeiMotion.reveal, value: store.agentDraft)
            .accessibilityIdentifier(wide ? "agent-input-tray-wide" : "agent-input-tray-compact")
        }
        .background(WeiBeiTheme.paper)
    }

    private var agentInputMaxWidth: CGFloat? {
        AgentChatLayoutMetrics.contentWidth(
            availableWidth: max(agentPaneWidth, 1),
            wide: usesWideChatLayout
        )
    }

    private var agentContentMaxWidth: CGFloat? {
        agentInputMaxWidth
    }

    /// Composer and rhythm follow the real column width, not the layout enum —
    /// a full-window chat tab deserves the same roomy composer as immersive.
    private var usesComfortableChatMetrics: Bool {
        usesWideChatLayout
            || (agentInputMaxWidth ?? 0) >= AgentChatLayoutMetrics.wideTypographyMinContentWidth
    }

    private var composerFieldHeight: CGFloat {
        AgentChatLayoutMetrics.composerHeight(wide: usesComfortableChatMetrics)
    }

    private var composerFontSize: CGFloat {
        AgentChatLayoutMetrics.composerFontSize(wide: usesComfortableChatMetrics)
    }

    private var agentScrollBottomInset: CGFloat {
        // Fixed inset only — tray GeometryReader preference → LazyVStack height feedback
        // re-entered sizeThatFits every scroll frame and froze the app.
        // Tray already sits outside the ScrollView (VStack), so keep this small;
        // large fixed insets stole message viewport height and made immersive feel tiny.
        hasVisibleRichAnswer
            ? (usesWideChatLayout ? 28 : 20)
            : (usesWideChatLayout ? 16 : 12)
    }

    private var hasVisibleRichAnswer: Bool {
        store.messages.contains { message in
            message.richAnswer?.mode == .rich && message.richAnswer?.scenes.isEmpty == false
        }
    }

    private var agentRailBottomInset: CGFloat {
        usesWideChatLayout ? 120 : 100
    }

    /// Compact catalog for immersive hover tab + pane header.
    private var agentSessionCatalogMenu: some View {
        Menu {
            sessionCatalogContent
        } label: {
            Label {
                Text(store.activeStudySessionScopeTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text(store.ui("对话目录", "Conversation catalog")))
        .help(store.ui("新建或切换对话", "Create or switch Chats"))
    }

    private var sessionMenu: some View {
        Menu {
            sessionCatalogContent
        } label: {
            Image(systemName: "list.bullet.rectangle")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
        .accessibilityLabel(Text(store.ui("学习会话", "Study Sessions")))
        .help(store.ui("新建或切换对话", "Create or switch Chats"))
    }

    @ViewBuilder
    private var sessionCatalogContent: some View {
        Button {
            store.createStudySession(courseID: nil)
        } label: {
            Label(store.ui("新建对话", "New Chat"), systemImage: "plus.bubble")
        }

        Divider()

        if let courseID = store.activeCourseID,
           let course = store.course(withID: courseID),
           !store.studySessions(in: courseID).isEmpty {
            Menu(store.ui("当前课程 · \(course.title)", "Current Course · \(course.title)")) {
                ForEach(store.studySessions(in: courseID).prefix(30)) { session in
                    sessionMenuButton(session)
                }
            }
        }

        if !store.historicalStudySessions.isEmpty {
            Section(store.ui("全部对话", "All Chats")) {
                ForEach(store.historicalStudySessions.prefix(30)) { session in
                    sessionMenuButton(session)
                }
            }
        }

        if let active = store.activeStudySession,
           !active.messages.isEmpty {
            Divider()
            Button(role: .destructive) {
                sessionPendingDeletion = active
            } label: {
                Label(store.ui("删除当前会话", "Delete Current Session"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func sessionMenuButton(_ session: StudySession) -> some View {
        Button {
            store.activateStudySession(
                session.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        } label: {
            if session.id == store.activeStudySessionID {
                Label(session.title, systemImage: "checkmark")
            } else if !session.relatedCourseIDs.isEmpty {
                Label(session.title, systemImage: "folder")
            } else {
                Text(session.title)
            }
        }
    }

    private func sessionDeletionMessage(_ session: StudySession) -> String {
        let courseNames = session.relatedCourseIDs.compactMap {
            store.course(withID: $0)?.title
        }
        guard !courseNames.isEmpty else {
            return store.ui(
                "消息和本地 Agent 运行记录都会删除。",
                "Messages and the local Agent run will be deleted."
            )
        }
        return store.ui(
            "这条对话也会从这些课程中消失：\(courseNames.joined(separator: "、"))。",
            "This Chat will also disappear from: \(courseNames.joined(separator: ", "))."
        )
    }

    private func scrollAgentToBottom(_ proxy: ScrollViewProxy) {
        guard agentFollowsLatest else { return }
        DispatchQueue.main.async {
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)
            }
        }
    }

}

private struct AgentPaneWidthKey: PreferenceKey {
    /// 0 = unmeasured. Must NOT default to 960: reduce used to max with 960 and
    /// multi-pane strips (e.g. 360pt) were forever treated as full-window wide,
    /// so messages/input centered off-canvas and "didn't adapt".
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 1 {
            value = next
        }
    }
}

private struct AgentSelectionAttachmentPill: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var pillHovering = false
    @State private var popoverHovering = false
    @State private var closeToken = UUID()

    var body: some View {
        if store.hasSelectionAttachments {
            HStack(spacing: 4) {
                // Popover anchor is only the label — keep the clear button outside so the first
                // click is not eaten by hover-popover dismissal.
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11, weight: .medium))
                    Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments"))
                        .font(.system(size: 12, weight: .medium))
                }
                .contentShape(Rectangle())
                .onHover { value in
                    setPillHovering(value)
                }
                .popover(isPresented: popoverPresented, arrowEdge: .bottom) { popoverContent }

                Button(action: clearAllAttachments) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 18))
                .accessibilityLabel(Text(store.ui("清空已选文本片段", "Clear selected text fragments")))
                .help(store.ui("清空已选文本片段", "Clear selected text fragments"))
            }
            .foregroundStyle(pillHovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 28)
            .background(WeiBeiTheme.paperRaised.opacity(pillHovering ? 0.72 : 0.54))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(pillHovering ? 0.68 : 0.38), lineWidth: 1)
            }
            .accessibilityLabel(Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments")))
            .help(store.ui("悬停查看选区", "Hover to preview selections"))
        }
    }

    private func clearAllAttachments() {
        closeToken = UUID()
        pillHovering = false
        popoverHovering = false
        store.clearSelectionAttachments()
    }

    private var popoverPresented: Binding<Bool> {
        Binding(
            get: { pillHovering || popoverHovering },
            set: { presented in
                if !presented {
                    pillHovering = false
                    popoverHovering = false
                }
            }
        )
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer()
                Text(store.ui("发问时会作为上下文", "Used as context when asking"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Button(store.ui("清空", "Clear")) {
                    clearAllAttachments()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .help(store.ui("清空全部选区片段", "Clear all selected fragments"))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(store.selectionAttachments.enumerated()), id: \.element.id) { index, selection in
                        selectionAttachmentRow(index: index, selection: selection)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(WeiBeiTheme.paperRaised)
        .onHover { value in
            setPopoverHovering(value)
        }
    }

    private func selectionAttachmentRow(index: Int, selection: SelectionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(store.ui("片段 \(index + 1)", "Fragment \(index + 1)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(selection.ownerTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 8)
                Button {
                    let shouldClose = store.selectionAttachments.count <= 1
                    closeToken = UUID()
                    store.removeSelectionAttachment(id: selection.id)
                    if shouldClose {
                        pillHovering = false
                        popoverHovering = false
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 20))
                .accessibilityLabel(Text(store.ui("移除片段 \(index + 1)", "Remove fragment \(index + 1)")))
                .help(store.ui("移除这个选区片段", "Remove this selected fragment"))
            }

            Text(selection.text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .lineLimit(5)
                .foregroundStyle(WeiBeiTheme.ink)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 1)
        }
        .padding(9)
        .background(WeiBeiTheme.paperInset.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(0.36), lineWidth: 1)
        }
    }

    private func setPillHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            withAnimation(WeiBeiMotion.hover) {
                pillHovering = true
            }
        } else {
            schedulePopoverClose()
        }
    }

    private func setPopoverHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            popoverHovering = true
        } else {
            popoverHovering = false
            schedulePopoverClose()
        }
    }

    private func schedulePopoverClose() {
        let token = UUID()
        closeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard closeToken == token, !popoverHovering else { return }
            withAnimation(WeiBeiMotion.hover) {
                pillHovering = false
                popoverHovering = false
            }
        }
    }
}

private struct FloatingSelectionPreview: View {
    @EnvironmentObject private var store: WorkspaceStore
    let text: String
    @State private var labelHovering = false
    @State private var popoverHovering = false
    @State private var closeToken = UUID()

    var body: some View {
        Button {
            closeToken = UUID()
            labelHovering = true
        } label: {
            Text(cleanedText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(labelHovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: setLabelHovering)
        .popover(isPresented: popoverPresented, arrowEdge: .bottom) {
            ScrollView(showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 240)
            .padding(14)
            .frame(width: 320, alignment: .leading)
            .background(WeiBeiTheme.paperRaised)
            .onHover(perform: setPopoverHovering)
        }
        .accessibilityLabel(Text(store.ui("查看完整原文", "View full passage")))
        .help(store.ui("查看完整原文", "View full passage"))
    }

    private var cleanedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private var popoverPresented: Binding<Bool> {
        Binding(
            get: { labelHovering || popoverHovering },
            set: { presented in
                if !presented {
                    labelHovering = false
                    popoverHovering = false
                }
            }
        )
    }

    private func setLabelHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            withAnimation(WeiBeiMotion.hover) { labelHovering = true }
        } else {
            schedulePopoverClose()
        }
    }

    private func setPopoverHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            popoverHovering = true
        } else {
            popoverHovering = false
            schedulePopoverClose()
        }
    }

    private func schedulePopoverClose() {
        let token = UUID()
        closeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard closeToken == token, !popoverHovering else { return }
            withAnimation(WeiBeiMotion.hover) {
                labelHovering = false
                popoverHovering = false
            }
        }
    }
}

struct FloatingSelectionAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var expanded: Bool
    var routesToConversation = false
    @State private var dragOffset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    private let panelWidth = CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2)
    @FocusState private var draftFocused: Bool
    @Namespace private var floatingNamespace

    var body: some View {
        Group {
            if showsExpandedBody {
                expandedBody
            } else {
                promptBody
            }
        }
        .matchedGeometryEffect(id: "selection-agent-surface", in: floatingNamespace)
        .transition(WeiBeiTransition.floating)
        .modifier(SelectionFloatChrome(expanded: showsExpandedBody))
        .scaleEffect(showsExpandedBody ? 1 : 0.985)
        .animation(WeiBeiMotion.panel, value: expanded)
        .animation(WeiBeiMotion.panel, value: store.pinnedFloatingAgent)
        .animation(WeiBeiMotion.panel, value: store.isAgentRunningInActiveChat)
        .offset(
            x: dragOffset.width + settledOffset.width,
            y: dragOffset.height + settledOffset.height + floatingFeedGrowthOffset
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    withAnimation(WeiBeiMotion.panel) {
                        settledOffset = CGSize(
                            width: settledOffset.width + value.translation.width,
                            height: settledOffset.height + value.translation.height
                        )
                        dragOffset = .zero
                        // Dragging repositions; pin is only set by the pin control.
                    }
                }
        )
        .onChange(of: store.selectionContext) { previous, next in
            guard !store.pinnedFloatingAgent, !store.isAgentRunningInActiveChat else { return }
            let sameContent = previous?.text == next?.text
                && previous?.source == next?.source
                && previous?.ownerTitle == next?.ownerTitle
                && previous?.isEditable == next?.isEditable
            guard !sameContent else { return }
            // Reopen uses SelectionContext.id == thread.id — expand beside the mark.
            let isThreadReopen = next.map { store.activeSelectionAskThreadID == $0.id } ?? false
            if isThreadReopen, store.keepFloatingSelectionForAnswer {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
                return
            }
            // Live reselection → capsule only.
            withAnimation(WeiBeiMotion.panel) {
                expanded = false
                store.keepFloatingSelectionForAnswer = false
                store.activeSelectionAskThreadID = nil
                dragOffset = .zero
                settledOffset = .zero
            }
        }
        .onChange(of: store.keepFloatingSelectionForAnswer) { _, keep in
            if keep {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
            }
        }
        .onChange(of: store.activeSelectionAskThreadID) { _, id in
            if id != nil, store.keepFloatingSelectionForAnswer {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
            }
        }
        .onChange(of: store.isAgentRunningInActiveChat) { _, asking in
            if asking {
                withAnimation(WeiBeiMotion.panel) { expanded = true }
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
            if store.pinnedFloatingAgent || store.isAgentRunningInActiveChat || store.keepFloatingSelectionForAnswer {
                expanded = true
            }
        }
        .onExitCommand {
            closeFloatingAgent()
        }
    }

    private var showsExpandedBody: Bool {
        // Capsule for bare selection; expand for 问 / pin / stream / 红线回访(keepOpen).
        expanded || store.pinnedFloatingAgent || store.isAgentRunningInActiveChat || store.keepFloatingSelectionForAnswer
    }

    private var promptBody: some View {
        HStack(spacing: 0) {
            Button(store.ui("问", "Ask")) {
                openExpandedComposer()
            }
            .foregroundStyle(WeiBeiTheme.link)
            .accessibilityLabel(Text(store.ui("就这段提问", "Ask about this passage")))
            .help(store.ui("就这段提问", "Ask about this passage"))

            if store.canOpenSelectedSourceReference {
                promptSeparator
                Button(store.ui("来源", "Source")) {
                    openSourceReference()
                }
            }

            if store.selectionContext != nil {
                promptSeparator
                Button(store.ui("摘录", "Excerpt")) {
                    store.appendSelectionToNote()
                    closeFloatingAgent()
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .fixedSize()
    }

    private var promptSeparator: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.78))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 8)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let selection = store.selectionContext?.text, !selection.isEmpty {
                    FloatingSelectionPreview(text: selection)
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(WeiBeiMotion.micro) { togglePinnedFloatingAgent() }
                } label: {
                    Image(systemName: store.pinnedFloatingAgent ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.pinnedFloatingAgent ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(store.pinnedFloatingAgent
                      ? store.ui("取消固定", "Unpin")
                      : store.ui("固定在当前位置", "Keep in place"))
                .accessibilityLabel(Text(store.pinnedFloatingAgent ? store.ui("取消固定", "Unpin") : store.ui("固定在当前位置", "Keep in place")))

                Button {
                    closeFloatingAgent()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(store.ui("关闭", "Close"))
                .accessibilityLabel(Text(store.ui("关闭", "Close")))
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 7)

            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if showsFloatingFeed {
                ScrollView(showsIndicators: false) {
                    // Same order as immersive chat: messages → streaming → thinking.
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleFloatingMessages) { message in
                            let displayText = store.agentDisplayText(for: message)
                            if message.completionState == .generating
                                && displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                AgentThinkingIndicator()
                                    .id(message.id)
                                    .padding(.vertical, 4)
                            } else {
                                FloatingSelectionMessageBubble(
                                    message: message,
                                    text: floatingText(for: message),
                                    isError: WorkspaceStore.isAgentFailureMessage(message.text)
                                )
                            }
                        }

                        if store.isAgentRunningInActiveChat
                            && !store.hasPersistedGeneratingAgentReply
                            && !store.agentStreamingText.isEmpty {
                            AgentStreamingResponse(
                                text: store.agentStreamingText,
                                isChatWideTypography: false,
                                compact: true
                            )
                            .id("selection-float-streaming")
                        }

                        if store.isAgentRunningInActiveChat
                            && !store.hasPersistedGeneratingAgentReply
                            && store.agentStreamingText.isEmpty {
                            AgentThinkingIndicator()
                                .id("selection-float-thinking")
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .environment(\.agentChatLayoutWidth, max(panelWidth - 28, 1))
                }
                .frame(height: floatingFeedHeight)
            }

            AgentComposerField(
                prompt: showsFloatingFeed
                    ? store.ui("再问一点…", "Ask a follow-up…")
                    : store.ui("问点什么…", "Ask anything…"),
                focused: $draftFocused,
                font: .system(size: 13.5),
                promptFont: .system(size: 13.5),
                lineLimit: 1...5,
                height: 48,
                sendButtonSize: 26,
                trailingPadding: 36,
                sendTrailing: 8,
                sendBottom: 6,
                horizontalPadding: 2,
                verticalPadding: 8,
                showsChrome: false
            ) {
                sendDraft()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .frame(width: panelWidth, alignment: .leading)
        .onAppear {
            draftFocused = true
        }
    }

    private var visibleFloatingMessages: [AgentMessage] {
        // Strict isolation: only messages belonging to the active selection-ask thread.
        // Never fall back to the global conversation feed.
        guard let threadID = store.activeSelectionAskThreadID,
              let thread = store.selectionAskThreads.first(where: { $0.id == threadID }) else {
            return []
        }
        let idSet = Set(thread.messageIDs)
        return store.messages.filter { idSet.contains($0.id) }
    }

    private var canPolishNoteSelection: Bool {
        store.selectionContext?.isNoteSelection == true
    }

    private var showsFloatingFeed: Bool {
        !visibleFloatingMessages.isEmpty || store.isAgentRunningInActiveChat
    }

    private var floatingFeedHeight: CGFloat {
        if store.isAgentRunningInActiveChat { return 180 }
        switch visibleFloatingMessages.count {
        case 0, 1: return 160
        default: return 180
        }
    }

    private var floatingFeedGrowthOffset: CGFloat {
        showsFloatingFeed ? floatingFeedHeight / 2 : 0
    }

    private func floatingText(for message: AgentMessage) -> String {
        store.agentDisplayText(for: message)
    }

    private func togglePinnedFloatingAgent() {
        let next = !store.pinnedFloatingAgent
        store.pinnedFloatingAgent = next
        if next {
            store.agentSurface = .selectionFloat
            store.keepFloatingSelectionForAnswer = true
        } else {
            // Unpin must not dismiss — keepOpen holds the float without a drag anchor.
            store.keepFloatingSelectionForAnswer = true
            store.agentSurface = .selectionFloat
            expanded = true
        }
    }

    private func openExpandedComposer() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.keepFloatingSelectionForAnswer = true
            // Do not invent a prompt or auto-send — only open a normal composer.
            store.askSelection()
            draftFocused = true
        }
    }

    private func openSourceReference() {
        store.openSelectedSourceReference()
    }

    private func sendDraft() {
        guard !store.isStoppingAgent,
              !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.keepFloatingSelectionForAnswer = true
            if let selection = store.selectionContext {
                store.addSelectionAttachment(selection)
                let thread = store.beginOrReuseSelectionAskThread(for: selection)
                store.activeSelectionAskThreadID = thread.id
            }
        }
        store.submitAgentDraft()
    }

    private func closeFloatingAgent() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = false
            dragOffset = .zero
            settledOffset = .zero
            store.dismissFloatingSelectionAgent()
        }
    }
}

/// Paper float chrome: one quiet surface for both compact and expanded states.
private struct SelectionFloatChrome: ViewModifier {
    var expanded: Bool

    func body(content: Content) -> some View {
        content
            .foregroundColor(WeiBeiTheme.ink)
            .background {
                RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous)
                    .fill(WeiBeiTheme.paperRaised.opacity(0.98))
            }
            .clipShape(RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous)
                    .strokeBorder(
                        WeiBeiTheme.hairline.opacity(0.65),
                        lineWidth: 1
                    )
            }
            .shadow(color: WeiBeiTheme.ink.opacity(0.06), radius: 8, y: 3)
    }
}

private struct FloatingSelectionMessageBubble: View {
    var message: AgentMessage
    var text: String
    var isError = false

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isError {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            } else {
                finalizedMessage
            }
        }
        .padding(.vertical, 3)
    }

    private var finalizedMessage: some View {
        AgentMessageMarkdownText(
            text: text,
            rendersRichMarkdown: !isUser,
            compact: true,
            isChatWideTypography: false,
            usesFinalizedKaTeX: !isUser,
            messageID: message.id,
            keepsMarkdownSurfaceMounted: !isUser && !isError,
            isStreaming: message.completionState == .generating
        )
    }
}

private struct AgentBubble: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var message: AgentMessage
    var isChatWideTypography = false
    @State private var hovering = false
    @State private var copiedMessage = false

    var body: some View {
        Group {
            if isUser {
                userTurn
            } else {
                assistantTurn
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !isUser {
                messageActionBar
                    .offset(x: 16, y: 16)
            }
        }
        .onHover { hovering in
            guard !isUser else { return }
            withAnimation(WeiBeiMotion.hover) {
                self.hovering = hovering
            }
        }
        .task(id: copiedMessage) {
            guard copiedMessage else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copiedMessage = false
        }
    }

    private var messageActionBar: some View {
        HStack(spacing: 5) {
            Button {
                copyMessage()
            } label: {
                Image(systemName: copiedMessage ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(copiedMessage ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.ui(copiedMessage ? "已复制" : "复制消息", copiedMessage ? "Copied" : "Copy message"))
            .accessibilityLabel(store.ui(copiedMessage ? "已复制" : "复制消息", copiedMessage ? "Copied" : "Copy message"))

            if message.id == store.lastRegeneratableAgentReplyID {
                Button {
                    store.regenerateLastAssistantReply()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.ui("重新生成最后一条回答", "Regenerate last response"))
                .accessibilityLabel(store.ui("重新生成最后一条回答", "Regenerate last response"))
            }
        }
        .opacity(hovering ? 1 : 0)
        .offset(y: hovering ? 0 : -1)
        .allowsHitTesting(hovering)
        .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: hovering)
    }

    private func copyMessage() {
        let markdown = isUser
            ? message.text
            : AgentCitationParser.parse(store.agentDisplayText(for: message)).displayText
        guard !markdown.isEmpty else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(markdown, forType: .string) {
            copiedMessage = true
        }
    }

    @ViewBuilder
    private var userTurn: some View {
        // Quiet paper chip on the right edge: role is encoded by position + surface,
        // so no "你" label, no accent rail, no messenger chrome.
        // Long material/section source strings are intentionally not shown — they clutter
        // the turn without helping the learner (navigation lives in tags / reader).
        VStack(alignment: .trailing, spacing: 4) {
            AgentMessageMarkdownText(
                text: message.text,
                rendersRichMarkdown: false
            )
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(userBubbleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(userBubbleStroke, lineWidth: 1)
                    }
                    .shadow(
                        color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.0 : (hovering ? 0.06 : 0.04)),
                        radius: hovering ? 6 : 4,
                        y: hovering ? 2 : 1.2
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .onTapGesture {
                copyMessage()
            }
            .help(store.ui(copiedMessage ? "已复制" : "点击复制消息", copiedMessage ? "Copied" : "Click to copy message"))
            .accessibilityLabel(message.text)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(store.ui("复制消息", "Copy message"))) {
                copyMessage()
            }
            .weibeiHoverLift(active: hovering || copiedMessage, amount: 0.6)
            .onHover { value in
                withAnimation(WeiBeiMotion.hover) {
                    hovering = value
                }
            }
            .frame(maxWidth: 520, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var userBubbleFill: Color {
        // Same paper family as chips/panels: a slightly raised slip of paper, not a tinted chat blob.
        store.appearanceMode.isDark
            ? WeiBeiTheme.paperRaised.opacity(hovering ? 0.58 : 0.46)
            : WeiBeiTheme.paperRaised.opacity(hovering ? 1.0 : 0.96)
    }

    private var userBubbleStroke: Color {
        if copiedMessage {
            return WeiBeiTheme.cinnabar.opacity(0.52)
        }
        return store.appearanceMode.isDark
            ? WeiBeiTheme.hairline.opacity(hovering ? 0.58 : 0.42)
            : WeiBeiTheme.hairline.opacity(hovering ? 0.52 : 0.38)
    }

    @ViewBuilder
    private var assistantTurn: some View {
        regularMessageContent
            .padding(.vertical, 10)
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private var regularMessageContent: some View {
        let answerText = store.agentDisplayText(for: message)
        let citationParse = AgentCitationParser.parse(answerText)
        let availableSources = message.sources.filter {
            store.canOpenAgentReplySource($0)
        }
        let legacyCitations = citationParse.citations.filter { citation in
            switch citation.kind {
            case .material, .note, .selection:
                return false
            case .learningRecord, .learningMemory, .session:
                return true
            }
        }
        let displayedStreamingText = store.agentReplyDisplayedStreamingText(message)
        return VStack(alignment: .leading, spacing: 8) {
            messageMetadata

            if message.completionState == .generating
                && answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AgentThinkingIndicator()
            } else if let richAnswer = message.richAnswer,
               richAnswer.mode == .rich,
               !richAnswer.scenes.isEmpty,
               !displayedStreamingText {
                richAnswerFlow(richAnswer)
                if !availableSources.isEmpty {
                    AgentReplySourceTagRow(sources: availableSources) { source in
                        activateSource(source)
                    }
                }
            } else {
                // One surface owns the answer from its first rendered token through
                // completion. State changes may freeze/cache it, but never replace it.
                AgentMessageMarkdownText(
                    text: citationParse.displayText,
                    rendersRichMarkdown: true,
                    isChatWideTypography: isChatWideTypography,
                    usesFinalizedKaTeX: !isFailureMessage,
                    messageID: message.id,
                    keepsMarkdownSurfaceMounted: !isFailureMessage,
                    isStreaming: message.completionState == .generating
                )
                if let richAnswer = message.richAnswer,
                   richAnswer.mode == .rich,
                   !richAnswer.scenes.isEmpty {
                    richAnswerSceneFlow(richAnswer)
                }
                if !availableSources.isEmpty {
                    AgentReplySourceTagRow(sources: availableSources) { source in
                        activateSource(source)
                    }
                }
            }

            if !legacyCitations.isEmpty {
                AgentCitationTagRow(citations: legacyCitations) { citation in
                    activateCitation(citation)
                }
            }

            if !message.actions.isEmpty {
                ForEach(message.actions) { action in
                    AgentReplyActionCard(
                        messageID: message.id,
                        action: action
                    )
                }
            }

            if let memoryUpdate = message.memoryUpdate,
               !memoryUpdate.memoryIDs.isEmpty {
                AgentReplyMemoryUpdateTag(
                    message: message,
                    update: memoryUpdate
                )
                .transition(WeiBeiTransition.floating)
            }

            if message.completionState == .interrupted && !isFailureMessage {
                HStack(spacing: 6) {
                    Text(store.ui("回答已中断，已保留现有内容", "Response interrupted; existing content was kept"))
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    if store.canRetryAgentRequest(
                        question: message.retryQuestion,
                        failureKind: message.failureKind
                    ), let question = message.retryQuestion {
                        Button(store.ui("重试", "Retry")) {
                            store.retryAgentRequest(
                                question,
                                targetCourseID: message.origin?.courseID
                            )
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                }
                .padding(.top, 2)
            } else if isFailureMessage {
                HStack(spacing: 6) {
                    if store.canRetryAgentRequest(
                        question: message.retryQuestion,
                        failureKind: message.failureKind
                    ), let question = message.retryQuestion {
                        Button(store.ui("重试", "Retry")) {
                            store.retryAgentRequest(
                                question,
                                targetCourseID: message.origin?.courseID
                            )
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                    if let question = message.retryQuestion, !question.isEmpty {
                        Button(store.ui("回填问题", "Restore question")) {
                            store.agentDraft = question
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            } else if message.id == store.lastUsableAgentAnswerID {
                HStack(spacing: 6) {
                    if store.selectionContext != nil {
                        Button(store.ui("摘录", "Excerpt")) {
                            store.appendSelectionToNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换", "Replace")) {
                            store.replaceSelectionWithLastAgentAnswer()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
        }
        .animation(reduceMotion ? nil : WeiBeiMotion.reveal, value: message.memoryUpdate)
    }

    private func activateSource(_ source: AgentReplySource) {
        withAnimation(WeiBeiMotion.panel) {
            _ = store.openAgentReplySource(source)
        }
    }

    @ViewBuilder
    private func richAnswerFlow(_ presentation: RichAnswerPresentation) -> some View {
        ForEach(Array(presentation.resolvedParts.enumerated()), id: \.offset) { index, part in
            switch part.kind {
            case .narrative:
                if let text = part.text, !text.isEmpty {
                    RichAnswerNarrativeText(
                        text: AgentCitationParser.parse(text).displayText
                    )
                        .frame(
                            // Same Codex-like column as chat text in every layout.
                            maxWidth: AgentChatLayoutMetrics.wideMaxWidth,
                            alignment: .leading
                        )
                }
            case .scene:
                if let sceneID = part.sceneID,
                   let scopedPresentation = scopedRichAnswer(presentation, sceneID: sceneID) {
                    RichAnswerHost(
                        presentation: scopedPresentation,
                        onOpenEvidence: openRichAnswerEvidence,
                        onOpenAsset: openRichAnswerAsset,
                        assetPreview: richAnswerAssetPreview,
                        onAction: submitRichAnswerAction
                    )
                    .id("rich-answer-\(message.id.uuidString)-\(sceneID)-\(index)")
                    .frame(
                        // Same Codex-like column as chat text in every layout.
                        maxWidth: AgentChatLayoutMetrics.wideMaxWidth,
                        alignment: .leading
                    )
                }
            }
        }
    }

    private func richAnswerSceneFlow(_ presentation: RichAnswerPresentation) -> some View {
        var scenesOnly = presentation
        scenesOnly.parts = presentation.resolvedParts.filter { $0.kind == .scene }
        return richAnswerFlow(scenesOnly)
    }

    private func scopedRichAnswer(
        _ presentation: RichAnswerPresentation,
        sceneID: String
    ) -> RichAnswerPresentation? {
        guard let scene = presentation.scenes.first(where: { $0.id == sceneID }) else { return nil }
        var scoped = presentation
        scoped.scenes = [scene]
        scoped.parts = nil
        let evidenceIDs = Set(scene.evidenceIDs)
        let openableSourceLabels = Set(message.sources.compactMap { source in
            store.canOpenAgentReplySource(source) ? source.label : nil
        })
        scoped.evidenceLedger = presentation.evidenceLedger.filter {
            evidenceIDs.contains($0.id) && openableSourceLabels.contains($0.sourceLabel)
        }
        return scoped
    }

    private func submitRichAnswerAction(_ prompt: String) {
        guard !store.isStoppingAgent else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.agentDraft = trimmed
        store.submitAgentDraft()
    }

    private var messageMetadata: some View {
        HStack(spacing: 6) {
            Text("WeiBei")
                .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
            if let backend = message.backend {
                Text(backendLabel(backend))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            if message.completionState == .generating,
               let activity = store.agentActivityText {
                Text(activity)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(0.82))
                    .lineLimit(1)
            }
            // Do not render message.source here — long "课程 HTML，章节标识…" strings
            // add noise; materials / learning context use citation tags instead.
            Spacer(minLength: 0)
        }
    }

    private func activateCitation(_ citation: AgentCitation) {
        switch citation.kind {
        case .material:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "material", value: citation.value)
            }
        case .note:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "note", value: citation.value)
            }
        case .selection:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "selection", value: citation.value)
            }
        case .learningRecord:
            withAnimation(WeiBeiMotion.panel) {
                store.resumePreviousStudy()
            }
        case .learningMemory:
            withAnimation(WeiBeiMotion.panel) {
                store.presentCourseWorkspace(.sessions)
            }
        case .session:
            break
        }
    }

    private func openRichAnswerEvidence(_ evidence: RichAnswerEvidence) {
        if let source = message.sources.first(where: {
            $0.label == evidence.sourceLabel
                && store.canOpenAgentReplySource($0)
        }) {
            _ = store.openAgentReplySource(source)
        }
    }

    private func openRichAnswerAsset(_ assetID: String) {
        withAnimation(WeiBeiMotion.panel) {
            store.select(itemID: assetID)
        }
    }

    private func richAnswerAssetPreview(_ assetID: String) -> NSImage? {
        guard let item = store.item(withID: assetID), let url = item.url else { return nil }
        if item.kind == .pdf,
           let page = PDFDocument(url: url)?.page(at: 0) {
            return page.thumbnail(of: NSSize(width: 1200, height: 1500), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var isFailureMessage: Bool {
        message.role == .assistant && WorkspaceStore.isAgentFailureMessage(message.text)
    }

    private func backendLabel(_ backend: StudyAgentBackend) -> String {
        switch backend {
        case .pi: return "PI"
        case .openAI: return "API"
        case .offline: return store.ui("离线", "Offline")
        }
    }
}

private struct RichAnswerNarrativeText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case let .heading(level):
                    Text(attributed(block.text))
                        .font(.system(size: level <= 2 ? 21 : 17, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .paragraph:
                    Text(attributed(block.text))
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(WeiBeiTheme.cinnabar)
                        Text(attributed(block.text))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(WeiBeiTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .quote:
                    Text(attributed(block.text))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(WeiBeiTheme.hairline.opacity(0.72))
                                .frame(width: 1)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(Block(kind: .paragraph, text: paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if isStandaloneSourceReference(line) {
                flushParagraph()
                continue
            }
            let headingMarkers = line.prefix { $0 == "#" }.count
            if headingMarkers > 0, headingMarkers <= 6, line.dropFirst(headingMarkers).first == " " {
                flushParagraph()
                result.append(
                    Block(
                        kind: .heading(level: headingMarkers),
                        text: String(line.dropFirst(headingMarkers)).trimmingCharacters(in: .whitespaces)
                    )
                )
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                result.append(Block(kind: .bullet, text: String(line.dropFirst(2))))
                continue
            }
            if line.hasPrefix("> ") {
                flushParagraph()
                result.append(Block(kind: .quote, text: String(line.dropFirst(2))))
                continue
            }
            paragraphLines.append(line)
        }
        flushParagraph()
        return result
    }

    private func isStandaloneSourceReference(_ line: String) -> Bool {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return false }
        return ["[材料：", "[笔记：", "[选区："].contains { line.hasPrefix($0) }
    }

    private func attributed(_ value: String) -> AttributedString {
        let displayValue = RichAnswerDisplayText.normalizedInlineMath(value)
        return (try? AttributedString(markdown: displayValue)) ?? AttributedString(displayValue)
    }

    private struct Block {
        enum Kind {
            case heading(level: Int)
            case paragraph
            case bullet
            case quote
        }

        let kind: Kind
        let text: String
    }
}

private struct AgentReplyMemoryUpdateTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: AgentMessage
    let update: AgentReplyMemoryUpdate
    @State private var expanded = false

    private var scope: LearningMemoryScope? {
        guard let origin = message.origin else { return nil }
        return origin.courseID.map(LearningMemoryScope.course) ?? .global
    }

    private var revisions: [LearningMemoryRevisionRecord]? {
        guard let scope else { return nil }
        return update.revisions(
            for: message.id,
            in: store.learningMemoryEntries(in: scope)
        )
    }

    private var canOpenAll: Bool {
        guard let courseID = message.origin?.courseID else { return false }
        return store.course(withID: courseID) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : WeiBeiMotion.micro) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .accessibilityHidden(true)
                    Text(store.ui(
                        "已更新学习记忆 · \(update.memoryIDs.count) 项",
                        "Learning memory updated · \(update.memoryIDs.count)"
                    ))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background {
                    Capsule()
                        .fill(WeiBeiTheme.cinnabarSoft.opacity(0.34))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(WeiBeiTheme.cinnabar.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(store.ui(
                expanded ? "已展开" : "已收起",
                expanded ? "Expanded" : "Collapsed"
            )))
            .accessibilityIdentifier("agent-memory-update-tag")

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    if let revisions {
                        ForEach(revisions) { revision in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text(store.learningMemoryKindLabel(revision.kind))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(WeiBeiTheme.cinnabar)
                                    .fixedSize()
                                Text(revision.text)
                                    .font(.caption)
                                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                                    .lineLimit(2)
                            }
                        }
                    } else {
                        Text(update.summary)
                            .font(.caption)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if canOpenAll {
                        Button(store.ui("查看全部", "View all")) {
                            guard let courseID = message.origin?.courseID else { return }
                            store.presentCourseWorkspace(.sessions, courseID: courseID)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                        .accessibilityIdentifier("agent-memory-update-view-all")
                    }
                }
                .padding(.leading, 9)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(WeiBeiTheme.cinnabar.opacity(0.28))
                        .frame(width: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Agent citation tags (materials / learning / selection)

/// Bracket citations Pi emits in answers, e.g. `[材料：…]`, `[学习记录：上次位置]`.
private enum AgentCitationKind: String, Equatable {
    case material
    case note
    case selection
    case learningRecord
    case learningMemory
    case session

    var systemImage: String {
        switch self {
        case .material: return "doc.text"
        case .note: return "note.text"
        case .selection: return "text.quote"
        case .learningRecord: return "bookmark"
        case .learningMemory: return "brain.head.profile"
        case .session: return "bubble.left.and.bubble.right"
        }
    }

    func shortLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .material: return language.text("材料", "Material")
        case .note: return language.text("笔记", "Note")
        case .selection: return language.text("选区", "Selection")
        case .learningRecord: return language.text("学习记录", "Study record")
        case .learningMemory: return language.text("学习记忆", "Memory")
        case .session: return language.text("会话", "Session")
        }
    }
}

private struct AgentCitation: Identifiable, Equatable {
    let id: String
    let kind: AgentCitationKind
    let raw: String
    let value: String

    var displayTitle: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.rawValue : trimmed
    }
}

private struct AgentReplyActionCard: View {
    @EnvironmentObject private var store: WorkspaceStore
    let messageID: UUID
    let action: AgentReplyAction
    private let headingPrefix: String
    @State private var title: String
    @State private var bodyText: String
    @State private var isWorking = false

    init(messageID: UUID, action: AgentReplyAction) {
        self.messageID = messageID
        self.action = action
        let draft = Self.noteDraft(from: action.proposedMarkdown ?? "")
        headingPrefix = draft.headingPrefix
        _title = State(initialValue: draft.title)
        _bodyText = State(initialValue: draft.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch action.state {
            case .pending, .failed:
                editableContent
            case .executed:
                completedContent
            case .cancelled:
                cancelledContent
            }
        }
        .padding(12)
        .frame(
            maxWidth: action.state == .pending || action.state == .failed ? 600 : nil,
            alignment: .leading
        )
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(WeiBeiTheme.paperRaised.opacity(0.82))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(WeiBeiTheme.hairline.opacity(0.58), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var editableContent: some View {
        if action.kind == .writeNote {
            Text(store.ui("建议写入内容：", "Suggested note content:"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)

            if let target = store.agentReplyActionTargetTitle(action) {
                Label(target, systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            TextField(store.ui("笔记小标题", "Note heading"), text: $title)
                .textFieldStyle(.plain)
                .weibeiInputSurface(height: 32)

            TextEditor(text: $bodyText)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .weibeiInputSurface(height: 104, horizontalPadding: 6)
        } else {
            Text(store.ui("建议建立关系：", "Suggested relation:"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    relationNoteLabel
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    relationSourceLabel
                }
                VStack(alignment: .leading, spacing: 6) {
                    relationNoteLabel
                    Image(systemName: "arrow.up.and.down")
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    relationSourceLabel
                }
            }
        }

        if let failure = action.failureMessage, !failure.isEmpty {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !action.evidence.isEmpty {
            Text(action.evidence.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .lineLimit(2)
        }

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { actionButtons }
            VStack(alignment: .leading, spacing: 6) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(action.state == .failed
            ? store.ui("重试", "Retry")
            : action.kind == .writeNote
                ? store.ui("写入笔记", "Write Note")
                : store.ui("建立关系", "Create Relation")) {
            performConfirmation()
        }
        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        .disabled(isWorking)

        if action.state == .failed,
           action.resultContentDigest != nil || action.createdRelationID != nil {
            Button(store.ui("撤销", "Undo")) {
                performUndo()
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
            .disabled(isWorking)
        } else {
            Button(store.ui("取消", "Cancel")) {
                store.cancelAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id
                )
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
            .disabled(isWorking)
        }
    }

    private var completedContent: some View {
        HStack(spacing: 8) {
            Label(
                action.kind == .writeNote
                    ? store.ui(
                        "已写入 · \(actionIdentityTitle)",
                        "Written · \(actionIdentityTitle)"
                    )
                    : store.ui(
                        "已建立关系 · \(actionIdentityTitle)",
                        "Relation created · \(actionIdentityTitle)"
                    ),
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .lineLimit(1)

            Spacer(minLength: 8)

            if action.kind == .writeNote || action.createdRelationID != nil {
                Button(store.ui("撤销", "Undo")) {
                    performUndo()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .disabled(isWorking)
            }
        }
    }

    private var cancelledContent: some View {
        Label(
            action.resultContentDigest != nil || action.createdRelationID != nil
                ? store.ui(
                    "已撤销\(action.kind == .writeNote ? "写入" : "关系") · \(actionIdentityTitle)",
                    "Undone \(action.kind == .writeNote ? "write" : "relation") · \(actionIdentityTitle)"
                )
                : store.ui(
                    "已取消\(action.kind == .writeNote ? "写入" : "关系") · \(actionIdentityTitle)",
                    "Cancelled \(action.kind == .writeNote ? "write" : "relation") · \(actionIdentityTitle)"
                ),
            systemImage: "minus.circle"
        )
        .font(.caption)
        .foregroundStyle(WeiBeiTheme.tertiaryInk)
        .lineLimit(1)
    }

    private var relationNoteLabel: some View {
        actionItemLabel(
            store.agentReplyActionTargetTitle(action)
                ?? store.ui("笔记已不存在", "Missing note"),
            systemImage: "note.text"
        )
    }

    private var relationSourceLabel: some View {
        actionItemLabel(
            store.agentReplyActionSourceTitle(action)
                ?? store.ui("文稿已不存在", "Missing material"),
            systemImage: "doc.text"
        )
    }

    private var actionIdentityTitle: String {
        if action.kind == .writeNote {
            return store.agentReplyActionTargetTitle(action)
                ?? store.ui("目标笔记", "target note")
        }
        let note = store.agentReplyActionTargetTitle(action)
            ?? store.ui("笔记", "note")
        let source = store.agentReplyActionSourceTitle(action)
            ?? store.ui("文稿", "material")
        return "\(note) ↔ \(source)"
    }

    private func actionItemLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(WeiBeiTheme.paperInset.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func performConfirmation() {
        isWorking = true
        Task {
            await store.confirmAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                proposedMarkdown: action.kind == .writeNote ? composedMarkdown : nil
            )
            isWorking = false
        }
    }

    private func performUndo() {
        isWorking = true
        Task {
            await store.undoAgentReplyAction(
                messageID: messageID,
                actionID: action.id
            )
            isWorking = false
        }
    }

    private var composedMarkdown: String {
        let body = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return body }
        guard !body.isEmpty else { return "\(headingPrefix) \(title)" }
        return "\(headingPrefix) \(title)\n\n\(body)"
    }

    private static func noteDraft(
        from markdown: String
    ) -> (headingPrefix: String, title: String, body: String) {
        var lines = markdown.components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }) {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            let prefix = String(line.prefix(while: { $0 == "#" }))
            let title = line.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                lines.remove(at: index)
                return (
                    prefix.isEmpty ? "##" : prefix,
                    title,
                    lines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return (
            "##",
            "整理建议",
            markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private enum AgentCitationParser {
    /// Matches `[材料：…]` / `[学习记录：上次位置]` style Pi citation labels.
    private static let pattern = #"\[(材料|笔记|选区|学习记录|学习记忆|会话)[：:]\s*([^\]\n]{1,300})\]"#

    static func parse(_ text: String) -> (displayText: String, citations: [AgentCitation]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var citations: [AgentCitation] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let kindRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { return }
            let kindToken = String(text[kindRange])
            let value = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = String(text[fullRange])
            guard let kind = kind(from: kindToken) else { return }
            let key = "\(kind.rawValue)|\(value)"
            guard seen.insert(key).inserted else { return }
            citations.append(
                AgentCitation(
                    id: key,
                    kind: kind,
                    raw: raw,
                    value: value
                )
            )
        }
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: "")
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? text : cleaned, citations)
    }

    private static func kind(from token: String) -> AgentCitationKind? {
        switch token {
        case "材料": return .material
        case "笔记": return .note
        case "选区": return .selection
        case "学习记录": return .learningRecord
        case "学习记忆": return .learningMemory
        case "会话": return .session
        default: return nil
        }
    }
}

private struct AgentReplySourceTagRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let sources: [AgentReplySource]
    var onActivate: (AgentReplySource) -> Void
    @State private var showsMore = false

    var body: some View {
        HStack(spacing: 6) {
            if let first = sources.first {
                AgentReplySourceTag(source: first) {
                    onActivate(first)
                }
            }
            if sources.count > 1 {
                Button("+\(sources.count - 1)") {
                    showsMore.toggle()
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    WeiBeiTheme.paperInset.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
                }
                .buttonStyle(.plain)
                .help(store.ui("查看另外 \(sources.count - 1) 个来源", "View \(sources.count - 1) more sources"))
                .popover(isPresented: $showsMore, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(sources.dropFirst())) { source in
                                Button {
                                    showsMore = false
                                    onActivate(source)
                                } label: {
                                    AgentReplySourceDetail(source: source)
                                }
                                .buttonStyle(.plain)
                                if source.id != sources.last?.id {
                                    Rectangle()
                                        .fill(WeiBeiTheme.hairline.opacity(0.42))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(width: 340, height: min(CGFloat(sources.count - 1) * 86, 360))
                    .padding(.vertical, 6)
                }
                .accessibilityLabel(
                    Text(store.ui("展开另外 \(sources.count - 1) 个来源", "Expand \(sources.count - 1) more sources"))
                )
            }
        }
        .padding(.top, 2)
    }
}

private struct AgentReplySourceTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    let source: AgentReplySource
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: source.kind.sourceSystemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(hovering ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                WeiBeiTheme.paperInset.opacity(hovering ? 0.58 : 0.40),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        hovering
                            ? WeiBeiTheme.cinnabar.opacity(0.28)
                            : WeiBeiTheme.hairline.opacity(0.40),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(detailText)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                self.hovering = hovering
            }
        }
        .accessibilityLabel(Text(store.ui("打开原文：\(label)", "Open source: \(label)")))
    }

    private var label: String {
        let title = source.title.count > 18
            ? String(source.title.prefix(16)) + "…"
            : source.title
        guard let position = source.positionLabel(language: store.interfaceLanguage) else {
            return title
        }
        return "\(title) · \(position)"
    }

    private var detailText: String {
        [
            source.title,
            source.positionLabel(language: store.interfaceLanguage),
            source.excerpt.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: "\n")
    }
}

private struct AgentReplySourceDetail: View {
    @EnvironmentObject private var store: WorkspaceStore
    let source: AgentReplySource

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: source.kind.sourceSystemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.82))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(source.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    if let position = source.positionLabel(language: store.interfaceLanguage) {
                        Text(position)
                            .font(.system(size: 10.5))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Text(source.excerpt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private extension AgentReplySourceKind {
    var sourceSystemImage: String {
        switch self {
        case .material: return "doc.text"
        case .note: return "note.text"
        case .selection: return "text.quote"
        }
    }
}

private struct AgentCitationTagRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citations: [AgentCitation]
    var onActivate: (AgentCitation) -> Void

    var body: some View {
        // Wrapping HStack via LazyVGrid-like flow using flexible chips.
        FlexibleCitationWrap(citations: citations, onActivate: onActivate)
    }
}

/// Simple left-to-right wrap without GeometryReader thrash on the chat LazyVStack.
private struct FlexibleCitationWrap: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citations: [AgentCitation]
    var onActivate: (AgentCitation) -> Void

    var body: some View {
        // Single horizontal wrap via ViewThatFits-style chunking is heavy; use a
        // multi-line HStack of lines built greedily at layout time via Preference-free
        // fixed wrapping: put chips in a wrapping layout using `HStack` + multiple rows
        // computed by character budget.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chunkedRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { citation in
                        AgentCitationTag(citation: citation) {
                            onActivate(citation)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var chunkedRows: [[AgentCitation]] {
        var rows: [[AgentCitation]] = []
        var current: [AgentCitation] = []
        var budget: CGFloat = 0
        let rowBudget: CGFloat = 52 // approx character units per row
        for citation in citations {
            let cost = CGFloat(min(citation.displayTitle.count + 6, 28))
            if !current.isEmpty, budget + cost > rowBudget {
                rows.append(current)
                current = []
                budget = 0
            }
            current.append(citation)
            budget += cost
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

private struct AgentCitationTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citation: AgentCitation
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: citation.kind.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(chipLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) { self.hovering = hovering }
        }
        .accessibilityLabel(Text(helpText))
    }

    private var chipLabel: String {
        let kindLabel = citation.kind.shortLabel(language: store.interfaceLanguage)
        switch citation.kind {
        case .learningRecord, .learningMemory, .session:
            // Value is already a short kind phrase ("上次位置").
            return "\(kindLabel) · \(citation.displayTitle)"
        case .material, .note, .selection:
            let short = citation.displayTitle.count > 18
                ? String(citation.displayTitle.prefix(16)) + "…"
                : citation.displayTitle
            return "\(kindLabel) · \(short)"
        }
    }

    private var helpText: String {
        switch citation.kind {
        case .material:
            return store.ui("打开材料：\(citation.displayTitle)", "Open material: \(citation.displayTitle)")
        case .note:
            return store.ui("打开笔记：\(citation.displayTitle)", "Open note: \(citation.displayTitle)")
        case .selection:
            return store.ui("查看选区：\(citation.displayTitle)", "Open selection: \(citation.displayTitle)")
        case .learningRecord:
            return store.ui("回到上次学习位置", "Resume last study location")
        case .learningMemory:
            return store.ui("查看学习记忆", "Open study memory")
        case .session:
            return store.ui("当前会话", "Current session")
        }
    }

    private var foreground: Color {
        switch citation.kind {
        case .material:
            return hovering ? WeiBeiTheme.moss : WeiBeiTheme.moss.opacity(0.92)
        case .note:
            return hovering ? WeiBeiTheme.link : WeiBeiTheme.link.opacity(0.90)
        case .selection:
            return hovering ? WeiBeiTheme.cinnabar : WeiBeiTheme.cinnabar.opacity(0.88)
        case .learningRecord:
            return hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk
        case .learningMemory:
            return hovering ? WeiBeiTheme.secondaryInk : WeiBeiTheme.tertiaryInk
        case .session:
            return WeiBeiTheme.tertiaryInk
        }
    }

    private var background: Color {
        switch citation.kind {
        case .material:
            return WeiBeiTheme.moss.opacity(hovering ? 0.14 : 0.09)
        case .note:
            return WeiBeiTheme.link.opacity(hovering ? 0.12 : 0.07)
        case .selection:
            return WeiBeiTheme.cinnabarSoft.opacity(hovering ? 0.55 : 0.38)
        case .learningRecord:
            return WeiBeiTheme.paperInset.opacity(hovering ? 0.55 : 0.38)
        case .learningMemory:
            return WeiBeiTheme.paperInset.opacity(hovering ? 0.42 : 0.28)
        case .session:
            return WeiBeiTheme.paperInset.opacity(0.22)
        }
    }

    private var border: Color {
        switch citation.kind {
        case .material:
            return WeiBeiTheme.moss.opacity(hovering ? 0.34 : 0.20)
        case .note:
            return WeiBeiTheme.link.opacity(hovering ? 0.32 : 0.18)
        case .selection:
            return WeiBeiTheme.cinnabar.opacity(hovering ? 0.36 : 0.22)
        case .learningRecord, .learningMemory, .session:
            return WeiBeiTheme.hairline.opacity(hovering ? 0.55 : 0.36)
        }
    }
}

/// Session-scoped first-frame height seeds for finalized agent Markdown rows.
/// The bucket never proves measurement success at the current exact width.
private enum AgentFinalizedMarkdownHeightCache {
    private static let lock = NSLock()
    private static var values: [String: CGFloat] = [:]

    static func height(for key: String) -> CGFloat? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    static func store(_ height: CGFloat, for key: String) {
        // Called only from a real WebKit contentHeightChanged event. Store the
        // raw measured value, including legitimate <=44pt short block content;
        // the synthetic 44pt SwiftUI loading frame never reaches this method.
        guard height.isFinite, height > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if let existing = values[key], abs(existing - height) < 2 { return }
        values[key] = height
    }

    static func cacheKey(messageID: UUID?, text: String, widthBucket: Int, wideTypography: Bool) -> String {
        let id = messageID?.uuidString ?? "anon"
        let prefix = text.prefix(64)
        let tier = wideTypography ? "wide" : "compact"
        return "\(id):\(text.count):\(prefix):w\(widthBucket):\(tier)"
    }

    static func widthBucket(_ width: CGFloat) -> Int {
        max(Int((width / 24.0).rounded(.down)) * 24, 0)
    }
}

private struct AgentChatLayoutWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct AgentChatPaneStructureTransitionKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var agentChatLayoutWidth: CGFloat {
        get { self[AgentChatLayoutWidthKey.self] }
        set { self[AgentChatLayoutWidthKey.self] = newValue }
    }

    var agentChatPaneStructureTransitionActive: Bool {
        get { self[AgentChatPaneStructureTransitionKey.self] }
        set { self[AgentChatPaneStructureTransitionKey.self] = newValue }
    }
}

private struct AgentScrollMetrics: Equatable {
    let distanceFromTop: CGFloat
    let distanceFromBottom: CGFloat
    let isUserScrolling: Bool
    let isScrollingTowardTop: Bool
}

/// Reports whether one finalized Markdown row intersects the chat viewport.
/// The boolean changes only at viewport boundaries, keeping offscreen WebKit
/// frames out of pane-animation reflow without putting SwiftUI geometry inside
/// the scroll stack.
private struct AgentScrollViewportVisibilityProbe: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = onChange
        nsView.ensureObserversInstalled()
        nsView.report()
    }

    final class ProbeView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?
        private weak var observedClipView: NSClipView?

        override func layout() {
            super.layout()
            // A representable can enter the SwiftUI hierarchy before its outer
            // ScrollView exists. The first real layout is the reliable point to
            // attach, so the first divider drag never uses stale visibility.
            ensureObserversInstalled()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            ensureObserversInstalled()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            ensureObserversInstalled()
        }

        fileprivate func report() {
            // Before AppKit attaches and lays out the row, visibility is unknown.
            // Reporting false here held the old Markdown width on the first drag,
            // so a fast shrink clipped content until the divider was released.
            guard let clipView = enclosingScrollView?.contentView,
                  window != nil,
                  bounds.width > 1,
                  bounds.height > 1 else { return }
            let frameInClip = convert(bounds, to: clipView)
            let intersection = frameInClip.intersection(clipView.bounds)
            let visible = !intersection.isNull
                && intersection.width > 1
                && intersection.height > 1
            guard visible != lastReported else { return }
            lastReported = visible
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(visible)
            }
        }

        fileprivate func ensureObserversInstalled() {
            guard let clipView = enclosingScrollView?.contentView else { return }
            guard observedClipView !== clipView else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in self?.report() })
            observers.append(center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in self?.report() })
            report()
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

/// AppKit-side scroll probe: observes the enclosing NSScrollView's clip-view
/// bounds and reports both history boundaries plus explicit live-scroll intent.
/// Deliberately NOT SwiftUI geometry — GeometryReader/preference feedback on
/// the chat scroll view re-entered sizeThatFits storms (contract-banned).
private struct AgentScrollDistanceProbe: NSViewRepresentable {
    var onChange: (AgentScrollMetrics) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = onChange
    }

    final class ProbeView: NSView {
        var onChange: ((AgentScrollMetrics) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: AgentScrollMetrics?
        private var isUserScrolling = false
        private var isScrollingTowardTop = false
        private var previousDistanceFromTop: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installObservers()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            installObservers()
        }

        private func installObservers() {
            removeObservers()
            guard window != nil, let scrollView = enclosingScrollView else { return }
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.isUserScrolling = true
                self?.isScrollingTowardTop = false
                self?.report()
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                // The clip view may stop sending bounds changes exactly at its
                // top edge. Flush that final user-directed position first.
                self?.report(force: true)
                self?.isUserScrolling = false
                self?.isScrollingTowardTop = false
                self?.report(force: true)
            })
            report()
        }

        private func report(force: Bool = false) {
            guard let scrollView = enclosingScrollView,
                  let documentView = scrollView.documentView else { return }
            let visible = scrollView.documentVisibleRect
            let distanceFromTop: CGFloat = documentView.isFlipped
                ? max(visible.minY - documentView.bounds.minY, 0)
                : max(documentView.bounds.maxY - visible.maxY, 0)
            let distanceFromBottom: CGFloat = documentView.isFlipped
                ? max(documentView.bounds.maxY - visible.maxY, 0)
                : max(visible.minY - documentView.bounds.minY, 0)
            if isUserScrolling, let previousDistanceFromTop,
               abs(distanceFromTop - previousDistanceFromTop) > 0.5 {
                isScrollingTowardTop = distanceFromTop < previousDistanceFromTop
            }
            previousDistanceFromTop = distanceFromTop
            let metrics = AgentScrollMetrics(
                distanceFromTop: distanceFromTop,
                distanceFromBottom: distanceFromBottom,
                isUserScrolling: isUserScrolling,
                isScrollingTowardTop: isScrollingTowardTop
            )
            if !force, let lastReported,
               abs(metrics.distanceFromTop - lastReported.distanceFromTop) <= 8,
               abs(metrics.distanceFromBottom - lastReported.distanceFromBottom) <= 8,
               metrics.isUserScrolling == lastReported.isUserScrolling,
               metrics.isScrollingTowardTop == lastReported.isScrollingTowardTop {
                return
            }
            lastReported = metrics
            onChange?(metrics)
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            isUserScrolling = false
            isScrollingTowardTop = false
            previousDistanceFromTop = nil
            lastReported = nil
        }

        deinit {
            removeObservers()
        }
    }
}

/// Agent chat markdown — shared by immersive conversation and selection float.
/// - Finalized assistant turns: full `MarkdownPreviewView` with width-aware frozen height.
/// - User turns, failures, and renderer fallback: native `AttributedString`.
private struct AgentMessageMarkdownText: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.agentChatLayoutWidth) private var layoutWidth
    @Environment(\.agentChatPaneStructureTransitionActive) private var paneStructureTransitionActive
    var text: String
    var rendersRichMarkdown: Bool
    /// Selection-float / narrow surfaces: smaller type, still fills available width.
    var compact: Bool = false
    /// Immersive conversation typography tier for finalized WebKit markdown.
    var isChatWideTypography: Bool = false
    /// Completed assistant turns only — never streaming, user, or failure bubbles.
    var usesFinalizedKaTeX: Bool = false
    var messageID: UUID? = nil
    var sources: [AgentReplySource] = []
    var onActivateSource: (AgentReplySource) -> Void = { _ in }
    /// Assistant replies keep this Web renderer mounted from the first streamed text
    /// through the completed message instead of handing off to a second view.
    var keepsMarkdownSurfaceMounted = false
    var isStreaming = false
    @State private var finalizedRendererReady = false
    @State private var finalizedRendererFailed = false
    @State private var awaitsFinalizedRendererReady = false
    @State private var finalizedHeightSettling = false
    @State private var finalizedHeightSettleGeneration = 0
    /// nil = newly mounted and not classified yet. Treat unknown as visible so
    /// an on-screen row never flashes the held offscreen width before the probe.
    @State private var isInScrollViewport: Bool?
    @State private var expandedSourceURL: String?

    private var sourcePresentation: AgentReplySourceInlinePresentation {
        AgentReplySourceInlinePresentation(
            text: text,
            sources: sources,
            language: store.interfaceLanguage
        )
    }

    private var finalizedMarkdown: String {
        AgentChatKaTeXMarkdown.prepare(displayMarkdown)
    }

    private var displayMarkdown: String {
        AgentCitationParser.parse(sourcePresentation.markdown).displayText
    }

    /// Coarse cache bucket — also drives MarkdownPreviewView freeze width.
    private var layoutWidthBucket: Int {
        AgentFinalizedMarkdownHeightCache.widthBucket(layoutWidth)
    }

    private var shouldUseFinalizedMarkdown: Bool {
        usesFinalizedKaTeX && rendersRichMarkdown
            && (keepsMarkdownSurfaceMounted
                || AgentChatKaTeXMarkdown.requiresWebRenderer(finalizedMarkdown))
    }

    private var heldOffscreenRendererWidth: CGFloat? {
        if paneStructureTransitionActive && isInScrollViewport == false {
            return max(layoutWidth, 1)
        }
        return nil
    }

    var body: some View {
        Group {
            if shouldUseFinalizedMarkdown {
                finalizedMarkdownBody
            } else {
                nativeBody
            }
        }
        .modifier(AgentMessageTextWidthModifier(fillsReadingColumn: rendersRichMarkdown || compact))
        .environment(\.openURL, OpenURLAction { url in
            handleSourceURL(url) ? .handled : .systemAction
        })
        .popover(
            isPresented: Binding(
                // Only the selected URL should drive presentation. Evaluating
                // expandedSources here rebuilt source presentations for every
                // message on every WorkspaceStore publish (send-path freeze sample).
                get: { expandedSourceURL != nil },
                set: { if !$0 { expandedSourceURL = nil } }
            ),
            arrowEdge: .bottom
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(expandedSources) { source in
                    Button {
                        expandedSourceURL = nil
                        onActivateSource(source)
                    } label: {
                        AgentReplySourceDetail(source: source)
                    }
                    .buttonStyle(.plain)
                    if source.id != expandedSources.last?.id {
                        Rectangle()
                            .fill(WeiBeiTheme.hairline.opacity(0.42))
                            .frame(height: 1)
                    }
                }
            }
            .frame(width: 340)
            .padding(.vertical, 6)
        }
        .help(sourceHelp)
        .onChange(of: finalizedMarkdown) { _, _ in
            // A live answer owns one renderer. Preserve its visible identity
            // while the same WebView accepts the next snapshot or final text.
            if !keepsMarkdownSurfaceMounted {
                finalizedHeightSettleGeneration &+= 1
                finalizedHeightSettling = false
                finalizedRendererReady = false
                finalizedRendererFailed = false
                awaitsFinalizedRendererReady = false
            }
        }
        .onChange(of: isStreaming) { wasStreaming, isStreaming in
            guard wasStreaming, !isStreaming,
                  keepsMarkdownSurfaceMounted else { return }
            // The streaming measurement only proves the previous DOM was ready.
            // Keep this WebView mounted, but wait for the finalized snapshot's
            // own measurement before letting it cover the native text.
            finalizedRendererReady = false
            finalizedRendererFailed = false
            awaitsFinalizedRendererReady = true
        }
    }

    private var cacheKey: String {
        AgentFinalizedMarkdownHeightCache.cacheKey(
            messageID: messageID,
            text: finalizedMarkdown,
            widthBucket: layoutWidthBucket,
            wideTypography: isChatWideTypography
        )
    }

    private var cachedFinalizedHeight: CGFloat? {
        AgentFinalizedMarkdownHeightCache.height(for: cacheKey)
    }

    @ViewBuilder
    private var finalizedMarkdownBody: some View {
        // The mature Markdown renderer handles paragraphs, headings, lists, tables,
        // fenced code and KaTeX through one path. Native text stays visible until
        // the first valid measurement and returns immediately if WebKit fails.
        // Settled/offscreen height freezes after a real measure; an on-screen
        // row stays live while its pane is resizing so new wraps are not clipped.
        // The 24pt-bucket cache supplies a first-frame seed, never readiness.
        // NEVER wire onContentHeightChange to scrollAgentToBottom.
        ZStack(alignment: .topLeading) {
            if !finalizedRendererFailed {
                MarkdownPreviewView(
                    markdown: finalizedMarkdown,
                    markdownBaseURL: store.currentMarkdownBaseURL,
                    appearanceMode: store.appearanceMode,
                    interfaceLanguage: store.interfaceLanguage,
                    compact: true,
                    fitsContentHeight: true,
                    // Freezing is only a recycle optimization for offscreen rows.
                    // A visible answer stays authoritative so delayed list, font,
                    // image, or KaTeX growth can never be clipped by an old frame.
                    freezeHeightAfterMeasure: !isStreaming
                        && (!paneStructureTransitionActive || isInScrollViewport == false)
                        && isInScrollViewport == false,
                    allowsHeightFreeze: !finalizedHeightSettling,
                    seedContentHeight: isStreaming ? nil : cachedFinalizedHeight,
                    layoutWidthKey: layoutWidthBucket,
                    isChatWideTypography: isChatWideTypography,
                    preservesHeightAcrossMarkdownChanges: keepsMarkdownSurfaceMounted,
                    streamsMarkdownUpdates: isStreaming,
                    acceptsHeightMeasurements: !awaitsFinalizedRendererReady,
                    onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
                    onSourceReference: { reference in
                        if let url = URL(string: reference),
                           handleSourceURL(url) {
                            return
                        }
                        store.openSourceReference(reference)
                    },
                    onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
                    onRenderReady: {
                        finalizedRendererFailed = false
                    },
                    onFinalizedSnapshotReady: { height in
                        guard !isStreaming else { return }
                        awaitsFinalizedRendererReady = false
                        finalizedRendererFailed = false
                        if !paneStructureTransitionActive {
                            AgentFinalizedMarkdownHeightCache.store(
                                height,
                                for: cacheKey
                            )
                        }
                        finalizedRendererReady = true
                        finalizedHeightSettleGeneration &+= 1
                        let settleGeneration = finalizedHeightSettleGeneration
                        finalizedHeightSettling = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 650_000_000)
                            guard settleGeneration
                                    == finalizedHeightSettleGeneration else {
                                return
                            }
                            finalizedHeightSettling = false
                        }
                    },
                    onRenderFailure: {
                        finalizedHeightSettleGeneration &+= 1
                        finalizedHeightSettling = false
                        awaitsFinalizedRendererReady = false
                        finalizedRendererReady = false
                        finalizedRendererFailed = true
                    },
                    onMeasuredHeight: { height in
                        if !awaitsFinalizedRendererReady,
                           !isStreaming,
                           !paneStructureTransitionActive {
                            AgentFinalizedMarkdownHeightCache.store(height, for: cacheKey)
                        }
                        if !awaitsFinalizedRendererReady,
                           !finalizedRendererReady {
                            finalizedRendererReady = true
                        }
                    }
                )
                // Keep an offscreen WebView at its settled width without letting
                // that fixed child establish the scroll document's minimum width.
                .frame(width: heldOffscreenRendererWidth, alignment: .leading)
                // The outer row always accepts the live parent proposal. Visible
                // renderers use it directly; held offscreen renderers are clipped.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(finalizedRendererReady && !isStreaming)
                .accessibilityHidden(!finalizedRendererReady)
                .opacity(isStreaming || finalizedRendererReady ? 1 : 0.01)
                .zIndex(0)
            }
            // Never flash native/raw Markdown over a live stream. Once streaming
            // completes, keep native Markdown visible until this same WebView has
            // measured the finalized snapshot; otherwise a cold Chat can show an
            // empty answer until the user scrolls.
            if !finalizedRendererReady
                && (!isStreaming
                    || !keepsMarkdownSurfaceMounted
                    || finalizedRendererFailed) {
                nativeBody
                    .background(WeiBeiTheme.paper)
                    .allowsHitTesting(false)
                    .zIndex(1)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .background {
            AgentScrollViewportVisibilityProbe { visible in
                if isInScrollViewport != Optional(visible) {
                    isInScrollViewport = visible
                }
            }
        }
    }

    private var nativeBody: some View {
        Text(renderedText)
            .font(.system(size: compact ? 13.2 : (rendersRichMarkdown ? 15 : 14.5)))
            .lineSpacing(compact ? 4.2 : (rendersRichMarkdown ? 5.5 : 4.5))
            .foregroundStyle(WeiBeiTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            // NEVER enable SwiftUI textSelection here. Sample 2026-08-01: SelectionOverlay
            // updateNSView + LazyVStack sizeThatFits spun the main thread at 100% after a
            // few HTML reader scrolls (store publish fanout). KaTeX WKWebView still selects.
            .textSelection(.disabled)
    }

    private var renderedText: AttributedString {
        // Streaming / no-math path: Unicode math readability without WKWebView.
        let display = RichAnswerDisplayText.normalizedInlineMath(displayMarkdown)
        var attributed = (try? AttributedString(markdown: display))
            ?? AttributedString(display)
        let sourceRanges = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard run.link.map(sourcePresentation.contains) == true else { return nil }
            return run.range
        }
        for range in sourceRanges {
            attributed[range].font = .system(size: compact ? 10.5 : 11, weight: .semibold)
            attributed[range].foregroundColor = WeiBeiTheme.cinnabar
            attributed[range].backgroundColor = WeiBeiTheme.paperInset.opacity(0.64)
            attributed[range].underlineStyle = nil
        }
        return attributed
    }

    private var expandedSources: [AgentReplySource] {
        expandedSourceURL.flatMap(sourcePresentation.additionalSources(for:)) ?? []
    }

    private var sourceHelp: String {
        sources.map { source in
            [
                source.title,
                source.positionLabel(language: store.interfaceLanguage),
                source.excerpt.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
        }
        .joined(separator: "\n")
    }

    @discardableResult
    private func handleSourceURL(_ url: URL) -> Bool {
        if let source = sourcePresentation.source(for: url) {
            onActivateSource(source)
            return true
        }
        if !sourcePresentation.additionalSources(for: url).isEmpty {
            expandedSourceURL = url.absoluteString
            return true
        }
        return false
    }
}

private struct AgentMessageTextWidthModifier: ViewModifier {
    let fillsReadingColumn: Bool

    func body(content: Content) -> some View {
        if fillsReadingColumn {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Hug text width (wraps within the bubble's maxWidth: 520), not a full-width bar.
            content
        }
    }
}

/// Product loading motion — 「行文进行中 V3」.
/// Driven solely by `store.agentActivityText` (no demo status carousel).
///
/// Hang-proof: motion runs in a fixed-size `NSView` + `CADisplayLink` that only
/// `setNeedsDisplay()`. It never enters SwiftUI `TimelineView`, so parent
/// `ScrollView` / `LazyVStack` do not re-run `sizeThatFits` every frame
/// (that thrash was freezing the app after a couple of scrolls).
///
/// Geometry: cinnabar orbit keeps equal padding on all four sides of the status text.
///
/// Model (view coords, flipped):
/// ```
/// ┌──────── path (stroke centerline) ────────┐
/// │  pad                                     │
/// │     ┌──── glyph / line box ────┐         │
/// │ pad │  加载词                  │ pad     │
/// │     └──────────────────────────┘         │
/// │  pad                                     │
/// └──────────────────────────────────────────┘
/// ```
/// `orbitPadding` is the clear gap from the line-box edge to the stroke *centerline*
/// on every side. Half the stroke width sits outside that centerline, so the view
/// grows by `lineWidth` total to avoid clipping.
private struct AgentThinkingIndicator: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cachedText = ""
    @State private var cachedTextWidth: CGFloat = 1
    @State private var motionEpoch = Date()
    @State private var lastStatusSwitch = Date.distantPast
    @State private var statusSwitchTask: Task<Void, Never>?

    private static let minimumStatusHold: TimeInterval = 0.6

    /// 14.5pt — user feedback: the 12pt status read as an afterthought; the
    /// status line is the primary signal of what the agent is doing.
    private static let statusFontSize: CGFloat = 14.5
    /// Clear gap from line-box edge → stroke centerline (all four sides).
    private static let orbitPadding: CGFloat = 6.5
    private static let lineWidth: CGFloat = 1.25
    /// Line box height matches the font’s typographic bounds so top/bottom pad stay equal.
    private static var textLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .medium)
        return max(1, ceil(font.ascender - font.descender))
    }
    /// Outer view size = line box + equal pad on both sides + half stroke outside the path.
    private static var pathOuterInset: CGFloat { orbitPadding + lineWidth / 2 }
    private static var pathHeight: CGFloat { textLineHeight + pathOuterInset * 2 }

    private var statusText: String {
        store.agentActivityText ?? store.ui("正在思考", "Thinking")
    }

    var body: some View {
        let text = cachedText.isEmpty ? statusText : cachedText
        let textWidth = max(1, cachedTextWidth)
        let orbitWidth = textWidth + Self.pathOuterInset * 2
        let pathHeight = Self.pathHeight

        Group {
            if reduceMotion {
                Text(text)
                    .font(.system(size: Self.statusFontSize, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.ink.opacity(0.93))
                    .lineLimit(1)
                    .frame(width: textWidth, height: Self.textLineHeight, alignment: .leading)
                    .padding(Self.pathOuterInset)
            } else {
                // AppKit host: fixed intrinsic size; ticks only repaint the NSView.
                AgentThinkingOrbitHost(
                    text: text,
                    textWidth: textWidth,
                    orbitWidth: orbitWidth,
                    pathHeight: pathHeight,
                    orbitPadding: Self.orbitPadding,
                    textLineHeight: Self.textLineHeight,
                    lineWidth: Self.lineWidth,
                    motionEpoch: motionEpoch,
                    appearanceMode: store.appearanceMode
                )
                .frame(width: orbitWidth, height: pathHeight, alignment: .leading)
                .allowsHitTesting(false)
            }
        }
        .frame(width: orbitWidth, height: pathHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear {
            refreshCache(for: statusText)
            motionEpoch = Date()
        }
        .onChange(of: statusText) { _, newText in
            // Hold each status >=600ms — rapid tool churn restarted the orbit
            // every few frames and read as flicker instead of progress.
            statusSwitchTask?.cancel()
            let now = Date()
            let elapsed = now.timeIntervalSince(lastStatusSwitch)
            if elapsed >= Self.minimumStatusHold {
                lastStatusSwitch = now
                refreshCache(for: newText)
                motionEpoch = Date()
                return
            }
            let delay = Self.minimumStatusHold - elapsed
            statusSwitchTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                lastStatusSwitch = Date()
                refreshCache(for: statusText)
                motionEpoch = Date()
            }
        }
    }

    private func refreshCache(for text: String) {
        cachedText = text
        cachedTextWidth = Self.measuredWidth(for: text)
    }

    private static func measuredWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return max(1, ceil(size.width))
    }
}

/// Bridges V3 orbit motion into AppKit so SwiftUI layout never sees per-frame updates.
private struct AgentThinkingOrbitHost: NSViewRepresentable {
    let text: String
    let textWidth: CGFloat
    let orbitWidth: CGFloat
    let pathHeight: CGFloat
    let orbitPadding: CGFloat
    let textLineHeight: CGFloat
    let lineWidth: CGFloat
    let motionEpoch: Date
    let appearanceMode: WeiBeiAppearanceMode

    func makeNSView(context: Context) -> AgentThinkingOrbitNSView {
        let view = AgentThinkingOrbitNSView()
        view.wantsLayer = true
        view.apply(
            text: text,
            textWidth: textWidth,
            orbitWidth: orbitWidth,
            pathHeight: pathHeight,
            orbitPadding: orbitPadding,
            textLineHeight: textLineHeight,
            lineWidth: lineWidth,
            motionEpoch: motionEpoch,
            appearanceMode: appearanceMode
        )
        return view
    }

    /// Fixed orbit size — never ask AppKit for fittingSize during agent-send layout storms.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: AgentThinkingOrbitNSView,
        context: Context
    ) -> CGSize? {
        CGSize(width: max(orbitWidth, 1), height: max(pathHeight, 1))
    }

    func updateNSView(_ nsView: AgentThinkingOrbitNSView, context: Context) {
        nsView.apply(
            text: text,
            textWidth: textWidth,
            orbitWidth: orbitWidth,
            pathHeight: pathHeight,
            orbitPadding: orbitPadding,
            textLineHeight: textLineHeight,
            lineWidth: lineWidth,
            motionEpoch: motionEpoch,
            appearanceMode: appearanceMode
        )
    }
}

/// Fixed-size AppKit painter for 「行文进行中 V3」: reveal + first-pass underline + TextOrbitSegment.
/// Text sits in a line box; orbit stroke centerline keeps equal `orbitPadding` on all four sides.
final class AgentThinkingOrbitNSView: NSView {
    private static let statusFontSize: CGFloat = 12
    private static let segmentLength: CGFloat = 10
    private static let firstPassDuration: TimeInterval = 0.88
    private static let orbitDuration: TimeInterval = 2.25

    private var statusText = ""
    private var textWidth: CGFloat = 1
    private var orbitWidth: CGFloat = 1
    private var pathHeight: CGFloat = 26
    private var orbitPadding: CGFloat = 5.5
    private var textLineHeight: CGFloat = 15
    private var lineWidth: CGFloat = 1.25
    private var motionEpoch = Date()
    private var appearanceMode: WeiBeiAppearanceMode = .paper
    private var displayLink: CADisplayLink?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: orbitWidth, height: pathHeight)
    }

    deinit {
        stopDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    func apply(
        text: String,
        textWidth: CGFloat,
        orbitWidth: CGFloat,
        pathHeight: CGFloat,
        orbitPadding: CGFloat,
        textLineHeight: CGFloat,
        lineWidth: CGFloat,
        motionEpoch: Date,
        appearanceMode: WeiBeiAppearanceMode
    ) {
        let sizeChanged = abs(self.orbitWidth - orbitWidth) > 0.5
            || abs(self.pathHeight - pathHeight) > 0.5
        statusText = text
        self.textWidth = max(1, textWidth)
        self.orbitWidth = max(1, orbitWidth)
        self.pathHeight = max(1, pathHeight)
        self.orbitPadding = max(1, orbitPadding)
        self.textLineHeight = max(1, textLineHeight)
        self.lineWidth = max(0.5, lineWidth)
        self.motionEpoch = motionEpoch
        self.appearanceMode = appearanceMode
        if sizeChanged {
            invalidateIntrinsicContentSize()
        }
        // Paint only — do not call setNeedsLayout / invalidate parent SwiftUI layout.
        needsDisplay = true
        if window != nil {
            startDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(handleDisplayTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayTick() {
        // Local repaint only. Never touch SwiftUI state from here.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = CGRect(x: 0, y: 0, width: orbitWidth, height: pathHeight)
        context.clear(bounds)

        let elapsed = max(0, Date().timeIntervalSince(motionEpoch))
        let reveal = TextOrbitSegment.revealProgress(at: elapsed)
        let firstPass = elapsed < Self.firstPassDuration
        let cursorProgress = firstPass ? reveal : 1
        let cursorOpacity = firstPass
            ? TextOrbitSegment.smootherStep(TextOrbitSegment.clamp(reveal / 0.14))
                * (1 - TextOrbitSegment.smootherStep(TextOrbitSegment.clamp((elapsed - 0.82) / 0.16)))
            : 0
        let orbitOpacity = firstPass
            ? TextOrbitSegment.smootherStep(TextOrbitSegment.clamp((elapsed - 0.82) / 0.18))
            : 1
        let orbitProgress = TextOrbitSegment.orbitProgress(at: elapsed)

        let ink = WeiBeiNativePalette.ink(for: appearanceMode).withAlphaComponent(0.93)
        let dim = WeiBeiNativePalette.tertiaryInk(for: appearanceMode).withAlphaComponent(0.70)
        let cinnabar = WeiBeiNativePalette.cinnabar(for: appearanceMode).withAlphaComponent(0.82)

        let font = NSFont.systemFont(ofSize: Self.statusFontSize, weight: .medium)
        // Line box inset so every side has the same gap to the stroke centerline.
        // view edge → stroke center = lineWidth/2
        // stroke center → line box edge = orbitPadding
        let contentOrigin = orbitPadding + lineWidth / 2
        let textRect = CGRect(
            x: contentOrigin,
            y: contentOrigin,
            width: textWidth,
            height: textLineHeight
        )
        // draw(in:) top-aligns in the flipped line box. Line-box height == ascender−descender,
        // so ink fills the box and all four sides keep the same gap to the stroke centerline.
        // Do not add capHeight/descender fudge — that broke equal top/bottom padding.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        let dimAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dim,
            .paragraphStyle: paragraph
        ]
        (statusText as NSString).draw(in: textRect, withAttributes: dimAttributes)

        if reveal > 0.001 {
            context.saveGState()
            context.clip(
                to: CGRect(
                    x: textRect.minX,
                    y: 0,
                    width: textWidth * CGFloat(reveal),
                    height: pathHeight
                )
            )
            let inkAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ink,
                .paragraphStyle: paragraph
            ]
            (statusText as NSString).draw(in: textRect, withAttributes: inkAttributes)
            context.restoreGState()
        }

        // First-pass proofread line: center of the bottom equal-padding band.
        if cursorOpacity > 0.01 {
            let bottomBandCenterY = textRect.maxY + orbitPadding / 2
            let x = textRect.minX + max(0, (textWidth - Self.segmentLength) * CGFloat(cursorProgress))
            let y = bottomBandCenterY - lineWidth / 2
            let segment = CGRect(x: x, y: y, width: Self.segmentLength, height: lineWidth)
            context.saveGState()
            context.setAlpha(CGFloat(cursorOpacity))
            context.setFillColor(cinnabar.cgColor)
            let path = CGPath(
                roundedRect: segment,
                cornerWidth: lineWidth / 2,
                cornerHeight: lineWidth / 2,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }

        // Orbit stroke centerline: equal orbitPadding from the line box on all four sides.
        if orbitOpacity > 0.01 {
            context.saveGState()
            context.setAlpha(CGFloat(orbitOpacity))
            TextOrbitSegment.stroke(
                progress: orbitProgress,
                width: orbitWidth,
                height: pathHeight,
                segmentLength: Self.segmentLength,
                lineWidth: lineWidth,
                color: cinnabar,
                in: context
            )
            context.restoreGState()
        }
    }
}

/// Short cinnabar segment orbiting a measured text box (V3 path geometry).
/// Pure geometry/paint helper — not a SwiftUI View — so it cannot thrash ScrollView layout.
enum TextOrbitSegment {
    static let firstPassDuration: TimeInterval = 0.88
    static let orbitDuration: TimeInterval = 2.25

    static func revealProgress(at elapsed: TimeInterval) -> Double {
        let raw = clamp((elapsed - 0.10) / 0.78)
        return 1 - pow(1 - raw, 3.2)
    }

    static func orbitProgress(at elapsed: TimeInterval) -> Double {
        guard elapsed >= firstPassDuration else { return 0 }
        let t = (elapsed - firstPassDuration) / orbitDuration
        let remainder = t.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func smootherStep(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    static func stroke(
        progress: Double,
        width: CGFloat,
        height: CGFloat,
        segmentLength: CGFloat,
        lineWidth: CGFloat,
        color: NSColor,
        in context: CGContext
    ) {
        let normalized = CGFloat(((progress.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1))
        let perimeter = TextOrbitPath.estimatedPerimeter(width: width, height: height, lineWidth: lineWidth)
        let fraction = min(0.08, segmentLength / max(1, perimeter))
        let end = normalized + fraction
        let fullPath = TextOrbitPath.cgPath(width: width, height: height, lineWidth: lineWidth)

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if end <= 1 {
            strokeTrimmed(fullPath, from: normalized, to: end, in: context)
        } else {
            strokeTrimmed(fullPath, from: normalized, to: 1, in: context)
            strokeTrimmed(fullPath, from: 0, to: end - 1, in: context)
        }
    }

    private static func strokeTrimmed(_ path: CGPath, from start: CGFloat, to end: CGFloat, in context: CGContext) {
        guard end > start else { return }
        let trimmed = path.trimmedPath(from: start, to: end)
        context.addPath(trimmed)
        context.strokePath()
    }
}

/// V3 orbit geometry: rounded rectangle starting bottom-right, clockwise.
/// Path centerline sits `lineWidth/2` inside the view so the stroke is fully visible
/// and the clear gap to the text line box is equal on all four sides.
enum TextOrbitPath {
    /// Matches AgentThinkingOrbitNSView lineWidth default; stroke() passes the live width via inset.
    static let defaultLineWidth: CGFloat = 1.25

    static func estimatedPerimeter(width: CGFloat, height: CGFloat, lineWidth: CGFloat = defaultLineWidth) -> CGFloat {
        let inset = lineWidth / 2
        let radius: CGFloat = 3
        let w = max(1, width - inset * 2)
        let h = max(1, height - inset * 2)
        return max(1, 2 * (w + h) - 8 * radius + 2 * .pi * radius)
    }

    static func cgPath(width: CGFloat, height: CGFloat, lineWidth: CGFloat = defaultLineWidth) -> CGPath {
        // Stroke centerline inset = half line width → equal visual margins when text box
        // is placed at (pad + lineWidth/2) with the same pad on every side.
        let inset = lineWidth / 2
        let radius: CGFloat = 3
        let minX = inset
        let maxX = width - inset
        let minY = inset
        let maxY = height - inset

        let path = CGMutablePath()
        path.move(to: CGPoint(x: maxX - radius, y: maxY))
        path.addQuadCurve(to: CGPoint(x: maxX, y: maxY - radius), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: minY + radius))
        path.addQuadCurve(to: CGPoint(x: maxX - radius, y: minY), control: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: minX + radius, y: minY))
        path.addQuadCurve(to: CGPoint(x: minX, y: minY + radius), control: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX, y: maxY - radius))
        path.addQuadCurve(to: CGPoint(x: minX + radius, y: maxY), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - radius, y: maxY))
        path.closeSubpath()
        return path
    }
}

private extension CGPath {
    /// Approximate trim for a closed path by walking the flattened polyline.
    func trimmedPath(from start: CGFloat, to end: CGFloat) -> CGPath {
        let points = flattenedPoints()
        guard points.count >= 2 else { return self }

        var lengths: [CGFloat] = [0]
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            lengths.append(total)
        }
        guard total > 0 else { return self }

        let startDistance = max(0, min(1, start)) * total
        let endDistance = max(0, min(1, end)) * total
        guard endDistance > startDistance else { return CGMutablePath() }

        let result = CGMutablePath()
        var started = false
        for index in 1..<points.count {
            let segmentStart = lengths[index - 1]
            let segmentEnd = lengths[index]
            if segmentEnd < startDistance { continue }
            if segmentStart > endDistance { break }

            let fromT = segmentEnd == segmentStart
                ? 0
                : max(0, (startDistance - segmentStart) / (segmentEnd - segmentStart))
            let toT = segmentEnd == segmentStart
                ? 1
                : min(1, (endDistance - segmentStart) / (segmentEnd - segmentStart))
            let p0 = points[index - 1]
            let p1 = points[index]
            let fromPoint = CGPoint(
                x: p0.x + (p1.x - p0.x) * fromT,
                y: p0.y + (p1.y - p0.y) * fromT
            )
            let toPoint = CGPoint(
                x: p0.x + (p1.x - p0.x) * toT,
                y: p0.y + (p1.y - p0.y) * toT
            )
            if !started {
                result.move(to: fromPoint)
                started = true
            }
            result.addLine(to: toPoint)
        }
        return result
    }

    func flattenedPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        applyWithBlock { elementPointer in
            Self.appendFlattened(element: elementPointer.pointee, into: &points)
        }
        return points
    }

    private static func appendFlattened(element: CGPathElement, into points: inout [CGPoint]) {
        switch element.type {
        case .moveToPoint:
            points.append(element.points[0])
        case .addLineToPoint:
            points.append(element.points[0])
        case .addQuadCurveToPoint:
            appendQuad(
                from: points.last ?? element.points[1],
                control: element.points[0],
                to: element.points[1],
                into: &points
            )
        case .addCurveToPoint:
            appendCubic(
                from: points.last ?? element.points[2],
                c1: element.points[0],
                c2: element.points[1],
                to: element.points[2],
                into: &points
            )
        case .closeSubpath:
            if let first = points.first {
                points.append(first)
            }
        @unknown default:
            break
        }
    }

    private static func appendQuad(
        from start: CGPoint,
        control: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint]
    ) {
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let mt = 1 - t
            let x = mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x
            let y = mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
            points.append(CGPoint(x: x, y: y))
        }
    }

    private static func appendCubic(
        from start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint]
    ) {
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let mt = 1 - t
            let x = mt * mt * mt * start.x
                + 3 * mt * mt * t * c1.x
                + 3 * mt * t * t * c2.x
                + t * t * t * end.x
            let y = mt * mt * mt * start.y
                + 3 * mt * mt * t * c1.y
                + 3 * mt * t * t * c2.y
                + t * t * t * end.y
            points.append(CGPoint(x: x, y: y))
        }
    }
}

private struct AgentStreamingResponse: View {
    @EnvironmentObject private var store: WorkspaceStore
    var text: String
    /// Bubble rows already carry the WeiBei metadata line — never draw a
    /// second brand mark inside the same bubble (user-reported duplication).
    var showsBrandHeader = true
    var isChatWideTypography = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsBrandHeader {
                HStack(spacing: 6) {
                    Text("WeiBei")
                        .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
                    Text("PI")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    // Status stays visible while tokens stream ("正在读取：…"),
                    // plain text only — WP9 forbids loading-card chrome here.
                    if let activity = store.agentActivityText {
                        Text(activity)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(0.82))
                            .lineLimit(1)
                            .padding(.leading, 2)
                    }
                }
            }
            AgentMessageMarkdownText(
                text: text,
                rendersRichMarkdown: true,
                compact: compact,
                isChatWideTypography: isChatWideTypography,
                usesFinalizedKaTeX: true,
                keepsMarkdownSurfaceMounted: true,
                isStreaming: true
            )
        }
        .padding(.vertical, compact ? 0 : 10)
        .padding(.leading, compact ? 0 : 20)
        .padding(.trailing, compact ? 0 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(store.ui("PI 正在回答", "PI is responding")))
    }
}
