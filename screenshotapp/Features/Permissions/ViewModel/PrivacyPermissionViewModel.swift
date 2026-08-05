import Combine
import Foundation

@MainActor
final class PrivacyPermissionViewModel: ObservableObject {
    @Published private var statuses: [PrivacyPermissionID: PrivacyPermissionStatus] = [:]
    @Published private var pendingPermissions: Set<PrivacyPermissionID> = []
    @Published private(set) var message: String?
    private var resetPermissions: Set<PrivacyPermissionID> = []

    func status(for permission: PrivacyPermissionID) -> PrivacyPermissionStatus {
        statuses[permission] ?? .checking
    }

    func isPending(_ permission: PrivacyPermissionID) -> Bool {
        pendingPermissions.contains(permission)
    }

    func refresh(_ permissions: [PrivacyPermissionID] = PrivacyPermissionID.allCases) {
        let requestedPermissions = Set(permissions)

        Task {
            let refreshedStatuses = await Task.detached {
                requestedPermissions.map { permission in
                    (permission, PrivacyPermissionService.status(for: permission))
                }
            }.value

            for (permission, status) in refreshedStatuses {
                if resetPermissions.contains(permission) {
                    statuses[permission] = .notGranted
                } else {
                    statuses[permission] = status
                }
            }
        }
    }

    func request(_ permission: PrivacyPermissionID) {
        pendingPermissions.insert(permission)
        statuses[permission] = .checking
        message = nil

        if permission == .screenRecording, resetPermissions.contains(permission) {
            PrivacyPermissionService.openSettings(for: permission)
            statuses[permission] = .notGranted
            pendingPermissions.remove(permission)
            message = AppLocalization.formatted(
                "Enable Screen Recording in System Settings, then quit and reopen %@.",
                AppConstants.displayName
            )
            return
        }

        resetPermissions.remove(permission)

        Task {
            let status = await PrivacyPermissionService.request(permission)
            statuses[permission] = status

            if permission == .screenRecording, status == .notGranted {
                PrivacyPermissionService.openSettings(for: permission)
                message = AppLocalization.formatted(
                    "Enable Screen Recording in System Settings, then quit and reopen %@.",
                    AppConstants.displayName
                )
            }

            pendingPermissions.remove(permission)
        }
    }

    func openSettings(for permission: PrivacyPermissionID) {
        PrivacyPermissionService.openSettings(for: permission)
    }

    func reset(_ permissions: [PrivacyPermissionID]) {
        let requestedPermissions = Set(permissions)
        pendingPermissions.formUnion(requestedPermissions)
        message = nil

        Task {
            do {
                try await Task.detached {
                    try PrivacyPermissionService.reset(Array(requestedPermissions))
                }.value

                for permission in requestedPermissions {
                    resetPermissions.insert(permission)
                    statuses[permission] = .notGranted
                }

                message = AppLocalization.string("Permissions reset. Access will be requested again when needed.")
            } catch {
                message = error.localizedDescription
                refresh(Array(requestedPermissions))
            }

            pendingPermissions.subtract(requestedPermissions)
        }
    }
}
