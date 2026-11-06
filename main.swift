import Cocoa
import Foundation

// MARK: - Constants & Config
let USER_SPRITES_DIR = NSString(string: "~/.desktop-pet/sprites").expandingTildeInPath
let PLUGIN_SPRITES_DIR = NSString(string: "~/.gemini/config/plugins/desktop-pet/sprites").expandingTildeInPath
let LIVE_STATE_FILE = NSString(string: "~/.desktop-pet/live_state.json").expandingTildeInPath
let POSITION_FILE = NSString(string: "~/.desktop-pet/position.json").expandingTildeInPath
let SETTINGS_FILE = NSString(string: "~/.desktop-pet/settings.json").expandingTildeInPath

// 10 minutes of inactivity required before sleeping
let SLEEP_INACTIVITY_SECONDS: TimeInterval = 600.0

enum PetState: String {
    case idle = "idle"
    case question = "question"
    case working = "working"
    case sleeping = "sleeping"
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var catWindow: CatWindow!
    var watchdogTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        catWindow = CatWindow()
        catWindow.makeKeyAndOrderFront(nil)

        setupEventListeners()
        startWatchdog()
    }

    private func setupEventListeners() {
        // Event-driven termination: instant exit when Antigravity closes, 0 CPU polling
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            let isAntigravityRunning = NSWorkspace.shared.runningApplications.contains {
                $0.localizedName?.lowercased().contains("antigravity") == true ||
                $0.bundleIdentifier?.lowercased().contains("antigravity") == true
            }
            if !isAntigravityRunning {
                NSApp.terminate(nil)
            }
        }

        // Battery saver: pause animation timer when displays go to sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.catWindow?.catView?.pauseAnimation()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.catWindow?.catView?.resumeAnimation()
        }
    }

    private func startWatchdog() {
        // Relaxed backup watchdog (every 15s instead of 3s)
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            let isAntigravityRunning = NSWorkspace.shared.runningApplications.contains {
                $0.localizedName?.lowercased().contains("antigravity") == true ||
                $0.bundleIdentifier?.lowercased().contains("antigravity") == true
            }
            if !isAntigravityRunning {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Cat Window (86x86 pt, level .statusBar, strictly clamped inside screen)
class CatWindow: NSPanel {
    var catView: CatView!

    init() {
        let size = NSSize(width: 86, height: 86)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.isMovableByWindowBackground = false

        catView = CatView(frame: NSRect(origin: .zero, size: size))
        catView.catWindow = self
        self.contentView = catView

        loadSavedPosition()
    }

    func activateAntigravity() {
        catView.lastActiveDate = Date()
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased().contains("antigravity") == true ||
            $0.bundleIdentifier?.lowercased().contains("antigravity") == true
        }) {
            app.activate()
        } else {
            let script = "tell application \"Antigravity\" to activate"
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
            }
        }

        // If a specific conversation is waiting for user input, switch directly to it!
        if let waitingId = catView.waitingConversationId, !waitingId.isEmpty {
            let scriptPath = NSString(string: "~/.gemini/config/plugins/desktop-pet/scripts/switch_conversation.py").expandingTildeInPath
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [scriptPath, waitingId]
            try? task.run()
        }
    }

    func savePosition() {
        let origin = self.frame.origin
        let data: [String: CGFloat] = ["x": origin.x, "y": origin.y]
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: URL(fileURLWithPath: POSITION_FILE))
        }
    }

    func loadSavedPosition() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: POSITION_FILE)),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: CGFloat],
           let x = dict["x"], let y = dict["y"] {
            let point = NSPoint(x: x, y: y)
            for screen in NSScreen.screens {
                if screen.frame.contains(point) {
                    self.setFrameOrigin(point)
                    catView?.territoryAnchor = point
                    return
                }
            }
        }
        resetToDefaultPosition()
    }

    func resetToDefaultPosition() {
        let screen = self.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let petSize: CGFloat = 86.0
        let x = visible.maxX - petSize - 24.0
        let y = visible.minY + 40.0
        let point = NSPoint(x: x, y: y)
        self.setFrameOrigin(point)
        catView?.territoryAnchor = point
        savePosition()
    }

    func moveToScreen(_ screen: NSScreen) {
        let visible = screen.visibleFrame
        let petSize: CGFloat = 86.0
        let x = visible.maxX - petSize - 24.0
        let y = visible.minY + 40.0
        let point = NSPoint(x: x, y: y)
        self.setFrameOrigin(point)
        catView?.territoryAnchor = point
        savePosition()
    }

    func settleOnNearestScreen() {
        let petSize: CGFloat = 86.0
        let windowRect = self.frame
        let windowCenter = NSPoint(x: windowRect.midX, y: windowRect.midY)

        let screen = NSScreen.screens.first { NSMouseInRect(windowCenter, $0.frame, false) }
            ?? self.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let visible = screen.visibleFrame
        let clampedX = max(visible.minX, min(windowRect.origin.x, visible.maxX - petSize))
        let clampedY = max(visible.minY, min(windowRect.origin.y, visible.maxY - petSize))
        self.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }
}

