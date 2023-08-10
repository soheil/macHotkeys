import Cocoa
import Foundation
import AudioToolbox

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
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &AudioObjectAddress.inputDevice, DispatchQueue.main, defaultMicListener)
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
    var imageView1: NSImageView?
    var imageView2: NSImageView?

    var lastEscapePressTimeStamp: TimeInterval?
    var delayForDoublePress: TimeInterval = 0.5

    func addImage(_ imageWindowRect: NSRect, _ imageView: inout NSImageView?) {
        window = NSWindow(contentRect: imageWindowRect, styleMask: .borderless, backing: .buffered, defer: false)
        window?.backgroundColor = NSColor.clear
        window?.isOpaque = false
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        imageView = NSImageView(frame: imageWindowRect)
        imageView?.imageScaling = .scaleProportionallyUpOrDown
        imageView?.alphaValue = 0.5
        imageView?.animates = true

        window?.contentView = imageView

        window?.makeKeyAndOrderFront(nil)
        window?.ignoresMouseEvents = true
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in

            if event.keyCode == 63 && event.modifierFlags.contains(.function) {
                Audio.shared.toggleMicMute()
                return
            }
            let flags = event.modifierFlags

            if event.keyCode == 53 { //53 is the keyCode for escape
                if let lastTimeStamp = self.lastEscapePressTimeStamp {
                    let delay = event.timestamp - lastTimeStamp

                    if delay < self.delayForDoublePress {
                        print("double escape!")

                        let script = """
                        if ps aux | grep -v grep | grep 'chat/run' > /dev/null
                        then
                            kill -2 $(ps aux | grep 'chat/run' | grep -v grep | awk '{print $2}')
                        else
                            ~/chat/run revert
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
            }

            let requiredFlags: NSEvent.ModifierFlags = [.option, .command]
            let requiredFlagsPressed = flags.intersection(requiredFlags) == requiredFlags

            if event.keyCode == 5 && requiredFlagsPressed {
                let script = """
                tell application "Sublime Text"
                    activate
                end tell

                tell application "System Events"
                    keystroke "2" using {command down, option down}
                    keystroke "2" using control down
                    keystroke "w" using {control down, option down}
                end tell
                do shell script "DIR=~/chat/gpt;find $DIR -type f -empty -delete;FILE=$DIR/$(date '+%Y-%m-%d_%H:%M:%S').md;touch $FILE;/usr/local/bin/subl $FILE"

                """
                print("output")

                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", script]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                task.launch()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print(output)
                }
            }
        }
        let screenRect = NSScreen.main!.frame
        let imageWindowWidth = screenRect.size.width / 3
        let imageWindowHeight = screenRect.size.height / 4

        let imageWindowRect1 = NSMakeRect(0, 20, imageWindowWidth, imageWindowHeight)
        addImage(imageWindowRect1, &imageView1)

        let imageWindowRect2 = NSMakeRect(imageWindowWidth/1.5, 20, imageWindowWidth, imageWindowHeight)
        addImage(imageWindowRect2, &imageView2)

        let muteListenerId = Audio.shared.addDeviceStateListener { [] in
            print(Audio.shared.micMuted)
            if !Audio.shared.micMuted || !Audio.shared.isRunning {
                self.imageView1?.image = nil
                self.imageView2?.image = nil
            } else {
                let iconPath = "~/chat/mic-muted.gif"
                let image = NSImage(contentsOfFile: iconPath)
                self.imageView1?.image = image
                self.imageView2?.image = image
            }
        }
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()

app.delegate = appDelegate
app.run()
