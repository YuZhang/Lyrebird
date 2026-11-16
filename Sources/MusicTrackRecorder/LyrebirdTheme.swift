import SwiftUI
import AppKit

enum LyrebirdTheme {
    static let accent = Color(red: 238 / 255, green: 64 / 255, blue: 82 / 255)
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(calibratedRed: 0.115, green: 0.11, blue: 0.105, alpha: 1)
            : NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.94, alpha: 1)
    })
    static let card = Color(nsColor: .controlBackgroundColor)
    static let separator = Color.primary.opacity(0.07)
}
