import Cocoa
import Foundation
import AudioToolbox
import Down
import Highlightr
import SwiftUI
// import MarkdownUI

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
    var textView = ClickableTextView()
    var scrollView = NSScrollView()
    // var hostingController: NSHostingController<ContentView>!
    @State var markdownText = "Initial String"
    // let model = ContentViewModel()
    let highlightr = Highlightr()


    var imageView1: NSImageView?
    var imageView2: NSImageView?
    
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
            if flags.contains(.function) {
                Audio.shared.toggleMicMute()
                return
            }

            print(flags.rawValue)
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

        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if self.textView.textClicked {
                return
            }
            let file = self.runBashCommand("find ~/chat/gpt -name '*.md' -type f -mtime -5s | head -n 1")
            self.scrollView.isHidden = file == ""
            if self.scrollView.isHidden {
                return
            }
            
            var markdownText = ""
            do {
                markdownText = try String(contentsOfFile: file.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch let error {
                print("An error occurred: \(error)")
                return                    
            }
            markdownText = markdownText.replacingOccurrences(of: "---==--==---", with: "___")

            // self.model.inputString = markdownText

            // if let hostingView = self.window?.contentView as? NSHostingView<ContentView> {
            //     print("inside if------------------------")
            //     hostingView.rootView.inputString = markdownText
            // }

            // highlightr.setTheme(to: "solarized-dark")
            // highlightr.setTheme(to: "base16-papercolor-dark")

            // self.highlightr?.setTheme(to: "paraiso-dark")

            let down = Down(markdownString: markdownText)


            let highlightedText = try! down.toAttributedString(styler: Styler())
            // let highlightedText = try! down.toAttributedString()
            // let highlightedText = highlightr.highlight(attributedText.string, as: "markdown", fastRender: true)


            // let highlightedText = highlightr.highlight(markdownText, as: "markdown", fastRender: true)


            let newHighlightedText = NSMutableAttributedString(attributedString: highlightedText)
            newHighlightedText.addAttributes([.font: NSFont(name: "Menlo-Regular", size: 12)], range: NSMakeRange(0, highlightedText.length))
            self.textView.textStorage?.setAttributedString(newHighlightedText)
        }

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



        window?.contentView?.addSubview(scrollView)


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

class Styler: DownStyler {
    // override func style(blockQuote str: NSMutableAttributedString) {
    //     // Override default styles
    // }
    let highlightr = Highlightr()
    let themes=["a11y-dark","a11y-light","agate","an-old-hope","androidstudio","arduino-light","arta","ascetic","atom-one-dark-reasonable</option","atom-one-light","base16-3024","base16-apathy","base16-apprentice","base16-ashes","base16-atelier-cave-light","base16-atelier-cave","base16-atelier-dune-light","base16-atelier-dune","base16-atelier-estuary-light","base16-atelier-estuary","base16-atelier-forest-light","base16-atelier-forest","base16-atelier-heath-light","base16-atelier-heath","base16-atelier-lakeside-light","base16-atelier-lakeside","base16-atelier-plateau-light","base16-atelier-plateau","base16-atelier-savanna-light","base16-atelier-savanna","base16-atelier-seaside-light","base16-atelier-seaside","base16-atelier-sulphurpool-light","base16-atelier-sulphurpool","base16-atlas","base16-bespin","base16-black-metal-bathory","base16-black-metal-burzum","base16-black-metal-dark-funeral","base16-black-metal-gorgoroth","base16-black-metal-immortal","base16-black-metal-khold","base16-black-metal-marduk","base16-black-metal-mayhem","base16-black-metal-nile","base16-black-metal-venom","base16-black-metal","base16-brewer","base16-bright","base16-brogrammer","base16-brush-trees-dark","base16-brush-trees","base16-chalk","base16-circus","base16-classic-dark","base16-classic-light","base16-codeschool","base16-colors","base16-cupcake","base16-cupertino","base16-danqing","base16-darcula","base16-dark-violet","base16-darkmoss","base16-darktooth","base16-decaf","base16-default-dark","base16-default-light","base16-dirtysea","base16-dracula","base16-edge-dark","base16-edge-light","base16-eighties","base16-embers","base16-equilibrium-dark","base16-equilibrium-gray-dark","base16-equilibrium-gray-light","base16-equilibrium-light","base16-espresso","base16-eva-dim","base16-eva","base16-flat","base16-framer","base16-fruit-soda","base16-gigavolt","base16-github","base16-google-dark","base16-google-light","base16-grayscale-dark","base16-grayscale-light","base16-green-screen","base16-gruvbox-dark-hard","base16-gruvbox-dark-medium","base16-gruvbox-dark-pale","base16-gruvbox-dark-soft","base16-gruvbox-light-hard","base16-gruvbox-light-medium","base16-gruvbox-light-soft","base16-hardcore","base16-harmonic16-dark","base16-harmonic16-light","base16-heetch-dark","base16-heetch-light","base16-helios","base16-hopscotch","base16-horizon-dark","base16-horizon-light","base16-humanoid-dark","base16-humanoid-light","base16-ia-dark","base16-ia-light","base16-icy-dark","base16-ir-black","base16-isotope","base16-kimber","base16-london-tube","base16-macintosh","base16-marrakesh","base16-materia","base16-material-darker","base16-material-lighter","base16-material-palenight","base16-material-vivid","base16-material","base16-mellow-purple","base16-mexico-light","base16-mocha","base16-monokai","base16-nebula","base16-nord","base16-nova","base16-ocean","base16-oceanicnext","base16-one-light","base16-onedark","base16-outrun-dark","base16-papercolor-dark","base16-papercolor-light","base16-paraiso","base16-pasque","base16-phd","base16-pico","base16-pop","base16-porple","base16-qualia","base16-railscasts","base16-rebecca","base16-ros-pine-dawn","base16-ros-pine-moon","base16-ros-pine","base16-sagelight","base16-sandcastle","base16-seti-ui","base16-shapeshifter","base16-silk-dark","base16-silk-light","base16-snazzy","base16-solar-flare-light","base16-solar-flare","base16-solarized-dark","base16-solarized-light","base16-spacemacs","base16-summercamp","base16-summerfruit-dark","base16-summerfruit-light","base16-synth-midnight-terminal-dark","base16-synth-midnight-terminal-light","base16-tango","base16-tender","base16-tomorrow-night","base16-tomorrow","base16-twilight","base16-unikitty-dark","base16-unikitty-light","base16-vulcan","base16-windows-10-light","base16-windows-10","base16-windows-95-light","base16-windows-95","base16-windows-high-contrast-light","base16-windows-high-contrast","base16-windows-nt-light","base16-windows-nt","base16-woodland","base16-xcode-dusk","base16-zenburn","brown-paper","codepen-embed","color-brewer","dark","default","devibeans","docco","far","felipec","foundation","github-dark-dimmed","github-dark","github","gml","googlecode","gradient-dark","gradient-light","grayscale","hybrid","idea","intellij-light","ir-black","isbl-editor-dark","isbl-editor-light","kimbie-dark","kimbie-light","lightfair","lioshi","magula","mono-blue","monokai-sublime","monokai","night-owl","nnfx-dark","nnfx-light","nord","obsidian","panda-syntax-dark","panda-syntax-light","paraiso-dark","paraiso-light","pojoaque","purebasic","qtcreator-dark","qtcreator-light","rainbow","routeros","school-book","shades-of-purple","srcery","stackoverflow-dark","stackoverflow-light","sunburst","tokyo-night-dark","tokyo-night-light","tomorrow-night-blue","tomorrow-night-bright","vs","vs2015","xcode","xt256"]
    // override init() {
    //     super.init()
        
    //     // Set base font color to White
    //     // self.fontColor = NSColor.white.withAlphaComponent(0.8)
            
    // }
        override func style(heading str: NSMutableAttributedString, level: Int) {
            str.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.8), range: NSRange(location: 0, length: str.length))
        }
        
        override func style(paragraph str: NSMutableAttributedString) {
            str.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.8), range: NSRange(location: 0, length: str.length))
        }
    override func style(codeBlock str: NSMutableAttributedString, fenceInfo: String?) {
        // Use Highlightr for syntax highlighting
        // highlightr?.setTheme(to: "tomorrow-night-bright")
        // highlightr?.setTheme(to: "monokai-sublime")
        // let darkThemes = themes.filter { $0.contains("dark") }
        // let theme = darkThemes.randomElement()!
        // print(theme)
        // highlightr?.setTheme(to: theme)
        highlightr?.setTheme(to: "monokai-sublime")
        guard let highlightr = highlightr, let code = highlightr.highlight(str.string, as: "swift") else {
            return
        }
        
        str.setAttributedString(code)
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()

app.delegate = appDelegate
app.run()
