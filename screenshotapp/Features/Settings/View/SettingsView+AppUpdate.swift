import SwiftUI

extension SettingsView {
    var aboutPane: some View {
        SettingsPage(title: AppLocalization.string("About DeskCast"), systemImage: "info.circle") {
            SettingsControlSection(title: AppLocalization.string("Application")) {
                SettingsControlRow(title: AppLocalization.string("Version")) {
                    Text(AppVersion.displayString)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                SettingsSectionDivider()

                SettingsControlRow(title: AppLocalization.string("Updates")) {
                    Button(AppLocalization.string("Check for Updates...")) {
                        updateService.checkForUpdates()
                    }
                    .disabled(!updateService.canCheckForUpdates)
                }
            }

            SettingsControlSection(title: AppLocalization.string("Developer")) {
                SettingsControlRow(title: AppLocalization.string("Name")) {
                    Text("Ahmet Buğra Özcan")
                        .foregroundStyle(.secondary)
                }

                SettingsSectionDivider()

                SettingsControlRow(title: AppLocalization.string("GitHub")) {
                    Link("github.com/ahmetbugraozcan", destination: developerGitHubURL)
                }
            }

            Text(AppLocalization.string("Updates are downloaded, verified, and installed securely."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var developerGitHubURL: URL {
        guard let url = URL(string: "https://github.com/ahmetbugraozcan") else {
            preconditionFailure("Invalid developer GitHub URL")
        }
        return url
    }
}
