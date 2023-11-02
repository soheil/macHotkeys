import Cocoa
import Foundation
import AudioToolbox
import SwiftUI

struct AudioObjectAddress {
    static var inputDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    static var muteState = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)

    static var deviceName = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    static var isRunning = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

class Audio {
    static let shared = Audio()
    typealias DeviceStateListener = () -> Void

    var inputDevice: AudioDeviceID?
    var inputDeviceName: String? {
        guard let deviceId = inputDevice else { return nil }
        return Self.nameOfDevice(id: deviceId)
    }

    var micMuted: Bool {
        get {
            guard let inputDevice = inputDevice else { return true }

            var muteState: UInt32 = 0
            var muteStateSize = UInt32(MemoryLayout.size(ofValue: muteState))

            let error = AudioObjectGetPropertyData(
                inputDevice, &AudioObjectAddress.muteState,
                0, nil,
                &muteStateSize, &muteState)

            return error == kAudioHardwareNoError ? muteState == 1 : true
        }

        set {
            guard let inputDevice = inputDevice else { return }

            var muteState: UInt32 = newValue ? 1 : 0
            let muteStateSize = UInt32(MemoryLayout.size(ofValue: muteState))

            AudioObjectSetPropertyData(
                inputDevice, &AudioObjectAddress.muteState,
                0, nil,
                muteStateSize, &muteState)
        }
    }

    var isRunning: Bool {
        guard let inputDevice = inputDevice else { return false }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))

        let error = AudioObjectGetPropertyData(
            inputDevice, &AudioObjectAddress.isRunning,
            0, nil,
            &size, &value)

        return error == kAudioHardwareNoError ? value == 1 : false
    }

    func toggleMicMute() {
        micMuted = !micMuted
    }

    func addDeviceStateListener(listener: @escaping Audio.DeviceStateListener) -> Int {
        let listenerId = nextListenerId
        nextListenerId += 1
        listeners[listenerId] = listener
        listener()

        return listenerId
    }

    func removeDeviceStateListener(listenerId: Int) {
        listeners.removeValue(forKey: listenerId)
    }

    private static func getInputDevice() -> AudioDeviceID? {
        var deviceId = kAudioObjectUnknown
        var deviceIdSize = UInt32(MemoryLayout.size(ofValue: deviceId))

        let error = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &AudioObjectAddress.inputDevice,
            0, nil,
            &deviceIdSize, &deviceId)

        return error == kAudioHardwareNoError && deviceId != kAudioObjectUnknown ? deviceId : nil
    }

    private static func nameOfDevice(id deviceId: AudioDeviceID) -> String? {
        var name = "" as CFString
        var nameSize = UInt32(MemoryLayout.size(ofValue: name))

        let error = AudioObjectGetPropertyData(
            deviceId,
            &AudioObjectAddress.deviceName,
            0, nil,
            &nameSize, &name)

        return error == kAudioHardwareNoError ? name as String : nil
    }

    private func notifyListeners() {
        self.listeners.forEach { $0.value() }
    }

    private func registerDeviceStateListener() {
        guard let inputDevice = self.inputDevice else { return }
        AudioObjectAddPropertyListenerBlock(inputDevice, &AudioObjectAddress.muteState, DispatchQueue.main, self.deviceStateListener)
        AudioObjectAddPropertyListenerBlock(inputDevice, &AudioObjectAddress.isRunning, DispatchQueue.main, self.deviceStateListener)

        listeners.forEach { $0.value() }
    }

    private func unregisterDeviceStateListener() {
        guard let inputDevice = self.inputDevice else { return }
        AudioObjectRemovePropertyListenerBlock(inputDevice, &AudioObjectAddress.isRunning, DispatchQueue.main, self.deviceStateListener)
        AudioObjectRemovePropertyListenerBlock(inputDevice, &AudioObjectAddress.muteState, DispatchQueue.main, self.deviceStateListener)
    }

    private func registerDefaultMicListener() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &AudioObjectAddress.inputDevice, DispatchQueue.main, defaultMicListener)
    }

    private func unregisterDefaultMicListener() {
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &AudioObjectAddress.inputDevice, DispatchQueue.main, defaultMicListener)
    }

    private func updateMicListeners() {
        self.unregisterDeviceStateListener()
        self.inputDevice = Self.getInputDevice()
        self.registerDeviceStateListener()
    }

    private lazy var defaultMicListener: AudioObjectPropertyListenerBlock = { (addressesCount, addresses) in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.updateMicListeners() }
    }

    private lazy var deviceStateListener: AudioObjectPropertyListenerBlock = { (addressesCount, addresses) in
        DispatchQueue.main.async { self.notifyListeners() }
    }

    private var listeners = [Int: Audio.DeviceStateListener]()
    private var nextListenerId: Int = 0

    init() {
        self.inputDevice = Self.getInputDevice()
        registerDeviceStateListener()
        registerDefaultMicListener()
    }
}

