import AVFoundation

/// Front camera session for the Camera Mirror panel. Runs only while the panel
/// is on screen; start/stop hop to a private queue as AVFoundation requires.
nonisolated final class CameraPreviewService: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.ahmetbugraozcan.screenshotapp.camera")
    private var isConfigured = false

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() {
        queue.async { [self] in
            if !isConfigured {
                configure()
            }

            if isConfigured, !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configure() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        if session.canAddInput(input) {
            session.addInput(input)
            isConfigured = true
        }

        session.commitConfiguration()
    }
}
