import Foundation

/// Hands one instance of a widget's manager to every view that shows the widget, for as long as one of them holds it.
/// The bar measures several candidate rows of its widgets (see `MenuBarView.fittingRow`) and the more widgets popup
/// shows them again, so a manager created per view would run its timers and polling once per copy.
///
/// Instances are held weakly: once no view holds one, it is released and stops, and the next view creates a new one.
/// Used on the main thread only, from view bodies and initializers.
final class SharedWhileInUse<Object: AnyObject> {
    private let instances = NSMapTable<NSString, Object>.strongToWeakObjects()

    /// The live instance for `key`, or a new one from `make`.
    func instance(for key: String = "", make: () -> Object) -> Object {
        if let instance = instances.object(forKey: key as NSString) {
            return instance
        }
        let instance = make()
        instances.setObject(instance, forKey: key as NSString)
        return instance
    }
}
