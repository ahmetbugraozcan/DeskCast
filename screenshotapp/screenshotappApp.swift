//
//  screenshotappApp.swift
//  screenshotapp
//
//  Created by Ahmet Buğra Özcan on 2.05.2026.
//

import AppKit
import SwiftUI

@main
struct screenshotappApp: App {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var screenshotStore = ScreenshotShelfStore()
    @StateObject private var dropShelfStore = DropShelfStore.shared
    @AppStorage(ToolboxSettings.Keys.menuLayout)
    private var menuLayoutRaw = ToolboxSettings.defaultMenuLayout.rawValue
    @AppStorage(ToolboxSettings.Keys.language)
    private var languageRaw = ToolboxSettings.defaultLanguage.rawValue
    @AppStorage(ToolboxSettings.Keys.captureSelectedAreaEnabled)
    private var captureSelectedAreaEnabled = ToolboxSettings.defaultCaptureSelectedAreaEnabled
    @AppStorage(ToolboxSettings.Keys.captureSelectedAreaShowInMenu)
    private var captureSelectedAreaShowInMenu = ToolboxSettings.defaultCaptureSelectedAreaShowInMenu
    @AppStorage(ToolboxSettings.Keys.captureOCREnabled)
    private var captureOCREnabled = ToolboxSettings.defaultCaptureOCREnabled
    @AppStorage(ToolboxSettings.Keys.captureOCRShowInMenu)
    private var captureOCRShowInMenu = ToolboxSettings.defaultCaptureOCRShowInMenu
    @AppStorage(ToolboxSettings.Keys.copyFinderPathEnabled)
    private var copyFinderPathEnabled = ToolboxSettings.defaultCopyFinderPathEnabled
    @AppStorage(ToolboxSettings.Keys.copyFinderPathShowInMenu)
    private var copyFinderPathShowInMenu = ToolboxSettings.defaultCopyFinderPathShowInMenu
    @AppStorage(ToolboxSettings.Keys.imageSearchEnabled)
    private var imageSearchEnabled = ToolboxSettings.defaultImageSearchEnabled
    @AppStorage(ToolboxSettings.Keys.imageSearchShowInMenu)
    private var imageSearchShowInMenu = ToolboxSettings.defaultImageSearchShowInMenu
    @AppStorage(ToolboxSettings.Keys.dropShelfEnabled)
    private var dropShelfEnabled = ToolboxSettings.defaultDropShelfEnabled
    @AppStorage(ToolboxSettings.Keys.dropShelfShowInMenu)
    private var dropShelfShowInMenu = ToolboxSettings.defaultDropShelfShowInMenu

    init() {
        ScreenshotShelfSettings.registerDefaults()
        DropShelfSettings.registerDefaults()
        ToolboxSettings.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra(AppConstants.displayName, systemImage: "camera.viewfinder") {
            switch selectedMenuLayout {
            case .expanded:
                expandedMenuContent
            case .grouped:
                groupedMenuContent
            }

            appMenuFooter
        }
        .environment(\.locale, selectedLanguage.locale)

        Settings {
            SettingsView()
        }
        .environment(\.locale, selectedLanguage.locale)

        Window(AppLocalization.string("Image Search"), id: "image-search") {
            ImageTextSearchView()
        }
        .defaultSize(width: 720, height: 500)
        .environment(\.locale, selectedLanguage.locale)
    }

    @ViewBuilder
    private var expandedMenuContent: some View {
        if shouldShowScreenshotActionsInMenu {
            menuSectionHeader(AppLocalization.string("Screenshots"))
            screenshotToolButtons

            if hasVisibleScreenshotTools {
                Divider()
            }

            screenshotShelfButtons

            Divider()
        }

        if shouldShowFileActionsInMenu {
            menuSectionHeader(AppLocalization.string("Files"))
            fileToolButtons
            Divider()
        }
    }

    @ViewBuilder
    private var groupedMenuContent: some View {
        if shouldShowScreenshotActionsInMenu {
            Menu {
                screenshotToolButtons

                if hasVisibleScreenshotTools {
                    Divider()
                }

                screenshotShelfButtons
            } label: {
                Label(AppLocalization.string("Screenshots"), systemImage: "camera.viewfinder")
            }

            Divider()
        }

        if shouldShowFileActionsInMenu {
            Menu {
                fileToolButtons
            } label: {
                Label(AppLocalization.string("Files"), systemImage: "folder")
            }

            Divider()
        }
    }

