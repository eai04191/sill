import SwiftUI

extension Font {
    /// The font for single-line text on the bar: the system menu bar's font, 13 points in the regular weight, since
    /// Sill takes the place of the menu bar.
    static let barText = Font(NSFont.menuBarFont(ofSize: 0))
    /// The font of a popup's heading, such as "Sound" or the calendar's month, the same in every popup. Popups mixed
    /// the headline, the larger title 2 and a fixed 14 points; the headline is the system's style for a short heading
    /// over a group of controls, as in the Control Center modules.
    static let popupHeading = Font.headline
}
