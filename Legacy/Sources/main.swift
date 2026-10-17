import AppKit

// macOS 10.12 版の起動処理です。@main や SwiftUI の App は使えないため、ここで NSApplication を動かします。
let application = NSApplication.shared
let appDelegate = LegacyAppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
