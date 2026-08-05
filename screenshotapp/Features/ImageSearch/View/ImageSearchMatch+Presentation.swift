import Foundation

extension ImageSearchMatch {
    var matchLabels: [String] {
        var labels: [String] = []

        if matchedFilename {
            labels.append(AppLocalization.string("Filename"))
        }

        if matchedText {
            labels.append(AppLocalization.string("Image text"))
        }

        return labels
    }
}
