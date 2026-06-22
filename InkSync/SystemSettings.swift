import AppKit
import Foundation

enum SystemSettings {
    static func openRemindersPrivacy() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Reminders",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
