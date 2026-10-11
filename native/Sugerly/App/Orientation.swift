import UIKit

// Sugerly stays upright on iPhone (iPad turns freely), except Sugar World,
// which plays sideways on both.
@MainActor
enum OrientationLock {
    private(set) static var landscape = false

    static var mask: UIInterfaceOrientationMask {
        if landscape { return .landscape }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    static func set(landscape on: Bool) {
        guard on != landscape else { return }
        landscape = on
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController
                while let c = controller {
                    c.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = c.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