class HoverDetectingImageView: NSImageView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        let trackingArea = NSTrackingArea(rect: bounds,
                                          options: [.activeAlways, .mouseEnteredAndExited],
                                          owner: self,
                                          userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Image view is being hovered over
        // Handle your logic here
        print("Hover started")
        self.alphaValue = 0.5
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Image view hover exited
        // Handle your logic here
        print("Hover ended")
        self.alphaValue = 0
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Mouse click detected
        // Add your custom logic here
        print("Image view clicked!")

        let cmdWKeyCode: CGKeyCode = 13  // 13 represents the 'w' key
        let cmdKeyFlag = CGEventFlags.maskCommand

        // Simulate Cmd+W keypress
        simulateKeyPress(keyCode: cmdWKeyCode, flags: cmdKeyFlag)
    }

    func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        keyDownEvent?.flags = flags
        keyDownEvent?.post(tap: .cghidEventTap)
        
        let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        keyUpEvent?.flags = flags
        keyUpEvent?.post(tap: .cghidEventTap)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var textView = ClickableTextView()
    var scrollView = NSScrollView()
    // var hostingController: NSHostingController<ContentView>!
    @State var markdownText = "Initial String"
    // let model = ContentViewModel()

    var imageView1: NSImageView?
    var imageView2: NSImageView?
    
    var imageViewLeft: HoverDetectingImageView?
    
    var lastEscapePressTimeStamp: TimeInterval?
    var lastShiftPressTimeStamp: TimeInterval?
    var delayForDoublePress: TimeInterval = 0.3
    var timer: Timer?

    func runBashCommand(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output: String = String(data: data, encoding: .utf8) ?? ""

        return output
    }

    func addImage(_ imageWindowRect: NSRect, _ imageView: inout NSImageView?) {
        imageView = NSImageView(frame: imageWindowRect)
        imageView?.imageScaling = .scaleProportionallyUpOrDown
        imageView?.alphaValue = 0.5
        imageView?.animates = true

        window?.contentView?.addSubview(imageView!)

        window?.makeKeyAndOrderFront(nil)
        // window?.ignoresMouseEvents = true
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let binaryPath = ProcessInfo.processInfo.arguments[0]
        let dir = NSString(string: binaryPath).deletingLastPathComponent


        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in

            let flags = event.modifierFlags
            // if event.keyCode == 63 && flags.contains(.function) {
            if flags.rawValue == 8388864 {
                Audio.shared.toggleMicMute()
                return
            }

            // print(flags.rawValue)
            let leftCmd = 1048840
            if flags.rawValue == leftCmd && event.keyCode == 53 {
                if let lastTimeStamp = self.lastEscapePressTimeStamp {
                    let delay = event.timestamp - lastTimeStamp

                    if delay < self.delayForDoublePress {
                        print("double escape!")

                        let script = "~/chat/run --stop"

                        let process = Process()
                        process.launchPath = "/bin/bash"
                        process.arguments = ["-c", script]
                        process.launch()
                    } else {
                        self.lastEscapePressTimeStamp = event.timestamp
                    }
                } else {
                    self.lastEscapePressTimeStamp = event.timestamp
                }
                return
            }

            // let leftCmdShift = 1179916
            // let rightCmdShift = 1179924
            // 60 means only if right shift key is down
            // if (flags.rawValue == leftCmdShift || flags.rawValue == rightCmdShift) && event.keyCode == 60 {
            // cmd+option+g
            if flags.rawValue == 1573160 && event.keyCode == 5 {
                // if let lastTimeStamp = self.lastShiftPressTimeStamp {
                //     let delay = event.timestamp - lastTimeStamp

                    // if delay < self.delayForDoublePress {
                        let task = Process()
                        // task.launchPath = "/bin/sh"
                        // task.arguments = ["-c", "/usr/bin/osascript \(dir)/ide-helper.scpt >/tmp/ran 2>&1"]
                        
                        task.launchPath = "/usr/bin/osascript"
                        task.arguments = ["\(dir)/ide-helper.scpt"]

                        task.launch()
                        task.waitUntilExit()
                    // } else {
                    //     self.lastShiftPressTimeStamp = event.timestamp
                    // }
                // } else {
                //     self.lastShiftPressTimeStamp = event.timestamp
                // }
                return
            }
            if flags.rawValue == 1310985 && event.keyCode == 9 {

                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["\(dir)/ide-helper-paste-code.scpt"]

                task.launch()
                task.waitUntilExit()

                return
            }
            if flags.contains(.command) && event.keyCode == 119 {
                let workspace = NSWorkspace.shared
                let frontmostApp = workspace.frontmostApplication
                let appName = frontmostApp?.localizedName

                if appName == "Zoom" {
                    print(self.runBashCommand("kill -9 $(ps aux|grep '[M]acOS/zoom'|awk '{print $2}')"))
                }
            }

        }
        let screenRect = NSScreen.main!.frame

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height), styleMask: .borderless, backing: .buffered, defer: false)
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]


        // model.inputString = """
        // Initial *str*ing!!
        // ```bash
        // echo 9
        // ls
        // ```
        // """

        // window?.contentView = NSHostingView(rootView: ContentView(model: model))



        let imageWindowWidth = screenRect.size.width / 3
        let imageWindowHeight = screenRect.size.height / 4

        let imageWindowRect1 = NSMakeRect(0, 20, imageWindowWidth, imageWindowHeight)
        addImage(imageWindowRect1, &imageView1)

        let imageWindowRect2 = NSMakeRect(imageWindowWidth/1.5, 20, imageWindowWidth, imageWindowHeight)
        addImage(imageWindowRect2, &imageView2)

        let imageWindowRectLeft = NSMakeRect(0, 0, 2, imageWindowHeight)

        imageViewLeft = HoverDetectingImageView(frame: imageWindowRectLeft)
        imageViewLeft?.alphaValue = 0

        imageViewLeft?.wantsLayer = true
        imageViewLeft?.layer?.backgroundColor = NSColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1.0).cgColor

        window?.contentView?.addSubview(imageViewLeft!)

        // backgroundView = NSView(frame: NSRect(x: screenRect.size.width*(2/3), y: 0, width: screenRect.size.width, height: screenRect.size.height))
        // backgroundView?.wantsLayer = true
        // backgroundView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor

        // textField = NSTextField(frame: NSRect(x: 10, y: 0, width: backgroundView!.frame.width/3-20, height: backgroundView!.frame.height))
        // textField?.stringValue
        // textField?.textColor = NSColor.white.withAlphaComponent(0.8)
        // textField?.isBordered = false
        // textField?.isEditable = false
        // textField?.backgroundColor = NSColor.clear
        // textField?.font = NSFont(name: "Menlo-Regular", size: 12)
        // textField?.cell?.wraps = true
        // textField?.cell?.isScrollable = false


        scrollView = NSScrollView(frame: NSRect(x: screenRect.size.width*(2/3), y: 0, width: screenRect.size.width/3, height: screenRect.size.height-35))

        textView = ClickableTextView(frame: scrollView.frame)
        textView.clickDelegate = self
        textView.isSelectable = true
        textView.isEditable = true

        // self.window?.makeFirstResponder(self.textView)

        // scrollView.documentView = ContentViewRepresentable(model: model)
        // NSHostingView(rootView: ContentView(model: model))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true


        // hostingController = NSHostingController(rootView: contentView)
        // window?.makeFirstResponder(window?.contentView)



        // window?.contentView?.addSubview(scrollView)

        let muteListenerId = Audio.shared.addDeviceStateListener { [] in
            print(Audio.shared.micMuted)
            print(99)
            if !Audio.shared.micMuted || !Audio.shared.isRunning {
                self.imageView1?.image = nil
                self.imageView2?.image = nil
            } else {
                let iconPath = "\(dir)/mic-muted.gif"
                let image = NSImage(contentsOfFile: iconPath)
                self.imageView1?.image = image
                self.imageView2?.image = image
            }
        }
    }
    func clicked(_ scrollView: ClickableTextView) {
        print("ScrollView clicked")
    }

    func rightClicked() {
        print("ScrollView right clicked")
    }
    func escapePressed() {
        print("escape pressed!")
    }

}

