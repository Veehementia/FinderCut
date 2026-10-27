import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Intercepts keyboard shortcuts in Finder to add "cut & paste" for files.
///
/// - ⌘X in Finder (when not editing text) is turned into ⌘C and the app remembers a cut is pending.
/// - ⌘V in Finder with a cut pending is turned into ⌥⌘V ("Move Item Here").
/// - ⌘C or Esc in Finder, or any new clipboard content, cancels the pending cut.
final class CutController {
    enum State: Equatable {
        case idle
        case cutPending(itemCount: Int)
    }

    /// Tags the key events we synthesize so the tap lets them through untouched.
    private static let syntheticMarker: Int64 = 0x4643_5554 // "FCUT"
    private static let finderBundleID = "com.apple.finder"

    var isEnabled = true {
        didSet { if !isEnabled { cancelCut() } }
    }
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Clipboard change count right after the cut's copy landed; nil while waiting for it.
    private var cutChangeCount: Int?
    private var clipboardWatcher: Timer?

    var isRunning: Bool { tap != nil }

    /// Installs the event tap. Fails (returns false) until Accessibility access is granted.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<CutController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        cancelCut()
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        case .keyDown:
            break
        default:
            return passThrough
        }

        guard isEnabled,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker,
              let finder = frontmostFinder()
        else { return passThrough }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])

        if modifiers.isEmpty, keyCode == kVK_Escape {
            cancelCut()
            return passThrough
        }

        guard modifiers == .maskCommand else { return passThrough }

        switch keyCode {
        case kVK_ANSI_X:
            // Renaming a file or typing in the search field: keep normal text cut.
            if isEditingText(in: finder) { return passThrough }
            beginCut()
            return nil

        case kVK_ANSI_C:
            if !isEditingText(in: finder) { cancelCut() }
            return passThrough

        case kVK_ANSI_V:
            guard case .cutPending = state, !isEditingText(in: finder) else { return passThrough }
            guard clipboardStillHoldsCut() else {
                cancelCut()
                return passThrough
            }
            postKey(kVK_ANSI_V, flags: [.maskCommand, .maskAlternate])
            cancelCut()
            return nil

        default:
            return passThrough
        }
    }

    // MARK: - Cut lifecycle

    private func beginCut() {
        let before = NSPasteboard.general.changeCount
        cutChangeCount = nil
        postKey(kVK_ANSI_C, flags: .maskCommand)

        // Finder writes the clipboard asynchronously; check what landed shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            let files = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []

            guard pasteboard.changeCount != before, !files.isEmpty else {
                // Nothing selected, so nothing was copied.
                self.cancelCut()
                NSSound.beep()
                return
            }
            self.cutChangeCount = pasteboard.changeCount
            self.state = .cutPending(itemCount: files.count)
            self.watchClipboard()
        }
    }

    func cancelCut() {
        cutChangeCount = nil
        clipboardWatcher?.invalidate()
        clipboardWatcher = nil
        state = .idle
    }

    private func clipboardStillHoldsCut() -> Bool {
        guard let cutChangeCount else { return false }
        return NSPasteboard.general.changeCount == cutChangeCount
    }

    /// Drops the pending cut as soon as something else is copied, so the menu bar icon stays truthful.
    private func watchClipboard() {
        clipboardWatcher?.invalidate()
        clipboardWatcher = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.clipboardStillHoldsCut() { self.cancelCut() }
        }
    }

    // MARK: - Helpers

    private func frontmostFinder() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.finderBundleID
        else { return nil }
        return app
    }

    private func isEditingText(in app: NSRunningApplication) -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }

        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
        let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
        return (role as? String).map(textRoles.contains) ?? false
    }

    private func postKey(_ keyCode: Int, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }
}
