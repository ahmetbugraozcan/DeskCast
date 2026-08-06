import AppKit
import AVFoundation
import QuickLookThumbnailing

struct VideoMetadata {
    let thumbnail: NSImage
    let durationSeconds: TimeInterval?
}

protocol VideoMetadataLoading {
    func loadMetadata(
        for url: URL,
        completion: @escaping (Result<VideoMetadata, Error>) -> Void
    )
}

struct VideoMetadataService: VideoMetadataLoading {
    func loadMetadata(
        for url: URL,
        completion: @escaping (Result<VideoMetadata, Error>) -> Void
    ) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 640, height: 400),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let representation else {
                let error = NSError(
                    domain: "DeskCast.VideoMetadata",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create a video thumbnail."]
                )
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let asset = AVURLAsset(url: url)
            Task {
                let duration = try? await asset.load(.duration)
                let seconds = duration.map(CMTimeGetSeconds).flatMap { $0.isFinite ? $0 : nil }
                let metadata = VideoMetadata(
                    thumbnail: representation.nsImage,
                    durationSeconds: seconds
                )
                await MainActor.run {
                    completion(.success(metadata))
                }
            }
        }
    }
}
