import Foundation

/// Extracts the optional chat-name marker from assistant responses.
enum ChatNameExtractor {
    /// Removes the first `<chatName=...>` snippet from the content if it contains a non-empty name.
    /// Returns the extracted name if found, otherwise nil and leaves content unchanged.
    static func extractAndRemove(from content: inout String) -> String? {
        let pattern = #"<chatName\s*=\s*(?:"([^"]+)"|([^>"\s]+))\s*(?:/?)>"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
        else {
            return nil
        }

        let name: String
        if let quotedRange = Range(match.range(at: 1), in: content), !quotedRange.isEmpty {
            name = String(content[quotedRange])
        } else if let unquotedRange = Range(match.range(at: 2), in: content), !unquotedRange.isEmpty {
            name = String(content[unquotedRange])
        } else {
            return nil
        }

        guard let snippetRange = Range(match.range, in: content) else {
            return nil
        }

        content.removeSubrange(snippetRange)
        return name
    }
}
