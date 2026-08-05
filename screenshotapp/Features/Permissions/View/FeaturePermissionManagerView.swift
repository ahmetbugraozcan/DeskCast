import AppKit
import SwiftUI

struct FeaturePermissionManagerView: View {
    @ObservedObject var store: PrivacyPermissionViewModel
    let permissions: [PrivacyPermissionID]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Permissions")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(permissions) { permission in
                    PermissionSettingsRow(
                        permission: permission,
                        status: store.status(for: permission),
                        isPending: store.isPending(permission),
                        requestAction: { store.request(permission) },
                        openSettingsAction: { store.openSettings(for: permission) },
                        resetAction: { store.reset([permission]) }
                    )
                }

                if permissions.count > 1 {
                    Button(role: .destructive) {
                        store.reset(permissions)
                    } label: {
                        Label("Reset Feature Permissions", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(permissions.contains { store.isPending($0) })
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let message = store.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear {
            store.refresh(permissions)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refresh(permissions)
        }
    }
}

private struct PermissionSettingsRow: View {
    let permission: PrivacyPermissionID
    let status: PrivacyPermissionStatus
    let isPending: Bool
    let requestAction: () -> Void
    let openSettingsAction: () -> Void
    let resetAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: permission.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .frame(width: 34, height: 34)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(permission.title)
                        .font(.system(size: 14, weight: .semibold))

                    Text(permission.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Label(status.title, systemImage: status.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .labelStyle(.titleAndIcon)
            }

            HStack(spacing: 8) {
                Spacer()

                Button {
                    requestAction()
                } label: {
                    Label("Request", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(status.isGranted || isPending)

                Button {
                    openSettingsAction()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Open Privacy Settings")
                .disabled(isPending)

                Button(role: .destructive) {
                    resetAction()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(isPending)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusTint: Color {
        switch status {
        case .checking:
            return .secondary
        case .granted:
            return .green
        case .notGranted:
            return .red
        case .unavailable:
            return .orange
        }
    }
}
