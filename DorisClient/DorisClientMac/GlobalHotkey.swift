import Cocoa
import Carbon.HIToolbox

/// Manages global keyboard shortcut (Option+Space) to summon Doris
class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var callback: (() -> Void)?

    private init() {}

    /// Register Option+Space as global hotkey
    func register(callback: @escaping () -> Void) {
        self.callback = callback

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install event handler
        let handlerResult = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.callback?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard handlerResult == noErr else {
            print("GlobalHotkeyManager: Failed to install event handler: \(handlerResult)")
            return
        }

        // Register Option+Space
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x444F5253), // "DORS"
            id: 1
        )

        let registerResult = RegisterEventHotKey(
            UInt32(kVK_Space),           // Space key
            UInt32(optionKey),           // Option modifier
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerResult == noErr {
            print("GlobalHotkeyManager: Registered Option+Space hotkey")
        } else {
            print("GlobalHotkeyManager: Failed to register hotkey: \(registerResult)")
        }
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        print("GlobalHotkeyManager: Unregistered hotkey")
    }

    deinit {
        unregister()
    }
}
