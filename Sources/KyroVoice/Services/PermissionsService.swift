import Foundation
import AppKit
import AVFoundation
import ApplicationServices
import IOKit

public enum PermissionStatus {
    case granted
    case denied
    case notDetermined
    case unknown

    public var displayName: String {
        switch self {
        case .granted:        return "Granted"
        case .denied:         return "Denied"
        case .notDetermined:  return "Not requested"
        case .unknown:        return "Unknown"
        }
    }

    public var isGranted: Bool { self == .granted }
}

/// Reports the status of the three permissions KyroVoice needs.
@MainActor
public final class PermissionsService: ObservableObject {
    @Published public private(set) var microphone: PermissionStatus = .notDetermined
    @Published public private(set) var accessibility: PermissionStatus = .notDetermined
    @Published public private(set) var inputMonitoring: PermissionStatus = .notDetermined

    public init() { refresh() }

    public func refresh() {
        microphone      = Self.microphoneStatus()
        accessibility   = Self.accessibilityStatus()
        inputMonitoring = Self.inputMonitoringStatus()
    }

    public func requestMicrophone() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { ok in cont.resume(returning: ok) }
            }
        }
        refresh()
    }

    /// Prompts the AX permission dialog if not yet decided.
    public func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let opts: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        refresh()
    }

    public func openSystemSettingsAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    public func openSystemSettingsInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    public func openSystemSettingsMicrophone() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Probes

    private static func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .granted
        case .denied,
             .restricted:    return .denied
        case .notDetermined: return .notDetermined
        @unknown default:    return .unknown
        }
    }

    private static func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Probe Input Monitoring by attempting to create a CGEvent source.
    /// On 10.15+ this requires the user to add the app to Input Monitoring.
    private static func inputMonitoringStatus() -> PermissionStatus {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:  return .denied
        case kIOHIDAccessTypeUnknown: return .notDetermined
        default:                      return .unknown
        }
    }
}
