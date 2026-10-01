import Foundation

extension DynamicIslandViewModel {
    /// DeskCast's own alerts peek in the closed island's wings unless the user
    /// asked for full banners.
    func postAlert(_ banner: DynamicIslandNotification, peek text: String) {
        post(preferences.fullBanners ? banner : banner.asPeek(showing: text))
    }

    /// A meeting with a Join button keeps its banner so the button can be clicked.
    func postReminder(_ banner: DynamicIslandNotification) {
        if banner.action == nil {
            postAlert(banner, peek: banner.title)
        } else {
            post(banner)
        }
    }
}
