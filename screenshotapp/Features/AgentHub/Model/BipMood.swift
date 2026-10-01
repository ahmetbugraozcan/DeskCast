import Foundation

/// Bip, DeskCast's agent mascot: a small monitor-shaped robot with LED eyes
/// on its screen and a lamp on its antenna. Its mood follows the agent it
/// stands for, and the user can poke it.
nonisolated enum BipMood: String, CaseIterable, Sendable {
    case idle
    case thinking
    case working
    case searching
    case approval
    case question
    case error
    case finished
    case rateLimited
    case sleeping
    case dizzy
    case annoyed
    case happy

    init(phase: AgentHubPhase) {
        switch phase {
        case .idle: self = .idle
        case .thinking: self = .thinking
        case .working: self = .working
        case .approval: self = .approval
        case .question: self = .question
        case .error: self = .error
        case .finished: self = .finished
        case .rateLimited: self = .rateLimited
        }
    }

    /// Lamp and screen tint.
    var tint: BipRGB {
        switch self {
        case .idle: BipRGB(red: 0.55, green: 0.85, blue: 1.0)
        case .thinking: BipRGB(red: 0.66, green: 0.52, blue: 1.0)
        case .working: BipRGB(red: 0.25, green: 0.63, blue: 1.0)
        case .searching: BipRGB(red: 0.4, green: 0.45, blue: 1.0)
        case .approval: BipRGB(red: 1.0, green: 0.7, blue: 0.2)
        case .question: BipRGB(red: 0.2, green: 0.86, blue: 0.95)
        case .error: BipRGB(red: 1.0, green: 0.33, blue: 0.38)
        case .finished, .happy: BipRGB(red: 0.3, green: 0.87, blue: 0.6)
        case .rateLimited: BipRGB(red: 1.0, green: 0.56, blue: 0.24)
        case .sleeping: BipRGB(red: 0.55, green: 0.62, blue: 0.72)
        case .dizzy: BipRGB(red: 0.98, green: 0.45, blue: 0.75)
        case .annoyed: BipRGB(red: 0.72, green: 0.4, blue: 1.0)
        }
    }

    /// The antenna lamp blinks while the agent works.
    var lampBlinkRate: Double {
        switch self {
        case .working, .searching: 3.2
        case .thinking: 1.6
        case .approval, .question, .error: 2.4
        default: 0
        }
    }
}

/// A color as RGB in 0...1, kept free of SwiftUI so models can use it.
nonisolated struct BipRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}
