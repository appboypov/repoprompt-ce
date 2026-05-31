import Foundation

enum ClaudeReasoningExtractionFeature {
    static let isEnabled = false
}

#if DEBUG
    enum ClaudeReasoningDebugLog {
        static let fileURL = URL(fileURLWithPath: "/tmp/repoprompt-claude-reasoning-debug.log")
        private static let lock = NSLock()

        static func emit(_ line: String) {
            print(line)
            append(line)
        }

        static func append(_ line: String) {
            lock.lock()
            defer { lock.unlock() }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let payload = "\(timestamp) \(line)\n"
            guard let data = payload.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL)
            {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
#endif
