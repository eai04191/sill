import SwiftUI

extension Font {
    /// The font for single-line text on the bar: the system menu bar's font, 13 points in the regular weight, since
    /// Barik takes the place of the menu bar.
    static let barText = Font(NSFont.menuBarFont(ofSize: 0))
}
