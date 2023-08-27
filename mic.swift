import Cocoa
import Foundation
import AudioToolbox
import Down

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

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var textView: NSTextView?

    var imageView1: NSImageView?
    var imageView2: NSImageView?
    
    var lastEscapePressTimeStamp: TimeInterval?
    var lastShiftPressTimeStamp: TimeInterval?
    var delayForDoublePress: TimeInterval = 0.3

    func addImage(_ imageWindowRect: NSRect, _ imageView: inout NSImageView?) {
        imageView = NSImageView(frame: imageWindowRect)
        imageView?.imageScaling = .scaleProportionallyUpOrDown
        imageView?.alphaValue = 0.5
        imageView?.animates = true

        window?.contentView?.addSubview(imageView!)

        window?.makeKeyAndOrderFront(nil)
        window?.ignoresMouseEvents = true
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let binaryPath = ProcessInfo.processInfo.arguments[0]
        let dir = NSString(string: binaryPath).deletingLastPathComponent

        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in

            let flags = event.modifierFlags
            // if event.keyCode == 63 && flags.contains(.function) {
            if flags.contains(.function) {
                Audio.shared.toggleMicMute()
                return
            }

            let leftCmd = 1048840
            if flags.rawValue == leftCmd && event.keyCode == 53 {
                if let lastTimeStamp = self.lastEscapePressTimeStamp {
                    let delay = event.timestamp - lastTimeStamp

                    if delay < self.delayForDoublePress {
                        print("double escape!")

                        let script = """
                        if ps aux | grep -v grep | grep 'chat/run' > /dev/null
                        then
                            kill -2 $(ps aux | grep 'chat/run' | grep -v grep | awk '{print $2}')
                        else
                            ~/chat/run --revert
                        fi
                        """

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

            let leftCmdShift = 1179916
            let rightCmdShift = 1179924
            // 60 means only if right shift key is down
            if (flags.rawValue == leftCmdShift || flags.rawValue == rightCmdShift) && event.keyCode == 60 {
                if let lastTimeStamp = self.lastShiftPressTimeStamp {
                    let delay = event.timestamp - lastTimeStamp

                    if delay < self.delayForDoublePress {
                        let task = Process()
                        // task.launchPath = "/bin/sh"
                        // task.arguments = ["-c", "/usr/bin/osascript \(dir)/ide-helper.scpt >/tmp/ran 2>&1"]
                        
                        task.launchPath = "/usr/bin/osascript"
                        task.arguments = ["\(dir)/ide-helper.scpt"]

                        task.launch()
                        task.waitUntilExit()
                    } else {
                        self.lastShiftPressTimeStamp = event.timestamp
                    }
                } else {
                    self.lastShiftPressTimeStamp = event.timestamp
                }
                return
            }
            if flags.contains(.command) && event.keyCode == 119 {
                let workspace = NSWorkspace.shared
                let frontmostApp = workspace.frontmostApplication
                let appName = frontmostApp?.localizedName

                if appName == "Zoom" {
                    // print(AppDelegate.runBashCommand("kill -9 $(ps aux|grep '[M]acOS/zoom'|awk '{print $2}')"))
                }
            }

        }
        let screenRect = NSScreen.main!.frame

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height), styleMask: .borderless, backing: .buffered, defer: false)
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]


        let imageWindowWidth = screenRect.size.width / 3
        let imageWindowHeight = screenRect.size.height / 4

        let imageWindowRect1 = NSMakeRect(0, 20, imageWindowWidth, imageWindowHeight)
        addImage(imageWindowRect1, &imageView1)

        let imageWindowRect2 = NSMakeRect(imageWindowWidth/1.5, 20, imageWindowWidth, imageWindowHeight)
        addImage(imageWindowRect2, &imageView2)

        // backgroundView = NSView(frame: NSRect(x: screenRect.size.width*(2/3), y: 0, width: screenRect.size.width, height: screenRect.size.height))
        // backgroundView?.wantsLayer = true
        // backgroundView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor

        // textField = NSTextField(frame: NSRect(x: 10, y: 0, width: backgroundView!.frame.width/3-20, height: backgroundView!.frame.height))
        // textField?.stringValue
        let markdownText = try! String(contentsOfFile: "/Users/soheil/chat/gpt/2023-08-27_06:35:32.md")
        // textField?.textColor = NSColor.white.withAlphaComponent(0.8)
        // textField?.isBordered = false
        // textField?.isEditable = false
        // textField?.backgroundColor = NSColor.clear
        // textField?.font = NSFont(name: "Menlo-Regular", size: 12)
        // textField?.cell?.wraps = true
        // textField?.cell?.isScrollable = false

        let down = Down(markdownString: markdownText)
        let attributedString = try? down.toAttributedString()
        textView?.attributedString = attributedString

        window?.contentView?.addSubview(textView!)

        let muteListenerId = Audio.shared.addDeviceStateListener { [] in
            print(Audio.shared.micMuted)
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
        print(muteListenerId)
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()

app.delegate = appDelegate
app.run()
