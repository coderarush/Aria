import Foundation
import AVFoundation
import Speech

/// Checks and requests the permissions the slice needs: microphone + speech.
/// Screen Recording permission is handled lazily by ScreenCaptureEngine (the
/// system prompts on first capture attempt).
enum PermissionsManager {

    enum Status {
        case granted, denied, undetermined
    }

    // MARK: Microphone

    static var microphoneStatus: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: Speech recognition

    static var speechStatus: Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .denied
        }
    }

    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Request everything the slice needs up front. Returns true if mic + speech
    /// are both granted (the minimum for wake-word listening).
    static func requestCorePermissions() async -> Bool {
        let mic = await requestMicrophone()
        let speech = await requestSpeech()
        Log.app.info("Permissions — mic: \(mic), speech: \(speech)")
        return mic && speech
    }
}
