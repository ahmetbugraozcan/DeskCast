import AppKit
import ApplicationServices

/// A banner another app posted through macOS Notification Center.
nonisolated struct SystemNotificationBanner: Equatable, Sendable {
    let appName: String?
    let title: String
    let message: String?

    /// Stable identity used to tell a new banner from one still on screen.
    var signature: String {
        [appName ?? "", title, message ?? ""].joined(separator: "\u{1F}")
    }
}

@MainActor
protocol SystemNotificationMonitoring: AnyObject {
    var onBanner: ((SystemNotificationBanner) -> Void)? { get set }
    var isAuthorized: Bool { get }
    func start()
    func stop()
}

/// Mirrors other apps' notification banners (Messages, Mail, Gmail in the
/// browser, …) by reading the Notification Center process through the
/// Accessibility API — there is no public API for this. Requires the
/// Accessibility permission; without it the monitor stays idle.
///
/// An `AXObserver` on the Notification Center app triggers an immediate scan
/// when a banner window appears, and a slow poll covers macOS versions that
/// reuse one window for every banner. Each scan diffs the visible banners
/// against the previous scan, so only newly appeared banners are reported.
@MainActor
final class SystemNotificationMonitorService: SystemNotificationMonitoring {
    var onBanner: ((SystemNotificationBanner) -> Void)?

    private let scanQueue = DispatchQueue(
        label: "com.ahmetbugraozcan.screenshotapp.notifications.scan",
        qos: .userInitiated
    )
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var pollTimer: Timer?
    private var pendingScan: DispatchWorkItem?
    private var visibleSignatures: Set<String>?
    private var isScanning = false
    private var isStarted = false

    private static let notificationCenterBundleID = "com.apple.notificationcenterui"
    private static let pollInterval: TimeInterval = 1
    /// More new banners than this in one scan means the user opened the full
    /// Notification Center (history), not that new notifications arrived.
    private static let maxNewBannersPerScan = 2

    var isAuthorized: Bool {
        AXIsProcessTrusted()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        tick()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        pollTimer?.invalidate()
        pollTimer = nil
        pendingScan?.cancel()
        pendingScan = nil
        removeObserver()
        visibleSignatures = nil
    }

    // MARK: - Observation

    private func tick() {
        guard isStarted else { return }

        // Permission can be granted (or revoked) while DeskCast runs.
        guard isAuthorized, let pid = notificationCenterPID() else {
            removeObserver()
            visibleSignatures = nil
            return
        }

        if observedPID != pid {
            removeObserver()
            installObserver(pid: pid)
        }

        scan(pid: pid)
    }