    @ViewBuilder
    private var screenshotToolButtons: some View {
        if shouldShowCaptureSelectedAreaInMenu {
            Button {
                screenshotStore.captureSelectedArea()
            } label: {
                Label(
                    ToolboxToolID.captureSelectedArea.title,
                    systemImage: ToolboxToolID.captureSelectedArea.systemImage
                )
            }
            .disabled(screenshotStore.isCapturing)
        }

        if shouldShowCaptureOCRInMenu {
            Button {
                screenshotStore.captureOCRTextFromSelectedArea()
            } label: {
                Label(ToolboxToolID.captureOCR.title, systemImage: ToolboxToolID.captureOCR.systemImage)
            }
            .disabled(screenshotStore.isCapturing)
        }

        if shouldShowImageSearchInMenu {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "image-search")
            } label: {
                Label(ToolboxToolID.imageSearch.title, systemImage: ToolboxToolID.imageSearch.systemImage)
            }
        }
    }

    @ViewBuilder
    private var screenshotShelfButtons: some View {
        Button {
            screenshotStore.copyAll()
        } label: {
            Label("Copy All", systemImage: "doc.on.doc")
        }
        .disabled(screenshotStore.screenshots.isEmpty)

        Button(role: .destructive) {
            screenshotStore.clearAll()
        } label: {
            Label("Clear All", systemImage: "trash")
        }
        .disabled(screenshotStore.screenshots.isEmpty)
    }

    private var copyFinderPathButton: some View {
        Button {
            screenshotStore.copyFrontFinderPath()
        } label: {
            Label(ToolboxToolID.copyFinderPath.title, systemImage: ToolboxToolID.copyFinderPath.systemImage)
        }
    }

    @ViewBuilder
    private var fileToolButtons: some View {
        if shouldShowCopyFinderPathInMenu {
            copyFinderPathButton
        }

        if shouldShowCopyFinderPathInMenu && shouldShowDropShelfInMenu {
            Divider()
        }

        if shouldShowDropShelfInMenu {
            dropShelfButtons
        }
    }

    @ViewBuilder
    private var dropShelfButtons: some View {
        Button {
            dropShelfStore.toggleShelf()
        } label: {
            Label(
                dropShelfStore.isShelfVisible
                    ? AppLocalization.string("Hide Drop Shelf")
                    : AppLocalization.string("Show Drop Shelf"),
                systemImage: ToolboxToolID.dropShelf.systemImage
            )
        }

        Button {
            dropShelfStore.sendAll()
        } label: {
            Label("Send Shelf Items", systemImage: "paperplane")
        }
        .disabled(dropShelfStore.items.isEmpty)

        Button(role: .destructive) {
            dropShelfStore.clearAll()
        } label: {
            Label("Clear Drop Shelf", systemImage: "trash")
        }
        .disabled(dropShelfStore.items.isEmpty)
    }

    @ViewBuilder
    private var appMenuFooter: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        Divider()

        Button(AppLocalization.formatted("Quit %@", AppConstants.displayName)) {
            NSApp.terminate(nil)
        }
    }

    private var selectedMenuLayout: ToolboxMenuLayout {
        ToolboxMenuLayout(rawValue: menuLayoutRaw) ?? ToolboxSettings.defaultMenuLayout
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? ToolboxSettings.defaultLanguage
    }

    private func menuSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .disabled(true)
    }

    private var shouldShowScreenshotActionsInMenu: Bool {
        hasVisibleScreenshotTools
            || !screenshotStore.screenshots.isEmpty
    }

    private var hasVisibleScreenshotTools: Bool {
        shouldShowCaptureSelectedAreaInMenu
            || shouldShowCaptureOCRInMenu
            || shouldShowImageSearchInMenu
    }

    private var shouldShowCaptureSelectedAreaInMenu: Bool {
        captureSelectedAreaEnabled && captureSelectedAreaShowInMenu
    }

    private var shouldShowCaptureOCRInMenu: Bool {
        captureOCREnabled && captureOCRShowInMenu
    }

    private var shouldShowCopyFinderPathInMenu: Bool {
        copyFinderPathEnabled && copyFinderPathShowInMenu
    }

    private var shouldShowImageSearchInMenu: Bool {
        imageSearchEnabled && imageSearchShowInMenu
    }

    private var shouldShowDropShelfInMenu: Bool {
        dropShelfEnabled && dropShelfShowInMenu
    }

    private var shouldShowFileActionsInMenu: Bool {
        shouldShowCopyFinderPathInMenu || shouldShowDropShelfInMenu
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon as early as possible. The app ships without
        // LSUIElement so Spotlight/Raycast can index it, and flips to accessory
        // here to stay menu-bar only with minimal Dock flash at launch.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
