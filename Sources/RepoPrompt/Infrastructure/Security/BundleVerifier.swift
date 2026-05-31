//
//  BundleVerifier.swift
//  RepoPrompt
//
//  Created by Eric Provencher on 2025-03-15.
//

import Foundation
import Security

/// Simple helper for verifying app bundle signature integrity
class BundleVerifier {
    private static let expectedBundleIdentifier = SecurityObfuscation.decode(SecurityObfuscation.expectedBundleIdentifierEncoded)
    private static let expectedTeamIdentifier = SecurityObfuscation.decode(SecurityObfuscation.expectedTeamIdentifierEncoded)

    /// Error types that can occur during bundle verification
    enum VerificationError: Error, CustomStringConvertible {
        case bundleURLInvalid
        case codeSignatureCreationFailed
        case signatureValidationFailed(OSStatus)

        var description: String {
            switch self {
            case .bundleURLInvalid:
                "Invalid bundle URL"
            case .codeSignatureCreationFailed:
                "Failed to create code signature reference"
            case let .signatureValidationFailed(status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Signature validation failed (\(status))"
            }
        }
    }

    /// Verifies the signature of the specified bundle
    /// - Parameter bundle: The bundle to verify (defaults to main bundle)
    /// - Returns: True if the signature is valid
    /// - Throws: VerificationError if validation fails
    @discardableResult
    static func verifyBundleSignature(bundle: Bundle = Bundle.main) throws -> Bool {
        // Get the bundle URL
        guard let bundleURL = bundle.bundleURL as CFURL? else {
            throw VerificationError.bundleURLInvalid
        }

        // Create a static code reference
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL, [], &staticCode)

        guard createStatus == errSecSuccess, let code = staticCode else {
            throw VerificationError.codeSignatureCreationFailed
        }

        // Set validation flags for thorough verification
        let validationFlags = SecCSFlags(
            rawValue:
            kSecCSStrictValidate | // Strict validation
                kSecCSCheckAllArchitectures | // Check all architectures
                kSecCSCheckNestedCode // Check embedded frameworks
        )

        // Verify the signature
        let validationResult = SecStaticCodeCheckValidity(code, validationFlags, nil)

        if validationResult != errSecSuccess {
            throw VerificationError.signatureValidationFailed(validationResult)
        }

        try verifySigningIdentity(for: code)

        return true
    }

    // MARK: - Identity Requirements

    private static func verifySigningIdentity(for code: SecStaticCode) throws {
        // In debug builds, verify team ID only (bundle ID differs between debug/release)
        // In release builds, verify both bundle ID and team ID
        #if DEBUG
            let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""
        #else
            let requirementString = "anchor apple generic and identifier \"\(expectedBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""
        #endif

        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)
        guard requirementStatus == errSecSuccess, let requirement else {
            throw VerificationError.signatureValidationFailed(requirementStatus)
        }

        let validationFlags = SecCSFlags(
            rawValue:
            kSecCSStrictValidate |
                kSecCSCheckAllArchitectures |
                kSecCSCheckNestedCode
        )
        let requirementCheck = SecStaticCodeCheckValidity(code, validationFlags, requirement)
        guard requirementCheck == errSecSuccess else {
            throw VerificationError.signatureValidationFailed(requirementCheck)
        }
    }
}
