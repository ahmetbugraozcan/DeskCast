//
//  DeskCastApp.swift
//  screenshotapp
//
//  Created by Ahmet Buğra Özcan on 2.05.2026.
//

import AppKit
import SwiftUI

@main
struct DeskCastApp: App {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment
    @StateObject private var screenRecorderStore: ScreenRecordingViewModel
    @StateObject private var screenshotStore: ScreenshotShelfViewModel
    @StateObject private var dropShelfStore: DropShelfViewModel
    @StateObject private var dynamicIslandStore: DynamicIslandViewModel
    @StateObject private var colorPickerStore: ColorPickerViewModel
    @AppStorage(ToolboxSettings.Keys.menuLayout)
    private var menuLayoutRaw = ToolboxSettings.defaultMenuLayout.rawValue
    @AppStorage(ToolboxSettings.Keys.language)
    private var languageRaw = ToolboxSettings.defaultLanguage.rawValue
    @AppStorage(ToolboxSettings.Keys.captureSelectedAreaEnabled)
    private var captureSelectedAreaEnabled = ToolboxSettings.defaultCaptureSelectedAreaEnabled
    @AppStorage(ToolboxSettings.Keys.captureSelectedAreaShowInMenu)
    private var captureSelectedAreaShowInMenu = ToolboxSettings.defaultCaptureSelectedAreaShowInMenu
    @AppStorage(ToolboxSettings.Keys.captureVideoEnabled)
    private var captureVideoEnabled = ToolboxSettings.defaultCaptureVideoEnabled
    @AppStorage(ToolboxSettings.Keys.captureVideoShowInMenu)
    private var captureVideoShowInMenu = ToolboxSettings.defaultCaptureVideoShowInMenu
    @AppStorage(ToolboxSettings.Keys.captureOCREnabled)
    private var captureOCREnabled = ToolboxSettings.defaultCaptureOCREnabled
    @AppStorage(ToolboxSettings.Keys.captureOCRShowInMenu)
    private var captureOCRShowInMenu = ToolboxSettings.defaultCaptureOCRShowInMenu
    @AppStorage(ToolboxSettings.Keys.pickColorEnabled)
    private var pickColorEnabled = ToolboxSettings.defaultPickColorEnabled
    @AppStorage(ToolboxSettings.Keys.pickColorShowInMenu)
    private var pickColorShowInMenu = ToolboxSettings.defaultPickColorShowInMenu
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
    @AppStorage(ToolboxSettings.Keys.dynamicIslandEnabled)
    private var dynamicIslandEnabled = ToolboxSettings.defaultDynamicIslandEnabled
    @AppStorage(ToolboxSettings.Keys.dynamicIslandShowInMenu)
    private var dynamicIslandShowInMenu = ToolboxSettings.defaultDynamicIslandShowInMenu

    init() {
        // Composition root wires the view models and their dependencies (and
        // registers UserDefaults defaults) in one place.
        let environment = AppEnvironment()
        _environment = StateObject(wrappedValue: environment)
        _screenRecorderStore = StateObject(wrappedValue: environment.screenRecorder)
        _screenshotStore = StateObject(wrappedValue: environment.screenshotShelf)
        _dropShelfStore = StateObject(wrappedValue: environment.dropShelf)
        _dynamicIslandStore = StateObject(wrappedValue: environment.dynamicIsland)
        _colorPickerStore = StateObject(wrappedValue: environment.colorPicker)
    }

