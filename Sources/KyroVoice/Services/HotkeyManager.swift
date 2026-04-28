import Foundation
import Carbon.HIToolbox
import AppKit

/// Global hotkey via Carbon RegisterEventHotKey.
/// Delivers both press AND release callbacks (required for push-to-talk).
public final class HotkeyManager {
    public var onHotkeyDown: (() -> Void)?
    public var onHotkeyUp: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private var currentID: UInt32 = 0
    private var registered = false

    private static let signature: OSType = {
        // 'KYRO' as a four-char code.
        let chars: [UInt8] = [0x4B, 0x59, 0x52, 0x4F]
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) |
               (OSType(chars[2]) << 8)  | OSType(chars[3])
    }()

    public init() {
        installEventHandler()
    }

    deinit {
        if let h = eventHandler { RemoveEventHandler(h) }
        unregister()
    }

    public func register(_ config: HotkeyConfig) -> Bool {
        unregister()

        var hkRef: EventHotKeyRef?
        nextID &+= 1
        currentID = nextID
        let hkID = EventHotKeyID(signature: Self.signature, id: currentID)

        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hkID,
            GetEventDispatcherTarget(),
            0,
            &hkRef
        )
        guard status == noErr, let ref = hkRef else {
            NSLog("KyroVoice: RegisterEventHotKey failed (status=\(status))")
            return false
        }
        hotKeyRef = ref
        registered = true
        return true
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registered = false
    }

    // MARK: - Carbon plumbing

    private func installEventHandler() {
        var spec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { (_: EventHandlerCallRef?, eventRef: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
            guard let eventRef, let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hkID = EventHotKeyID()
            let getStatus = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard getStatus == noErr, hkID.id == manager.currentID else { return noErr }

            let kind = GetEventKind(eventRef)
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) {
                    manager.onHotkeyDown?()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    manager.onHotkeyUp?()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            spec.count,
            &spec,
            selfPtr,
            &eventHandler
        )
    }
}
