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
                    .weiBeiText(12, weight: .medium)
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
    @EnvironmentObject private var paneState: WorkspacePaneState
    @State private var noteTabTitleDraft = ""
    @State private var editingNoteTabTitle = false
    @State private var editorRecoveryGeneration = 0
    @State private var editorRecoveryState = EditorRecoveryState.idle
    @State private var noteOutline: [NoteEditorOutlineItem] = []
    @State private var activeNoteRailID: String?
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil

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

                    if let conflict = store.noteEditorRecoveryConflict {
                        HStack(spacing: 12) {
                            Text(conflict.checkpointIsPersisted
                                ? store.ui(
                                    "这份笔记在应用外也发生了修改，未写内容已保存在魏碑中。请选择下一步。",
                                    "This note was also changed outside WeiBei. Unsaved content is stored in WeiBei. Choose what to do next."
                                )
                                : store.ui(
                                    "这份笔记在应用外也发生了修改。未写内容仍在当前编辑中，但尚未安全保存；请不要关闭并重试。",
                                    "This note was also changed outside WeiBei. Unsaved content remains in the current editor but is not safely stored yet; do not close it, and retry."
                                ))
                            Spacer(minLength: 8)
                            Button(store.ui("使用磁盘版本", "Use Disk Version")) {
                                Task { await store.resolveNoteEditorRecoveryConflict(useDisk: true) }
                            }
                            Button(store.ui("恢复魏碑中的内容", "Restore WeiBei Content")) {
                                Task { await store.resolveNoteEditorRecoveryConflict(useDisk: false) }
                            }
                        }
                        .weiBeiText(10.5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(WeiBeiTheme.paperRaised)
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
                        onActivate: { activateNoteRailItem($0, railOnly: railOnly) },
                        motionPreference: store.motionPreference
                    )
                    .zIndex(4)
                }
            }
            .overlay(alignment: .top) {
                if !showsPaneHeader && hasNoteContent && !railOnly {
                    immersiveNoteHeader
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
        .animation(WeiBeiMotion.panel, value: store.notebookCreationDraft?.id)
        .onDisappear {
            store.noteEditingSession.requestSnapshot()
        }
        .onChange(of: store.activeNoteItemID) { _, _ in
            editingNoteTabTitle = false
            editorRecoveryState = .idle
            noteOutline = []
            activeNoteRailID = nil
        }
        .onChange(of: paneState.focusedPane) { _, pane in
            if pane != .notes {
                store.noteEditingSession.requestSnapshot()
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
                latinMark: store.interfaceLanguage == .chinese ? "NOTE" : nil,
                subtitle: noteHeaderSubtitle,
                appearanceMode: store.appearanceMode,
                reorderRole: reorderRole
            ) {
                NoteSaveStatusLabel(session: store.noteEditingSession)
                ContextualContentListButton(kind: .note)
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
                mark: "NOTE",
                title: noteHeaderSubtitle,
                appearanceMode: store.appearanceMode,
                isPinned: store.notebookCreationDraft != nil,
                reorderRole: reorderRole,
                titleRename: noteTabRename
            ) {
                NoteSaveStatusLabel(session: store.noteEditingSession)
                ContextualContentListButton(kind: .note)
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

    /// 浮动 tab 的笔记名支持行内重命名；自定义名持久化在笔记条目上，清空即恢复自动跟随。
    private var noteTabRename: HoverTitleRename? {
        guard let noteID = store.activeNoteItem?.id else { return nil }
        return HoverTitleRename(
            draft: $noteTabTitleDraft,
            isEditing: editingNoteTabTitle,
            hint: store.ui("点击重命名显示名；清空后恢复自动跟随", "Click to rename the tab title; clear it to resume auto-follow"),
            begin: {
                // 预填解析后的当前显示名（自定义名 / title / 正文回退），从现有名字开始编辑。
                noteTabTitleDraft = store.agentNoteTitle
                withAnimation(WeiBeiMotion.panel) { editingNoteTabTitle = true }
            },
            commit: {
                // 空白提交 = 清除自定义名，恢复自动跟随 title / 正文。
                store.setNoteCustomDisplayTitle(noteTabTitleDraft, for: noteID)
                withAnimation(WeiBeiMotion.panel) { editingNoteTabTitle = false }
            },
            cancel: {
                withAnimation(WeiBeiMotion.panel) { editingNoteTabTitle = false }
            }
        )
    }

    private var noteHeaderSubtitle: String {
        store.agentNoteTitle
    }

    @ViewBuilder
    private var noteBody: some View {
        if store.activeNoteItem == nil
            && store.blankNoteDraftMaterialID == nil {
            ContextualContentPicker(kind: .note)
        } else {
            if store.activeNoteIsLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text(store.ui("正在载入笔记", "Loading note")))
            } else {
                // 笔记固定为所见即所得（rich）写作，源码 / 对照模式入口已全部移除。
                if editorRecoveryState == .stopped {
                    editorRecoveryFailure
                } else {
                    richEditor
                }
            }
        }
    }

    private var editorRecoveryFailure: some View {
        VStack(spacing: 12) {
            Text(store.ui(
                "编辑器连续恢复失败，已停止自动重建。恢复草稿仍保留，可手动重试。",
                "The editor repeatedly failed to recover, so automatic rebuilding stopped. The recovery draft is preserved; retry manually."
            ))
                .weiBeiText(13, weight: .medium)
                .foregroundStyle(WeiBeiTheme.ink)
                .multilineTextAlignment(.center)
            Button(store.ui("重试编辑器", "Retry Editor")) {
                editorRecoveryState.retryManually()
                editorRecoveryGeneration &+= 1
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noteRailItems: [ContentRailItem] {
        noteOutline.map { heading in
            return ContentRailItem(
                id: heading.id,
                position: CGFloat(heading.position),
                level: max(heading.level - 1, 0),
                title: heading.title,
                excerpt: "",
                metadata: store.ui(
                    "第 \(heading.index + 1) / \(noteOutline.count) 节 · H\(heading.level)",
                    "Section \(heading.index + 1) / \(noteOutline.count) · H\(heading.level)"
                )
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
            store.requestPaneExpansion(.notes, onCompleted: navigate)
        } else {
            navigate()
        }
    }

    private func railPreviewText(_ value: String) -> String {
        let collapsed = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(180))
    }

    private var richEditor: some View {
        let recoveryGeneration = editorRecoveryGeneration
        return RichMarkdownEditorView(documentID: store.activeNoteEditorDocumentID, markdown: store.noteText, command: Binding(get: {
            store.noteEditorCommand
        }, set: { value in
            store.noteEditorCommand = value
        }),
        editingSession: store.noteEditingSession,
        isEditable: true,
        isFocused: paneState.focusedPane == .notes,
        focusRequest: paneState.focusRequest,
        markdownBaseURL: store.currentMarkdownBaseURL,
        attachmentDirectory: store.currentAttachmentDirectory,
        appearanceMode: store.appearanceMode,
        interfaceLanguage: store.interfaceLanguage,
        onSelectionChange: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
        }, onSelectionFormattingChange: { formatting in
            store.interaction.noteSelectionFormatting = formatting
        }, onLinkEditorRequest: {
            store.interaction.noteLinkEditorRequest &+= 1
        }, onAskAgentWithSelection: { text, anchor in
            store.noteEditingSession.requestSnapshot()
            store.updateSelection(text, source: .note, anchor: anchor)
            store.askSelection()
        }, onActiveHeadingChange: { index in
            activeNoteRailID = index.map { "note-heading-\($0)" }
        }, onOutlineChange: { items in
            noteOutline = items
        }, onWikiLink: { title in
            store.openOrCreateWikiNote(title: title)
        }, onSourceReference: { reference in
            store.openSourceReference(reference)
        }, onRenderReady: {
            guard recoveryGeneration == editorRecoveryGeneration else { return }
            editorRecoveryState.renderBecameReady()
        }, onRenderFailure: {
            guard recoveryGeneration == editorRecoveryGeneration else { return }
            store.noteEditingSession.invalidateBridgeGeneration()
            Task { await store.reconcileActiveNoteEditorWithBackingFile() }
            if editorRecoveryState.renderFailed() {
                editorRecoveryGeneration &+= 1
            }
        }, onContentCommandPending: { documentID, command in
            store.noteEditorContentCommandPending(command, documentID: documentID)
        }, onContentCommandApplied: { documentID, command in
            store.noteEditorContentCommandApplied(command, documentID: documentID)
        }, onCommandRejected: { documentID, command in
            store.noteEditorCommandRejected(command, documentID: documentID)
        })
        .id("\(store.activeNoteEditorDocumentID):\(editorRecoveryGeneration)")
        .background(WeiBeiTheme.paper)
    }

}

enum EditorRecoveryState: Equatable {
    case idle
    case rebuilding
    case stopped

    mutating func renderFailed() -> Bool {
        guard self == .idle else {
            self = .stopped
            return false
        }
        self = .rebuilding
        return true
    }

    mutating func renderBecameReady() {
        guard self != .stopped else { return }
        self = .idle
    }

    mutating func retryManually() {
        self = .idle
    }
}

private struct NoteSaveStatusLabel: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject var session: NoteEditingSession

    var body: some View {
        if let title {
            Text(title)
                .weiBeiText(10.5, weight: .medium)
                .foregroundStyle(
                    store.activeNoteSaveStatus == .failed
                        || store.activeNoteSaveStatus == .externallyModified
                        ? WeiBeiTheme.cinnabar
                        : WeiBeiTheme.secondaryInk
                )
                .lineLimit(1)
                .accessibilityLabel(Text(title))
        }
    }

    private var title: String? {
        guard store.activeNoteSaveStatus.showsStatusLabel else { return nil }
        switch store.activeNoteSaveStatus {
        case .saving:
            return store.ui("保存中", "Saving")
        case .failed:
            return store.ui("保存失败", "Save Failed")
        case .externallyModified:
            return store.ui("外部修改", "Modified Externally")
        case .idle, .writtenToFile, .savedInWeiBei:
            return nil
        }
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
                .weiBeiText(12, weight: .semibold)
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
            .weiBeiText(15, weight: .medium)
            .foregroundColor(WeiBeiTheme.ink)
            .focused($focused)
            .onSubmit(confirm)
            .frame(maxWidth: .infinity)
            .frame(height: 24)

            Button(action: confirm) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.plain)
            .weiBeiText(15, weight: .semibold)
            .foregroundStyle(confirmColor)
            .frame(width: 28, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(confirmBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(confirmBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
            .weiBeiText(15, weight: .semibold)
            .foregroundStyle(cancelColor)
            .frame(width: 28, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(cancelBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(cancelBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
            RoundedRectangle(cornerRadius: 8)
                .fill(WeiBeiTheme.paperInset.opacity(0.24))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
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
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onRenderReady: () -> Void = {}
    var onFinalizedSnapshotReady: (CGFloat) -> Void = { _ in }
    var onRenderFailure: () -> Void = {}
    var onSelectionChange: (String, CGPoint?) -> Void = { _, _ in }
    var onContentHeightChange: () -> Void = {}
    private static let compactPreviewLoadingHeight: CGFloat = 44
    private static let compactPreviewMaximumHeight: CGFloat = 20_000

    static func resolvedContentHeight(
        current: CGFloat,
        proposed: CGFloat,
        preservesCurrentFloor: Bool
    ) -> CGFloat {
        preservesCurrentFloor ? max(current, proposed) : proposed
    }

    var onMeasuredHeight: (CGFloat) -> Void = { _ in }
    @State private var command: NoteEditorCommand?
    @State private var contentHeight: CGFloat = Self.compactPreviewLoadingHeight
    @State private var heightFrozen = false
    @State private var acceptedMeasureCount = 0
    @State private var maxObservedMeasuredHeight: CGFloat = 0
    @State private var hasAcceptedStreamingHeight = false
    /// Post-completion height floor: once this row has shown streamed text, a
    /// later shrink (caret row unwrap, tail blank settling after finalize)
    /// never re-anchors the reader. Width-bucket and typography resets clear it.
    @State private var everStreamedHeight = false
    @State private var preservesFinalizedHeightFloor = false
    @State private var finalizedStreamingMarkdown: String?
    @State private var lastLayoutWidthKey = 0
    @State private var lastChatWideTypography = false

    var body: some View {
        RichMarkdownEditorView(
            markdown: markdown,
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
                if streamsMarkdownUpdates {
                    hasAcceptedStreamingHeight = true
                    everStreamedHeight = true
                }
                // Mid-stream markdown converges downward too: loose paragraphs
                // become tight lists once markers arrive, trailing blanks collapse,
                // withheld formulas land as blocks. Accepting the shrink yanks a
                // bottom-anchored reader upward mid-stream; real convergence is
                // settled by the finalized receipt and the width-bucket resets.
                // everStreamedHeight extends the floor past completion: the caret
                // decoration row unwraps and tail blanks settle up to ~600ms
                // AFTER the finalized receipt, when the floor flags above have
                // already been cleared by markdown-changed bookkeeping.
                if preservesFinalizedHeightFloor || streamsMarkdownUpdates || everStreamedHeight,
                   nextFrameHeight < contentHeight {
                    WeiBeiPerf.event(
                        "webview.markdown_height_ignored",
                        extra: preservesFinalizedHeightFloor
                            ? "reason=finalized-floor"
                            : (streamsMarkdownUpdates ? "reason=streaming-floor" : "reason=poststream-floor")
                    )
                    onMeasuredHeight(contentHeight)
                    return
                }
                if freezeHeightAfterMeasure, heightFrozen {
                    // Keep rejecting recycled-row shrink and jitter, but accept
                    // real late growth from Mermaid, formulas, fonts or images.
                    if allowsHeightFreeze || nextFrameHeight < contentHeight + 2 {
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
                // Instant apply: an eased frame lags the WebView content for the
                // animation's duration and .clipped() cuts the last wrapped
                // line mid-flight. Growth now arrives in streaming-sized steps
                // (the web side types the completion tail out), so there is no
                // large snap left to smooth.
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
                preservesFinalizedHeightFloor = preservesHeightAcrossMarkdownChanges
                    && hasAcceptedStreamingHeight
                let settledHeight = Self.resolvedContentHeight(
                    current: contentHeight,
                    proposed: nextFrameHeight,
                    preservesCurrentFloor: preservesFinalizedHeightFloor
                )
                let didChangeHeight = settledHeight != contentHeight
                heightFrozen = false
                acceptedMeasureCount = 0
                contentHeight = settledHeight
                maxObservedMeasuredHeight = settledHeight
                onMeasuredHeight(measuredHeight)
                if didChangeHeight {
                    onContentHeightChange()
                }
                onFinalizedSnapshotReady(settledHeight)
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
            hasAcceptedStreamingHeight = false
            everStreamedHeight = false
            preservesFinalizedHeightFloor = false
            finalizedStreamingMarkdown = nil
            heightFrozen = false
            acceptedMeasureCount = 0
            maxObservedMeasuredHeight = 0
        }
        .onChange(of: isChatWideTypography) { _, wideTypography in
            guard wideTypography != lastChatWideTypography else { return }
            lastChatWideTypography = wideTypography
            hasAcceptedStreamingHeight = false
            everStreamedHeight = false
            preservesFinalizedHeightFloor = false
            finalizedStreamingMarkdown = nil
            heightFrozen = false
            acceptedMeasureCount = 0
            maxObservedMeasuredHeight = 0
        }
        .onChange(of: markdown) { _, nextMarkdown in
            guard compact && fitsContentHeight else { return }
            if !streamsMarkdownUpdates {
                if hasAcceptedStreamingHeight,
                   finalizedStreamingMarkdown == nil {
                    finalizedStreamingMarkdown = nextMarkdown
                    preservesFinalizedHeightFloor = preservesHeightAcrossMarkdownChanges
                } else if finalizedStreamingMarkdown != nextMarkdown {
                    hasAcceptedStreamingHeight = false
                    preservesFinalizedHeightFloor = false
                    finalizedStreamingMarkdown = nil
                }
            }
            heightFrozen = false
            acceptedMeasureCount = 0
            maxObservedMeasuredHeight = 0
            if preservesHeightAcrossMarkdownChanges { return }
            contentHeight = Self.compactPreviewLoadingHeight
            onContentHeightChange()
        }
        .onChange(of: streamsMarkdownUpdates) { wasStreaming, isStreaming in
            if isStreaming {
                hasAcceptedStreamingHeight = false
                preservesFinalizedHeightFloor = false
                finalizedStreamingMarkdown = nil
            } else if wasStreaming, hasAcceptedStreamingHeight {
                finalizedStreamingMarkdown = markdown
                preservesFinalizedHeightFloor = preservesHeightAcrossMarkdownChanges
            }
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
    static let composerHeight: CGFloat = 52
    static let composerFontSize: CGFloat = 15

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
}

struct AgentPaneView: View {
    @Environment(\.weiBeiTextScale) private var textScale
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil
    @FocusState private var draftFocused: Bool
    @State private var activeAgentRailID: String?
    @State private var agentFollowsLatest = true
    @State private var sessionPendingDeletion: StudySession?
    @State private var sessionRenameDraft = ""
    @State private var isRenamingSession = false
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
    /// History grows one page at a time; measured distant rows may release their views.
    @State private var agentVisibleMessageLimit = AgentPaneView.agentHistoryPageSize
    @State private var isRevealingEarlierAgentHistory = false
    @State private var isAgentHistoryRevealButtonHovered = false
    /// Turn-start rows report reading-line crossings here at scroll rate. A
    /// reference type on purpose: per-event dictionary writes must not publish
    /// SwiftUI state; only the derived activeAgentRailID write renders.
    @State private var turnReadingPositions = AgentTurnReadingPositionModel()
    /// Far-row IDs represented by their measured row heights. Empty unless the
    /// unload flag is on; published only when the set changes, not per scroll pixel.
    @State private var offscreenPlaceholderIDs: Set<UUID> = []

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
        // One O(n) set per render — row backgrounds only do Set.contains.
        let railTurnStartMessageIDs = showsContentRail ? agentRailTurnStartMessageIDs : []
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
            let composerHeight = AgentChatLayoutMetrics.composerHeight
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
                            // Stable native rows; history expands on demand. Only measured
                            // rows well beyond the viewport release their rendering views.
                            VStack(alignment: .leading, spacing: comfy ? 22 : 12) {
                                if hiddenAgentHistoryCount > 0 {
                                    agentHistoryRevealButton(proxy: proxy)
                                        .transition(WeiBeiTransition.message)
                                }
                                ForEach(visibleAgentMessages) { message in
                                    AgentMessageViewportGatedRow(
                                        isPlaceholder: offscreenPlaceholderIDs.contains(message.id),
                                        placeholderHeight: AgentMessageViewportWindow.cachedHeight(
                                            message: message,
                                            layoutWidth: markdownContentWidth,
                                            wideTypography: comfy,
                                            textScale: textScale
                                        )
                                    ) {
                                        agentMessageRow(
                                            message: message,
                                            contentWidth: contentWidth,
                                            wide: wide
                                        )
                                        .background {
                                            GeometryReader { geometry in
                                                Color.clear
                                                    .onAppear { cacheMessageHeight(geometry.size.height, message: message, width: markdownContentWidth, wide: comfy) }
                                                    .onChange(of: geometry.size.height) { _, height in
                                                        cacheMessageHeight(height, message: message, width: markdownContentWidth, wide: comfy)
                                                    }
                                            }
                                        }
                                    }
                                    .background {
                                        if railTurnStartMessageIDs.contains(message.id) {
                                            AgentTurnReadingPositionProbe(messageID: message.id) {
                                                handleTurnReadingPosition(messageID: $0, passed: $1)
                                            }
                                        }
                                    }
                                }
                                if store.isAgentRunningInActiveChat
                                    && !store.hasPersistedGeneratingAgentReply
                                {
                                    agentReadingColumn(
                                        alignment: .leading
                                    ) {
                                        AgentLiveResponse(
                                            streaming: store.agentStreaming,
                                            isChatWideTypography: comfy
                                        )
                                    }
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
                            .offset(y: initialComposerOffset(
                                paneHeight: paneGeometry.size.height,
                                headerHeight: headerHeight,
                                composerHeight: composerHeight
                            ))
                            .animation(
                                reduceMotion ? nil : .smooth(duration: 0.42),
                                value: paneState.centersInitialAgentComposer
                            )
                            .animation(WeiBeiMotion.panel, value: store.layout)
                            .animation(WeiBeiMotion.panel, value: wide)
                    }
                    .overlay(alignment: .bottom) {
                        if showsJumpToLatest {
                            jumpToLatestButton(proxy: proxy)
                                .padding(.bottom, composerHeight + 34)
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
                            onActivate: { activateAgentRailItem($0, railOnly: railOnly, proxy: proxy) },
                            motionPreference: store.motionPreference
                        )
                        .zIndex(4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
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
                    } else if !railOnly {
                        // Match notes: floating slip overlay only — no extra clear ZStack.
                        ImmersiveHoverTitleView(
                            mark: "CHAT",
                            title: store.agentConversationSubtitle,
                            appearanceMode: store.appearanceMode,
                            reorderRole: reorderRole
                        ) {
                            sessionMenu
                        }
                    }
                }
                .onChange(of: store.messages.map(\.id)) { oldIDs, newIDs in
                    if oldIDs.isEmpty, !newIDs.isEmpty {
                        paneState.dockInitialAgentComposer()
                    }
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
                    turnReadingPositions.passedByMessageID.removeAll()
                    activeAgentRailID = nil
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
        .onChange(of: paneState.focusRequest) { _, _ in
            draftFocused = paneState.focusedPane == .agent
        }
        .onAppear {
            draftFocused = paneState.focusedPane == .agent
            if usesWideChatLayout, measuredPaneWidth < 700 {
                measuredPaneWidth = max(measuredPaneWidth, 1100)
            }
        }
        .alert(
            store.ui("重命名会话", "Rename Chat"),
            isPresented: $isRenamingSession
        ) {
            TextField(store.ui("会话名称", "Chat name"), text: $sessionRenameDraft)
            Button(store.ui("取消", "Cancel"), role: .cancel) {}
            Button(store.ui("保存", "Save")) {
                if let sessionID = store.activeStudySessionID {
                    store.renameStudySession(sessionID, title: sessionRenameDraft)
                }
            }
            .disabled(sessionRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

        // Native text rows: no per-message WKWebView height callbacks that thrash scroll.
        return agentReadingColumn(
            alignment: isUser ? .trailing : .leading
        ) {
            // One view type owns the row across the generating → completed flip,
            // so the markdown surface is never torn down at completion. Only the
            // generating row observes the live streaming state; completed rows
            // observe a state that never publishes.
            AgentMessageBubble(
                message: message,
                streaming: message.completionState == .generating
                    || store.agentStreaming.isDisplaying(message.id)
                    ? store.agentStreaming
                    : inertAgentStreamingState,
                // Typography follows the real column width, not the layout enum.
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
        alignment: HorizontalAlignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let readingWidth = AgentChatLayoutMetrics.wideMaxWidth
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

    /// Rows whose message starts a rail turn — the only rows that need a
    /// reading-position probe. Rail ticks are turns, not messages.
    private var agentRailTurnStartMessageIDs: Set<UUID> {
        Set(agentRailTurns.map(\.startMessageID))
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
            store.requestPaneExpansion(.agent, onCompleted: navigate)
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

    /// Mirrors the web editors' reading-line rule: the rail marks the last
    /// turn whose question row top has crossed the upper third of the viewport.
    private func handleTurnReadingPosition(messageID: UUID, passed: Bool) {
        guard turnReadingPositions.passedByMessageID[messageID] != passed else { return }
        turnReadingPositions.passedByMessageID[messageID] = passed
        let turns = agentRailTurns
        guard let activeTurn = turns.last(where: {
            turnReadingPositions.passedByMessageID[$0.startMessageID] == true
        }) ?? turns.first else { return }
        let id = "chat-turn-\(activeTurn.id.uuidString)"
        if activeAgentRailID != id {
            activeAgentRailID = id
        }
    }

    private func handleScrollMetrics(_ metrics: AgentScrollMetrics, proxy: ScrollViewProxy) {
        refreshOffscreenPlaceholders(
            viewportMinY: metrics.distanceFromTop,
            viewportHeight: metrics.visibleHeight
        )
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
                .weiBeiText(13, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(Circle().fill(WeiBeiTheme.paperRaised))
                .overlay(Circle().stroke(WeiBeiTheme.hairline.opacity(0.6), lineWidth: 1))
                .shadow(color: WeiBeiTheme.ink.opacity(0.14), radius: 9, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.ui("回到最新消息", "Jump to latest"))
    }

    private func cacheMessageHeight(_ height: CGFloat, message: AgentMessage, width: CGFloat, wide: Bool) {
        AgentFinalizedMarkdownHeightCache.store(height, for: AgentFinalizedMarkdownHeightCache.cacheKey(
            messageID: message.id, text: message.text,
            widthBucket: AgentFinalizedMarkdownHeightCache.widthBucket(width),
            wideTypography: wide, textScale: textScale
        ))
    }

    private func refreshOffscreenPlaceholders(viewportMinY: CGFloat, viewportHeight: CGFloat) {
        let width = AgentChatLayoutMetrics.contentWidth(availableWidth: heldPaneLayoutWidth ?? agentPaneWidth, wide: usesWideChatLayout)
        let next = AgentMessageViewportWindow.placeholderIDs(
            enabled: AgentChatOffscreenUnloadFlag.isEnabled,
            messages: Array(visibleAgentMessages),
            layoutWidth: width,
            wideTypography: usesWideChatLayout
                || width >= AgentChatLayoutMetrics.wideTypographyMinContentWidth,
            textScale: textScale,
            viewportMinY: viewportMinY,
            viewportHeight: viewportHeight,
            spacing: usesWideChatLayout ? 22 : 12
        )
        if next != offscreenPlaceholderIDs {
            offscreenPlaceholderIDs = next
        }
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
                    .weiBeiText(9.5, weight: .semibold)
                Text(store.ui("查看更早的 \(revealCount) 条消息", "Show \(revealCount) earlier messages"))
                    .weiBeiText(12, weight: .medium)
            }
                .foregroundStyle(isAgentHistoryRevealButtonHovered ? WeiBeiTheme.link : WeiBeiTheme.secondaryInk)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .weibeiEtchedCapsuleBackground(
                    fill: WeiBeiTheme.paperInset.opacity(isAgentHistoryRevealButtonHovered ? 0.42 : 0.24),
                    stroke: WeiBeiTheme.hairline.opacity(isAgentHistoryRevealButtonHovered ? 0.72 : 0.44),
                    contactShadow: isAgentHistoryRevealButtonHovered
                )
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
        let minHeight = AgentChatLayoutMetrics.composerHeight
        let fontSize = AgentChatLayoutMetrics.composerFontSize
        // ChatGPT-like: the tray shares the exact conversation paper — no
        // gradient strip, no glass seam, no divider. The rounded field alone
        // separates input from messages.
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                AgentUnconfiguredHint(store: store)

                if store.hasSelectionAttachments {
                    AgentSelectionAttachmentPill()
                        .transition(WeiBeiTransition.floating)
                }

                ComposerView(
                    prompt: agentPrompt,
                    focused: $draftFocused,
                    fontSize: fontSize,
                    lineLimit: nil,
                    height: minHeight,
                    sendButtonSize: 28,
                    trailingPadding: wide ? 48 : 40,
                    sendTrailing: wide ? 8 : 10,
                    horizontalPadding: wide ? 16 : 12,
                    verticalPadding: 8
                ) {
                    submitAgentDraft()
                }
            }
            .weiBeiText(fontSize)
            .frame(maxWidth: AgentChatLayoutMetrics.wideMaxWidth, alignment: .bottom)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(wide ? "agent-input-tray-wide" : "agent-input-tray-compact")
        }
        .background(WeiBeiTheme.paper)
    }

    private func initialComposerOffset(
        paneHeight: CGFloat,
        headerHeight: CGFloat,
        composerHeight: CGFloat
    ) -> CGFloat {
        guard paneState.centersInitialAgentComposer, store.messages.isEmpty else { return 0 }
        let trayHeight = composerHeight + 16
        let availableHeight = max(paneHeight - headerHeight, trayHeight)
        return -(availableHeight - trayHeight) * 0.45
    }

    private func submitAgentDraft() {
        let hasPrompt = !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasPrompt {
            paneState.dockInitialAgentComposer()
        }
        store.submitAgentDraft()
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

    private var agentScrollBottomInset: CGFloat {
        // Fixed inset only — tray GeometryReader preference → LazyVStack height feedback
        // re-entered sizeThatFits every scroll frame and froze the app.
        // Tray already sits outside the ScrollView (VStack), so keep this small;
        // large fixed insets stole message viewport height and made immersive feel tiny.
        usesWideChatLayout ? 16 : 12
    }

    private var agentRailBottomInset: CGFloat {
        usesWideChatLayout ? 120 : 100
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
                let courseSessions = store.studySessions(in: courseID)
                ForEach(courseSessions.prefix(30)) { session in
                    sessionMenuButton(session)
                }
                if courseSessions.count > 30 {
                    Button(store.ui(
                        "查看全部 \(courseSessions.count) 个对话",
                        "View all \(courseSessions.count) chats"
                    )) {
                        store.presentCourseWorkspace(.sessions, courseID: courseID)
                    }
                }
            }
        }

        if !store.historicalStudySessions.isEmpty {
            Section(store.ui("全部对话", "All Chats")) {
                ForEach(store.historicalStudySessions.prefix(30)) { session in
                    sessionMenuButton(session)
                }
                if store.historicalStudySessions.count > 30,
                   let courseID = store.activeCourseID {
                    Button(store.ui(
                        "查看全部 \(store.historicalStudySessions.count) 个对话",
                        "View all \(store.historicalStudySessions.count) chats"
                    )) {
                        store.presentCourseWorkspace(.sessions, courseID: courseID)
                    }
                }
            }
        }

        if let active = store.activeStudySession,
           !active.messages.isEmpty {
            Divider()
            Button {
                sessionRenameDraft = active.title
                isRenamingSession = true
            } label: {
                Label(store.ui("重命名当前会话", "Rename Current Chat"), systemImage: "pencil")
            }
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
            if store.isAgentRunning(in: session.id) {
                Label(session.title + store.ui(" · 处理中", " · Working"), systemImage: "ellipsis.circle")
            } else if session.id == store.activeStudySessionID {
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
        let chatID = store.activeStudySessionID
        DispatchQueue.main.async {
            guard agentFollowsLatest, store.activeStudySessionID == chatID else { return }
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)
            }
        }
        // WebView rows publish height on a ~100ms cadence, so the animated
        // pass targets a bottom anchor that is already stale once the next
        // measurement lands — the viewport then gets shoved again. A silent
        // re-anchor after the reporting window keeps the follow settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard agentFollowsLatest, store.activeStudySessionID == chatID else { return }
            proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)
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
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @State private var pillHovering = false
    @State private var popoverHovering = false
    @State private var closeToken = UUID()

    var body: some View {
        if !interaction.selectionAttachments.isEmpty {
            HStack(spacing: 4) {
                // Popover anchor is only the label — keep the clear button outside so the first
                // click is not eaten by hover-popover dismissal.
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .weiBeiText(12, weight: .medium)
                    Text(store.ui("\(interaction.selectionAttachments.count) 个已选文本片段", "\(interaction.selectionAttachments.count) selected text fragments"))
                        .weiBeiText(12, weight: .medium)
                }
                .contentShape(Rectangle())
                .onHover { value in
                    setPillHovering(value)
                }
                .popover(isPresented: popoverPresented, arrowEdge: .bottom) { popoverContent }

                Button(action: clearAllAttachments) {
                    Image(systemName: "xmark")
                        .weiBeiText(9.5, weight: .semibold)
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 18))
                .accessibilityLabel(Text(store.ui("清空已选文本片段", "Clear selected text fragments")))
                .help(store.ui("清空已选文本片段", "Clear selected text fragments"))
            }
            .foregroundStyle(pillHovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 28)
            .weibeiEtchedBackground(
                fill: WeiBeiTheme.paperRaised.opacity(pillHovering ? 0.72 : 0.54),
                stroke: WeiBeiTheme.hairline.opacity(pillHovering ? 0.68 : 0.38),
                cornerRadius: 8,
                contactShadow: pillHovering
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(Text(store.ui("\(interaction.selectionAttachments.count) 个已选文本片段", "\(interaction.selectionAttachments.count) selected text fragments")))
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
                Text(store.ui("\(interaction.selectionAttachments.count) 个已选文本片段", "\(interaction.selectionAttachments.count) selected text fragments"))
                    .weiBeiText(12, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer()
                Text(store.ui("发问时会作为上下文", "Used as context when asking"))
                    .weiBeiText(10.5, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Button(store.ui("清空", "Clear")) {
                    clearAllAttachments()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .help(store.ui("清空全部选区片段", "Clear all selected fragments"))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(interaction.selectionAttachments.enumerated()), id: \.element.id) { index, selection in
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
                    .weiBeiText(12, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(selection.ownerTitle)
                    .weiBeiText(10.5, weight: .medium)
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 8)
                Button {
                    let shouldClose = interaction.selectionAttachments.count <= 1
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
                .weiBeiText(12)
                .lineSpacing(3)
                .lineLimit(5)
                .foregroundStyle(WeiBeiTheme.ink)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 1)
        }
        .padding(9)
        .weibeiEtchedBackground(
            fill: WeiBeiTheme.paperInset.opacity(0.32),
            stroke: WeiBeiTheme.hairline.opacity(0.36),
            cornerRadius: 8
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    let text: String

    var body: some View {
        Text(cleanedText)
            .weiBeiText(12, weight: .medium)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(text))
    }

    private var cleanedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}

struct FloatingSelectionAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @Binding var expanded: Bool
    var routesToConversation = false
    @State private var dragOffset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    @State private var panelWidth = CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2)
    @State private var userFeedHeight: CGFloat?
    @State private var measuredFeedContentHeight = CGFloat(SelectionFloatingAgentPlacement.minimumAutomaticContentHeight)
    @State private var previousFeedContentHeight: CGFloat?
    @State private var feedHeightLocked = false
    @State private var resizeOrigin: FloatingAgentSize?
    @State private var resizeOriginOffset: CGSize?
    @State private var linkDraft = ""
    @State private var showsLinkEditor = false
    @FocusState private var draftFocused: Bool
    @FocusState private var linkFocused: Bool
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
        .animation(WeiBeiMotion.panel, value: interaction.pinnedFloatingAgent)
        .animation(WeiBeiMotion.panel, value: store.isAgentRunningInActiveChat)
        .offset(
            x: dragOffset.width + settledOffset.width,
            y: dragOffset.height + settledOffset.height + floatingFeedGrowthOffset
        )
        .onChange(of: interaction.selectionContext) { previous, next in
            guard !interaction.pinnedFloatingAgent, !store.isAgentRunningInActiveChat else { return }
            let sameContent = previous?.text == next?.text
                && previous?.source == next?.source
                && previous?.ownerTitle == next?.ownerTitle
                && previous?.isEditable == next?.isEditable
            guard !sameContent else { return }
            // Reopen uses SelectionContext.id == thread.id — expand beside the mark.
            let isThreadReopen = next.map { interaction.activeSelectionAskThreadID == $0.id } ?? false
            if isThreadReopen, interaction.keepFloatingSelectionForAnswer {
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
                interaction.keepFloatingSelectionForAnswer = false
                interaction.activeSelectionAskThreadID = nil
                dragOffset = .zero
                settledOffset = .zero
            }
        }
        .onChange(of: interaction.keepFloatingSelectionForAnswer) { _, keep in
            if keep {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
            }
        }
        .onChange(of: interaction.activeSelectionAskThreadID) { _, id in
            if id != nil, interaction.keepFloatingSelectionForAnswer {
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
        .onChange(of: paneState.focusRequest) { _, _ in
            draftFocused = paneState.focusedPane == .agent
        }
        .onAppear {
            draftFocused = paneState.focusedPane == .agent
            if interaction.pinnedFloatingAgent || store.isAgentRunningInActiveChat || interaction.keepFloatingSelectionForAnswer {
                expanded = true
            }
        }
        .onExitCommand {
            // 两段式 Esc:先收成胶囊,再按才整体关闭;流式/固定状态下保持直接关闭。
            if showsExpandedBody && !store.isAgentRunningInActiveChat && !interaction.pinnedFloatingAgent {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = false
                    store.keepFloatingSelectionForAnswer = false
                }
            } else {
                closeFloatingAgent()
            }
        }
        .onChange(of: interaction.floatingComposerMode) { _, mode in
            if mode == .ask { focusAskComposerUntilFocused() }
        }
    }

    private var showsExpandedBody: Bool {
        // Capsule for bare selection; expand for 问 / pin / stream / 红线回访(keepOpen).
        expanded || interaction.pinnedFloatingAgent || store.isAgentRunningInActiveChat || interaction.keepFloatingSelectionForAnswer
    }

    private var promptBody: some View {
        Group {
            if showsNoteFormattingToolbar {
                noteFormattingToolbar
            } else {
                defaultPromptBody
            }
        }
    }

    private var defaultPromptBody: some View {
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
                Button(store.ui("记", "Remark")) {
                    openRemarkComposer()
                }
                .foregroundStyle(WeiBeiTheme.link)
                .accessibilityLabel(Text(store.ui("记下这段", "Remark on this passage")))
                .help(store.ui("记下这段(留空只存原文)", "Remark on this passage (empty saves excerpt only)"))
            }
        }
        .weiBeiText(12, weight: .semibold)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .fixedSize()
    }

    private var showsNoteFormattingToolbar: Bool {
        store.selectionContext?.isReplaceableNoteSelection == true
    }

    private var noteFormattingToolbar: some View {
        HStack(spacing: 2) {
            formattingButton("bold", icon: "bold", label: store.ui("加粗", "Bold"))
            formattingButton("italic", icon: "italic", label: store.ui("斜体", "Italic"))
            formattingButton("strike", icon: "strikethrough", label: store.ui("删除线", "Strikethrough"))
            formattingButton("highlight", icon: "highlighter", label: store.ui("高亮", "Highlight"))
            Button {
                linkDraft = interaction.noteSelectionFormatting?.linkTarget ?? ""
                showsLinkEditor = true
                DispatchQueue.main.async { linkFocused = true }
            } label: {
                Image(systemName: "link")
            }
            .buttonStyle(WeiBeiIconButtonStyle(active: isFormattingActive("link"), size: 30, cornerRadius: 4))
            .help(store.ui("链接", "Link"))
            .accessibilityLabel(Text(store.ui("链接", "Link")))
            .popover(isPresented: $showsLinkEditor, arrowEdge: .bottom) {
                linkEditor
            }
            .onChange(of: interaction.noteLinkEditorRequest) { _, _ in
                guard interaction.noteSelectionFormatting != nil else { return }
                linkDraft = interaction.noteSelectionFormatting?.linkTarget ?? ""
                showsLinkEditor = true
                DispatchQueue.main.async { linkFocused = true }
            }

            formattingButton("inlineCode", icon: "chevron.left.forwardslash.chevron.right", label: store.ui("行内代码", "Inline code"))
            formattingButton(
                "inlineMath",
                icon: "function",
                label: isFormattingActive("inlineMath") ? store.ui("转回文字", "Convert to text") : store.ui("转为行内公式", "Convert to formula"),
                enabled: interaction.noteSelectionFormatting?.canConvertToMath == true
            )
            formattingButton("quote", icon: "text.quote", label: store.ui("引用", "Quote"), active: interaction.noteSelectionFormatting?.blockType == "blockquote")

            promptSeparator
            writingFontMenu
            promptSeparator
            Button(store.ui("问", "Ask")) { openExpandedComposer() }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                .accessibilityLabel(Text(store.ui("就这段提问", "Ask about this passage")))
                .help(store.ui("就这段提问", "Ask about this passage"))
        }
        .weiBeiText(12, weight: .semibold)
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .fixedSize()
    }

    private var writingFontMenu: some View {
        let current = WeiBeiWritingFont.allCases.first { isFormattingActive("font:\($0.rawValue)") }
        return Menu {
            ForEach(WeiBeiWritingFont.allCases) { font in
                Button {
                    runSelectionCommand("font", value: font.rawValue)
                } label: {
                    HStack {
                        Text(font.displayName)
                        if font == current {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "textformat")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 30, cornerRadius: 4))
        .help(current.map { store.ui("选中文字字体：\($0.displayName)", "Selected font: \($0.displayName)") }
            ?? store.ui("更改选中文字字体", "Change selected font"))
        .accessibilityLabel(Text(store.ui("更改选中文字字体", "Change selected font")))
    }

    private func formattingButton(
        _ action: String,
        icon: String,
        label: String,
        enabled: Bool = true,
        active: Bool? = nil
    ) -> some View {
        Button { runSelectionCommand(action) } label: {
            Image(systemName: icon)
        }
        .buttonStyle(WeiBeiIconButtonStyle(active: active ?? isFormattingActive(action), size: 30, cornerRadius: 4))
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(Text(label))
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.ui("链接地址", "Link address"))
                .weiBeiText(12, weight: .semibold)
            TextField("https://", text: $linkDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .focused($linkFocused)
                .onSubmit { commitLink() }
            HStack {
                if isFormattingActive("link") {
                    Button(store.ui("移除链接", "Remove link")) {
                        linkDraft = ""
                        commitLink()
                    }
                }
                Spacer()
                Button(store.ui("取消", "Cancel")) { showsLinkEditor = false }
                Button(store.ui("完成", "Done")) { commitLink() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .onExitCommand { showsLinkEditor = false }
    }

    private func isFormattingActive(_ action: String) -> Bool {
        let mark = action == "bold" ? "strong"
            : action == "italic" ? "emphasis"
            : action == "strike" ? "strike_through"
            : action
        return interaction.noteSelectionFormatting?.activeMarks.contains(mark) == true
    }

    private func runSelectionCommand(_ action: String, value: String? = nil) {
        store.noteEditorCommand = NoteEditorCommand(kind: .selectionCommand, markdown: action, value: value)
    }

    private func commitLink() {
        runSelectionCommand("link", value: linkDraft)
        showsLinkEditor = false
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
                FloatingAgentModeSwitch()
                if let selection = store.selectionContext?.text, !selection.isEmpty {
                    FloatingSelectionPreview(text: selection)
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(WeiBeiMotion.micro) { togglePinnedFloatingAgent() }
                } label: {
                    Image(systemName: store.pinnedFloatingAgent ? "pin.fill" : "pin")
                        .weiBeiText(12, weight: .semibold)
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
                        .weiBeiText(10.5, weight: .bold)
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
            .contentShape(Rectangle())
            .gesture(moveFloatingAgentGesture)

            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if showsFloatingFeed {
                ScrollView(showsIndicators: false) {
                    // Same order as immersive chat: messages → streaming → thinking.
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleFloatingMessages) { message in
                            FloatingSelectionMessageRow(
                                message: message,
                                streaming: message.completionState == .generating
                                    || store.agentStreaming.isDisplaying(message.id)
                                    ? store.agentStreaming
                                    : inertAgentStreamingState
                            )
                        }

                        if store.isAgentRunningInActiveChat
                            && !store.hasPersistedGeneratingAgentReply {
                            AgentLiveResponse(
                                streaming: store.agentStreaming,
                                compact: true
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .environment(\.agentChatLayoutWidth, max(panelWidth - 28, 1))
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: FloatingSelectionFeedHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                }
                .frame(height: resolvedFloatingFeedHeight)
                .onPreferenceChange(FloatingSelectionFeedHeightKey.self) { height in
                    guard userFeedHeight == nil, !feedHeightLocked, height > 1,
                          abs(height - measuredFeedContentHeight) > 1 else { return }
                    // Two-state oscillation lock: the LazyVStack row set depends on the
                    // frame height, so an A/B alternation means this measure-writeback
                    // loop cannot converge. Lock instead of churning layout (and
                    // re-entering the AttributeGraph cycle) on every frame.
                    if let previousFeedContentHeight,
                       abs(height - previousFeedContentHeight) <= 1 {
                        feedHeightLocked = true
                        return
                    }
                    previousFeedContentHeight = measuredFeedContentHeight
                    measuredFeedContentHeight = height
                }
            }

            composerField
        }
        .frame(width: panelWidth, alignment: .leading)
        .overlay {
            floatingResizeBorder
        }
        .onChange(of: showsFloatingFeed) { _, _ in
            unlockFeedHeightFeedback()
        }
        .onChange(of: visibleFloatingMessages.count) { _, _ in
            unlockFeedHeightFeedback()
        }
        .onAppear {
            draftFocused = true
        }
    }

    /// 问/记共用同一浮层,底部输入框按模式切换;两种草稿互不覆盖。
    @ViewBuilder private var composerField: some View {
        if interaction.floatingComposerMode == .remark {
            SelectionRemarkField {
                submitRemark()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 5)
        } else {
            ComposerView(
                prompt: showsFloatingFeed
                    ? store.ui("再问一点…", "Ask a follow-up…")
                    : store.ui("问点什么…", "Ask anything…"),
                focused: $draftFocused,
                fontSize: 15,
                lineLimit: 1...5,
                height: SelectionFloatingAgentPlacement.expandedComposerCollapsedHeight,
                compactMaxHeight: SelectionFloatingAgentPlacement.expandedComposerMaxHeight,
                sendButtonSize: 26,
                trailingPadding: 38,
                sendTrailing: 4,
                horizontalPadding: 2,
                verticalPadding: 4,
                showsChrome: false
            ) {
                sendDraft()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 5)
        }
    }

    private func unlockFeedHeightFeedback() {
        feedHeightLocked = false
        previousFeedContentHeight = nil
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

    private var resolvedFloatingFeedHeight: CGFloat {
        userFeedHeight ?? CGFloat(
            SelectionFloatingAgentPlacement.automaticContentHeight(
                measuredContentHeight: Double(measuredFeedContentHeight)
            )
        )
    }

    private var floatingFeedGrowthOffset: CGFloat {
        showsFloatingFeed ? resolvedFloatingFeedHeight / 2 : 0
    }

    private var moveFloatingAgentGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
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
    }

    private var floatingResizeBorder: some View {
        ZStack {
            FloatingSelectionResizeHitRegion(edge: .top, cursor: .resizeUpDown, onChanged: resizeFloatingAgent)
                .frame(height: 8)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity, alignment: .top)
            FloatingSelectionResizeHitRegion(edge: .bottom, cursor: .resizeUpDown, onChanged: resizeFloatingAgent)
                .frame(height: 8)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity, alignment: .bottom)
            FloatingSelectionResizeHitRegion(edge: .leading, cursor: .resizeLeftRight, onChanged: resizeFloatingAgent)
                .frame(width: 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            FloatingSelectionResizeHitRegion(edge: .trailing, cursor: .resizeLeftRight, onChanged: resizeFloatingAgent)
                .frame(width: 8)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)

            FloatingSelectionResizeHitRegion(edge: .topLeading, cursor: .crosshair, onChanged: resizeFloatingAgent)
                .frame(width: 12, height: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            FloatingSelectionResizeHitRegion(edge: .topTrailing, cursor: .crosshair, onChanged: resizeFloatingAgent)
                .frame(width: 12, height: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            FloatingSelectionResizeHitRegion(edge: .bottomLeading, cursor: .crosshair, onChanged: resizeFloatingAgent)
                .frame(width: 12, height: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            FloatingSelectionResizeHitRegion(edge: .bottomTrailing, cursor: .crosshair, onChanged: resizeFloatingAgent)
                .frame(width: 12, height: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(store.ui("拖动边框调整浮窗大小", "Drag the border to resize")))
        .accessibilityIdentifier("selection-float-resize-border")
    }

    private func resizeFloatingAgent(edge: FloatingAgentResizeEdge, value: DragGesture.Value?) {
        guard let value else {
            resizeOrigin = nil
            resizeOriginOffset = nil
            return
        }

        let origin = resizeOrigin ?? FloatingAgentSize(
            width: Double(panelWidth),
            height: Double(resolvedFloatingFeedHeight)
        )
        let originOffset = resizeOriginOffset ?? settledOffset
        if resizeOrigin == nil {
            resizeOrigin = origin
            resizeOriginOffset = originOffset
        }

        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1_200, height: 800)
        let resized = SelectionFloatingAgentPlacement.resizedFrame(
            current: origin,
            translation: FloatingAgentSize(
                width: Double(value.translation.width),
                height: Double(value.translation.height)
            ),
            canvas: FloatingAgentSize(width: Double(screen.width), height: Double(screen.height)),
            edge: edge
        )
        let feedGrowthCorrection = (origin.height - resized.size.height) / 2

        // Drag updates stay animation-free and use global coordinates. The old
        // local-coordinate corner drag changed its own coordinate space while
        // resizing, so the panel visibly shook under the pointer.
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            panelWidth = CGFloat(resized.size.width)
            userFeedHeight = CGFloat(resized.size.height)
            settledOffset = CGSize(
                width: originOffset.width + CGFloat(resized.offset.x),
                height: originOffset.height + CGFloat(resized.offset.y + feedGrowthCorrection)
            )
        }
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
            interaction.floatingComposerMode = .ask
            expanded = true
            store.keepFloatingSelectionForAnswer = true
            // Do not invent a prompt or auto-send — only open a normal composer.
            store.askSelection()
            draftFocused = true
        }
        focusAskComposerUntilFocused()
    }

    /// 展开动画/挂载时序竞态会让单次设焦点丢失;分次重试直到浮层仍在问模式。
    private func focusAskComposerUntilFocused(attempt: Int = 0) {
        guard attempt < 5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard showsExpandedBody, interaction.floatingComposerMode == .ask else { return }
            draftFocused = true
            focusAskComposerUntilFocused(attempt: attempt + 1)
        }
    }

    /// 胶囊"记":展开共用浮层进入札记模式,不建提问线程、不带附件。
    private func openRemarkComposer() {
        withAnimation(WeiBeiMotion.panel) {
            interaction.floatingComposerMode = .remark
            expanded = true
            store.keepFloatingSelectionForAnswer = true
        }
    }

    /// 提交札记:空输入=纯摘录;保存后收浮层,草稿清空。
    private func submitRemark() {
        store.saveSelectionRemark(interaction.selectionNoteDraft)
        interaction.selectionNoteDraft = ""
        closeFloatingAgent()
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

private struct FloatingSelectionFeedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 1 {
            value = next
        }
    }
}

private struct FloatingSelectionResizeHitRegion: View {
    let edge: FloatingAgentResizeEdge
    let cursor: NSCursor
    let onChanged: (FloatingAgentResizeEdge, DragGesture.Value?) -> Void
    @State private var cursorPushed = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        onChanged(edge, value)
                    }
                    .onEnded { _ in
                        onChanged(edge, nil)
                    }
            )
            .onHover { hovering in
                if hovering, !cursorPushed {
                    cursor.push()
                    cursorPushed = true
                } else if !hovering {
                    popCursorIfNeeded()
                }
            }
            .onDisappear(perform: popCursorIfNeeded)
    }

    private func popCursorIfNeeded() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
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
                WeiBeiEtchedBackdrop(
                    shape: RoundedRectangle(cornerRadius: expanded ? 12 : 8, style: .continuous),
                    fill: WeiBeiTheme.paperRaised.opacity(0.98),
                    stroke: WeiBeiTheme.hairline.opacity(0.65),
                    showsContactShadow: true
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: expanded ? 12 : 8, style: .continuous))
            .shadow(color: WeiBeiTheme.ink.opacity(0.06), radius: 8, y: 3)
    }
}

private struct FloatingSelectionMessageBubble: View {
    @EnvironmentObject private var store: WorkspaceStore
    var message: AgentMessage
    var text: String
    var isError = false
    var isStreaming = false

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isError {
                Text(text)
                    .weiBeiText(13)
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
            text: isUser ? text : AgentNativeMessageContent.markdown(text: text, blocks: message.contentBlocks),
            rendersRichMarkdown: !isUser,
            compact: true,
            isChatWideTypography: false,
            messageID: message.id,
            sources: message.sources,
            onActivateSource: { _ = store.openAgentReplySource($0) },
            isStreaming: isStreaming,
            contentBlocks: message.contentBlocks
        )
    }
}

/// Floating-panel message row. A single type across the generating →
/// completed flip keeps the markdown surface mounted at completion. The
/// caller passes the live streaming state only for the generating row;
/// completed rows receive `inertAgentStreamingState`, which never publishes.
private struct FloatingSelectionMessageRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    var message: AgentMessage
    @ObservedObject var streaming: AgentStreamingState

    @ViewBuilder
    var body: some View {
        let isStreaming = streaming.isDisplaying(message.id)
        let text = isStreaming ? streaming.text : store.agentDisplayText(for: message)
        // Keep the native body mounted while the first-token indicator is visible.
        ZStack(alignment: .topLeading) {
            FloatingSelectionMessageBubble(
                message: message,
                text: text,
                isError: WorkspaceStore.isAgentFailureMessage(message.text),
                isStreaming: isStreaming
            )
            if message.completionState == .generating
                && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AgentThinkingIndicator(activityText: streaming.activityText, compact: true)
                    .id(message.id)
                    .padding(.vertical, 4)
            }
        }
        .onAppear { store.setAgentStreamingReduceMotion(reduceMotion) }
        .onDisappear {
            if streaming.isDisplaying(message.id) {
                store.landAgentStreamingDisplayImmediately()
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            store.setAgentStreamingReduceMotion(enabled)
        }
    }
}

/// Never publishes. Completed rows observe this instead of the live
/// AgentStreamingState: @ObservedObject subscribes regardless of whether the
/// body reads the object, so pointing finished rows at the shared live state
/// would re-broadcast every token to every mounted bubble (what e058c61
/// removed). Only the generating row observes the real streaming state.
@MainActor private let inertAgentStreamingState = AgentStreamingState()

/// Bubble row for one assistant/user message. A single type across the
/// generating → completed flip keeps the native body alive at completion.
private struct AgentMessageBubble: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    var message: AgentMessage
    @ObservedObject var streaming: AgentStreamingState
    var isChatWideTypography = false

    var body: some View {
        let isStreaming = streaming.isDisplaying(message.id)
        AgentBubble(
            message: message,
            liveStreamingText: isStreaming ? streaming.text : nil,
            liveActivityText: message.completionState == .generating ? streaming.activityText : nil,
            isStreaming: isStreaming,
            isChatWideTypography: isChatWideTypography
        )
        .onAppear { store.setAgentStreamingReduceMotion(reduceMotion) }
        .onDisappear {
            if streaming.isDisplaying(message.id) {
                store.landAgentStreamingDisplayImmediately()
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            store.setAgentStreamingReduceMotion(enabled)
        }
    }
}

struct AgentBubble: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.openWindow) private var openSettingsWindow
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    var message: AgentMessage
    var liveStreamingText: String? = nil
    var liveActivityText: String? = nil
    var isStreaming = false
    var isChatWideTypography = false
    @State private var hovering = false
    @State private var copiedMessage = false
    /// Copy feedback identity: a second copy within the 1.2s window re-arms the
    /// full display instead of being swallowed by the still-running first task.
    @State private var copyFeedbackGeneration = 0

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
                    // Keep actions close to the last rendered line.
                    .offset(x: 16, y: 2)
            }
        }
        .onHover { hovering in
            guard !isUser else { return }
            withAnimation(WeiBeiMotion.hover) {
                self.hovering = hovering
            }
        }
        .task(id: copyFeedbackGeneration) {
            guard copiedMessage else { return }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            copiedMessage = false
        }
    }

    private var messageActionBar: some View {
        HStack(spacing: 5) {
            Button {
                copyMessage()
            } label: {
                Image(systemName: copiedMessage ? "checkmark" : "doc.on.doc")
                    .weiBeiText(12, weight: .medium)
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
                        .weiBeiText(12, weight: .medium)
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
            copyFeedbackGeneration += 1
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(userBubbleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(userBubbleStroke, lineWidth: 1)
                    }
                    .shadow(
                        color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.0 : (hovering ? 0.06 : 0.04)),
                        radius: hovering ? 6 : 4,
                        y: hovering ? 2 : 1.2
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        let answerText = liveStreamingText ?? store.agentDisplayText(for: message)
        let citationParse = AgentCitationParser.parse(answerText)
        // 来源标签只承载资料编号+定位信息;点击时走正常打开逻辑,打不开有提示,无需预验证。
        let availableSources = message.sources
        let legacyCitations = citationParse.citations.filter { citation in
            switch citation.kind {
            case .material, .note, .selection:
                return false
            case .learningRecord, .learningMemory:
                return message.origin?.courseID != nil
            case .session:
                return true
            }
        }
        let isAwaitingFirstToken = message.completionState == .generating
            && answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                AgentMessageMarkdownText(
                    text: AgentNativeMessageContent.markdown(text: answerText, blocks: message.contentBlocks),
                    rendersRichMarkdown: true,
                    isChatWideTypography: isChatWideTypography,
                    messageID: message.id,
                    sources: availableSources,
                    onActivateSource: activateSource,
                    isStreaming: isStreaming,
                    contentBlocks: message.contentBlocks
                )
                if isAwaitingFirstToken {
                    AgentThinkingIndicator(
                        activityText: liveActivityText,
                        chatWideTypography: isChatWideTypography
                    )
                }
            }
            if !availableSources.isEmpty {
                AgentReplySourceTagRow(sources: availableSources) { source in
                    activateSource(source)
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

            if message.origin?.courseID != nil,
               let memoryUpdate = message.memoryUpdate,
               !memoryUpdate.memoryIDs.isEmpty {
                AgentReplyMemoryUpdateTag(
                    message: message,
                    update: memoryUpdate
                )
                .transition(WeiBeiTransition.floating)
            }

            if message.origin?.courseID != nil,
               let profileUpdate = message.profileUpdate,
               !profileUpdate.entryIDs.isEmpty {
                AgentReplyProfileUpdateTag(update: profileUpdate)
                    .transition(WeiBeiTransition.floating)
            }

            if message.completionState == .interrupted && !isFailureMessage {
                HStack(spacing: 6) {
                    Text(store.ui("回答已中断，已保留现有内容", "Response interrupted; existing content was kept"))
                        .weiBeiText(10.5)
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
                    if message.failureKind == .unauthorized
                        || !AgentProviderReadiness.isConfigured(for: store) {
                        Button(store.ui("去设置", "Open Settings")) {
                            openSettingsWindow(id: "weibei-settings")
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            } else if message.id == store.lastUsableAgentAnswerID,
                      store.selectionContext != nil || store.canReplaceNoteSelection {
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
        .animation(reduceMotion ? nil : WeiBeiMotion.reveal, value: message.profileUpdate)
    }

    private func activateSource(_ source: AgentReplySource) {
        withAnimation(WeiBeiMotion.panel) {
            _ = store.openAgentReplySource(source)
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
            if let courseID = message.origin?.courseID {
                withAnimation(WeiBeiMotion.panel) {
                    store.presentCourseWorkspace(.memory, courseID: courseID)
                }
            }
        case .session:
            break
        }
    }


    private var isUser: Bool { message.role == .user }
    private var isFailureMessage: Bool {
        message.role == .assistant && WorkspaceStore.isAgentFailureMessage(message.text)
    }
}

// MARK: - Agent citation tags (materials / learning / selection)

/// Bracket citations Agent emits in answers, e.g. `[材料：…]`, `[学习记录：上次位置]`.
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
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                fill: WeiBeiTheme.paperRaised.opacity(0.82),
                stroke: WeiBeiTheme.hairline.opacity(0.58),
                showsContactShadow: true
            )
        }
    }

    @ViewBuilder
    private var editableContent: some View {
        if action.kind == .writeNote {
            Text(store.ui("建议写入内容：", "Suggested note content:"))
                .weiBeiText(12, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)

            if let target = store.agentReplyActionTargetTitle(action) {
                Label(target, systemImage: "note.text")
                    .weiBeiText(10.5)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            TextField(store.ui("笔记小标题", "Note heading"), text: $title)
                .textFieldStyle(.plain)
                .weibeiInputSurface(height: 32)

            TextEditor(text: $bodyText)
                .weiBeiText(12)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .weibeiInputSurface(height: 104, horizontalPadding: 6)
        } else {
            Text(store.ui("建议建立关系：", "Suggested relation:"))
                .weiBeiText(12, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    relationNoteLabel
                    Image(systemName: "arrow.left.and.right")
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    relationSourceLabel
                }
                VStack(alignment: .leading, spacing: 6) {
                    relationNoteLabel
                    Image(systemName: "arrow.up.and.down")
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    relationSourceLabel
                }
            }
        }

        if let failure = action.failureMessage, !failure.isEmpty {
            Label(failure, systemImage: "exclamationmark.triangle")
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !action.evidence.isEmpty {
            Text(action.evidence.joined(separator: " · "))
                .weiBeiText(9.5)
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
                isWorking = true
                Task {
                    await store.cancelAgentReplyAction(
                        messageID: messageID,
                        actionID: action.id
                    )
                    isWorking = false
                }
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
            .weiBeiText(10.5)
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
        .weiBeiText(10.5)
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
                ?? store.ui("新建笔记", "New note")
        }
        let note = store.agentReplyActionTargetTitle(action)
            ?? store.ui("笔记", "note")
        let source = store.agentReplyActionSourceTitle(action)
            ?? store.ui("文稿", "material")
        return "\(note) ↔ \(source)"
    }

    private func actionItemLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .weiBeiText(10.5)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .weibeiEtchedBackground(
                fill: WeiBeiTheme.paperInset.opacity(0.34),
                stroke: WeiBeiTheme.hairline.opacity(0.3),
                cornerRadius: 8
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
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

/// Memoizes display-only source and formula normalization for one message row.
/// A reference type in @State so recomputation never invalidates the view.
final class AgentMessageMarkdownMemo {
    private var key: String?
    private var display = ""
    private var finalized = ""

    func outputs(
        text: String,
        sources: [AgentReplySource],
        language: WeiBeiInterfaceLanguage
    ) -> (display: String, finalized: String) {
        let nextKey = "\(language.rawValue)|\(sources.map(\.id.uuidString).joined(separator: ","))|\(text)"
        if nextKey != key {
            let presentation = AgentReplySourceInlinePresentation(
                text: text,
                sources: sources,
                language: language
            )
            display = AgentCitationParser.parse(presentation.markdown).displayText
            finalized = AgentChatKaTeXMarkdown.prepare(display)
            key = nextKey
        }
        return (display, finalized)
    }
}

private enum AgentCitationParser {
    /// Matches `[材料：…]` / `[学习记录：上次位置]` style Agent citation labels.
    private static let pattern = #"\[(材料|笔记|选区|学习记录|学习记忆|会话)[：:]\s*([^\]\n]{1,300})\]"#
    private static let regex = try? NSRegularExpression(pattern: pattern)
    /// Tail of an unterminated citation label (`[材料：书法笔` mid-stream). The
    /// kind tokens are listed with every proper prefix so the tail is withheld
    /// from the very first character that can only belong to a citation. The
    /// whole group is optional so a lone trailing `[` is withheld too — it is
    /// either the start of a citation (kept hidden) or an ordinary bracket
    /// (reappears with the next character, one pump tick later). Ordinary
    /// brackets with non-citation content (`[x`, `[1`) never match.
    private static let trailingOpenCitation = try? NSRegularExpression(
        pattern: #"\[(?:(?:材|材料|笔|笔记|选|选区|学|学习|学习记|学习记录|学习记忆|会|会话)[：:]?[^\]\n]*)?$"#
    )

    static func parse(_ text: String) -> (displayText: String, citations: [AgentCitation]) {
        guard let regex else {
            return (text, [])
        }
        // Hide an incomplete citation while it arrives. Whitespace belongs to
        // the answer: collapsing it changes code indentation and blank lines.
        var working = text
        if let trailingOpenCitation,
           let match = trailingOpenCitation.firstMatch(in: working, range: fullNSRange(working)),
           let range = Range(match.range, in: working) {
            working = String(working[..<range.lowerBound])
        }
        let nsRange = fullNSRange(working)
        var citations: [AgentCitation] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: working, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: working),
                  let kindRange = Range(match.range(at: 1), in: working),
                  let valueRange = Range(match.range(at: 2), in: working) else { return }
            let kindToken = String(working[kindRange])
            let value = String(working[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = String(working[fullRange])
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
        let cleaned = regex.stringByReplacingMatches(in: working, options: [], range: nsRange, withTemplate: "")
        return (cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? working : cleaned, citations)
    }

    private static func fullNSRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..<text.endIndex, in: text)
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
                .weiBeiText(10.5, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    WeiBeiTheme.paperInset.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .weiBeiText(9.5, weight: .semibold)
                Text(label)
                    .weiBeiText(10.5, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(hovering ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                WeiBeiTheme.paperInset.opacity(hovering ? 0.58 : 0.40),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                .weiBeiText(12, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.82))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(source.title)
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    if let position = source.positionLabel(language: store.interfaceLanguage) {
                        Text(position)
                            .weiBeiText(10.5)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Text(source.excerpt)
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .weiBeiText(9.5, weight: .semibold)
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
                    .weiBeiText(9.5, weight: .semibold)
                Text(chipLabel)
                    .weiBeiText(10.5, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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

private struct AgentChatLayoutWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var agentChatLayoutWidth: CGFloat {
        get { self[AgentChatLayoutWidthKey.self] }
        set { self[AgentChatLayoutWidthKey.self] = newValue }
    }
}

private struct AgentScrollMetrics: Equatable {
    let distanceFromTop: CGFloat
    let distanceFromBottom: CGFloat
    let visibleHeight: CGFloat
    let isUserScrolling: Bool
    let isScrollingTowardTop: Bool
}

/// Reads the enclosing scroll view's position and user scroll direction.
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
                visibleHeight: visible.height,
                isUserScrolling: isUserScrolling,
                isScrollingTowardTop: isScrollingTowardTop
            )
            if !force, let lastReported,
               abs(metrics.distanceFromTop - lastReported.distanceFromTop) <= 8,
               abs(metrics.distanceFromBottom - lastReported.distanceFromBottom) <= 8,
               abs(metrics.visibleHeight - lastReported.visibleHeight) <= 8,
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

/// Assistant text shares one native document across live, saved and floating conversations.
private struct AgentMessageMarkdownText: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.agentChatLayoutWidth) private var layoutWidth
    @Environment(\.weiBeiTextScale) private var textScale
    var text: String
    var rendersRichMarkdown: Bool
    var compact = false
    var isChatWideTypography = false
    var messageID: UUID? = nil
    var sources: [AgentReplySource] = []
    var onActivateSource: (AgentReplySource) -> Void = { _ in }
    var isStreaming = false
    var contentBlocks: [AgentMessageContentBlock] = []
    @State private var expandedSourceURL: String?
    @State private var markdownMemo = AgentMessageMarkdownMemo()
    @State private var imageHandler = MarkdownImageSchemeHandler()
    @State private var measuredHeight: CGFloat?

    private var sourcePresentation: AgentReplySourceInlinePresentation {
        AgentReplySourceInlinePresentation(text: text, sources: sources, language: store.interfaceLanguage)
    }

    private var preparedMarkdown: String {
        markdownMemo.outputs(text: text, sources: sources, language: store.interfaceLanguage).finalized
    }

    var body: some View {
        Group {
            if rendersRichMarkdown {
                NativeChatMarkdownView(
                    markdown: preparedMarkdown,
                    messageID: messageID,
                    fontSize: (isChatWideTypography && !compact ? 16 : 14) * textScale,
                    isDark: store.appearanceMode.isDark,
                    appearanceKey: store.appearanceMode.rawValue,
                    interfaceLanguage: store.interfaceLanguage,
                    onOpenURL: openLink,
                    onHeightChange: { height in
                        measuredHeight = height
                    },
                    visualizationView: { identifier, width, onHeight in
                        guard let messageID else { return nil }
                        let host = NSHostingView(rootView: AgentNativeContentAttachment(
                            messageID: messageID,
                            identifier: identifier.removingPercentEncoding ?? identifier,
                            initialBlocks: contentBlocks,
                            onHeight: onHeight
                        ).environmentObject(store).environment(\.weiBeiTextScale, textScale))
                        host.sizingOptions = []
                        host.frame.size = NSSize(width: width, height: 160)
                        return host
                    },
                    imageLoader: { source, completion in
                        imageHandler.update(
                            markdownBaseURLString: store.currentMarkdownBaseURL?.absoluteString ?? "",
                            attachmentDirectory: store.currentAttachmentDirectory,
                            appearanceMode: store.appearanceMode,
                            interfaceLanguage: store.interfaceLanguage
                        )
                        imageHandler.loadImage(source: source, completion: completion)
                    }
                )
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: measuredHeight ?? initialBodyHeight, alignment: .leading)
            } else {
                Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
                    .weiBeiText(compact ? 13.2 : 14.5)
                    .lineSpacing(compact ? 4.2 : 4.5)
                    .foregroundStyle(WeiBeiTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.disabled)
            }
        }
        .modifier(AgentMessageTextWidthModifier(fillsReadingColumn: rendersRichMarkdown || compact))
        .popover(isPresented: Binding(
            get: { expandedSourceURL != nil },
            set: { if !$0 { expandedSourceURL = nil } }
        ), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(expandedSources) { source in
                    Button {
                        expandedSourceURL = nil
                        onActivateSource(source)
                    } label: { AgentReplySourceDetail(source: source) }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 340)
            .padding(.vertical, 6)
        }
        .onDisappear {
            imageHandler.invalidate()
            imageHandler = MarkdownImageSchemeHandler()
        }
    }

    private var initialBodyHeight: CGFloat {
        guard !compact, !isStreaming, sources.isEmpty else { return 1 }
        let key = AgentFinalizedMarkdownHeightCache.cacheKey(
            messageID: messageID, text: text,
            widthBucket: AgentFinalizedMarkdownHeightCache.widthBucket(layoutWidth),
            wideTypography: isChatWideTypography, textScale: textScale
        )
        return max(1, (AgentFinalizedMarkdownHeightCache.height(for: key) ?? 21) - 20)
    }

    private var expandedSources: [AgentReplySource] {
        expandedSourceURL.flatMap(sourcePresentation.additionalSources(for:)) ?? []
    }

    private func openLink(_ url: URL) {
        if let source = sourcePresentation.source(for: url) {
            onActivateSource(source)
        } else if !sourcePresentation.additionalSources(for: url).isEmpty {
            expandedSourceURL = url.absoluteString
        } else if url.scheme == "weibei-note" {
            store.openOrCreateWikiNote(title: String(url.absoluteString.dropFirst("weibei-note:".count)).removingPercentEncoding ?? url.path)
        } else if url.scheme == "weibei-source" {
            store.openSourceReference(String(url.absoluteString.dropFirst("weibei-source:".count)).removingPercentEncoding ?? url.path)
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        } else {
            imageHandler.update(markdownBaseURLString: store.currentMarkdownBaseURL?.absoluteString ?? "",
                attachmentDirectory: store.currentAttachmentDirectory,
                appearanceMode: store.appearanceMode, interfaceLanguage: store.interfaceLanguage)
            if let imageURL = imageHandler.validatedLocalImageURL(source: url.absoluteString) {
                NSWorkspace.shared.open(imageURL)
            }
        }
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

private struct AgentLiveResponse: View {
    @ObservedObject var streaming: AgentStreamingState
    var isChatWideTypography = false
    var compact = false

    @ViewBuilder
    var body: some View {
        if streaming.text.isEmpty {
            AgentThinkingIndicator(
                activityText: streaming.activityText,
                chatWideTypography: isChatWideTypography,
                compact: compact
            )
                .id(compact ? "selection-float-thinking" : "agent-thinking")
                .padding(.vertical, compact ? 4 : 0)
        } else {
            AgentStreamingResponse(
                text: streaming.text,
                isChatWideTypography: isChatWideTypography,
                compact: compact
            )
            .id(compact ? "selection-float-streaming" : "agent-streaming-response")
        }
    }
}

/// Product loading motion — 「行文进行中 V3」.
/// Driven solely by `AgentStreamingState.activityText` (no demo status carousel).
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
    var activityText: String?
    /// Match the native answer text in wide and compact conversation surfaces.
    var chatWideTypography = false
    var compact = false
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Environment(\.weiBeiTextScale) private var textScale
    @State private var cachedText = ""
    @State private var cachedTextWidth: CGFloat = 1
    @State private var motionEpoch = Date()
    @State private var lastStatusSwitch = Date.distantPast
    @State private var statusSwitchTask: Task<Void, Never>?

    private static let minimumStatusHold: TimeInterval = 0.6

    /// Same font bases and user text scale as the answer body.
    private static let chatWideFontSize: CGFloat = 16
    private static let compactFontSize: CGFloat = 14
    private var baseFontSize: CGFloat {
        chatWideTypography && !compact ? Self.chatWideFontSize : Self.compactFontSize
    }
    /// Single source for measure + line box + AppKit painting. Drawing at a
    /// different size than the measured width is what made the orbit sit far
    /// from the text on the right and close on the left.
    private var scaledFontSize: CGFloat { baseFontSize * max(0.1, textScale) }
    /// Clear gap from line-box edge → stroke centerline (all four sides).
    private static let orbitPadding: CGFloat = 6.5
    private static let lineWidth: CGFloat = 1.25
    /// Line box height matches the font’s typographic bounds so top/bottom pad stay equal.
    private var textLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: scaledFontSize, weight: .medium)
        return max(1, ceil(font.ascender - font.descender))
    }
    /// Outer view size = line box + equal pad on both sides + half stroke outside the path.
    private static var pathOuterInset: CGFloat { orbitPadding + lineWidth / 2 }
    private var pathHeight: CGFloat { textLineHeight + Self.pathOuterInset * 2 }

    private var statusText: String {
        activityText ?? store.ui("正在思考", "Thinking")
    }

    var body: some View {
        let text = cachedText.isEmpty ? statusText : cachedText
        let textWidth = max(1, cachedTextWidth)
        let orbitWidth = textWidth + Self.pathOuterInset * 2

        Group {
            if reduceMotion {
                Text(text)
                    .weiBeiText(baseFontSize, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.ink.opacity(0.93))
                    .lineLimit(1)
                    .frame(width: textWidth, height: textLineHeight, alignment: .leading)
                    .padding(Self.pathOuterInset)
            } else {
                // AppKit host: fixed intrinsic size; ticks only repaint the NSView.
                AgentThinkingOrbitHost(
                    text: text,
                    textWidth: textWidth,
                    orbitWidth: orbitWidth,
                    pathHeight: pathHeight,
                    orbitPadding: Self.orbitPadding,
                    textLineHeight: textLineHeight,
                    lineWidth: Self.lineWidth,
                    fontSize: scaledFontSize,
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
        .offset(x: -Self.pathOuterInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear {
            refreshCache(for: statusText)
            motionEpoch = Date()
            // The 600ms hold starts with the first status: without this the second
            // status (elapsed = ∞ vs distantPast) would immediately stomp the first.
            lastStatusSwitch = Date()
        }
        .onDisappear {
            statusSwitchTask?.cancel()
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
        .onChange(of: textScale) { _, _ in
            // ⌘± tier change: re-measure the box at the new size so the orbit
            // keeps equal padding; the motion phase itself is untouched.
            refreshCache(for: statusText)
        }
    }

    private func refreshCache(for text: String) {
        cachedText = text
        cachedTextWidth = Self.measuredWidth(for: text, fontSize: scaledFontSize)
    }

    private static func measuredWidth(for text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
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
    /// Already scaled by the ⌘± tier — the same size used to measure `textWidth`.
    let fontSize: CGFloat
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
            fontSize: fontSize,
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
            fontSize: fontSize,
            motionEpoch: motionEpoch,
            appearanceMode: appearanceMode
        )
    }
}

/// Fixed-size AppKit painter for 「行文进行中 V3」: reveal + first-pass underline + TextOrbitSegment.
/// Text sits in a line box; orbit stroke centerline keeps equal `orbitPadding` on all four sides.
final class AgentThinkingOrbitNSView: NSView {
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
    /// Painted at the caller-measured size — a divergent local constant here is
    /// what made the right gap ~10pt wider than the left.
    private var fontSize: CGFloat = 16
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
        fontSize: CGFloat,
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
        self.fontSize = max(1, fontSize)
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

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
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
    var isChatWideTypography = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AgentMessageMarkdownText(
                text: text,
                rendersRichMarkdown: true,
                compact: compact,
                isChatWideTypography: isChatWideTypography,
                isStreaming: true
            )
        }
        .padding(.vertical, compact ? 0 : 10)
        .padding(.leading, compact ? 0 : 20)
        .padding(.trailing, compact ? 0 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { WeiBeiPerf.event("agent.mdrow", extra: "where=liveRow textlen=\(text.count) compact=\(compact ? 1 : 0)") }
        .accessibilityLabel(Text(store.ui("魏碑正在回答", "WeiBei is responding")))
    }
}