// MARK: - Cat View (Calm 0.5–0.7 FPS Pacing, Zero Noise)
class CatView: NSView {
    weak var catWindow: CatWindow?

    var imageView: NSImageView!
    var currentState: PetState = .idle
    var animStep: Int = 0
    var lastActiveDate: Date = Date()
    var waitingConversationId: String? = nil

    var animTimer: Timer?
    var liveStateTimer: Timer?
    var sprites: [String: [NSImage]] = [:]

    var initialMouseLocation: NSPoint = .zero
    var initialWindowLocation: NSPoint = .zero
    var isDragging: Bool = false

    var typingSoundsEnabled: Bool = true
    var completionChimeEnabled: Bool = true
    var questionAlertEnabled: Bool = true
    private var lastSettingsModTime: time_t = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.drawsAsynchronously = true

        imageView = NSImageView(frame: bounds)
        imageView.wantsLayer = true
        imageView.layer?.drawsAsynchronously = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)

        loadSettings()
        loadAllSprites()
        startTimers()
    }

    func loadSettings() {
        if FileManager.default.fileExists(atPath: SETTINGS_FILE) {
            var statBuf = stat()
            if stat(SETTINGS_FILE, &statBuf) == 0 {
                lastSettingsModTime = statBuf.st_mtimespec.tv_sec
            }
            if let data = try? Data(contentsOf: URL(fileURLWithPath: SETTINGS_FILE)),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let ts = dict["typingSounds"] as? Bool { typingSoundsEnabled = ts }
                else if let se = dict["soundEffects"] as? Bool { typingSoundsEnabled = se }

                if let cc = dict["completionChime"] as? Bool { completionChimeEnabled = cc }
                else if let se = dict["soundEffects"] as? Bool { completionChimeEnabled = se }

                if let qa = dict["questionAlert"] as? Bool { questionAlertEnabled = qa }
                else if let qc = dict["questionChime"] as? Bool { questionAlertEnabled = qc }

                saveSettings()
            }
        } else {
            saveSettings()
        }
    }

    func saveSettings() {
        let dict: [String: Any] = [
            "typingSounds": typingSoundsEnabled,
            "completionChime": completionChimeEnabled,
            "questionAlert": questionAlertEnabled
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: SETTINGS_FILE))
            var statBuf = stat()
            if stat(SETTINGS_FILE, &statBuf) == 0 {
                lastSettingsModTime = statBuf.st_mtimespec.tv_sec
            }
        }
    }

    func reloadSettingsIfNeeded() {
        var statBuf = stat()
        if stat(SETTINGS_FILE, &statBuf) == 0 {
            if statBuf.st_mtimespec.tv_sec != lastSettingsModTime {
                loadSettings()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadAllSprites() {
        func getImg(_ name: String) -> NSImage? {
            let userURL = URL(fileURLWithPath: USER_SPRITES_DIR).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: userURL.path), let img = NSImage(contentsOf: userURL) {
                return img
            }
            let pluginURL = URL(fileURLWithPath: PLUGIN_SPRITES_DIR).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: pluginURL.path), let img = NSImage(contentsOf: pluginURL) {
                return img
            }
            return nil
        }

        func loadFrames(_ base: String, count: Int = 12) -> [NSImage] {
            var frames: [NSImage] = []
            for i in 1...count {
                if let img = getImg("\(base)_\(i).png") {
                    frames.append(img)
                }
            }
            if frames.isEmpty, let single = getImg("\(base).png") {
                frames.append(single)
            }
            return frames
        }

        sprites["idle"] = loadFrames("idle", count: 8)
        sprites["sleeping"] = loadFrames("sleeping", count: 12)
        sprites["working"] = loadFrames("working", count: 12)
        sprites["question"] = loadFrames("question", count: 8)
        sprites["walking"] = loadFrames("walking", count: 8)

        updateSprite()
    }

    private func startTimers() {
        // High-efficiency dynamic frame timer (schedules exact delay, zero wasted wakeups)
        scheduleNextFrame()

        // Lightweight live hook state watcher (250ms with stat() mtime caching)
        liveStateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkLiveState()
        }
        checkLiveState()

        // Setup periodic local stroll loop
        setupStrollTimer()
    }

    var isScreenSleeping: Bool = false

    func pauseAnimation() {
        isScreenSleeping = true
        cancelStroll()
        animTimer?.invalidate()
        animTimer = nil
    }

    func resumeAnimation() {
        guard isScreenSleeping else { return }
        isScreenSleeping = false
        scheduleNextFrame()
    }

    func setState(_ newState: PetState) {
        guard currentState != newState else { return }

        let previousState = currentState
        currentState = newState
        animStep = 0

        // If transitioning away from idle, stop any active walking immediately
        if newState != .idle {
            cancelStroll()
        } else {
            if territoryAnchor == .zero {
                territoryAnchor = catWindow?.frame.origin ?? .zero
            }
            nextStrollTime = Date().addingTimeInterval(Double.random(in: 30.0...50.0))
        }

        switch newState {
        case .question:
            if questionAlertEnabled {
                NSSound(named: "Ping")?.play()
            }
            lastActiveDate = Date()
        case .working:
            if typingSoundsEnabled {
                NSSound(named: "Tink")?.play()
            }
            lastActiveDate = Date()
        case .idle:
            if previousState == .working && completionChimeEnabled {
                NSSound(named: "Glass")?.play()
            }
            lastActiveDate = Date()
        case .sleeping:
            break
        }

        updateSprite()
        scheduleNextFrame()
    }

    // MARK: - Event-Driven Dynamic Flipbook Loop (Zero Idle Overhead)
    private func frameDuration(for state: PetState) -> CFTimeInterval {
        if isWalking {
            return 1.0 / 10.0 // 10 FPS: smooth brisk walk cycle
        }
        switch state {
        case .working:
            return 1.0 / 12.0  // 12 FPS: snappy paw clacking
        case .idle:
            return 1.0 / 8.0   // 8 FPS: calm 1.0s breathing & tail flick cycle
        case .sleeping:
            return 1.0 / 7.0   // 7 FPS: peaceful snoozing & cyan 'z'
        case .question:
            return 1.0 / 8.0   // 8 FPS: curious ping-pong head tilt
        }
    }

    private func scheduleNextFrame() {
        guard !isScreenSleeping else { return }
        let duration = frameDuration(for: currentState)
        animTimer?.invalidate()
        animTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.stepAnimationFrame()
        }
    }

    private func stepAnimationFrame() {
        animStep += 1
        updateSprite()
        scheduleNextFrame()
    }

    private func updateSprite() {
        let key = isWalking ? "walking" : currentState.rawValue
        let frames = sprites[key] ?? sprites["idle"] ?? []
        guard !frames.isEmpty else { return }

        let count = frames.count
        if count == 1 {
            imageView.image = frames[0]
            return
        }

        let frameIndex = animStep % count
        imageView.image = frames[frameIndex]
    }

    // MARK: - Local Roaming Territory Engine
    var isWalking: Bool = false
    var territoryAnchor: NSPoint = .zero
    let territoryRadius: CGFloat = 180.0
    var strollTimer: Timer?
    private var currentWalkUUID: UUID? = nil
    private var nextStrollTime: Date = Date().addingTimeInterval(35.0)

    func setFacing(right: Bool) {
        if right {
            imageView.layer?.transform = CATransform3DIdentity
        } else {
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, bounds.width, 0, 0)
            transform = CATransform3DScale(transform, -1.0, 1.0, 1.0)
            imageView.layer?.transform = transform
        }
    }

    func cancelStroll() {
        currentWalkUUID = nil
        if isWalking {
            isWalking = false
            if let win = catWindow {
                // Instantly cancel ongoing animation and freeze at current window frame
                win.setFrame(win.frame, display: true)
                catWindow?.savePosition()
            }
            setFacing(right: true)
            animStep = 0
            updateSprite()
            scheduleNextFrame()
        }
    }

    private func setupStrollTimer() {
        strollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.considerTakingStroll()
        }
    }

    private func considerTakingStroll() {
        guard currentState == .idle, !isDragging, !isWalking, !isScreenSleeping else { return }
        guard Date() >= nextStrollTime else { return }

        // Next stroll interval (between 35 and 60 seconds)
        nextStrollTime = Date().addingTimeInterval(Double.random(in: 35.0...60.0))

        startStroll()
    }

    func startStroll() {
        guard let window = catWindow, currentState == .idle, !isDragging, !isWalking else { return }

        if territoryAnchor == .zero {
            territoryAnchor = window.frame.origin
        }

        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let petSize: CGFloat = 86.0

        // Strict boundary: territory bounding box clamped to visible display area
        let minX = max(visible.minX + 24.0, territoryAnchor.x - territoryRadius)
        let maxX = min(visible.maxX - petSize - 24.0, territoryAnchor.x + territoryRadius)
        let minY = max(visible.minY + 24.0, territoryAnchor.y - territoryRadius)
        let maxY = min(visible.maxY - petSize - 24.0, territoryAnchor.y + territoryRadius)

        let curX = window.frame.origin.x
        let curY = window.frame.origin.y

        // Pick random hop distance (60 to 130 px)
        let distance = CGFloat.random(in: 60.0...130.0)

        // Check if near territory boundaries: if so, softly turn back toward territoryAnchor
        var angle = Double.random(in: 0.0...(2.0 * .pi))
        let distFromAnchor = hypot(curX - territoryAnchor.x, curY - territoryAnchor.y)

        if distFromAnchor > territoryRadius * 0.65 || curX < minX + 30 || curX > maxX - 30 || curY < minY + 30 || curY > maxY - 30 {
            let inwardAngle = atan2(Double(territoryAnchor.y - curY), Double(territoryAnchor.x - curX))
            angle = inwardAngle + Double.random(in: -(.pi / 3.0)...(.pi / 3.0))
        }

        var rawX = curX + distance * CGFloat(cos(angle))
        var rawY = curY + distance * CGFloat(sin(angle))

        // Ensure target stays within territory circle
        let targetDistFromAnchor = hypot(rawX - territoryAnchor.x, rawY - territoryAnchor.y)
        if targetDistFromAnchor > territoryRadius {
            let scale = territoryRadius / targetDistFromAnchor
            rawX = territoryAnchor.x + (rawX - territoryAnchor.x) * scale
            rawY = territoryAnchor.y + (rawY - territoryAnchor.y) * scale
        }

        let targetX = max(minX, min(rawX, maxX))
        let targetY = max(minY, min(rawY, maxY))
        let targetPoint = NSPoint(x: targetX, y: targetY)

        let travelDist = hypot(targetPoint.x - curX, targetPoint.y - curY)
        if travelDist < 25.0 { return }

        isWalking = true
        animStep = 0
        updateSprite()
        scheduleNextFrame()

        walkTo(targetPoint: targetPoint, speed: 50.0) { [weak self] in
            guard let self = self, self.isWalking, self.currentState == .idle else { return }

            // Reached destination: settle down here as new spot within territory
            self.isWalking = false
            self.animStep = 0
            self.updateSprite()
            self.scheduleNextFrame()
            self.catWindow?.savePosition()
        }
    }

    private func walkTo(targetPoint: NSPoint, speed: CGFloat = 50.0, completion: @escaping () -> Void) {
        guard let win = catWindow, currentState == .idle, !isDragging else { return }
        let currentPoint = win.frame.origin
        let distance = hypot(targetPoint.x - currentPoint.x, targetPoint.y - currentPoint.y)
        guard distance > 4.0 else {
            completion()
            return
        }

        let dx = targetPoint.x - currentPoint.x
        if abs(dx) > 6.0 {
            setFacing(right: dx > 0)
        }

        let duration = max(0.4, Double(distance / speed))

        let thisWalkUUID = UUID()
        currentWalkUUID = thisWalkUUID

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            win.animator().setFrame(NSRect(origin: targetPoint, size: win.frame.size), display: false)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            guard self.isWalking, self.currentState == .idle, !self.isDragging, self.currentWalkUUID == thisWalkUUID else {
                return
            }
            completion()
        })
    }

    // MARK: - State Watcher with POSIX stat() Caching & 10-Minute Sleep Rule
    private var lastFileModTime: time_t = 0
    private var cachedStateStr: String = "idle"

    private func checkLiveState() {
        reloadSettingsIfNeeded()
        var statBuf = stat()
        let ret = stat(LIVE_STATE_FILE, &statBuf)
        if ret == 0 {
            let currentModTime = statBuf.st_mtimespec.tv_sec
            // Only read disk and parse JSON when the file has actually been modified
            if currentModTime != lastFileModTime {
                lastFileModTime = currentModTime
                if let data = try? Data(contentsOf: URL(fileURLWithPath: LIVE_STATE_FILE)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let state = json["state"] as? String {
                    cachedStateStr = state
                    waitingConversationId = json["waitingConversationId"] as? String
                }
            }
        }

        let stateStr = cachedStateStr
        if stateStr == "working" {
            self.lastActiveDate = Date()
            self.setState(.working)
        } else if stateStr == "question" {
            self.lastActiveDate = Date()
            self.setState(.question)
        } else {
            let inactiveSeconds = Date().timeIntervalSince(self.lastActiveDate)

            if inactiveSeconds >= SLEEP_INACTIVITY_SECONDS {
                if self.currentState != .sleeping {
                    self.currentState = .sleeping
                    self.animStep = 0
                    self.scheduleNextFrame()
                }
            } else {
                if self.currentState == .sleeping {
                    self.setState(.idle)
                } else if self.currentState != .idle {
                    self.setState(.idle)
                }
            }
        }
    }

    // MARK: - Multi-Monitor Dragging with Seamless Traversal
    override func mouseDown(with event: NSEvent) {
        lastActiveDate = Date()
        cancelStroll()
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowLocation = catWindow?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        let currentMouseLocation = NSEvent.mouseLocation
        let rawOrigin = NSPoint(
            x: initialWindowLocation.x + (currentMouseLocation.x - initialMouseLocation.x),
            y: initialWindowLocation.y + (currentMouseLocation.y - initialMouseLocation.y)
        )

        let petSize: CGFloat = 86.0

        // Prioritize screen containing the mouse cursor
        let windowCenter = NSPoint(x: rawOrigin.x + petSize / 2.0, y: rawOrigin.y + petSize / 2.0)
        let targetScreen = NSScreen.screens.first { NSMouseInRect(currentMouseLocation, $0.frame, false) }
            ?? NSScreen.screens.first { NSMouseInRect(windowCenter, $0.frame, false) }
            ?? catWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        // Allow smooth traversal across adjacent displays without hitting an invisible wall
        var minX = targetScreen.visibleFrame.minX
        var maxX = targetScreen.visibleFrame.maxX - petSize
        var minY = targetScreen.visibleFrame.minY
        var maxY = targetScreen.visibleFrame.maxY - petSize

        for other in NSScreen.screens where other != targetScreen {
            // Screen adjacent on the left
            if abs(other.frame.maxX - targetScreen.frame.minX) <= 2.0 {
                minX = min(minX, other.visibleFrame.minX)
            }
            // Screen adjacent on the right
            if abs(other.frame.minX - targetScreen.frame.maxX) <= 2.0 {
                maxX = max(maxX, other.visibleFrame.maxX - petSize)
            }
            // Screen adjacent below
            if abs(other.frame.maxY - targetScreen.frame.minY) <= 2.0 {
                minY = min(minY, other.visibleFrame.minY)
            }
            // Screen adjacent above
            if abs(other.frame.minY - targetScreen.frame.maxY) <= 2.0 {
                maxY = max(maxY, other.visibleFrame.maxY - petSize)
            }
        }

        let clampedX = max(minX, min(rawOrigin.x, maxX))
        let clampedY = max(minY, min(rawOrigin.y, maxY))

        catWindow?.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    override func mouseUp(with event: NSEvent) {
        lastActiveDate = Date()
        let dist = hypot(NSEvent.mouseLocation.x - initialMouseLocation.x, NSEvent.mouseLocation.y - initialMouseLocation.y)

        if dist < 5 && !isDragging {
            catWindow?.activateAntigravity()
        } else {
            catWindow?.settleOnNearestScreen()
            catWindow?.savePosition()
            territoryAnchor = catWindow?.frame.origin ?? territoryAnchor
        }
        isDragging = false
    }

    override func rightMouseUp(with event: NSEvent) {
        lastActiveDate = Date()
        cancelStroll()
        let menu = NSMenu()

        func addItem(_ title: String, action: Selector?, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            menu.addItem(item)
            return item
        }

        _ = addItem("Switch to Antigravity", action: #selector(switchMenu), target: self)
        _ = addItem("Take a Stroll", action: #selector(takeStrollMenu), key: "s", target: self)
        menu.addItem(NSMenuItem.separator())

        // Sounds Submenu
        let soundMenu = NSMenu()

        let completionItem = NSMenuItem(title: "Task Completion Chime", action: #selector(toggleCompletionChimeMenu), keyEquivalent: "")
        completionItem.target = self
        completionItem.state = completionChimeEnabled ? .on : .off
        soundMenu.addItem(completionItem)

        let questionItem = NSMenuItem(title: "Question Alert", action: #selector(toggleQuestionAlertMenu), keyEquivalent: "")
        questionItem.target = self
        questionItem.state = questionAlertEnabled ? .on : .off
        soundMenu.addItem(questionItem)

        let typingItem = NSMenuItem(title: "Typing Sounds", action: #selector(toggleTypingSoundsMenu), keyEquivalent: "")
        typingItem.target = self
        typingItem.state = typingSoundsEnabled ? .on : .off
        soundMenu.addItem(typingItem)

        soundMenu.addItem(NSMenuItem.separator())

        let isAnySoundOn = completionChimeEnabled || questionAlertEnabled || typingSoundsEnabled
        let muteAllTitle = isAnySoundOn ? "Mute All" : "Unmute All"
        let muteItem = NSMenuItem(title: muteAllTitle, action: #selector(toggleMuteAllMenu), keyEquivalent: "")
        muteItem.target = self
        soundMenu.addItem(muteItem)

        let soundMenuItem = NSMenuItem(title: "Sounds", action: nil, keyEquivalent: "")
        soundMenuItem.submenu = soundMenu
        menu.addItem(soundMenuItem)

        menu.addItem(NSMenuItem.separator())

        if NSScreen.screens.count > 1 {
            let monitorMenu = NSMenu()
            for (idx, screen) in NSScreen.screens.enumerated() {
                let name = screen.localizedName
                let isCurrent = (catWindow?.screen == screen)
                let item = NSMenuItem(title: "\(name)", action: #selector(selectMonitorMenu(_:)), keyEquivalent: "")
                item.target = self
                item.tag = idx
                item.state = isCurrent ? .on : .off
                monitorMenu.addItem(item)
            }
            let monitorMenuItem = NSMenuItem(title: "Move to Screen", action: nil, keyEquivalent: "")
            monitorMenuItem.submenu = monitorMenu
            menu.addItem(monitorMenuItem)
        }

        _ = addItem("Reset Position to Corner", action: #selector(resetPositionMenu), target: self)
        _ = addItem("Open Sprites Folder...", action: #selector(openSpritesMenu), target: self)
        menu.addItem(NSMenuItem.separator())
        _ = addItem("Quit Desktop Pet", action: #selector(quitAppMenu), key: "q", target: self)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func selectMonitorMenu(_ sender: NSMenuItem) {
        if sender.tag >= 0 && sender.tag < NSScreen.screens.count {
            let screen = NSScreen.screens[sender.tag]
            catWindow?.moveToScreen(screen)
        }
    }

    @objc func switchMenu() { catWindow?.activateAntigravity() }
    @objc func takeStrollMenu() { startStroll() }

    @objc func toggleCompletionChimeMenu() {
        completionChimeEnabled.toggle()
        saveSettings()
    }

    @objc func toggleQuestionAlertMenu() {
        questionAlertEnabled.toggle()
        saveSettings()
    }

    @objc func toggleTypingSoundsMenu() {
        typingSoundsEnabled.toggle()
        saveSettings()
    }

    @objc func toggleMuteAllMenu() {
        if completionChimeEnabled || questionAlertEnabled || typingSoundsEnabled {
            completionChimeEnabled = false
            questionAlertEnabled = false
            typingSoundsEnabled = false
        } else {
            completionChimeEnabled = true
            questionAlertEnabled = true
            typingSoundsEnabled = true
        }
        saveSettings()
    }

    @objc func openSpritesMenu() { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: USER_SPRITES_DIR) }
    @objc func resetPositionMenu() { catWindow?.resetToDefaultPosition() }
    @objc func quitAppMenu() { NSApp.terminate(nil) }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
