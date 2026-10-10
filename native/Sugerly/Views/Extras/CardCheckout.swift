import Foundation
import StoreKit

// Apple lets App Store apps send buyers to a card checkout only on the US
// storefront (App Review Guideline 3.1.1(a)); elsewhere digital goods need
// In-App Purchase. Use the storefront in TestFlight too: a provisioning
// profile doesn't distinguish an independent distribution from TestFlight.
extension Payments {
    static func cardCheckoutAllowed() async -> Bool {
        return await Storefront.current?.countryCode == "USA"
    }
}
