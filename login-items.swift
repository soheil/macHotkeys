import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let binaryPath = ProcessInfo.processInfo.arguments[0]
        let dir = NSString(string: binaryPath).deletingLastPathComponent

        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["\(dir)/login-items.sh"]
        task.launch()
        exit(0)
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()

app.delegate = appDelegate
app.run()
