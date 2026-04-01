import Foundation
import LocalAuthentication

enum DeviceOwnerAuthenticationError: LocalizedError {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}

enum DeviceOwnerAuthenticationGate {
    @MainActor
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            let message = authError?.localizedDescription
                ?? "Set up Face ID, Touch ID, or a device passcode to reveal your private key."
            throw DeviceOwnerAuthenticationError.unavailable(message)
        }

        do {
            let success = try await evaluate(
                context: context,
                policy: .deviceOwnerAuthentication,
                reason: reason
            )
            guard success else {
                throw DeviceOwnerAuthenticationError.failed("Authentication didn’t complete.")
            }
        } catch let error as DeviceOwnerAuthenticationError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == LAError.errorDomain {
                switch LAError.Code(rawValue: nsError.code) {
                case .userCancel, .systemCancel, .appCancel:
                    throw DeviceOwnerAuthenticationError.failed("Authentication was cancelled.")
                default:
                    break
                }
            }
            throw DeviceOwnerAuthenticationError.failed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private static func evaluate(
        context: LAContext,
        policy: LAPolicy,
        reason: String
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
