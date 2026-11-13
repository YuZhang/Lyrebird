import Foundation

enum RecordingCompleteness {
    static func canStart(at position: Double) -> Bool {
        position <= 1.2
    }

    static func reachedEnd(duration: Double, position: Double) -> Bool {
        duration > 0 && duration - position <= 0.2
    }

    static func completedBeforeChange(duration: Double, position: Double?) -> Bool {
        guard let position else { return false }
        return duration > 0 && duration - position <= 1.0
    }
}