    /// Banner windows are created before their text is filled in; scanning a
    /// beat later avoids announcing a half-populated banner.
    private func scheduleTick() {
        pendingScan?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        pendingScan = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func notificationCenterPID() -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.notificationCenterBundleID)
            .first?
            .processIdentifier
    }

    private func installObserver(pid: pid_t) {
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let service = Unmanaged<SystemNotificationMonitorService>.fromOpaque(context).takeUnretainedValue()

            // The observer's run loop source lives on the main run loop.
            MainActor.assumeIsolated {
                service.scheduleTick()
            }
        }

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let newObserver else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        // Unretained: `removeObserver()` runs before the service could go away
        // (it lives for the app's lifetime, retained by the view model).
        let context = Unmanaged.passUnretained(self).toOpaque()

        for notification in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(newObserver, appElement, notification as CFString, context)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        observer = newObserver
        observedPID = pid
    }

    private func removeObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        observer = nil
        observedPID = nil
    }

    // MARK: - Scanning

    private func scan(pid: pid_t) {
        // AX calls are cross-process IPC; keep them off the main thread and
        // never stack scans.
        guard !isScanning else { return }
        isScanning = true

        scanQueue.async { [weak self] in
            let banners = Self.visibleBanners(pid: pid)

            Task { @MainActor in
                self?.isScanning = false
                self?.apply(banners)
            }
        }
    }

    private func apply(_ banners: [SystemNotificationBanner]?) {
        guard isStarted else { return }

        // A nil result means the tree couldn't be read (e.g. Notification Center
        // is busy); keep the previous state instead of re-announcing.
        guard let banners else { return }

        let signatures = Set(banners.map(\.signature))

        defer { visibleSignatures = signatures }

        // First scan only records what is already on screen.
        guard let previous = visibleSignatures else { return }

        let newBanners = banners.filter { !previous.contains($0.signature) }

        guard !newBanners.isEmpty, newBanners.count <= Self.maxNewBannersPerScan else { return }

        newBanners.forEach { onBanner?($0) }
    }

    nonisolated private static func visibleBanners(pid: pid_t) -> [SystemNotificationBanner]? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.5)

        guard let windows: [AXUIElement] = attribute(appElement, kAXWindowsAttribute) else {
            return nil
        }

        var banners: [SystemNotificationBanner] = []
        var seen = Set<String>()

        for window in windows {
            for banner in notificationBanners(in: window) where seen.insert(banner.signature).inserted {
                banners.append(banner)
            }
        }

        return banners
    }

    /// Notification Center marks each banner group with an `AXNotificationCenter…`
    /// subrole (banner, alert, or stacked group). Its static texts are
    /// title/subtitle/body in reading order; the group description usually
    /// starts with the app name ("Messages, John, Hi there").
    nonisolated private static func notificationBanners(in window: AXUIElement) -> [SystemNotificationBanner] {
        var groups: [AXUIElement] = []
        var visited = 0
        collectNotificationGroups(in: window, depth: 0, visited: &visited, into: &groups)

        return groups.compactMap { group in
            var texts: [String] = []
            var visitedTexts = 0
            collectStaticTexts(in: group, depth: 0, visited: &visitedTexts, into: &texts)

            let description: String? = attribute(group, kAXDescriptionAttribute)
            return makeBanner(texts: texts, description: description)
        }
    }

    nonisolated private static func makeBanner(texts: [String], description: String?) -> SystemNotificationBanner? {
        var texts = texts
        var appName: String?

        if let description {
            let components = description
                .components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // The leading component is the app name when it isn't one of the texts.
            if let first = components.first, components.count > 1, first != texts.first {
                appName = first
            }

            if texts.isEmpty {
                texts = Array(components.dropFirst(appName == nil ? 0 : 1))
            }
        }

        if let appName, texts.first == appName {
            texts.removeFirst()
        }

        guard let title = texts.first else { return nil }

        let message = texts.dropFirst().joined(separator: " ")

        return SystemNotificationBanner(
            appName: appName,
            title: title,
            message: message.isEmpty ? nil : message
        )
    }

    nonisolated private static func collectNotificationGroups(
        in element: AXUIElement,
        depth: Int,
        visited: inout Int,
        into groups: inout [AXUIElement]
    ) {
        visited += 1
        guard depth < 10, visited < 400 else { return }

        if let subrole: String = attribute(element, kAXSubroleAttribute),
           subrole.hasPrefix("AXNotificationCenter"),
           subrole != "AXNotificationCenterBannerStack" {
            groups.append(element)
            return
        }

        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return }

        for child in children {
            collectNotificationGroups(in: child, depth: depth + 1, visited: &visited, into: &groups)
        }
    }

    nonisolated private static func collectStaticTexts(
        in element: AXUIElement,
        depth: Int,
        visited: inout Int,
        into texts: inout [String]
    ) {
        visited += 1
        guard depth < 8, visited < 120 else { return }

        if let role: String = attribute(element, kAXRoleAttribute), role == kAXStaticTextRole {
            if let value: String = attribute(element, kAXValueAttribute) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

                if !trimmed.isEmpty {
                    texts.append(trimmed)
                }
            }

            return
        }

        guard let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { return }

        for child in children {
            collectStaticTexts(in: child, depth: depth + 1, visited: &visited, into: &texts)
        }
    }

    nonisolated private static func attribute<Value>(_ element: AXUIElement, _ name: String) -> Value? {
        var value: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }

        return value as? Value
    }
}