class ClickableTextView: NSTextView {
    weak var clickDelegate: AppDelegate?
    var timer: Timer?
    var textClicked = false
    var textRightClicked = false

    override var acceptsFirstResponder: Bool {
        return true
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        print("Mouse clicked!")
        timer?.invalidate()
        clickDelegate?.clicked(self)
        textClicked = true
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { timer in
            self.textClicked = false
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
        textRightClicked = true
        clickDelegate?.rightClicked()
    }
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        print(event)
        if event.keyCode == 53 {
            print("Escape key pressed!")
            clickDelegate?.escapePressed()
        }
    }
}



// @NSApplicationMain
// class AppDelegate: NSObject, NSApplicationDelegate {

//     var window: NSWindow!

//     func applicationDidFinishLaunching(_ aNotification: Notification) {
//         // Create the SwiftUI view that provides the window contents.
//         let contentView = ContentView()

//         hostingController = NSHostingController(rootView: contentView)
        
//         // Create the window and set the content view. 
//         window = NSWindow(
//             contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
//             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
//             backing: .buffered, defer: false)
        
//         window.isReleasedWhenClosed = false
//         window.center()
//         window.contentView = NSHostingView(rootView: contentView)
//         window.makeKeyAndOrderFront(nil)
//     }
// }

// struct ContentViewRepresentable: NSViewRepresentable {
//     @ObservedObject var model: ContentViewModel
    
//     func makeNSView(context: Context) -> NSHostingView<ContentView> {
//         return NSHostingView(rootView: ContentView(model: model))
//     }
    
//     func updateNSView(_ nsView: NSHostingView<ContentView>, context: Context) {
//         nsView.rootView = ContentView(model: model)
//     }
// }



// class ContentViewModel: ObservableObject {
//     @Published var inputString: String = ""
// }
// struct ContentView: View {
    // @ObservedObject var model: ContentViewModel
    // var body: some View {

           // Markdown(MarkdownContent(model.inputString))
           //     .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

    // }
// }


let app = NSApplication.shared
let appDelegate = AppDelegate()

app.delegate = appDelegate
app.run()
