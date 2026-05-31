import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    import Darwin
#else
    import Glibc
#endif

extension FileSystemService {
    // MARK: - File and folder manipulation utilities

    /// Atomically move/rename a **file** inside the same root.
    func moveFile(
        atRelativePath oldRelPath: String,
        toRelativePath newRelPath: String
    ) async throws {
        let fm = fm // Cache for multiple calls in this method

        // --- prepare -----------------------------------------------------
        // ── 0. Validate that both paths are *relative* to `self.path` ──────────
        guard !oldRelPath.hasPrefix("/"),
              !newRelPath.hasPrefix("/")
        else {
            throw FileSystemError.invalidRelativePath
        }

        let oldFull = fullPath(forRelativePath: oldRelPath)
        let newFull = fullPath(forRelativePath: newRelPath)

        // 1) Source must exist
        guard fm.fileExists(atPath: oldFull, isDirectory: nil) else {
            throw FileSystemError.fileNotFound
        }

        // 2) Destination must not exist
        guard !fm.fileExists(atPath: newFull, isDirectory: nil) else {
            throw FileSystemError.fileAlreadyExists
        }

        // 3) Ensure parent folder exists (this is fast, keep it in-actor)
        let destDir = (newFull as NSString).deletingLastPathComponent
        try fm.createDirectory(
            atPath: destDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // --- 1. do I/O off-actor ----------------------------------------
        // 4) Perform the move on disk
        do {
            try await Task.detached(priority: .utility) {
                try FileManager.default.moveItem(atPath: oldFull, toPath: newFull)
            }.value // bubbles error
        } catch {
            throw FileSystemError.failedToCreateFile(error)
        }

        // --- 2. in-memory bookkeeping (still inside actor) --------------
        // 5) Immediate in‑memory bookkeeping (fixes race window) ───────────────
        let stdOld = (oldRelPath as NSString).standardizingPath
        let stdNew = (newRelPath as NSString).standardizingPath

        if let wasDir = visitedItems.removeValue(forKey: stdOld) {
            visitedItems[stdNew] = wasDir // will be 'false' for files
        }
        visitedPaths.remove(stdOld)
        visitedPaths.insert(stdNew)

        // Transfer encoding if we have it
        if let encoding = encodingMap[stdOld] {
            encodingMap.removeValue(forKey: stdOld)
            encodingMap[stdNew] = encoding
        }

        // 6) Emit synthetic deltas so the UI updates before FSEvents arrive
        changePublisher.send([.fileRemoved(stdOld), .fileAdded(stdNew)])
    }

    func createFile(atRelativePath relativePath: String, content: String) async throws {
        let fm = fm // Cache for multiple calls in this method
        // --- prepare -----------------------------------------------------
        let fullPath = fullPath(forRelativePath: relativePath)
        let fullURL = URL(fileURLWithPath: fullPath)

        // Ensure directory exists (this is fast, keep it in-actor)
        let directoryURL = fullURL.deletingLastPathComponent()
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        // Check if file already exists
        if fm.fileExists(atPath: fullPath, isDirectory: nil) {
            throw FileSystemError.fileAlreadyExists
        }

        // Prepare data with UTF-8 encoding
        guard let data = content.data(using: .utf8) else {
            throw FileSystemError.failedToCreateFile(
                NSError(
                    domain: "encoding",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to encode text as UTF-8"]
                )
            )
        }

        // --- 1. do I/O off-actor ----------------------------------------
        do {
            try await Task.detached(priority: .utility) {
                try FileSystemService.writeFileRobust(to: fullURL, data: data)
            }.value // bubbles error
            fileSystemDebugLog("File created at \(fullURL.path)")
        } catch {
            throw FileSystemError.failedToCreateFile(error)
        }

        // --- 2. in-memory bookkeeping (still inside actor) --------------
        // update encoding cache (new files default to UTF-8)
        encodingMap[relativePath] = .utf8

        // update visited* sets
        if !visitedPaths.contains(relativePath) {
            visitedPaths.insert(relativePath)
            visitedItems[relativePath] = false
        }

        // emit a *synthetic* delta so the UI updates immediately
        changePublisher.send([.fileAdded(relativePath)])
    }

    func deleteFile(atRelativePath relativePath: String) async throws {
        let fullPath = fullPath(forRelativePath: relativePath)
        let url = URL(fileURLWithPath: fullPath)
        do {
            try fm.removeItem(at: url)
            fileSystemDebugLog("File deleted at \(url.path)")
        } catch {
            throw FileSystemError.failedToDeleteFile(error)
        }
    }

    func moveItemToTrash(atRelativePath relativePath: String) async throws {
        guard !relativePath.hasPrefix("/") else {
            throw FileSystemError.invalidRelativePath
        }

        let normalizedRelativePath = Self.trimPathSlashes((relativePath as NSString).standardizingPath)
        guard !normalizedRelativePath.isEmpty,
              normalizedRelativePath != ".",
              !normalizedRelativePath.hasPrefix("../"),
              normalizedRelativePath != ".."
        else {
            throw FileSystemError.invalidRelativePath
        }

        let url = rootURL.appendingPathComponent(normalizedRelativePath).standardizedFileURL
        let fullPath = url.path
        guard fullPath != standardizedRootPath,
              hasDirectoryPrefix(fullPath, standardizedRootPath)
        else {
            throw FileSystemError.invalidRelativePath
        }

        var isDirectory = ObjCBool(false)
        guard fm.fileExists(atPath: fullPath, isDirectory: &isDirectory) else {
            throw FileSystemError.fileNotFound
        }

        do {
            _ = try moveURLToTrash(url)
            fileSystemDebugLog("File moved to Trash at \(url.path)")
        } catch {
            throw FileSystemError.failedToDeleteFile(error)
        }

        let keysToForget = encodingMap.keys.filter {
            $0 == normalizedRelativePath || $0.hasPrefix(normalizedRelativePath + "/")
        }
        for key in keysToForget {
            encodingMap.removeValue(forKey: key)
        }

        var deltas = removeSubtree(for: normalizedRelativePath)
        if deltas.isEmpty {
            deltas = [isDirectory.boolValue ? .folderRemoved(normalizedRelativePath) : .fileRemoved(normalizedRelativePath)]
        }
        if !deltas.isEmpty {
            changePublisher.send(deltas)
        }
    }

    private func moveURLToTrash(_ url: URL) throws -> URL? {
        #if DEBUG
            return try fm.moveItemToTrash(at: url)
        #else
            var resultingItemURL: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resultingItemURL)
            return resultingItemURL as URL?
        #endif
    }

