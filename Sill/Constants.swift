import CoreFoundation

struct Constants {
    static let menuBarHeight = CGFloat(55)
    static let menuBarHorizontalPadding = CGFloat(25)
    /// Corner radius of Liquid Glass popups and their modules, close to the Control Center modules.
    static let popupCornerRadius = CGFloat(28)
    /// Space between the glass modules of a popup.
    static let popupModuleSpacing = CGFloat(10)
    /// Space between a popup's glass edge and its content, the same in every popup so that they read as one family
    /// (HIG, Layout). Popups used 15 to 30 points each. 20 points is what the usage modules already used, the usual
    /// margin of macOS window content, and keeps the content clear of the 28-point corners.
    static let popupPadding = CGFloat(20)
}
