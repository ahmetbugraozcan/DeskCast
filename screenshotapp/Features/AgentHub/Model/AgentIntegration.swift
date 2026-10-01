import Foundation

/// A service the Connections page can follow with the user's own key.
nonisolated enum AgentIntegration: String, CaseIterable, Identifiable, Sendable {
    case stripe
    case vercel
    case n8n
    case github
    case resend
    case notion
    case calcom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .stripe: "Stripe"
        case .vercel: "Vercel"
        case .n8n: "n8n"
        case .github: "GitHub"
        case .resend: "Resend"
        case .notion: "Notion"
        case .calcom: "Cal.com"
        }
    }

    var secret: AgentSecret {
        switch self {
        case .stripe: .stripe
        case .vercel: .vercel
        case .n8n: .n8n
        case .github: .github
        case .resend: .resend
        case .notion: .notion
        case .calcom: .calcom
        }
    }

    /// Brand-ish color for its pill and its Bip.
    var tint: BipRGB {
        switch self {
        case .stripe: BipRGB(red: 0.39, green: 0.36, blue: 1)
        case .vercel: BipRGB(red: 0.9, green: 0.9, blue: 0.92)
        case .n8n: BipRGB(red: 0.95, green: 0.42, blue: 0.36)
        case .github: BipRGB(red: 0.55, green: 0.62, blue: 0.72)
        case .resend: BipRGB(red: 0.3, green: 0.85, blue: 0.55)
        case .notion: BipRGB(red: 0.82, green: 0.78, blue: 0.7)
        case .calcom: BipRGB(red: 0.79, green: 0.58, blue: 0.42)
        }
    }

    var systemImage: String {
        switch self {
        case .stripe: "creditcard"
        case .vercel: "triangle.fill"
        case .n8n: "point.3.filled.connected.trianglepath.dotted"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .resend: "paperplane"
        case .notion: "doc.text"
        case .calcom: "calendar"
        }
    }

    /// How often it's checked while turned on.
    var pollInterval: TimeInterval {
        switch self {
        case .n8n: 15
        case .stripe, .vercel: 30
        case .resend: 60
        case .github, .notion, .calcom: 300
        }
    }

    /// Where the key is made.
    var keyHelpURL: String {
        switch self {
        case .stripe: "https://dashboard.stripe.com/apikeys"
        case .vercel: "https://vercel.com/account/tokens"
        case .n8n: "https://docs.n8n.io/api/authentication/"
        case .github: "https://github.com/settings/tokens"
        case .resend: "https://resend.com/api-keys"
        case .notion: "https://www.notion.so/profile/integrations"
        case .calcom: "https://app.cal.com/settings/developer/api-keys"
        }
    }
}

// MARK: - Snapshots

nonisolated struct StripePayment: Identifiable, Equatable, Sendable {
    let id: String
    let amount: Int
    let currency: String
    let summary: String?
    let date: Date
    let succeeded: Bool
}

nonisolated struct StripeSnapshot: Equatable, Sendable {
    var balance: Int
    var currency: String
    var payments: [StripePayment]
}

nonisolated struct VercelDeployment: Identifiable, Equatable, Sendable {
    let id: String
    let project: String
    let url: String
    /// READY, ERROR, CANCELED, BUILDING, QUEUED…
    let state: String
    let date: Date
    let commit: String?
    let branch: String?

    var isFinished: Bool { ["READY", "ERROR", "CANCELED"].contains(state) }
    var succeeded: Bool { state == "READY" }
}

nonisolated struct N8nExecution: Identifiable, Equatable, Sendable {
    let id: String
    let workflowID: String?
    var workflowName: String?
    /// success, error, crashed, canceled, running, waiting…
    let status: String
    let date: Date?

    var isFinished: Bool { ["success", "error", "crashed", "canceled", "failed"].contains(status) }
    var failed: Bool { ["error", "crashed", "failed"].contains(status) }
}

nonisolated struct ResendEmail: Identifiable, Equatable, Sendable {
    let id: String
    let recipients: [String]
    let subject: String
    let date: Date
    /// delivered, bounced, opened, sent…
    let lastEvent: String
}

nonisolated struct GitHubSummary: Equatable, Sendable {
    let login: String
    let repositories: Int
    let stars: Int
    let followers: Int
}

nonisolated struct NotionPage: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let emoji: String?
    let date: Date
    let url: String
}

nonisolated struct CalBooking: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let attendee: String?
}

/// The latest reading of one integration.
nonisolated enum IntegrationSnapshot: Equatable, Sendable {
    case stripe(StripeSnapshot)
    case vercel([VercelDeployment])
    case n8n([N8nExecution])
    case resend(emails: [ResendEmail], total: Int?)
    case github(GitHubSummary)
    case notion([NotionPage])
    case calcom([CalBooking])
}
