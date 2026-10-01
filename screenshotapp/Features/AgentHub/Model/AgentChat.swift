import Foundation

/// The window Bip was dropped on: what it is, and a picture of it.
nonisolated struct AgentWindowContext: Equatable, Sendable {
    var appName: String
    var title: String
    /// The active tab's address, for browsers.
    var url: String?
    /// JPEG, at most 1568 px wide.
    var image: Data?
    /// The window's frame in AppKit screen coordinates (for the halo).
    var frame: CGRect

    /// "Safari · example.com", "Xcode · Project.swift"…
    var label: String {
        if let host = url.flatMap(URL.init(string:))?.host {
            return "\(appName) · \(host)"
        }
        return title.isEmpty ? appName : "\(appName) · \(title)"
    }
}

/// What a question is about besides its text.
nonisolated enum AgentChatAttachment: Equatable, Sendable {
    case file(URL)
    case window(AgentWindowContext)

    var label: String {
        switch self {
        case .file(let url): url.lastPathComponent
        case .window(let context): context.label
        }
    }

    var systemImage: String {
        switch self {
        case .file: "doc"
        case .window: "macwindow"
        }
    }
}

nonisolated struct AgentChatSource: Equatable, Sendable, Identifiable {
    let title: String
    let url: String

    var id: String { url }
}

/// One bubble of the conversation shown in the island.
nonisolated struct AgentChatEntry: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
        case failure
    }

    let id = UUID()
    let role: Role
    let text: String
    var sources: [AgentChatSource] = []
    var attachment: String?
}

/// A decoded Messages API response.
nonisolated struct ClaudeChatReply: Sendable {
    let text: String
    let sources: [AgentChatSource]
    let stopReason: String?
    /// The response's content blocks as JSON, sent back unchanged in the
    /// next request (thinking and search blocks included).
    let content: Data
}

nonisolated enum ClaudeChatError: LocalizedError, Equatable {
    case missingKey
    case unsupportedFile(String)
    case unreadableFile(String)
    case api(String)
    case refused

    var errorDescription: String? {
        switch self {
        case .missingKey: AppLocalization.string("agentHub.ask.error.key")
        case .unsupportedFile(let name): AppLocalization.formatted("agentHub.ask.error.unsupported", name)
        case .unreadableFile(let name): AppLocalization.formatted("agentHub.ask.error.unreadable", name)
        case .api(let message): message
        case .refused: AppLocalization.string("agentHub.ask.error.refused")
        }
    }
}

/// Builds Messages API requests and reads their responses. Pure.
nonisolated enum ClaudeChatProtocol {
    static let fallbackModels = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-5-1"]
    static let maxTextFileBytes = 200_000
    static let maxBinaryFileBytes = 24_000_000

    static let systemPrompt = """
    You are Bip, the assistant in DeskCast, a Mac menu bar app; your answers show in a small panel \
    around the Mac's notch. You can search the web. Answer in the user's language. Keep answers short \
    and direct: a few sentences or a short list, as plain text with line breaks. No Markdown headings, \
    tables, bold or code fences. When the question is about an attached window or file, answer about it.
    """

    /// Models that take the dynamic-filtering web search tool.
    private static let dynamicSearchPrefixes = [
        "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5", "claude-sonnet-4-6"
    ]

    /// Models that accept `fallbacks: "default"` (a refusal is answered by
    /// another model instead of failing).
    private static let defaultFallbackModels: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"
    ]

    static let fallbackBeta = "server-side-fallback-2026-07-01"

    static func webSearchTool(for model: String) -> [String: Any] {
        let isDynamic = dynamicSearchPrefixes.contains { model.hasPrefix($0) }
        return ["type": isDynamic ? "web_search_20260209" : "web_search_20250305", "name": "web_search", "max_uses": 5]
    }

    static func usesDefaultFallback(_ model: String) -> Bool {
        defaultFallbackModels.contains(model)
    }

    static func body(model: String, messages: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "system": systemPrompt,
            "tools": [webSearchTool(for: model)],
            "messages": messages
        ]
        if usesDefaultFallback(model) {
            body["fallbacks"] = "default"
        }
        return body
    }

    /// The user turn: the attachment's blocks (only on the first question
    /// about it), then the question.
    static func userContent(question: String, attachment: AgentChatAttachment?) throws -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        switch attachment {
        case .file(let url):
            blocks.append(try fileBlock(url))
            blocks.append(["type": "text", "text": "Attached file: \(url.lastPathComponent)"])
        case .window(let context):
            if let image = context.image {
                blocks.append(imageBlock(image, mediaType: "image/jpeg"))
            }
            var text = "Attached window — app: \(context.appName), title: \(context.title)"
            if let url = context.url {
                text += ", URL: \(url)"
            }
            blocks.append(["type": "text", "text": text])
        case nil:
            break
        }

        blocks.append(["type": "text", "text": question])
        return blocks
    }

    static func fileBlock(_ url: URL) throws -> [String: Any] {
        let name = url.lastPathComponent
        let mediaType = imageMediaType(for: url.pathExtension.lowercased())
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let limit = isPDF || mediaType != nil ? maxBinaryFileBytes : maxTextFileBytes

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { throw ClaudeChatError.unsupportedFile(name) }
        guard let data = try? Data(contentsOf: url) else { throw ClaudeChatError.unreadableFile(name) }

        if isPDF {
            return ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]]
        }
        if let mediaType {
            return imageBlock(data, mediaType: mediaType)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClaudeChatError.unsupportedFile(name)
        }
        return ["type": "text", "text": "Contents of \(name):\n\(text)"]
    }

    static func imageMediaType(for fileExtension: String) -> String? {
        switch fileExtension {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "webp": "image/webp"
        default: nil
        }
    }

    private static func imageBlock(_ data: Data, mediaType: String) -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]]
    }

    static func parseReply(_ data: Data) throws -> ClaudeChatReply {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else {
            throw ClaudeChatError.api(AppLocalization.string("agentHub.ask.error.response"))
        }

        let stopReason = object["stop_reason"] as? String
        if stopReason == "refusal" {
            throw ClaudeChatError.refused
        }

        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var sources: [AgentChatSource] = []
        for block in content where block["type"] as? String == "web_search_tool_result" {
            for result in block["content"] as? [[String: Any]] ?? [] {
                guard let url = result["url"] as? String, !sources.contains(where: { $0.url == url }) else { continue }
                sources.append(AgentChatSource(title: result["title"] as? String ?? url, url: url))
            }
        }

        let contentData = (try? JSONSerialization.data(withJSONObject: content)) ?? Data("[]".utf8)
        return ClaudeChatReply(text: text, sources: Array(sources.prefix(4)), stopReason: stopReason, content: contentData)
    }

    /// `error.message` of an API error, or a short fallback.
    static func errorMessage(_ data: Data, status: Int, model: String) -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let error = object["error"] as? [String: Any] else {
            return AppLocalization.formatted("agentHub.ask.error.status", status)
        }
        if error["type"] as? String == "not_found_error" {
            return AppLocalization.formatted("agentHub.ask.error.model", model)
        }
        if error["type"] as? String == "authentication_error" {
            return AppLocalization.string("agentHub.ask.error.badKey")
        }
        return error["message"] as? String ?? AppLocalization.formatted("agentHub.ask.error.status", status)
    }

    /// `GET /v1/models` → (id, display name), newest first as returned.
    static func parseModels(_ data: Data) -> [(id: String, name: String)] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = object["data"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return (id, item["display_name"] as? String ?? id)
        }
    }
}
