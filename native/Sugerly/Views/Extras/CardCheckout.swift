import Foundation
import StoreKit

// Apple lets App Store apps send buyers to a card checkout only on the US
// storefront (App Review Guideline 3.1.1(a)); elsewhere digital goods need
// In-App Purchase. Copies installed outside the App Store (sideloaded IPAs
// carry a provisioning profile) can always pay by card.
extension Payments {
    static func cardCheckoutAllowed() async -> Bool {
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil { return true }
        return await Storefront.current?.countryCode == "USA"
    }
}
