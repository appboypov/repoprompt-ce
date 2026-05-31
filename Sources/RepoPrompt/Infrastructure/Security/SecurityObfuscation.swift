//
//  SecurityObfuscation.swift
//  RepoPrompt
//
//  Centralized XOR obfuscation for security-sensitive strings.
//  Encoded values are internal for testability; decoded values stay private to each consumer.
//

import Foundation

enum SecurityObfuscation {
    static let key: UInt8 = 0x5A

    static func decode(_ bytes: [UInt8]) -> String {
        let decoded = bytes.map { $0 ^ key }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    // MARK: - BundleVerifier Keys

    static let expectedBundleIdentifierEncoded: [UInt8] = [
        57, 53, 55, 116, 42, 44, 52, 57, 50, 63, 40, 116, 40, 63, 42,
        53, 42, 40, 53, 55, 42, 46, 116, 57, 63
    ]

    static let expectedTeamIdentifierEncoded: [UInt8] = [
        108, 110, 98, 27, 104, 109, 23, 9, 14, 111
    ]

    // MARK: - Agent Permission Secure Store Keys

    static let agentPermissionSubagentDocumentKeyEncoded: [UInt8] = [
        40, 42, 116, 59, 61, 63, 52, 46, 116, 42, 63, 40, 55, 51, 41, 41,
        51, 53, 52, 41, 116, 41, 47, 56, 59, 61, 63, 52, 46, 116, 44, 107
    ]

    static let agentPermissionCodexDocumentKeyEncoded: [UInt8] = [
        40, 42, 116, 59, 61, 63, 52, 46, 116, 42, 63, 40, 55, 51, 41, 41,
        51, 53, 52, 41, 116, 57, 53, 62, 63, 34, 116, 44, 107
    ]

    static let agentPermissionClaudeDocumentKeyEncoded: [UInt8] = [
        40, 42, 116, 59, 61, 63, 52, 46, 116, 42, 63, 40, 55, 51, 41, 41,
        51, 53, 52, 41, 116, 57, 54, 59, 47, 62, 63, 116, 44, 107
    ]

    static let agentPermissionOpenCodeDocumentKeyEncoded: [UInt8] = [
        40, 42, 116, 59, 61, 63, 52, 46, 116, 42, 63, 40, 55, 51, 41, 41,
        51, 53, 52, 41, 116, 53, 42, 63, 52, 25, 53, 62, 63, 116, 44, 107
    ]

    static let agentPermissionCursorDocumentKeyEncoded: [UInt8] = [
        40, 42, 116, 59, 61, 63, 52, 46, 116, 42, 63, 40, 55, 51, 41, 41,
        51, 53, 52, 41, 116, 57, 47, 40, 41, 53, 40, 116, 44, 107
    ]

    // MARK: - SparkleUpdateManager Keys

    static let expectedFeedURLEncoded: [UInt8] = [
        50, 46, 46, 42, 41, 96, 117, 117, 40, 63, 42, 53, 42, 40, 53,
        55, 42, 46, 116, 41, 105, 116, 47, 41, 119, 63, 59, 41, 46,
        119, 104, 116, 59, 55, 59, 32, 53, 52, 59, 45, 41, 116, 57,
        53, 55, 117, 59, 42, 42, 57, 59, 41, 46, 116, 34, 55, 54
    ]

    static let expectedPublicEdKeyEncoded: [UInt8] = [
        17, 21, 104, 10, 44, 57, 40, 109, 21, 8, 51, 60, 3, 44, 14,
        109, 35, 47, 104, 117, 62, 56, 110, 98, 10, 61, 32, 9, 20,
        20, 117, 8, 29, 99, 62, 49, 99, 105, 105, 107, 51, 47, 11, 103
    ]
}
