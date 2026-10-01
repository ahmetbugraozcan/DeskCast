import SwiftUI
import UniformTypeIdentifiers

/// The Ask page: chat with Claude from the island. Drop a file on it to ask
/// about it (or mail it), or drag Bip onto any window to ask about that.
struct AgentAskView: View {
    @ObservedObject var chat: AgentChatViewModel

    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if chat.hasKey {
                conversation
            } else {
                AgentKeySetupCard(chat: chat)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Self.loadFile(from: providers) { chat.attach(file: $0) }
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AgentHubPhase.finished.color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(RoundedRectangle(cornerRadius: 16).fill(AgentHubPhase.finished.color.opacity(0.08)))
                    .overlay(
                        Label(AppLocalization.string("agentHub.ask.dropHere"), systemImage: "arrow.down.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .onAppear { chat.panelDidAppear() }
        .onDisappear { chat.panelDidDisappear() }
    }

    private var conversation: some View {
        VStack(spacing: 8) {
            if let mailDraft = chat.mailDraft {
                AgentMailForm(chat: chat, draft: mailDraft)
            } else {
                AgentConversationView(chat: chat)
            }

            AgentAskInputBar(chat: chat)
        }
        .overlay(alignment: .top) {
            if let note = chat.note {
                Text(note)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: chat.note)
    }

    static func loadFile(from providers: [NSItemProvider], perform: @escaping @MainActor (URL) -> Void) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, url.isFileURL else { return }
            Task { @MainActor in perform(url) }
        }
    }
}

// MARK: - Conversation

private struct AgentConversationView: View {
    @ObservedObject var chat: AgentChatViewModel

    var body: some View {
        if chat.entries.isEmpty, !chat.isSending {
            AgentWashCard {
                HStack(spacing: 14) {
                    BipMascotView(mood: chat.attachment == nil ? .idle : .happy, size: 66)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.string(chat.attachment == nil ? "agentHub.ask.title" : "agentHub.ask.attachedTitle"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("agentHub.ask.hint"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(IslandPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(chat.entries) { entry in
                            AgentChatBubble(chat: chat, entry: entry)
                                .id(entry.id)
                        }
                        if chat.isSending {
                            HStack(spacing: 8) {
                                BipMascotView(mood: chat.mood, size: 28, isInteractive: false)
                                AgentShimmerText(text: AppLocalization.string(
                                    chat.attachment == nil ? "agentHub.ask.searching" : "agentHub.ask.reading"
                                ), size: 12.5)
                            }
                            .id("sending")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chat.entries.count) { _, _ in
                    withAnimation { proxy.scrollTo(chat.entries.last?.id, anchor: .bottom) }
                }
                .onChange(of: chat.isSending) { _, sending in
                    if sending { withAnimation { proxy.scrollTo("sending", anchor: .bottom) } }
                }
            }
            .padding(10)
            .frame(maxHeight: .infinity)
            .background(IslandPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct AgentChatBubble: View {
    @ObservedObject var chat: AgentChatViewModel
    let entry: AgentChatEntry

    var body: some View {
        switch entry.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    if let attachment = entry.attachment {
                        Label(attachment, systemImage: "paperclip")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(IslandPalette.secondaryText)
                            .lineLimit(1)
                    }
                    Text(entry.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.94)))
                        .textSelection(.enabled)
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    ForEach(entry.sources) { source in
                        IslandChipButton(title: URL(string: source.url)?.host ?? source.title, systemImage: "link") {
                            chat.open(source)
                        }
                        .help(source.title)
                    }
                    IslandIconButton(systemImage: "doc.on.doc", help: AppLocalization.string("agentHub.ask.copy"), size: 10.5) {
                        chat.copy(entry)
                    }
                }
            }
        case .failure:
            Label(entry.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.59))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
