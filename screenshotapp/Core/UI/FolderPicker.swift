import AppKit

/// Presents a directory chooser. Injected so view models don't run `NSOpenPanel`
/// modals directly (keeps them UI-free and testable).
@MainActor
protocol FolderPicking {
    func pickDirectory(prompt: String, canCreate: Bool) -> URL?
}

@MainActor
struct FolderPicker: FolderPicking {
    func pickDirectory(prompt: String, canCreate: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = canCreate
        panel.prompt = prompt

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url
    }
}
