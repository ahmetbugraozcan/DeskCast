import AppKit
import Combine

/// A model the user can pick for the chat.
struct AgentModelOption: Identifiable, Hashable {
    let id: String
    let name: String
}

/// The mail form for a dropped file.
struct AgentMailDraft: Equatable {
    var recipient = ""
    var subject = ""
    var message = ""
}

/// The Ask page: a conversation with Claude (web search on) about a
/// question, a dropped file, or a window Bip was dragged onto; dropped files
/// can also be mailed with Apple Mail. Claude is reached through the
/// Anthropic API with the user's key, or through their installed Claude Code.
@MainActor
final class AgentChatViewModel: ObservableObject {
    @Published private(set) var entries: [AgentChatEntry] = []
    @Published var draft = ""
    @Published private(set) var attachment: AgentChatAttachment?
    @Published private(set) var isSending = false
    @Published private(set) var hasKey = false
    @Published private(set) var backend: AgentAskBackend
    /// The `claude` command was found (checked when the page appears).
    @Published private(set) var hasClaudeCode = false
    @Published private(set) var models: [AgentModelOption] = []
    @Published var mailDraft: AgentMailDraft?
    @Published private(set) var isMailing = false
    @Published private(set) var note: String?
    /// Bip is being dragged out of the island.
    @Published private(set) var isDraggingBip = false
    @Published private(set) var isCapturingWindow = false
    /// The text field (or key field) has keyboard focus; the island keeps it.
    @Published var isInputFocused = false

    /// Opens the island's AI panel on the Ask page (for a dropped file).
    var onReveal: (() -> Void)?
    /// Keeps the island open while Bip is dragged outside it.
    var holdIsland: ((Bool) -> Void)?

    private let messaging: ClaudeMessaging
    private let claudeCode: ClaudeCodeAsking
    private let secrets: AgentSecretStoring
    private let windows: WindowContextProviding
    private let mail: MailSending
    private let dragPresenter: BipDragPresenting
    private let defaults: UserDefaults
    /// The conversation as sent to the API (content blocks kept as returned).
    private var history: [[String: Any]] = []
    /// The Claude Code conversation so far.
    private var claudeCodeSessionID: String?
    private var attachmentSent = false
    private var sendTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?

    private static let maxPauseContinuations = 3

    init(
        messaging: ClaudeMessaging? = nil,
        claudeCode: ClaudeCodeAsking? = nil,
        secrets: AgentSecretStoring? = nil,
        windows: WindowContextProviding? = nil,
        mail: MailSending? = nil,
        dragPresenter: BipDragPresenting? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.messaging = messaging ?? ClaudeMessagesService()
        self.claudeCode = claudeCode ?? ClaudeCodeChatService()
        self.secrets = secrets ?? AgentKeychain()
        self.windows = windows ?? WindowContextService()
        self.mail = mail ?? MailSendService()
        self.dragPresenter = dragPresenter ?? BipDragPresenter()
        self.defaults = defaults
        hasKey = self.secrets.value(for: .anthropic) != nil
        backend = AgentHubSettings.askBackend(in: defaults)
        hasClaudeCode = self.claudeCode.executablePath != nil
    }

    /// Ready to ask: a saved key, or Claude Code installed.
    var isReady: Bool {
        switch backend {
        case .api: hasKey
        case .claudeCode: hasClaudeCode
        }
    }

    /// Switching starts a new conversation.
    func useBackend(_ newValue: AgentAskBackend) {
        hasClaudeCode = claudeCode.executablePath != nil
        guard newValue != backend else { return }
        clear()
        backend = newValue
        defaults.set(newValue.rawValue, forKey: AgentHubSettings.Keys.askBackend)
        if newValue == .api, hasKey, models.isEmpty {
            loadModels()
        }
    }

    var model: String {
        AgentHubSettings.claudeModel(in: defaults)
    }

    var mood: BipMood {
        if isSending { return attachment == nil ? .searching : .thinking }
        if entries.last?.role == .failure { return .error }
        if entries.last?.role == .assistant { return .happy }
        return .idle
    }

