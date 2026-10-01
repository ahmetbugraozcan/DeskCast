import SwiftUI

/// First run of the Ask page: paste an Anthropic API key (kept in the Keychain).
struct AgentKeySetupCard: View {
    @ObservedObject var chat: AgentChatViewModel

    @State private var key = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        AgentWashCard(tint: AgentHubPhase.thinking.color) {
            HStack(spacing: 14) {
                BipMascotView(mood: .question, size: 66)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string("agentHub.ask.keyTitle"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(AppLocalization.string("agentHub.ask.keyMessage"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        SecureField("sk-ant-…", text: $key)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .focused($isFocused)
                            .onSubmit(save)

                        AgentActionButton(title: AppLocalization.string("agentHub.ask.saveKey"), isPrimary: true, action: save)
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    Link(AppLocalization.string("agentHub.ask.getKey"), destination: Self.consoleURL)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AgentHubPhase.idle.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: isFocused) { _, focused in chat.isInputFocused = focused }
    }

    // swiftlint:disable:next force_unwrapping
    private static let consoleURL = URL(string: "https://console.anthropic.com/settings/keys")!

    private func save() {
        chat.saveKey(key)
        key = ""
        isFocused = false
    }
}

/// Bip (drag it onto a window), the attachment, the question field and Send.
struct AgentAskInputBar: View {
    @ObservedObject var chat: AgentChatViewModel

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            draggableBip

            if let attachment = chat.attachment {
                attachmentChip(attachment)
            }

            TextField(AppLocalization.string("agentHub.ask.placeholder"), text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1...3)
                .focused($isFocused)
                .onSubmit { chat.send() }
                .frame(maxWidth: .infinity)

            Menu {
                if case .file = chat.attachment {
                    Button(AppLocalization.string("agentHub.mail.start"), systemImage: "envelope") { chat.startMail() }
                }
                Button(AppLocalization.string("agentHub.ask.clear"), systemImage: "trash") { chat.clear() }
                    .disabled(chat.entries.isEmpty && chat.attachment == nil)
                Divider()
                Button(AppLocalization.string("agentHub.ask.removeKey"), systemImage: "key.slash", role: .destructive) { chat.removeKey() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button(action: chat.send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(chat.canSend ? Color.black : Color.white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(chat.canSend ? Color.white : Color.white.opacity(0.1)))
            }
            .buttonStyle(IslandScaleButtonStyle())
            .disabled(!chat.canSend)
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Capsule().fill(IslandPalette.card))
        .overlay(Capsule().stroke(isFocused ? Color.white.opacity(0.2) : IslandPalette.cardStroke, lineWidth: 1))
        .onChange(of: isFocused) { _, focused in chat.isInputFocused = focused }
        .onChange(of: chat.isInputFocused) { _, focused in if !focused { isFocused = false } }
        .onDisappear { chat.isInputFocused = false }
    }

    private var draggableBip: some View {
        BipMascotView(mood: chat.isCapturingWindow ? .searching : chat.mood, size: 34, isInteractive: false)
            .opacity(chat.isDraggingBip ? 0 : 1)
            .help(AppLocalization.string("agentHub.ask.dragBip"))
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { _ in
                        chat.beginBipDrag()
                        chat.moveBipDrag()
                    }
                    .onEnded { value in
                        // A short drag that stays in the island is a cancel.
                        let travel = hypot(value.translation.width, value.translation.height)
                        chat.endBipDrag(at: travel > 80 ? NSEvent.mouseLocation : nil)
                    }
            )
    }

    private func attachmentChip(_ attachment: AgentChatAttachment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: attachment.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(attachment.label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                chat.removeAttachment()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .frame(maxWidth: 180)
        .background(Capsule().fill(BipMood.searching.color.opacity(0.3)))
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// To / Subject / Message for sending the dropped file with Mail.
struct AgentMailForm: View {
    @ObservedObject var chat: AgentChatViewModel
    let draft: AgentMailDraft

    @FocusState private var focus: Field?

    private enum Field {
        case recipient
        case subject
        case message
    }

    var body: some View {
        AgentWashCard(tint: AgentHubPhase.idle.color) {
            VStack(alignment: .leading, spacing: 8) {
                Label(AppLocalization.string("agentHub.mail.title"), systemImage: "envelope.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                field(AppLocalization.string("agentHub.mail.to"), text: binding(\.recipient), field: .recipient)
                field(AppLocalization.string("agentHub.mail.subject"), text: binding(\.subject), field: .subject)
                field(AppLocalization.string("agentHub.mail.message"), text: binding(\.message), field: .message)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text(AppLocalization.string("agentHub.mail.note"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(IslandPalette.tertiaryText)
                    Spacer()
                    AgentActionButton(title: AppLocalization.string("agentHub.cancel")) { chat.mailDraft = nil }
                    AgentActionButton(
                        title: AppLocalization.string("agentHub.mail.send"), systemImage: "paperplane.fill", isPrimary: true
                    ) {
                        chat.sendMail()
                    }
                    .disabled(!chat.canSendMail)
                    .opacity(chat.canSendMail ? 1 : 0.5)
                }
            }
        }
        .onAppear { focus = .recipient }
        .onChange(of: focus) { _, value in chat.isInputFocused = value != nil }
    }

    private func binding(_ keyPath: WritableKeyPath<AgentMailDraft, String>) -> Binding<String> {
        Binding(
            get: { chat.mailDraft?[keyPath: keyPath] ?? "" },
            set: { chat.mailDraft?[keyPath: keyPath] = $0 }
        )
    }

    private func field(_ title: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(IslandPalette.secondaryText)
                .frame(width: 58, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .focused($focus, equals: field)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}
