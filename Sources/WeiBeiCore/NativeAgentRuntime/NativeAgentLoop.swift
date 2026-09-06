import Foundation

public actor NativeAgentLoop {
    private var cancelled = false

    public init() {}

    public func cancel() {
        cancelled = true
    }

    public func reset() {
        cancelled = false
    }

    public func run(
        request: StudyAgentRequest,
        ledger: NativeAgentLedger,
        registry: NativeToolRegistry,
        adapter: NativeLLMAdapter,
        model: String,
        contextWindow: Int? = nil,
        hostToolHandler: StudyAgentHostToolHandler?,
        systemPrompt: String,
        liveStores: NativeLiveStores = .empty,
        mode: NativeAgentMode = .assistant,
        progress: StudyAgentProgressHandler?
    ) async throws -> NativeLoopResult {
        await progress?(.preparing)
        let turn = ((await ledger.allEvents()).compactMap(\.turn).max() ?? 0) + 1
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(type: .turnStart, seq: seq, timeMS: time, turn: turn)
        }
        var userMessage: String
        if let selection = request.selectionText,
           !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let title = request.selectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectionTitle = title.flatMap { $0.isEmpty ? nil : $0 }
                ?? request.language.text("当前选区", "Current selection")
            userMessage = request.language.text(
                "[选中文字：\(selectionTitle)]\n\(selection)\n\n[问题]\n\(request.question)",
                "[Selected text: \(selectionTitle)]\n\(selection)\n\n[Question]\n\(request.question)"
            )
        } else {
            userMessage = request.question
        }
        if let location = NativeTurnLocation.block(for: request) {
            userMessage += "\n\n\(location)"
        }
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(
                type: .userMessage,
                seq: seq,
                timeMS: time,
                turn: turn,
                text: userMessage
            )
        }

        var context = NativeToolExecutionContext(
            request: request,
            mode: mode,
            hostToolHandler: hostToolHandler,
            persistentAssetIDsByContextID: Dictionary(
                uniqueKeysWithValues: request.courseContext.items.map { ($0.id, $0.id) }
            ),
            liveStores: liveStores
        )
        let scope = NativeToolScope.session(request.id.uuidString)
        let tools = await registry.resolved(scope: scope)

        var collectedText = ""
        var toolTrace: [String] = []
        var noteProposal: StudyAgentNoteProposal?
        var relationProposal: StudyAgentRelationProposal?
        var learningUpdate: StudyAgentLearningUpdate?
        var courseProfileUpdate: StudyAgentCourseProfileUpdate?
        var appliedMemoryUpdate: AgentReplyMemoryUpdate?
        var appliedProfileUpdate: AgentReplyProfileUpdate?
        var loadedSkills: [StudyAgentLoadedSkill] = []
        var readItemIDs: [String] = []
        var sources: [AgentReplySource] = []
        var contentBlocks: [AgentMessageContentBlock] = []
        var pendingUnstarted: [NativeToolCall] = []

        do {
            var step = 0
            while true {
                step += 1
                try checkCancelled()
                let projection = await ledger.deriveProjection()
                var messages = [NativeModelMessage(role: .system, content: systemPrompt)]
                messages.append(contentsOf: projection.messages)
                if let invariant = NativeAgentInvariant.mismatch(
                    logged: projection.messages,
                    outgoing: Array(messages.dropFirst())
                ) {
                    assertionFailure(invariant)
                }
                var llmRequest = NativeLLMRequest(model: model, messages: messages, tools: tools)
                // 搜索开关对全协议族生效;推理档仅 Responses 家族支持。
                llmRequest.enableNativeWebSearch = tools.contains { $0.name == "weibei_course_map" }
                if adapter.family.contains("responses") {
                    llmRequest.reasoningEffort = "low"
                }
                #if DEBUG
                let effectiveContextWindow = (adapter as? NativeContextWindowTestingAdapter)?.contextWindowForTesting
                    ?? contextWindow
                #else
                let effectiveContextWindow = contextWindow
                #endif
                if let effectiveContextWindow {
                    let candidate: NativeContextCompactionCandidate?
                    do {
                        candidate = try await NativeContextCompaction.prepareCandidate(
                            request: llmRequest,
                            projection: projection,
                            adapter: adapter,
                            contextWindow: effectiveContextWindow
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let failure as NativeLLMFailure where failure.code == "cancelled" {
                        throw failure
                    } catch {
                        candidate = nil
                    }
                    if let candidate {
                        try checkCancelled()
                        _ = try await ledger.append { seq, time in
                            NativeSessionEvent(
                                type: .contextCompaction,
                                seq: seq,
                                timeMS: time,
                                summary: candidate.summary,
                                firstKeptSeq: candidate.firstKeptSeq
                            )
                        }
                        llmRequest = candidate.request
                    }
                }
                _ = try await ledger.append { seq, time in
                    NativeSessionEvent(type: .stepStart, seq: seq, timeMS: time, turn: turn, step: step)
                }
                var assembler = NativeToolCallAssembler()
                var finish: NativeFinishReason?
                var stepText = ""
                var stepUsage: NativeTokenUsage?
                var receivedChunk = false
                var recoveredOverflow = false
                streamAttempt: while true {
                    do {
                        for try await chunk in adapter.stream(llmRequest) {
                            try checkCancelled()
                            receivedChunk = true
                            assembler.apply(chunk)
                            _ = try await ledger.append { seq, time in
                                NativeSessionEvent(
                                    type: .assistantChunk,
                                    seq: seq,
                                    timeMS: time,
                                    turn: turn,
                                    step: step,
                                    chunk: chunk
                                )
                            }
                            switch chunk {
                            case let .textDelta(_, text):
                                stepText += text
                                collectedText += text
                                if !contentBlocks.isEmpty {
                                    if case let .text(previous)? = contentBlocks.last {
                                        contentBlocks[contentBlocks.count - 1] = .text(previous + text)
                                    } else {
                                        contentBlocks.append(.text(text))
                                    }
                                }
                                await progress?(.text(collectedText, contentBlocks))
                            case let .webSearchSource(url):
                                if !context.currentRunSourceURLs.contains(url) {
                                    context.currentRunSourceURLs.append(url)
                                }
                            case let .toolCallDelta(_, _, name, _):
                                if let name {
                                    await progress?(.usingTool(name, nil))
                                }
                            case let .usage(usage):
                                stepUsage = stepUsage?.merging(usage) ?? usage
                            case let .finish(reason, _):
                                finish = reason
                            default:
                                break
                            }
                        }
                        break streamAttempt
                    } catch let failure as NativeLLMFailure
                        where failure.isContextOverflow
                            && !recoveredOverflow
                            && !receivedChunk {
                        let candidate: NativeContextCompactionCandidate?
                        do {
                            let recoveryProjection = await ledger.deriveProjection()
                            candidate = try await NativeContextCompaction.prepareOverflowCandidate(
                                request: llmRequest,
                                projection: recoveryProjection,
                                adapter: adapter,
                                contextWindow: effectiveContextWindow
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch let cancellation as NativeLLMFailure where cancellation.code == "cancelled" {
                            throw cancellation
                        } catch {
                            throw failure
                        }
                        guard let candidate else { throw failure }
                        try checkCancelled()
                        _ = try await ledger.append { seq, time in
                            NativeSessionEvent(
                                type: .contextCompaction,
                                seq: seq,
                                timeMS: time,
                                summary: candidate.summary,
                                firstKeptSeq: candidate.firstKeptSeq
                            )
                        }
                        llmRequest = candidate.request
                        recoveredOverflow = true
                    }
                }
                let completedUsage: NativeTokenUsage? = if finish == .stop || finish == .toolCalls || finish == .length {
                    stepUsage
                } else {
                    nil
                }
                if !stepText.isEmpty || completedUsage != nil {
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .assistantMessage,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            text: stepText,
                            usage: completedUsage
                        )
                    }
                }

                let callResults = (finish == .toolCalls || finish == .stop) ? assembler.callResults() : []
                let calls = callResults.map { $0.call }
                if calls.isEmpty {
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(type: .stepEnd, seq: seq, timeMS: time, turn: turn, step: step)
                    }
                    guard finish == .stop else {
                        try await ledger.closeTurn(turn: turn, reason: .error)
                        throw NativeLLMFailure(
                            code: finish?.rawValue ?? "incomplete",
                            message: "模型回答未正常结束，请继续。"
                        )
                    }
                    break
                }
                pendingUnstarted = calls
                for call in calls {
                    toolTrace.append(call.name)
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .toolCall,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            toolCallID: call.id,
                            toolName: call.name,
                            argumentsJSON: call.arguments
                        )
                    }
                }
                for callResult in callResults {
                    let call = callResult.call
                    try checkCancelled()
                    pendingUnstarted.removeAll { $0.id == call.id }
                    let result: NativeToolExecutionResult
                    let previousBlocks = contentBlocks
                    if let failure = callResult.failure {
                        result = NativeToolExecutionResult(text: failure.localizedDescription, isError: true)
                    } else if call.name == "$web_search" {
                        // Kimi 内置搜索:把模型给出的搜索参数原样回传,服务端执行检索。
                        result = NativeToolExecutionResult(text: call.arguments)
                    } else {
                        do {
                            result = try await registry.execute(
                                NativeToolCallRequest(name: call.name, argumentsJSON: call.arguments, callID: call.id),
                                context: context,
                                scope: scope
                            )
                        } catch {
                            result = NativeToolExecutionResult(text: error.localizedDescription, isError: true)
                        }
                    }
                    applySideEffects(
                        name: call.name,
                        result: result,
                        contextRevision: request.contextRevision,
                        noteProposal: &noteProposal,
                        relationProposal: &relationProposal,
                        learningUpdate: &learningUpdate,
                        courseProfileUpdate: &courseProfileUpdate,
                        appliedMemoryUpdate: &appliedMemoryUpdate,
                        appliedProfileUpdate: &appliedProfileUpdate,
                        loadedSkills: &loadedSkills,
                        readItemIDs: &readItemIDs,
                        sources: &sources,
                        contentBlocks: &contentBlocks,
                        context: &context
                    )
                    if call.name == "weibei_visualize", !result.isError,
                       let changed = contentBlocks.first(where: { block in
                           if case .visualization = block { return !previousBlocks.contains(block) }
                           return false
                       }), case let .visualization(visualization) = changed {
                        // Preserve text before the first figure, then append later text in place.
                        if contentBlocks.count == 1, !collectedText.isEmpty {
                            contentBlocks.insert(.text(collectedText), at: 0)
                        }
                        await progress?(.visualization(visualization, contentBlocks))
                    }
                    _ = try await ledger.append { seq, time in
                        NativeSessionEvent(
                            type: .toolResult,
                            seq: seq,
                            timeMS: time,
                            turn: turn,
                            step: step,
                            text: result.text,
                            toolCallID: call.id,
                            toolName: call.name,
                            isError: result.isError,
                            imageMediaType: result.image?.mediaType,
                            imageBase64: result.image?.base64
                        )
                    }
                }
                _ = try await ledger.append { seq, time in
                    NativeSessionEvent(type: .stepEnd, seq: seq, timeMS: time, turn: turn, step: step)
                }
            }
            try await ledger.closeTurn(turn: turn, reason: .completed)
            return NativeLoopResult(
                text: collectedText,
                contentBlocks: contentBlocks,
                sources: sources,
                toolTrace: toolTrace,
                noteProposal: noteProposal,
                relationProposal: relationProposal,
                learningUpdate: learningUpdate,
                courseProfileUpdate: courseProfileUpdate,
                appliedMemoryUpdate: appliedMemoryUpdate,
                appliedProfileUpdate: appliedProfileUpdate,
                loadedSkills: loadedSkills,
                readItemIDs: readItemIDs
            )
        } catch is CancellationError {
            try await balanceCancellation(
                ledger: ledger,
                turn: turn,
                pending: pendingUnstarted
            )
            throw NativeLLMFailure(code: "cancelled", message: "cancelled")
        } catch let failure as NativeLLMFailure where failure.code == "cancelled" {
            try await balanceCancellation(
                ledger: ledger,
                turn: turn,
                pending: pendingUnstarted
            )
            throw failure
        }
    }

    private func checkCancelled() throws {
        if cancelled || Task.isCancelled {
            throw CancellationError()
        }
    }

    private func balanceCancellation(
        ledger: NativeAgentLedger,
        turn: Int,
        pending: [NativeToolCall]
    ) async throws {
        for call in pending {
            _ = try await ledger.append { seq, time in
                NativeSessionEvent(
                    type: .toolResult,
                    seq: seq,
                    timeMS: time,
                    turn: turn,
                    text: "not executed: cancelled",
                    toolCallID: call.id,
                    toolName: call.name,
                    isError: true
                )
            }
        }
        try await ledger.closeTurn(turn: turn, reason: .cancelled)
    }

    private func applySideEffects(
        name: String,
        result: NativeToolExecutionResult,
        contextRevision: String,
        noteProposal: inout StudyAgentNoteProposal?,
        relationProposal: inout StudyAgentRelationProposal?,
        learningUpdate: inout StudyAgentLearningUpdate?,
        courseProfileUpdate: inout StudyAgentCourseProfileUpdate?,
        appliedMemoryUpdate: inout AgentReplyMemoryUpdate?,
        appliedProfileUpdate: inout AgentReplyProfileUpdate?,
        loadedSkills: inout [StudyAgentLoadedSkill],
        readItemIDs: inout [String],
        sources: inout [AgentReplySource],
        contentBlocks: inout [AgentMessageContentBlock],
        context: inout NativeToolExecutionContext
    ) {
        if result.isError { return }
        let details = result.details
        if name == "weibei_course_search"
            || name == "weibei_course_read"
            || name == "weibei_search_workspace" {
            if let items = (try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(result.text.utf8)))?.items {
                for item in items {
                    if !context.searchedItemIDs.contains(item.item.id) {
                        context.searchedItemIDs.append(item.item.id)
                    }
                    readItemIDs.append(item.item.id)
                    if let revision = item.sourceRevision {
                        context.readSourceRevisions[item.item.id] = revision
                    }
                    let excerpt = item.item.searchText
                    let kind: AgentReplySourceKind = item.item.role == "note" ? .note : .material
                    let label = kind == .note ? "[笔记：\(item.item.title)]" : "[材料：\(item.item.title)]"
                    if !sources.contains(where: { $0.itemID == item.item.id }) {
                        sources.append(
                            AgentReplySource(
                                itemID: item.item.id,
                                kind: kind,
                                title: item.item.title,
                                label: label,
                                excerpt: String(excerpt.prefix(160))
                            )
                        )
                    }
                }
            }
        }
        if name == "weibei_web_open",
           let pages = (try? JSONDecoder().decode(
            StudyAgentHostToolResult.self,
            from: Data(result.text.utf8)
           ))?.webPages {
            for link in pages.flatMap(\.links) where !context.currentRunSourceURLs.contains(link) {
                context.currentRunSourceURLs.append(link)
            }
        }
        if name == "weibei_note_proposal" {
            noteProposal = StudyAgentProposalDecoding.noteProposal(from: details)
        }
        if name == "weibei_relation_proposal" {
            relationProposal = StudyAgentProposalDecoding.relationProposal(from: details)
        }
        if name == "weibei_read_learning_memory" {
            context.lastReadMemoryRevision = context.request.learningContext.memoryRevision
        }
        if name == "weibei_update_learning_memory" {
            learningUpdate = StudyAgentProposalDecoding.learningUpdate(from: details)
            if let applied = memoryApplyReceipt(from: details) {
                appliedMemoryUpdate = applied
            }
        }
        if name == "weibei_course_profile_update" {
            courseProfileUpdate = StudyAgentProposalDecoding.courseProfileUpdate(from: details)
            if let applied = profileApplyReceipt(from: details) {
                appliedProfileUpdate = applied
            }
        }
        if name == "weibei_visualize",
           let id = details["id"] as? String,
           let spec = details["spec"],
           let specData = try? JSONSerialization.data(withJSONObject: spec),
           let specJSON = String(data: specData, encoding: .utf8) {
            let block = AgentMessageContentBlock.visualization(AgentVisualization(id: id, specJSON: specJSON))
            if let index = contentBlocks.firstIndex(where: {
                if case let .visualization(value) = $0 { return value.id == id }
                return false
            }) {
                contentBlocks[index] = block
            } else {
                contentBlocks.append(block)
            }
        }
        if name == "load_skill" {
            if let loaded = details["loaded"] as? [String: Any],
               let id = loaded["id"] as? String,
               let skillName = loaded["name"] as? String,
               let sha = loaded["sha256"] as? String,
               let relative = loaded["relativePath"] as? String {
                context.loadedSkillIDs.insert(id)
                let skill = StudyAgentLoadedSkill(
                    id: id,
                    name: skillName,
                    version: loaded["version"] as? String ?? "1.0.0",
                    sha256: sha,
                    byteCount: loaded["byteCount"] as? Int ?? 0,
                    relativePath: relative,
                    loadedAtContextRevision: contextRevision
                )
                if let index = loadedSkills.firstIndex(where: { $0.id == skill.id }) {
                    loadedSkills[index] = skill
                } else {
                    loadedSkills.append(skill)
                }
            }
        }
    }

    private func memoryApplyReceipt(from details: [String: Any]) -> AgentReplyMemoryUpdate? {
        guard let applied = details["appliedMemoryUpdate"] as? [String: Any],
              let rawIDs = applied["memoryIDs"] as? [String] else { return nil }
        let ids = rawIDs.compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return nil }
        return AgentReplyMemoryUpdate(
            memoryIDs: ids,
            summary: applied["summary"] as? String ?? ""
        )
    }

    private func profileApplyReceipt(from details: [String: Any]) -> AgentReplyProfileUpdate? {
        guard let applied = details["appliedProfileUpdate"] as? [String: Any],
              let rawIDs = applied["entryIDs"] as? [String] else { return nil }
        let ids = rawIDs.compactMap { UUID(uuidString: $0) }
        guard !ids.isEmpty else { return nil }
        return AgentReplyProfileUpdate(
            entryIDs: ids,
            summary: applied["summary"] as? String ?? "",
            texts: applied["texts"] as? [String] ?? []
        )
    }
}

public struct NativeLoopResult: Sendable {
    public var text: String
    public var contentBlocks: [AgentMessageContentBlock]
    public var sources: [AgentReplySource]
    public var toolTrace: [String]
    public var noteProposal: StudyAgentNoteProposal?
    public var relationProposal: StudyAgentRelationProposal?
    public var learningUpdate: StudyAgentLearningUpdate?
    public var courseProfileUpdate: StudyAgentCourseProfileUpdate?
    public var appliedMemoryUpdate: AgentReplyMemoryUpdate?
    public var appliedProfileUpdate: AgentReplyProfileUpdate?
    public var loadedSkills: [StudyAgentLoadedSkill]
    public var readItemIDs: [String]
}

enum NativeAgentInvariant {
    static func mismatch(logged: [NativeModelMessage], outgoing: [NativeModelMessage]) -> String? {
        guard logged.count == outgoing.count else {
            return "model-visible ⟺ logged failed: count \(logged.count) vs \(outgoing.count)"
        }
        for (left, right) in zip(logged, outgoing) {
            if left.role != right.role || left.content != right.content || left.images != right.images {
                return "model-visible ⟺ logged failed: role/content drift"
            }
        }
        return nil
    }
}
