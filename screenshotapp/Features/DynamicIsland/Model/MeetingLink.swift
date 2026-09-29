import Foundation

/// A video call link found in a calendar event.
struct MeetingLink: Equatable {
    enum Service: Equatable {
        case zoom
        case googleMeet
        case teams
        case webex
        case faceTime
        case other

        var displayName: String {
            switch self {
            case .zoom: "Zoom"
            case .googleMeet: "Google Meet"
            case .teams: "Teams"
            case .webex: "Webex"
            case .faceTime: "FaceTime"
            case .other: ""
            }
        }
    }

    let url: URL
    let service: Service

    /// The first meeting link in the event's URL, location or notes, in that
    /// order. Only known video call hosts count, so ordinary links (agendas,
    /// documents) never turn into a "Join" button.
    static func find(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = MeetingLink(url) {
            return link
        }

        for text in [location, notes].compactMap({ $0 }) where !text.isEmpty {
            if let link = links(in: text).lazy.compactMap(MeetingLink.init).first {
                return link
            }
        }

        return nil
    }

    init?(_ url: URL) {
        guard let service = Self.service(for: url) else { return nil }
        self.url = url
        self.service = service
    }

    private static func service(for url: URL) -> Service? {
        let scheme = url.scheme?.lowercased() ?? ""

        switch scheme {
        case "zoommtg", "zoomus": return .zoom
        case "msteams": return .teams
        case "facetime": return .faceTime
        case "http", "https": break
        default: return nil
        }

        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()

        func matches(_ domain: String) -> Bool {
            host == domain || host.hasSuffix("." + domain)
        }

        if matches("zoom.us") || matches("zoomgov.com") {
            // Meeting and webinar joins, personal rooms; not zoom.us marketing pages.
            return ["/j/", "/w/", "/my/", "/s/"].contains { path.hasPrefix($0) } ? .zoom : nil
        }

        if host == "meet.google.com" {
            return path.count > 1 ? .googleMeet : nil
        }

        if matches("teams.microsoft.com") || matches("teams.live.com") {
            return path.contains("meet") ? .teams : nil
        }

        if matches("webex.com") {
            return .webex
        }

        if host == "facetime.apple.com" {
            return .faceTime
        }

        if ["whereby.com", "around.co", "chime.aws", "meet.jit.si", "gotomeeting.com"].contains(where: matches) {
            return .other
        }

        return nil
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }

        return detector
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
    }
}
