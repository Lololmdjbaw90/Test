#if DEBUG
import SwiftUI
import UIKit

// Simulator UI tests use local fixtures, never an account or production data.
enum DesignPreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--design-preview") }
    static let profile: Doc = ["id": "preview", "email": "preview@example.invalid", "display_name": "Sugar Studio", "bio": "A little color, a little creativity.", "role": "admin", "coins": 125, "xp": 350, "daily_streak": 3]
    static func documents(_ collection: String) -> [Doc] {
        if collection == "User" { return [profile] }
        if collection == "CommunityPost" { return [["id": "preview-post", "title": "A little pink inspiration", "content": "Make something lovely today.", "user_email": "preview@example.invalid", "user_display_name": "Sugar Studio", "created_date": FS.nowISO(), "likes": [String]()]] }
        return []
    }
    static func verifyFonts() {
        for name in ["Bubbly-Regular", "CuteHereRegular", "PlusJakartaSans-Regular"] {
            precondition(UIFont(name: name, size: 20) != nil, "Missing bundled font: \(name)")
        }
    }
}
#endif