    var body: some Scene {
        // The panel and the classic menus need different MenuBarExtra styles,
        // so each layout has its own scene and only one is inserted.
        MenuBarExtra(isInserted: menuLayoutBinding(isPanel: true)) {
            MenuBarPanelView(
                screenshots: screenshotStore,
                recorder: screenRecorderStore,
                dropShelf: dropShelfStore,
                island: dynamicIslandStore,
                colorPicker: colorPickerStore,
                visibility: menuPanelVisibility,
                actions: menuPanelActions
            )
            .environment(\.locale, selectedLanguage.locale)
        } label: {
            Image(systemName: "camera.viewfinder")
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(
            AppConstants.displayName,
            systemImage: "camera.viewfinder",
            isInserted: menuLayoutBinding(isPanel: false)
        ) {
            switch selectedMenuLayout {
            case .expanded, .panel:
                expandedMenuContent
            case .grouped:
                groupedMenuContent
            }

            appMenuFooter
        }
        .environment(\.locale, selectedLanguage.locale)

        Settings {
            SettingsView(updateService: environment.appUpdate)
        }
        .environment(\.locale, selectedLanguage.locale)
        .windowResizability(.contentSize)

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

        if shouldShowDynamicIslandInMenu {
            menuSectionHeader(AppLocalization.string("Media"))
            mediaControlButtons
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

        if shouldShowDynamicIslandInMenu {
            Menu {
                mediaControlButtons
            } label: {
                Label(AppLocalization.string("Media"), systemImage: "music.note")
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

        if shouldShowCaptureVideoInMenu {
            Button {
                screenRecorderStore.captureSelectedAreaVideo()
            } label: {
                Label(
                    ToolboxToolID.captureVideo.title,
                    systemImage: ToolboxToolID.captureVideo.systemImage
                )
            }
            .disabled(screenRecorderStore.isRecording)
        }

        if shouldShowCaptureOCRInMenu {
            Button {
                screenshotStore.captureOCRTextFromSelectedArea()
            } label: {
                Label(ToolboxToolID.captureOCR.title, systemImage: ToolboxToolID.captureOCR.systemImage)
            }
            .disabled(screenshotStore.isCapturing)
        }

        if shouldShowPickColorInMenu {
            Button {
                colorPickerStore.pickColor()
            } label: {
                Label(ToolboxToolID.pickColor.title, systemImage: ToolboxToolID.pickColor.systemImage)
            }
            .disabled(colorPickerStore.isPicking)
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
            Label(AppLocalization.string("Copy All"), systemImage: "doc.on.doc")
        }
        .disabled(screenshotStore.screenshots.isEmpty)

        Button(role: .destructive) {
            screenshotStore.clearAll()
        } label: {
            Label(AppLocalization.string("Clear All"), systemImage: "trash")
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
            Label(AppLocalization.string("Send Shelf Items"), systemImage: "paperplane")
        }
        .disabled(dropShelfStore.items.isEmpty)

        Button(role: .destructive) {
            dropShelfStore.clearAll()
        } label: {
            Label(AppLocalization.string("Clear Drop Shelf"), systemImage: "trash")
        }
        .disabled(dropShelfStore.items.isEmpty)
    }

    @ViewBuilder
    private var mediaControlButtons: some View {
        if let nowPlaying = dynamicIslandStore.nowPlaying {
            Text(
                nowPlaying.artist.isEmpty
                    ? nowPlaying.title
                    : "\(nowPlaying.title) – \(nowPlaying.artist)"
            )
            .disabled(true)
        }

        Button {
            dynamicIslandStore.togglePlayPause()
        } label: {
            Label(
                AppLocalization.string("Play / Pause"),
                systemImage: dynamicIslandStore.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill"
            )
        }
        .disabled(dynamicIslandStore.nowPlaying == nil)

        Button {
            dynamicIslandStore.previousTrack()
        } label: {
            Label(AppLocalization.string("Previous Track"), systemImage: "backward.fill")
        }
        .disabled(dynamicIslandStore.nowPlaying == nil)

        Button {
            dynamicIslandStore.nextTrack()
        } label: {
            Label(AppLocalization.string("Next Track"), systemImage: "forward.fill")
        }
        .disabled(dynamicIslandStore.nowPlaying == nil)
    }

    @ViewBuilder
    private var appMenuFooter: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label(AppLocalization.string("Settings"), systemImage: "gearshape")
        }

        Divider()

        Button(AppLocalization.formatted("Quit %@", AppConstants.displayName)) {
            NSApp.terminate(nil)
        }
    }

    /// Inserted state for the panel (`isPanel`) or classic menu scene. Removing
    /// the icon from the menu bar isn't offered, so writes are ignored.
    private func menuLayoutBinding(isPanel: Bool) -> Binding<Bool> {
        Binding(
            get: { (selectedMenuLayout == .panel) == isPanel },
            set: { _ in }
        )
    }

    private var menuPanelVisibility: MenuBarPanelVisibility {
        MenuBarPanelVisibility(
            captureSelectedArea: shouldShowCaptureSelectedAreaInMenu,
            captureVideo: shouldShowCaptureVideoInMenu,
            captureOCR: shouldShowCaptureOCRInMenu,
            pickColor: shouldShowPickColorInMenu,
            imageSearch: shouldShowImageSearchInMenu,
            copyFinderPath: shouldShowCopyFinderPathInMenu,
            dropShelf: shouldShowDropShelfInMenu,
            dynamicIsland: shouldShowDynamicIslandInMenu
        )
    }

    private var menuPanelActions: MenuBarPanelActions {
        MenuBarPanelActions(
            openImageSearch: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "image-search")
            },
            openSettings: {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            },
            quit: { NSApp.terminate(nil) }
        )
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
            || shouldShowCaptureVideoInMenu
            || shouldShowCaptureOCRInMenu
            || shouldShowPickColorInMenu
            || shouldShowImageSearchInMenu
    }

    private var shouldShowCaptureSelectedAreaInMenu: Bool {
        captureSelectedAreaEnabled && captureSelectedAreaShowInMenu
    }

    private var shouldShowCaptureVideoInMenu: Bool {
        captureVideoEnabled && captureVideoShowInMenu
    }

    private var shouldShowCaptureOCRInMenu: Bool {
        captureOCREnabled && captureOCRShowInMenu
    }

    private var shouldShowPickColorInMenu: Bool {
        pickColorEnabled && pickColorShowInMenu
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

    private var shouldShowDynamicIslandInMenu: Bool {
        dynamicIslandEnabled && dynamicIslandShowInMenu
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