    // MARK: - Key and models

    func saveKey(_ key: String) {
        secrets.set(key, for: .anthropic)
        hasKey = secrets.value(for: .anthropic) != nil
        if hasKey {
            loadModels()
        }
    }

    func removeKey() {
        secrets.set(nil, for: .anthropic)
        hasKey = false
        models = []
    }

    func loadModels() {
        guard let key = secrets.value(for: .anthropic) else { return }
        Task {
            let fetched = await messaging.models(key: key)
            let ids = fetched.isEmpty ? ClaudeChatProtocol.fallbackModels.map { ($0, $0) } : fetched
            models = ids.map { AgentModelOption(id: $0.id, name: $0.name) }
        }
    }

    // MARK: - Conversation

    var canSend: Bool {
        isReady && !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() {
        guard canSend else { return }
        if backend == .claudeCode {
            sendToClaudeCode()
            return
        }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = secrets.value(for: .anthropic) else { return }

        let content: [[String: Any]]
        do {
            content = try ClaudeChatProtocol.userContent(question: question, attachment: attachmentSent ? nil : attachment)
        } catch {
            fail(error)
            return
        }

        draft = ""
        entries.append(AgentChatEntry(role: .user, text: question, attachment: attachmentSent ? nil : attachment?.label))
        history.append(["role": "user", "content": content])
        attachmentSent = attachment != nil
        isSending = true
        BipSoundPlayer.shared.play(.send)

        sendTask = Task { [weak self] in
            await self?.run(key: key)
        }
    }

    private func run(key: String) async {
        defer { isSending = false }
        do {
            var continuations = 0
            while true {
                let data = try await messaging.send(ClaudeChatProtocol.body(model: model, messages: history), key: key)
                guard !Task.isCancelled else { return }
                let reply = try ClaudeChatProtocol.parseReply(data)
                let content = (try? JSONSerialization.jsonObject(with: reply.content)) ?? []
                history.append(["role": "assistant", "content": content])

                // A long server-side search pauses the turn; send it back to go on.
                if reply.stopReason == "pause_turn", continuations < Self.maxPauseContinuations {
                    continuations += 1
                    continue
                }

                let text = reply.text.isEmpty ? AppLocalization.string("agentHub.ask.empty") : reply.text
                entries.append(AgentChatEntry(role: .assistant, text: text, sources: reply.sources))
                BipSoundPlayer.shared.play(.received)
                return
            }
        } catch {
            guard !Task.isCancelled else { return }
            // Drop the unanswered question so the conversation stays valid.
            while let last = history.last, last["role"] as? String == "assistant" {
                history.removeLast()
            }
            if !history.isEmpty {
                history.removeLast()
            }
            fail(error)
        }
    }

    private func sendToClaudeCode() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAttachment = attachmentSent ? nil : attachment
        var windowImagePath: String?
        var extraFolders: [String] = []
        switch newAttachment {
        case .file(let url):
            extraFolders = [url.deletingLastPathComponent().path]
        case .window(let context):
            windowImagePath = context.image.flatMap { claudeCode.saveWindowImage($0) }
        case nil:
            break
        }
        let prompt = ClaudeCodeChatProtocol.prompt(question: question, attachment: newAttachment, windowImagePath: windowImagePath)

        draft = ""
        entries.append(AgentChatEntry(role: .user, text: question, attachment: newAttachment?.label))
        attachmentSent = attachment != nil
        isSending = true
        BipSoundPlayer.shared.play(.send)

        let sessionID = claudeCodeSessionID
        sendTask = Task { [weak self] in
            guard let self else { return }
            defer { isSending = false }
            do {
                let reply = try await claudeCode.ask(prompt: prompt, sessionID: sessionID, extraFolders: extraFolders)
                guard !Task.isCancelled else { return }
                claudeCodeSessionID = reply.sessionID ?? sessionID
                let text = reply.text.isEmpty ? AppLocalization.string("agentHub.ask.empty") : reply.text
                entries.append(AgentChatEntry(role: .assistant, text: text))
                BipSoundPlayer.shared.play(.received)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        entries.append(AgentChatEntry(role: .failure, text: message))
        BipSoundPlayer.shared.play(.error)
    }

    func clear() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        entries = []
        history = []
        claudeCodeSessionID = nil
        attachmentSent = false
        removeAttachment()
        mailDraft = nil
    }

    func copy(_ entry: AgentChatEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        show(note: AppLocalization.string("agentHub.ask.copied"))
    }

    func open(_ source: AgentChatSource) {
        guard let url = URL(string: source.url), url.scheme == "https" || url.scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Attachments

    /// A new attachment starts a new conversation about it.
    private func setAttachment(_ newValue: AgentChatAttachment?) {
        if !history.isEmpty || claudeCodeSessionID != nil {
            entries = []
            history = []
            claudeCodeSessionID = nil
        }
        attachmentSent = false
        attachment = newValue
        if case .window(let context) = newValue {
            dragPresenter.showHalo(around: context.frame)
        } else {
            dragPresenter.hideHalo()
        }
    }

    func attach(file url: URL) {
        setAttachment(.file(url))
        mailDraft = nil
        BipSoundPlayer.shared.play(.attach)
        onReveal?()
    }

    func removeAttachment() {
        attachment = nil
        attachmentSent = false
        dragPresenter.hideHalo()
    }

    /// The panel closed: the halo goes with it.
    func panelDidDisappear() {
        dragPresenter.hideHalo()
        if isDraggingBip {
            endBipDrag(at: nil)
        }
    }

    func panelDidAppear() {
        if case .window(let context) = attachment {
            dragPresenter.showHalo(around: context.frame)
        }
        refreshAvailability()
    }

    /// Looks for `claude` again (it may have been installed meanwhile) and
    /// loads the API's model list when needed.
    func refreshAvailability() {
        hasClaudeCode = claudeCode.executablePath != nil
        if backend == .api, hasKey, models.isEmpty {
            loadModels()
        }
    }

    // MARK: - Dragging Bip onto a window

    func beginBipDrag() {
        guard !isDraggingBip else { return }
        isDraggingBip = true
        holdIsland?(true)
        dragPresenter.showGhost(at: NSEvent.mouseLocation)
        BipSoundPlayer.shared.play(.poke)
    }

    func moveBipDrag() {
        dragPresenter.moveGhost(to: NSEvent.mouseLocation)
    }

    /// `point` is where Bip was let go (AppKit screen coordinates), or `nil`
    /// to cancel.
    func endBipDrag(at point: CGPoint?) {
        guard isDraggingBip else { return }
        isDraggingBip = false
        dragPresenter.hideGhost()
        holdIsland?(false)
        guard let point else { return }

        isCapturingWindow = true
        Task {
            defer { isCapturingWindow = false }
            guard let context = await windows.context(at: point) else {
                show(note: AppLocalization.string("agentHub.ask.noWindow"))
                return
            }
            setAttachment(.window(context))
            BipSoundPlayer.shared.play(.attach)
            if context.image == nil {
                show(note: AppLocalization.string("agentHub.ask.noCapture"))
            }
        }
    }

    // MARK: - Mail

    func startMail() {
        guard case .file(let url) = attachment else { return }
        mailDraft = AgentMailDraft(subject: url.deletingPathExtension().lastPathComponent)
    }

    var canSendMail: Bool {
        guard let mailDraft, !isMailing else { return false }
        return MailSendService.isValidAddress(mailDraft.recipient)
    }

    func sendMail() {
        guard canSendMail, let draft = mailDraft, case .file(let url) = attachment else { return }
        isMailing = true
        Task {
            defer { isMailing = false }
            do {
                try await mail.send(file: url, to: draft.recipient, subject: draft.subject, message: draft.message)
                mailDraft = nil
                show(note: AppLocalization.formatted("agentHub.mail.sent", draft.recipient))
                BipSoundPlayer.shared.play(.send)
            } catch {
                show(note: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                BipSoundPlayer.shared.play(.error)
            }
        }
    }

    private func show(note text: String) {
        note = text
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.note = nil
        }
    }
}