    /// Re-written non-blocking version
    func editFile(atRelativePath relativePath: String, newContent: String) async throws {
        // --- prepare -----------------------------------------------------
        let fullPath = fullPath(forRelativePath: relativePath)
        let fullURL = URL(fileURLWithPath: fullPath)
        guard fm.fileExists(atPath: fullPath, isDirectory: nil) else {
            throw FileSystemError.fileNotFound
        }
        let enc = encodingMap[relativePath] ?? .utf8
        guard let data = newContent.data(using: enc) else {
            throw FileSystemError.failedToEditFile(
                NSError(
                    domain: "encoding",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to encode text as \(enc)"]
                )
            )
        }

        // --- 1. do I/O off-actor ----------------------------------------
        do {
            try await Task.detached(priority: .utility) {
                try FileSystemService.writeFileRobust(to: fullURL, data: data)
            }.value // bubbles error
        } catch {
            throw FileSystemError.failedToEditFile(error)
        }

        // --- 2. in-memory bookkeeping (still inside actor) --------------
        // refresh encoding cache
        encodingMap[relativePath] = enc

        // update visited* sets so later FSEvents don't look "new"
        if !visitedPaths.contains(relativePath) {
            visitedPaths.insert(relativePath)
            visitedItems[relativePath] = false
        }

        // emit a *synthetic* delta so the UI updates immediately, with mtime if available
        let mdate = try? await getFileModificationDate(atRelativePath: relativePath)
        changePublisher.send([.fileModified(relativePath, mdate)])
    }

    func checkFilePermissions(atRelativePath relativePath: String) -> Bool {
        let fullPath = fullPath(forRelativePath: relativePath)
        return fm.isWritableFile(atPath: fullPath)
    }

    func getFileModificationDate(atRelativePath relativePath: String) async throws -> Date {
        let fullPath = fullPath(forRelativePath: relativePath)
        let attributes = try fm.attributesOfItem(atPath: fullPath)
        return attributes[.modificationDate] as? Date ?? Date()
    }

    func getItemModificationDateIfAvailable(atRelativePath relativePath: String) async -> Date? {
        let fullPath = fullPath(forRelativePath: relativePath)
        guard let attributes = try? fm.attributesOfItem(atPath: fullPath) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private static func writeFile(
        to url: URL,
        data: Data
    ) throws {
        try data.write(to: url, options: .atomic) // blocking write
    }

    /// Robust write that works across external/network volumes:
    /// 1) try atomic write
    /// 2) write to temp in the same directory then move into place (delete destination if needed)
    /// 3) POSIX open(O_CREAT|O_TRUNC)+write+fsync fallback
    private static func writeFileRobust(
        to url: URL,
        data: Data
    ) throws {
        // Fast path: try Foundation's atomic write first.
        do {
            try data.write(to: url, options: [.atomic])
            return
        } catch {
            // fall through to robust fallbacks
        }

        let fm = FileManager.default
        let dirURL = url.deletingLastPathComponent()
        let tmpURL = dirURL.appendingPathComponent(".repoprompt.tmp.\(UUID().uuidString)")

        // Fallback #1: write to temp in the same directory then move/replace.
        do {
            try data.write(to: tmpURL, options: [])
            if fm.fileExists(atPath: url.path) {
                // Removing the destination first avoids exchange/rename restrictions on some filesystems
                // (exFAT/SMB may reject replace semantics).
                try? fm.removeItem(at: url)
            }
            try fm.moveItem(at: tmpURL, to: url)
            return
        } catch {
            // Clean up temp if it remains
            try? fm.removeItem(at: tmpURL)
        }

        // Fallback #2: POSIX open/write/fsync.
        try writeFilePOSIX(to: url, data: data)
    }

    /// Low-level write that avoids Foundation's atomic/replace semantics entirely.
    private static func writeFilePOSIX(
        to url: URL,
        data: Data
    ) throws {
        let path = url.path
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd == -1 {
            let code = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: "open() failed for \(path) (\(code))"]
            )
        }

        var writeError: Int32 = 0
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            guard var base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var remaining = data.count
            while remaining > 0 {
                let n = Darwin.write(fd, base, remaining)
                if n < 0 {
                    writeError = errno
                    break
                }
                remaining -= n
                base = base.advanced(by: n)
            }
        }

        if writeError == 0 {
            if fsync(fd) != 0 {
                writeError = errno
            }
        }

        // Always attempt to close; prefer first error if any.
        let closeResult = close(fd)
        if writeError != 0 {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(writeError),
                userInfo: [NSLocalizedDescriptionKey: "write/fsync failed for \(path) (\(writeError))"]
            )
        }
        if closeResult != 0 {
            let code = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: "close() failed for \(path) (\(code))"]
            )
        }
    }
}
