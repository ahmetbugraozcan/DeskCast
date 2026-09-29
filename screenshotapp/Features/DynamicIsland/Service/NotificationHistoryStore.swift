import AppKit
import Foundation

/// Keeps the island's notification history between launches.
@MainActor
protocol NotificationHistoryPersisting: AnyObject {
    func load() -> [DynamicIslandNotification]
    func save(_ notifications: [DynamicIslandNotification])
}

/// Codable form of a history entry: text, time and the posting app. Images
/// aren't stored; system notifications get their app's icon back on load.
nonisolated struct StoredIslandNotification: Codable, Equatable, Sendable {
    let caption: String?
    let title: String
    let message: String?
    let systemImage: String
    let style: String
    let date: Date
    let sourceAppPath: String?
}

extension StoredIslandNotification {
    init?(_ notification: DynamicIslandNotification) {
        guard let style = Self.name(of: notification.style) else { return nil }
        caption = notification.caption
        title = notification.title
        message = notification.message
        systemImage = notification.systemImage
        self.style = style
        date = notification.date
        sourceAppPath = notification.sourceAppURL?.path
    }

    var notification: DynamicIslandNotification? {
        guard let style = Self.style(named: style) else { return nil }
        let appURL = sourceAppPath.map { URL(fileURLWithPath: $0) }
        return DynamicIslandNotification(
            date: date,
            caption: caption,
            title: title,
            message: message,
            systemImage: systemImage,
            style: style,
            image: appURL.map { NSWorkspace.shared.icon(forFile: $0.path) },
            sourceAppURL: appURL
        )
    }

    /// Media banners are transient and never kept.
    private static func name(of style: DynamicIslandNotificationStyle) -> String? {
        switch style {
        case .info: "info"
        case .success: "success"
        case .warning: "warning"
        case .error: "error"
        case .battery: "battery"
        case .system: "system"
        case .media: nil
        }
    }

    private static func style(named name: String) -> DynamicIslandNotificationStyle? {
        let styles: [DynamicIslandNotificationStyle] = [.info, .success, .warning, .error, .battery, .system]
        return styles.first { Self.name(of: $0) == name }
    }
}

/// JSON file in Application Support, readable only by the user.
@MainActor
final class NotificationHistoryFileStore: NotificationHistoryPersisting {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.deskcast.notification-history", qos: .utility)

    init(fileURL: URL = NotificationHistoryFileStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("DeskCast", isDirectory: true)
            .appendingPathComponent("NotificationHistory.json")
    }

    func load() -> [DynamicIslandNotification] {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([StoredIslandNotification].self, from: data) else {
            return []
        }
        return stored.compactMap(\.notification)
    }

    func save(_ notifications: [DynamicIslandNotification]) {
        let stored = notifications.compactMap(StoredIslandNotification.init)
        let fileURL = fileURL
        queue.async {
            guard !stored.isEmpty else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            guard let data = try? JSONEncoder().encode(stored) else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }
}
