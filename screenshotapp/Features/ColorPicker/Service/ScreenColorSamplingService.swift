import AppKit

@MainActor
protocol ColorSampling: AnyObject {
    /// Shows the system magnifier loupe and reports the clicked color, or nil
    /// when the user cancels with Escape.
    func sampleColor(completion: @escaping @MainActor (NSColor?) -> Void)
}

/// `NSColorSampler` reads the pixel under the loupe itself, so picking a color
/// needs no Screen Recording permission.
@MainActor
final class ScreenColorSamplingService: ColorSampling {
    /// Kept alive until the loupe reports back.
    private var sampler: NSColorSampler?

    func sampleColor(completion: @escaping @MainActor (NSColor?) -> Void) {
        let sampler = NSColorSampler()
        self.sampler = sampler

        sampler.show { [weak self] color in
            Task { @MainActor in
                self?.sampler = nil
                completion(color)
            }
        }
    }
}
